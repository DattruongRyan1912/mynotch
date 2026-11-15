import Foundation

/// What the tab's search field, kind chips and board pills select.
nonisolated struct ClipboardQuery: Sendable, Hashable {
    var text = ""
    var kind: ClipboardKind?
    var boardID: UUID?
}

nonisolated enum ClipboardSearch {
    /// One-off search. The tab keeps a `ClipboardSearchIndex` across keystrokes instead, so unchanged items are not re-folded.
    static func filter(_ history: ClipboardHistory, _ query: ClipboardQuery) -> [ClipboardItem] {
        ClipboardSearchIndex().filter(history, query)
    }
}
