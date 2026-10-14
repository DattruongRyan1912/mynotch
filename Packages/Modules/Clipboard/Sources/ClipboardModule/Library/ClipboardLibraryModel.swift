import Foundation
import Observation

/// Everything the library window decides apart from drawing: which items its selection, search, filter and sort
/// show, the counts beside them, which cards are selected and what keys, drops and deletes do. It follows the
/// module's `ClipboardState` only while it exists, so a closed library costs nothing.
@Observable
final class ClipboardLibraryModel {
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
        didSet { if selection != oldValue { refreshItems() } }
    }
    /// Narrows the selection to one kind.
    var kindFilter: ClipboardKind? {
        didSet { if kindFilter != oldValue { refreshItems() } }
    }
    var searchText = "" {
        didSet { if searchText != oldValue { refreshItems() } }
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
    /// Cards per row now; set by the view, which knows the width. Arrow keys move by this many in the grid.
    var columns = 1

    // MARK: What follows from it

    private(set) var history: ClipboardHistory
    /// What the content shows, in display order.
    private(set) var items: [ClipboardItem] = []
    private(set) var counts = ClipboardLibraryCounts()
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

    @ObservationIgnored var onPreferencesChange: ((ClipboardLibraryPreferences) -> Void)?
    /// Owned by the library, so its thumbnails go with the window.
    @ObservationIgnored let thumbnails: ClipboardThumbnailCache

    @ObservationIgnored private let state: ClipboardState
    @ObservationIgnored private let actions: any ClipboardLibraryActions
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let searchIndex = ClipboardSearchIndex()
    /// Where a ⇧-click or ⇧-arrow range starts.
    @ObservationIgnored private var anchorID: UUID?
    @ObservationIgnored private var noticeCount = 0

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
        refreshAll()
        state.observeHistory(self) { [weak self] in self?.refreshAll() }
    }

    /// Stops following the store; called when the window closes.
    func detach() {
        state.stopObservingHistory(self)
    }

    var preferences: ClipboardLibraryPreferences {
        ClipboardLibraryPreferences(layout: layout, sort: sort, cardSize: cardSize)
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

    // MARK: Selecting

    func select(_ id: UUID, mode: SelectMode) {
        let ids = items.map(\.id)
        guard let index = ids.firstIndex(of: id) else { return }
        switch mode {
        case .replace:
            selectedIDs = [id]
            anchorID = id
            focusID = id
        case .toggle:
            if selectedIDs.remove(id) == nil {
                selectedIDs.insert(id)
                focusID = id
            } else if focusID == id {
                focusID = items.last { selectedIDs.contains($0.id) }?.id
            }
            anchorID = id
        case .range:
            guard let anchor = anchorID.flatMap({ ids.firstIndex(of: $0) }) else {
                select(id, mode: .replace)
                return
            }
            selectedIDs = Set(ids[min(anchor, index)...max(anchor, index)])
            focusID = id
        }
    }

    func selectAll() {
        selectedIDs = Set(items.map(\.id))
        anchorID = items.first?.id
        focusID = items.last?.id
    }

    func clearSelection() {
        selectedIDs = []
        anchorID = nil
        focusID = nil
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

    @discardableResult
    private func pin(_ ids: [UUID], to boardID: UUID) -> Bool {
        guard !ids.isEmpty, let board = history.boards.first(where: { $0.id == boardID }) else { return false }
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
        history = state.history
        counts = ClipboardLibraryContent.counts(of: history)
        pinnedIDs = Set(history.boards.flatMap(\.itemIDs))
        let existing = Set(history.items.map(\.id))
        if let pending = pendingDeletion {
            let remaining = pending.intersection(existing)
            pendingDeletion = remaining.isEmpty ? nil : remaining
        }
        switch selection {
        case .board(let id) where !history.boards.contains(where: { $0.id == id }): selection = .all
        case .app(let key) where !counts.apps.contains(where: { $0.id == key }): selection = .all
        default: refreshItems()
        }
    }

    private func refreshItems() {
        items = ClipboardLibraryContent.items(
            in: history, selection: selection, kindFilter: kindFilter, searchText: searchText, sort: sort,
            apps: counts.apps, index: searchIndex
        )
        let shown = Set(items.map(\.id))
        if !selectedIDs.isSubset(of: shown) { selectedIDs.formIntersection(shown) }
        if let focusID, !selectedIDs.contains(focusID) {
            self.focusID = items.last { selectedIDs.contains($0.id) }?.id
        }
        if let anchorID, !shown.contains(anchorID) { self.anchorID = focusID }
    }
}
