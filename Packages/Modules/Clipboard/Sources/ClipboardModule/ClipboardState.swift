import Foundation
import Observation

/// What the tab shows. The module owns `history`; the tab sets `query` and `selectedID`.
@Observable
final class ClipboardState {
    /// Changed only by the module; every change refreshes `visibleItems`.
    var history = ClipboardHistory() {
        didSet { historyChanged() }
    }
    /// A real change starts the keyboard selection from the first card again; writing the same value (the search field
    /// re-sends its text after a pause) keeps it.
    var query = ClipboardQuery() {
        didSet {
            guard query != oldValue else { return }
            selectedID = nil
            refreshVisibleItems()
        }
    }
    var selectedID: UUID?
    /// Pasteboard access is set to "always deny", so the tab explains how to allow it instead of showing an empty history.
    var pasteboardDenied = false
    /// A click pastes, but Accessibility is not allowed, so the tab and the library say how to allow it.
    var needsAccessibility = false
    /// Items matching `query`: newest first, or in pin order when a board is selected.
    private(set) var visibleItems: [ClipboardItem] = []
    /// Kept across changes so typing and new copies fold only the items that are new or changed. Filtering with
    /// search text folds what is missing, so nothing is folded until the user searches.
    @ObservationIgnored private(set) var searchIndex = ClipboardSearchIndex()
    /// Told after every change of `history`, by whoever shows more than the tab (the library window while it is open).
    /// Plain closures rather than observation, so the work stops the moment its owner is gone.
    @ObservationIgnored private var historyObservers: [ObjectIdentifier: () -> Void] = [:]
    var historyObserverCount: Int { historyObservers.count }

    /// Replaces any action `owner` registered before.
    func observeHistory(_ owner: AnyObject, _ action: @escaping () -> Void) {
        historyObservers[ObjectIdentifier(owner)] = action
    }

    func stopObservingHistory(_ owner: AnyObject) {
        historyObservers[ObjectIdentifier(owner)] = nil
    }

    /// Back to the state of a module that never started.
    func reset() {
        searchIndex = ClipboardSearchIndex()
        history = ClipboardHistory()
        query = ClipboardQuery()
        selectedID = nil
        pasteboardDenied = false
        needsAccessibility = false
    }

    /// Drops a board filter or selection whose board or item is gone.
    private func historyChanged() {
        if let boardID = query.boardID, !history.boards.contains(where: { $0.id == boardID }) {
            query.boardID = nil
        } else {
            refreshVisibleItems()
        }
        if let selectedID, !history.items.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
        for action in Array(historyObservers.values) { action() }
    }

    private func refreshVisibleItems() {
        visibleItems = searchIndex.filter(history, query)
    }
}
