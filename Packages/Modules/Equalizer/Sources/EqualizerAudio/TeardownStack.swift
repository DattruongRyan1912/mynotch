import Synchronization

/// The undo of every setup step that succeeded, run newest first. A pipeline pushes one after each step, so
/// unwinding after a step failed (or after a normal run) undoes exactly what exists, in the order Core Audio
/// needs: stop, then the IO proc, then the aggregate device, then the tap.
nonisolated final class TeardownStack: Sendable {
    private let steps = Mutex<[@Sendable () -> Void]>([])

    func push(_ undo: @escaping @Sendable () -> Void) {
        steps.withLock { $0.append(undo) }
    }

    /// Runs and forgets every step, newest first. A second call finds nothing left to do.
    func unwind() {
        while let undo = steps.withLock({ $0.popLast() }) { undo() }
    }
}
