/// A module's view of the shared scheduler: everything still pending is cancelled when the module stops,
/// so a forgotten timer cannot fire into a stopped module.
final class ModuleScheduler: Scheduler {
    private let base: any Scheduler
    private var pending: [Int: ScheduledAction] = [:]
    private var nextID = 0
    private var isActive = true

    init(base: any Scheduler) { self.base = base }

    /// Actions that have neither fired nor been cancelled (for tests).
    var pendingCount: Int { pending.count }

    @discardableResult
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ScheduledAction {
        guard isActive else {
            let handle = ScheduledAction()
            handle.cancel()
            return handle
        }
        nextID += 1
        let id = nextID
        let inner = base.schedule(after: delay) { [weak self] in
            self?.pending[id] = nil
            action()
        }
        // Removing the entry on cancel keeps repeating timers from growing `pending`.
        let handle = ScheduledAction { [weak self] in
            inner.cancel()
            self?.pending[id] = nil
        }
        pending[id] = handle
        return handle
    }

    func invalidate() {
        isActive = false
        let handles = pending.values
        pending.removeAll()
        handles.forEach { $0.cancel() }
    }
}
