import CoreGraphics
import Foundation
import Observation

/// What the panel asks of the module. A protocol so the panel's tests never touch a pasteboard.
protocol ClipboardPanelActions: AnyObject {
    /// The click action from Settings: copy, or copy and paste. nil while the module is stopped.
    @discardableResult func activate(_ item: ClipboardItem) -> ClipboardPaster.Outcome?
}

extension ClipboardModule: ClipboardPanelActions {}

/// Everything the floating panel decides apart from drawing: which items its search shows, which one is selected, what
/// the keys, a click and ⌘1 to ⌘9 do, and what is pinned. It follows the module's `ClipboardState` only while it
/// exists, and searches with the same index, `@` words and suggestions as the tab and the library.
@Observable
final class ClipboardPanelModel {
    /// ⌘1 to ⌘9.
    static let shortcutCount = 9

    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            // A new search starts from its best match.
            chosenID = nil
            refreshItems()
        }
    }

    // MARK: What follows from it

    /// Newest first, as the search shows them.
    private(set) var items: [ClipboardItem] = []
    /// The rows under the search field while an `@` word is being typed.
    private(set) var suggestions = ClipboardSuggestionList()
    /// Items in any board.
    private(set) var pinnedIDs: Set<UUID> = []
    /// Stays open after an action, and can be moved.
    private(set) var isPinned: Bool
    /// What a copy did, shown while the panel stays open.
    private(set) var notice: ClipboardLibraryNotice?
    /// Owned by the panel, so its thumbnails go with it.
    @ObservationIgnored let thumbnails: ClipboardThumbnailCache

    /// Closes the window. The panel asks for it at most once.
    @ObservationIgnored var onClose: (() -> Void)?
    /// Takes the keyboard from the panel and gives it to the app in front, for a pinned panel that stays on screen.
    @ObservationIgnored var onReturnKeyboard: (() -> Void)?
    @ObservationIgnored var onPinnedChange: ((Bool) -> Void)?
    /// Where the user dragged a pinned panel to: its frame's origin.
    @ObservationIgnored var onMove: ((CGPoint) -> Void)?

    /// What the user moved or clicked to; the first item stands in until then, or when it is gone.
    private var chosenID: UUID?
    private var history: ClipboardHistory
    /// The apps of the history, for `@` words; only kept up to date while the search text has an "@".
    @ObservationIgnored private var apps: [ClipboardLibraryApp] = []
    @ObservationIgnored private let state: ClipboardState
    @ObservationIgnored private let actions: any ClipboardPanelActions
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let searchIndex = ClipboardSearchIndex()
    @ObservationIgnored private var noticeCount = 0
    /// Set when the panel closes, whoever asked: from then on nothing acts, so a late key or a second resign cannot
    /// close twice or paste.
    @ObservationIgnored private var isClosed = false

    init(
        state: ClipboardState, actions: any ClipboardPanelActions, isPinned: Bool,
        thumbnails: ClipboardThumbnailCache = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize),
        now: @escaping () -> Date = { .now }
    ) {
        self.state = state
        self.actions = actions
        self.isPinned = isPinned
        self.thumbnails = thumbnails
        self.now = now
        history = state.history
        refreshAll()
        state.observeHistory(self) { [weak self] in self?.refreshAll() }
    }

    /// Stops following the store and ignores everything from now on; called when the window closes.
    func detach() {
        isClosed = true
        state.stopObservingHistory(self)
    }

    // MARK: Words

    /// Why the list is empty; nil when it is not.
    var emptyMessage: String? {
        guard items.isEmpty else { return nil }
        if !searchText.allSatisfy(\.isWhitespace) || !history.items.isEmpty { return "Không tìm thấy" }
        return "Chưa có gì trong lịch sử"
    }

    /// The `@` tokens of the search text the user has finished, shown as removable chips.
    var chips: [ClipboardSearchToken] {
        ClipboardSearchTerms(parsing: searchText, apps: apps).chips
    }

    func timeLabel(for item: ClipboardItem) -> String {
        ClipboardCardText.relativeTime(item.copiedAt, now: now())
    }

    /// What VoiceOver reads for the item's row.
    func accessibilityLabel(for item: ClipboardItem) -> String {
        ClipboardCardText.accessibilityLabel(for: item, isPinned: pinnedIDs.contains(item.id), now: now())
    }

    // MARK: Selecting

    /// The item Return acts on: the one the user moved to while it is shown, else the first.
    var selectedID: UUID? {
        if let chosenID, items.contains(where: { $0.id == chosenID }) { return chosenID }
        return items.first?.id
    }

    var selectedItem: ClipboardItem? {
        let id = selectedID
        return items.first { $0.id == id }
    }

    /// The ⌘N that picks the item, for the first nine.
    func shortcutNumber(of id: UUID) -> Int? {
        guard let index = items.prefix(Self.shortcutCount).firstIndex(where: { $0.id == id }) else { return nil }
        return index + 1
    }

    // MARK: Keys

    /// A key typed in the search field. False for the keys the field keeps (Tab with nothing to complete).
    func handleKey(_ command: ClipboardKeyCommand) -> Bool {
        guard !isClosed else { return false }
        // While suggestions are shown the keys are theirs.
        var text = searchText
        if suggestions.handle(command, text: &text) {
            searchText = text
            return true
        }
        switch command {
        case .next:
            chosenID = ClipboardSelection.next(in: items.map(\.id), current: selectedID)
        case .previous:
            chosenID = ClipboardSelection.previous(in: items.map(\.id), current: selectedID)
        case .activate:
            if let id = selectedID { activate(id) }
        case .clearSearch, .close:
            // Esc closes the panel, with text in the field or not.
            requestClose()
        case .complete:
            return false
        }
        return true
    }

    /// ⌘1 to ⌘9: selects the Nth item and uses it. False when there is no such item.
    @discardableResult
    func pick(number: Int) -> Bool {
        guard !isClosed, (1...Self.shortcutCount).contains(number), items.indices.contains(number - 1) else { return false }
        activate(items[number - 1].id)
        return true
    }

    /// Return, ⌘N and a click: the module's click action on the item. An unpinned panel closes behind it, so the
    /// keyboard is back in the app in front before ⌘V is sent; a pinned one stays and hands the keyboard back instead.
    /// A copy that failed changes nothing and says so.
    func activate(_ id: UUID) {
        guard !isClosed, let item = items.first(where: { $0.id == id }) else { return }
        chosenID = id
        switch actions.activate(item) {
        case .pasted: finishAction(nil)
        case .copied: finishAction(("Đã chép", "checkmark.circle.fill"))
        case .copiedNeedsPermission: finishAction(("Đã chép — nhấn ⌘V để dán", "doc.on.clipboard"))
        case .failed: post("Không chép được mục này", systemImage: "exclamationmark.triangle.fill")
        case nil: requestClose()
        }
    }

    // MARK: Search tokens

    /// A click on a suggestion.
    func acceptSuggestion(at index: Int) {
        var text = searchText
        suggestions.accept(index, into: &text)
        searchText = text
    }

    func removeChip(_ token: ClipboardSearchToken) {
        searchText = ClipboardSearchTerms.removing(token, from: searchText)
    }

    func dismissNotice(_ id: Int) {
        if notice?.id == id { notice = nil }
    }

    // MARK: Pinning and focus

    func togglePin() {
        guard !isClosed else { return }
        isPinned.toggle()
        onPinnedChange?(isPinned)
    }

    /// The user dragged the panel. Only a pinned panel is remembered.
    func moved(to origin: CGPoint) {
        if isPinned && !isClosed { onMove?(origin) }
    }

    /// The panel lost the keyboard or the user clicked elsewhere: an unpinned panel is done.
    func focusLost() {
        if !isPinned { requestClose() }
    }

    func requestClose() {
        guard !isClosed else { return }
        isClosed = true
        onClose?()
    }

    // MARK: Private

    private func finishAction(_ outcome: (text: String, systemImage: String)?) {
        guard isPinned else {
            requestClose()
            return
        }
        if let outcome { post(outcome.text, systemImage: outcome.systemImage) }
        onReturnKeyboard?()
    }

    private func post(_ text: String, systemImage: String) {
        noticeCount += 1
        notice = ClipboardLibraryNotice(id: noticeCount, text: text, systemImage: systemImage)
    }

    /// The store changed: take its history and search it again.
    private func refreshAll() {
        history = state.history
        pinnedIDs = Set(history.boards.flatMap(\.itemIDs))
        refreshItems()
    }

    private func refreshItems() {
        apps = searchText.contains("@") ? ClipboardLibraryContent.counts(of: history).apps : []
        suggestions.update(text: searchText, apps: apps)
        items = searchIndex.filter(history, ClipboardQuery(text: searchText), apps: apps)
        if let chosenID, !items.contains(where: { $0.id == chosenID }) { self.chosenID = nil }
    }
}
