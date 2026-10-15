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
    /// The copy stack: copies collected while it is on, to be pasted one by one. Changed only by the module.
    var stack = CopyStack()
    /// Pasteboard access is set to "always deny", so the tab explains how to allow it instead of showing an empty history.
    var pasteboardDenied = false
    /// A click pastes, but Accessibility is not allowed, so the tab and the library say how to allow it.
    var needsAccessibility = false
    /// Items matching `query`: newest first, or in pin order when a board is selected.
    private(set) var visibleItems: [ClipboardItem] = []
    /// The rows under the search field while an `@` word is being typed.
    private(set) var suggestions = ClipboardSuggestionList()
    /// The apps of the history, for `@app` tokens; only kept up to date while the search text has an "@".
    @ObservationIgnored private var apps: [ClipboardLibraryApp] = []
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

    /// The `@` tokens of the search text the user has finished, shown as removable chips.
    var chips: [ClipboardSearchToken] {
        ClipboardSearchTerms(parsing: query.text, apps: apps).chips
    }

    /// A key typed in the search field while suggestions are shown. False when there are none, so the key keeps its
    /// usual meaning in the tab.
    func handleSuggestionKey(_ command: ClipboardKeyCommand) -> Bool {
        var text = query.text
        guard suggestions.handle(command, text: &text) else { return false }
        query.text = text
        return true
    }

    /// A click on a suggestion.
    func acceptSuggestion(at index: Int) {
        var text = query.text
        suggestions.accept(index, into: &text)
        query.text = text
    }

    func removeChip(_ token: ClipboardSearchToken) {
        query.text = ClipboardSearchTerms.removing(token, from: query.text)
    }

    /// Back to the state of a module that never started.
    func reset() {
        searchIndex = ClipboardSearchIndex()
        history = ClipboardHistory()
        query = ClipboardQuery()
        suggestions = ClipboardSuggestionList()
        selectedID = nil
        stack = CopyStack()
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
        apps = query.text.contains("@") ? ClipboardLibraryContent.counts(of: history).apps : []
        suggestions.update(text: query.text, apps: apps)
        visibleItems = searchIndex.filter(history, query, apps: apps)
    }
}
