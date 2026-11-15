/// Undo and redo for the recording editor as whole snapshots: what the person can change is small, and a snapshot makes every
/// edit undoable without writing its inverse.
nonisolated struct EditHistory<Value: Equatable & Sendable>: Equatable, Sendable {
    private(set) var value: Value
    private var undoStates: [Value] = []
    private var redoStates: [Value] = []

    init(_ value: Value) {
        self.value = value
    }

    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }

    /// Applies `change` as one undoable step and forgets what could be redone. A change that leaves the value as it was adds
    /// no step. Returns whether anything changed.
    @discardableResult
    mutating func apply(_ change: (inout Value) -> Void) -> Bool {
        var changed = value
        change(&changed)
        guard changed != value else { return false }
        undoStates.append(value)
        redoStates.removeAll()
        value = changed
        return true
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let previous = undoStates.popLast() else { return false }
        redoStates.append(value)
        value = previous
        return true
    }

    @discardableResult
    mutating func redo() -> Bool {
        guard let next = redoStates.popLast() else { return false }
        undoStates.append(value)
        value = next
        return true
    }
}
