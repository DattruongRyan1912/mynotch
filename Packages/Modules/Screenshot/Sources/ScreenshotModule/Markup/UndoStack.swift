/// Undo history for the markup editor as whole-document snapshots: documents are small, and snapshots make
/// every edit undoable without writing an inverse for each kind of change.
nonisolated struct UndoStack: Equatable, Sendable {
    private(set) var document: MarkupDocument
    private var undoStates: [MarkupDocument] = []
    private var redoStates: [MarkupDocument] = []

    init(_ document: MarkupDocument) {
        self.document = document
    }

    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }

    /// Applies `edit` as one undoable step and forgets the redo history; an edit that changes nothing adds no step.
    mutating func apply(_ edit: (inout MarkupDocument) -> Void) {
        var edited = document
        edit(&edited)
        guard edited != document else { return }
        undoStates.append(document)
        redoStates.removeAll()
        document = edited
    }

    mutating func undo() {
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(document)
        document = previous
    }

    mutating func redo() {
        guard let next = redoStates.popLast() else { return }
        undoStates.append(document)
        document = next
    }
}
