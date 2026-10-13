import Foundation
import Observation

/// What the tab shows. The module owns `history`; the tab sets `query` and `selectedID`.
@Observable
final class ClipboardState {
    /// Changed only by the module; every change refreshes the search index and `visibleItems`.
    var history = ClipboardHistory() {
        didSet { historyChanged() }
    }
    var query = ClipboardQuery() {
        didSet { if query != oldValue { refreshVisibleItems() } }
    }
    var selectedID: UUID?
    /// Pasteboard access is set to "always deny", so the tab explains how to allow it instead of showing an empty history.
    var pasteboardDenied = false
    /// Items matching `query`: newest first, or in pin order when a board is selected.
    private(set) var visibleItems: [ClipboardItem] = []
    /// Kept across changes so typing and new copies fold only the items that are new or changed.
    @ObservationIgnored private(set) var searchIndex = ClipboardSearchIndex()

    /// Back to the state of a module that never started.
    func reset() {
        searchIndex = ClipboardSearchIndex()
        query = ClipboardQuery()
        history = ClipboardHistory()
        selectedID = nil
        pasteboardDenied = false
    }

    /// Drops a board filter or selection whose board or item is gone.
    private func historyChanged() {
        searchIndex.update(history)
        if let boardID = query.boardID, !history.boards.contains(where: { $0.id == boardID }) {
            query.boardID = nil
        } else {
            refreshVisibleItems()
        }
        if let selectedID, !history.items.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    private func refreshVisibleItems() {
        visibleItems = searchIndex.filter(history, query)
    }
}
