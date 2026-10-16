import Foundation
import Observation

/// Everything the library window decides apart from drawing: which items its selection, search, filter and sort
/// show, the counts beside them, which cards are selected and what keys, drops and deletes do. It follows the
/// module's `ClipboardState` only while it exists, so a closed library costs nothing.
@Observable
final class ClipboardLibraryModel: ClipboardPreviewHosting {
    enum SelectMode {
        /// A plain click.
        case replace
        /// ⌘-click.
        case toggle
        /// ⇧-click: from the anchor to the item.
        case range
    }

    // MARK: What the user chose

    var selection = ClipboardLibrarySelection.all {
        didSet {
            guard selection != oldValue else { return }
            refreshItems()
            visitCurrentPlace()
        }
    }
    /// Narrows the selection to one kind.
    var kindFilter: ClipboardKind? {
        didSet {
            guard kindFilter != oldValue else { return }
            refreshItems()
            visitCurrentPlace()
        }
    }
    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            refreshItems()
            searchTextChanged()
        }
    }
    var sort: ClipboardLibrarySort {
        didSet {
            guard sort != oldValue else { return }
            refreshItems()
            onPreferencesChange?(preferences)
        }
    }
    var layout: ClipboardLibraryLayout {
        didSet { if layout != oldValue { onPreferencesChange?(preferences) } }
    }
    var cardSize: ClipboardLibraryCardSize {
        didSet { if cardSize != oldValue { onPreferencesChange?(preferences) } }
    }
    /// The inspector pane beside the cards; remembered between openings.
    var isInspectorVisible: Bool {
        didSet { if isInspectorVisible != oldValue { onPreferencesChange?(preferences) } }
    }
    /// Cards per row now; set by the view, which knows the width. Arrow keys move by this many in the grid.
    var columns = 1

    // MARK: What follows from it

    private(set) var history: ClipboardHistory
    /// What the content shows, in display order.
    private(set) var items: [ClipboardItem] = []
    private(set) var counts = ClipboardLibraryCounts()
    /// The rows under the search field while an `@` word is being typed.
    private(set) var suggestions = ClipboardSuggestionList()
    /// Items in any board.
    private(set) var pinnedIDs: Set<UUID> = []
    /// Always a subset of `items`.
    private(set) var selectedIDs: Set<UUID> = []
    /// The card Return and ⌘C act on, and where the arrow keys start: the last one clicked or moved to.
    private(set) var focusID: UUID?
    /// Items waiting for the user to confirm deleting pinned ones.
    private(set) var pendingDeletion: Set<UUID>?
    private(set) var notice: ClipboardLibraryNotice?
    private(set) var draggingIDs: [UUID] = []
    /// Where the user has been, for ⌘[ and ⌘] like Finder. Not kept anywhere: a new window starts with nowhere to go back to.
    private(set) var navigation = ClipboardLibraryNavigation(
        start: ClipboardLibraryNavigation.Place(selection: .all, kindFilter: nil, searchText: "", selectedID: nil)
    )

    @ObservationIgnored var onPreferencesChange: ((ClipboardLibraryPreferences) -> Void)?
    /// The library's handle on the module's thumbnails; the pictures only it needed go when the window closes (`release()`).
    @ObservationIgnored let thumbnails: ClipboardThumbnailCache
    /// The large preview of the focused card (Space, ⌘Y), which follows the focus while it is open.
    let preview = ClipboardPreviewState()

    @ObservationIgnored private let state: ClipboardState
    @ObservationIgnored private let actions: any ClipboardLibraryActions
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let searchIndex = ClipboardSearchIndex()
    /// Where a ⇧-click or ⇧-arrow range starts.
    @ObservationIgnored private var anchorID: UUID?
    @ObservationIgnored private var noticeCount = 0
    /// True while a place from the list is being put back, or the model itself moves off a place that is gone: neither is a step
    /// the user took, so neither adds a place.
    @ObservationIgnored private var isMovingByItself = false
    /// True while the search text is being typed, so the letters of one word make one place.
    @ObservationIgnored private var isTypingSearch = false

    init(
        state: ClipboardState, actions: any ClipboardLibraryActions, preferences: ClipboardLibraryPreferences = ClipboardLibraryPreferences(),
        thumbnails: ClipboardThumbnailCache = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize),
        now: @escaping () -> Date = { .now }
    ) {
        self.state = state
        self.actions = actions
        self.now = now
        self.thumbnails = thumbnails
        history = state.history
        sort = preferences.sort
        layout = preferences.layout
        cardSize = preferences.cardSize
        isInspectorVisible = preferences.inspectorVisible
        refreshAll()
        state.observeHistory(self) { [weak self] in self?.refreshAll() }
    }

    /// Stops following the store; called when the window closes.
    func detach() {
        preview.close()
        state.stopObservingHistory(self)
    }

    var preferences: ClipboardLibraryPreferences {
        ClipboardLibraryPreferences(layout: layout, sort: sort, cardSize: cardSize, inspectorVisible: isInspectorVisible)
    }

    // MARK: Words

    var title: String {
        switch selection {
        case .all: "Tất cả"
        case .board(let id): history.boards.first { $0.id == id }?.name ?? "Tất cả"
        case .kind(let kind): kind.title
        case .app(let key): counts.apps.first { $0.id == key }?.name ?? "Tất cả"
        }
    }

    /// Why the content is empty; nil when it is not.
    var emptyMessage: String? {
        guard items.isEmpty else { return nil }
        if kindFilter != nil || !searchText.allSatisfy(\.isWhitespace) { return "Không tìm thấy" }
        switch selection {
        case .board: return "Board trống — kéo mục vào đây"
        case .all where history.items.isEmpty: return "Chưa có gì trong lịch sử"
        case .all, .kind, .app: return "Không tìm thấy"
        }
    }

    /// The `@` tokens of the search text the user has finished, shown as removable chips.
    var chips: [ClipboardSearchToken] {
        ClipboardSearchTerms(parsing: searchText, apps: counts.apps).chips
    }

    /// The board on show when it is locked: the content asks to open it instead of listing cards.
    var lockedSelectedBoard: ClipboardBoard? {
        guard case .board(let id) = selection else { return nil }
        return history.boards.first { $0.id == id && $0.isLocked }
    }

    /// The boards row above the history: only for the whole history, and not while searching.
    var showsBoardTiles: Bool {
        selection == .all && searchText.allSatisfy(\.isWhitespace)
    }

    func timeLabel(for item: ClipboardItem) -> String {
        ClipboardCardText.relativeTime(item.copiedAt, now: now())
    }

    /// What VoiceOver reads for the item's card or row.
    func accessibilityLabel(for item: ClipboardItem) -> String {
        ClipboardCardText.accessibilityLabel(for: item, isPinned: pinnedIDs.contains(item.id), now: now())
    }

    var pendingDeletionIncludesPinned: Bool {
        pendingDeletion.map { !$0.isDisjoint(with: pinnedIDs) } ?? false
    }

    // MARK: Search tokens

    /// A key typed in the search field while suggestions are shown. False when there are none, so the key keeps its
    /// usual meaning.
    func handleSearchKey(_ command: ClipboardKeyCommand) -> Bool {
        var text = searchText
        guard suggestions.handle(command, text: &text) else { return false }
        // Completing a word is a choice of its own, not one more letter.
        isTypingSearch = false
        searchText = text
        return true
    }

    /// A click on a suggestion.
    func acceptSuggestion(at index: Int) {
        var text = searchText
        suggestions.accept(index, into: &text)
        isTypingSearch = false
        searchText = text
    }

    func removeChip(_ token: ClipboardSearchToken) {
        isTypingSearch = false
        searchText = ClipboardSearchTerms.removing(token, from: searchText)
    }

    // MARK: Selecting

    func select(_ id: UUID, mode: SelectMode) {
        let ids = items.map(\.id)
        guard let index = ids.firstIndex(of: id) else { return }
        switch mode {
        case .replace:
            selectedIDs = [id]
            anchorID = id
            focusID = id
            reviseCurrentPlace()
        case .toggle:
            if selectedIDs.remove(id) == nil {
                selectedIDs.insert(id)
                focusID = id
            } else if focusID == id {
                focusID = items.last { selectedIDs.contains($0.id) }?.id
            }
            anchorID = id
            reviseCurrentPlace()
        case .range:
            guard let anchor = anchorID.flatMap({ ids.firstIndex(of: $0) }) else {
                select(id, mode: .replace)
                return
            }
            selectedIDs = Set(ids[min(anchor, index)...max(anchor, index)])
            focusID = id
            reviseCurrentPlace()
        }
    }

    func selectAll() {
        selectedIDs = Set(items.map(\.id))
        anchorID = items.first?.id
        focusID = items.last?.id
        reviseCurrentPlace()
    }

    func clearSelection() {
        selectedIDs = []
        anchorID = nil
        focusID = nil
        reviseCurrentPlace()
    }

    /// An arrow key. Nothing focused yet starts at the first card. In the grid up and down move a row, and a
    /// card with nothing below it goes to the last card.
    func move(_ direction: ClipboardLibraryDirection, extend: Bool) {
        guard !items.isEmpty else { return }
        var target = 0
        if let focusID, let index = items.firstIndex(where: { $0.id == focusID }) {
            let last = items.count - 1
            let perRow = layout == .grid ? max(columns, 1) : 1
            switch direction {
            case .left: target = max(index - 1, 0)
            case .right: target = min(index + 1, last)
            case .up: target = index - perRow >= 0 ? index - perRow : index
            case .down: target = index + perRow <= last ? index + perRow : (index / perRow == last / perRow ? index : last)
            }
        }
        select(items[target].id, mode: extend ? .range : .replace)
    }

    // MARK: Acting

    /// The module's click action on an item: copy, or paste, as Settings says.
    @discardableResult
    func activate(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        // Before anything is written or pasted, so the preview is never in the way of the keyboard or of ⌘V.
        preview.close()
        show(actions.activate(item))
        return true
    }

    /// Return.
    @discardableResult
    func activateSelection() -> Bool {
        focusID.map { activate($0) } ?? false
    }

    /// ⌘C: copies the focused card, since the pasteboard holds one item.
    @discardableResult
    func copySelection() -> Bool {
        guard let focusID, let item = items.first(where: { $0.id == focusID }) else { return false }
        show(actions.copy(item, plainText: false))
        return true
    }

    /// Shows what a copy or paste did, for actions that do not go through the model, like the context menu's.
    func show(_ outcome: ClipboardPaster.Outcome?) {
        switch outcome {
        case .copied: post("Đã chép", systemImage: "checkmark.circle.fill")
        case .copiedNeedsPermission: post("Đã chép — nhấn ⌘V để dán", systemImage: "doc.on.clipboard")
        case .failed: post("Không chép được mục này", systemImage: "exclamationmark.triangle.fill")
        case .pasted, nil: notice = nil
        }
    }

    func dismissNotice(_ id: Int) {
        if notice?.id == id { notice = nil }
    }

    // MARK: The inspector

    /// What the inspector shows: the focused card's facts, or only that the board on show is locked.
    var inspector: ClipboardInspectorContent {
        ClipboardInspectorContent.make(for: focusedItem, in: history, boardIsLocked: lockedSelectedBoard != nil)
    }

    /// The card Return and ⌘C act on, as the item itself.
    var focusedItem: ClipboardItem? {
        focusID.flatMap { id in items.first { $0.id == id } }
    }

    /// ⌘I.
    func toggleInspector() {
        isInspectorVisible.toggle()
    }

    /// The inspector's "Dán": the focused card is copied and pasted whatever the click action says. False with no card focused.
    @discardableResult
    func pasteFocused() -> Bool {
        guard let item = focusedItem else { return false }
        // Before anything is written or pasted, so the preview is never in the way of the keyboard or of ⌘V.
        preview.close()
        show(actions.paste(item, plainText: false))
        return true
    }

    /// The inspector's "Sửa…".
    @discardableResult
    func editFocused() -> Bool {
        guard let item = focusedItem else { return false }
        return edit(item)
    }

    /// Opens the editor on `item` if it can be edited (a text, a code or a link, not in a closed board).
    @discardableResult
    func edit(_ item: ClipboardItem) -> Bool {
        guard history.canEdit(item.id) else { return false }
        return actions.edit(item)
    }

    // MARK: The large preview

    var isPreviewOpen: Bool { preview.isOpen }

    @ObservationIgnored var onPreviewChange: ((Bool) -> Void)? {
        get { preview.onChange }
        set { preview.onChange = newValue }
    }

    /// The focused card while the preview is open.
    var previewedItem: ClipboardItem? {
        preview.isOpen ? previewableFocus : nil
    }

    /// Space and ⌘Y: opens the preview on the focused card, or closes it.
    func togglePreview() {
        if preview.isOpen {
            preview.close()
        } else if previewableFocus != nil {
            preview.open()
        }
    }

    func closePreview() {
        preview.close()
    }

    /// A key the library's window saw before its search field or its cards did. True when the preview took it.
    func handlePreviewKey(_ key: ClipboardPreviewKeys.Key, target: ClipboardPreviewKeys.Target, hasMarkedText: Bool) -> Bool {
        let command = preview.command(
            for: key, target: target, hasMarkedText: hasMarkedText, searchIsEmpty: searchText.isEmpty,
            suggestionsAreOpen: suggestions.isOpen, hasItem: previewableFocus != nil
        )
        switch command {
        case nil: return false
        case .ignore: return true
        case .toggle: togglePreview()
        case .close: preview.close()
        case .activate: activateSelection()
        }
        return true
    }

    // MARK: Back and forward

    var canGoBack: Bool { navigation.canGoBack }
    var canGoForward: Bool { navigation.canGoForward }

    /// ⌘[ and the toolbar's arrow: the place before this one. False when there is none.
    @discardableResult
    func goBack() -> Bool {
        guard let place = navigation.back() else { return false }
        show(place)
        return true
    }

    /// ⌘] and the toolbar's arrow.
    @discardableResult
    func goForward() -> Bool {
        guard let place = navigation.forward() else { return false }
        show(place)
        return true
    }

    private var currentPlace: ClipboardLibraryNavigation.Place {
        ClipboardLibraryNavigation.Place(selection: selection, kindFilter: kindFilter, searchText: searchText, selectedID: focusID)
    }

    /// The sidebar or the kind filter changed: a new place.
    private func visitCurrentPlace() {
        guard !isMovingByItself else { return }
        isTypingSearch = false
        navigation.visit(currentPlace)
    }

    /// The search text changed: one place for a whole run of typing, which goes on until something else is chosen.
    private func searchTextChanged() {
        guard !isMovingByItself else { return }
        if isTypingSearch {
            // Typing back to where it started joins the places, so the next letter starts a place of its own.
            if navigation.revise(currentPlace) { isTypingSearch = false }
        } else {
            navigation.visit(currentPlace)
            isTypingSearch = true
        }
    }

    /// A card was picked: that is part of where the user is, not a new place.
    private func reviseCurrentPlace() {
        guard !isMovingByItself else { return }
        isTypingSearch = false
        navigation.revise(currentPlace)
    }

    /// Puts a place of the list back: its sidebar choice, filter and search, and its pick if that card is still there.
    private func show(_ place: ClipboardLibraryNavigation.Place) {
        isMovingByItself = true
        defer { isMovingByItself = false }
        selection = place.selection
        kindFilter = place.kindFilter
        searchText = place.searchText
        if let id = place.selectedID, items.contains(where: { $0.id == id }) {
            select(id, mode: .replace)
        } else {
            clearSelection()
        }
        isTypingSearch = false
    }

    // MARK: Deleting

    /// Deletes `ids` (the selection when nil) at once, or asks first when pinned items are among them.
    func requestDelete(_ ids: Set<UUID>? = nil) {
        let ids = ids ?? selectedIDs
        let shown = Set(items.map(\.id)).intersection(ids)
        guard !shown.isEmpty else { return }
        if shown.isDisjoint(with: pinnedIDs) {
            delete(shown)
        } else {
            pendingDeletion = shown
        }
    }

    func confirmDelete() {
        guard let ids = pendingDeletion else { return }
        pendingDeletion = nil
        delete(ids)
    }

    func cancelDelete() {
        pendingDeletion = nil
    }

    /// Keeps keyboard flow going: the card that takes the deleted one's place becomes the selection.
    private func delete(_ ids: Set<UUID>) {
        let hadSelection = !selectedIDs.isDisjoint(with: ids)
        let place = items.firstIndex { ids.contains($0.id) }
        actions.delete(ids: ids)
        guard hadSelection, let place, !items.isEmpty else { return }
        select(items[min(place, items.count - 1)].id, mode: .replace)
    }

    // MARK: Boards

    /// Creates the board, pins `ids` to it and shows it. nil for an empty name.
    @discardableResult
    func createBoard(named name: String, pinning ids: [UUID] = []) -> UUID? {
        guard let id = actions.createBoard(named: name) else { return nil }
        if !ids.isEmpty { actions.pin(ids: ids, to: id) }
        selection = .board(id)
        return id
    }

    /// Starts a drag of the card; a card in the selection carries the whole selection. SwiftUI reports no end of a
    /// drag and its provider holds no ids, so the library keeps them here until a board takes them or `endDrag`.
    func beginDrag(of id: UUID) -> [UUID] {
        let ids = selectedIDs.contains(id) ? orderedSelection : [id]
        draggingIDs = ids
        return ids
    }

    func endDrag() {
        draggingIDs = []
    }

    /// A drop of the dragged cards on a board. Refused when nothing from the library is being dragged, e.g. a
    /// file from Finder.
    @discardableResult
    func drop(onBoard boardID: UUID) -> Bool {
        let ids = draggingIDs
        draggingIDs = []
        return pin(ids, to: boardID)
    }

    func addSelection(toBoard boardID: UUID) {
        pin(orderedSelection, to: boardID)
    }

    // MARK: Private

    private var orderedSelection: [UUID] {
        items.map(\.id).filter(selectedIDs.contains)
    }

    private var previewableFocus: ClipboardItem? {
        guard let focusID, let item = items.first(where: { $0.id == focusID }), history.canPreview(item.id) else { return nil }
        return item
    }

    @discardableResult
    private func pin(_ ids: [UUID], to boardID: UUID) -> Bool {
        guard !ids.isEmpty, let board = history.boards.first(where: { $0.id == boardID }) else { return false }
        // A board that is locked takes nothing until it is opened.
        guard !board.isLocked else {
            post("Hãy mở khoá “\(board.name)” trước khi thêm mục", systemImage: "lock.fill")
            return false
        }
        actions.pin(ids: ids, to: boardID)
        post("Đã thêm \(ids.count) mục vào “\(board.name)”", systemImage: "pin.fill")
        return true
    }

    private func post(_ text: String, systemImage: String) {
        noticeCount += 1
        notice = ClipboardLibraryNotice(id: noticeCount, text: text, systemImage: systemImage)
    }

    /// The store changed: take its history, recount, and drop what no longer exists.
    private func refreshAll() {
        // A card that is gone (deleted, or its board locked) takes its preview with it, rather than the preview moving on to
        // whatever the focus falls back to.
        let previewed = preview.isOpen ? focusID : nil
        defer {
            if let previewed, !history.items.contains(where: { $0.id == previewed }) { preview.close() }
        }
        history = state.history
        counts = ClipboardLibraryContent.counts(of: history)
        pinnedIDs = Set(history.boards.flatMap(\.itemIDs))
        let existing = Set(history.items.map(\.id))
        if let pending = pendingDeletion {
            let remaining = pending.intersection(existing)
            pendingDeletion = remaining.isEmpty ? nil : remaining
        }
        if navigation.places.contains(where: { !canShow($0.selection) }) { navigation.removePlaces { !canShow($0.selection) } }
        if canShow(selection) {
            refreshItems()
        } else {
            // The place on show is gone. "Tất cả" takes its place in the list: the model moved, not the user.
            isMovingByItself = true
            selection = .all
            isMovingByItself = false
            navigation.revise(currentPlace)
        }
    }

    /// Whether a sidebar choice still exists: a board that was deleted, or an app none of whose items is left, does not.
    private func canShow(_ selection: ClipboardLibrarySelection) -> Bool {
        switch selection {
        case .all, .kind: true
        case .board(let id): history.boards.contains { $0.id == id }
        case .app(let key): counts.apps.contains { $0.id == key }
        }
    }

    private func refreshItems() {
        items = ClipboardLibraryContent.items(
            in: history, selection: selection, kindFilter: kindFilter, searchText: searchText, sort: sort,
            apps: counts.apps, index: searchIndex
        )
        suggestions.update(text: searchText, apps: counts.apps)
        let shown = Set(items.map(\.id))
        if !selectedIDs.isSubset(of: shown) { selectedIDs.formIntersection(shown) }
        if let focusID, !selectedIDs.contains(focusID) {
            self.focusID = items.last { selectedIDs.contains($0.id) }?.id
        }
        if let anchorID, !shown.contains(anchorID) { self.anchorID = focusID }
        // Nothing left to show (a search or a filter that hides the card, a board with no cards).
        if preview.isOpen, previewableFocus == nil { preview.close() }
    }
}
