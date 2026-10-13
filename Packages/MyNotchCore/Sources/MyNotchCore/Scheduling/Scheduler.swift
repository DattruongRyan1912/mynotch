/// Handle to a scheduled action; cancelling prevents it from running.
public final class ScheduledAction {
    public private(set) var isCancelled = false
    private let onCancel: () -> Void

    public init(onCancel: @escaping () -> Void = {}) { self.onCancel = onCancel }

    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel()
    }
}

/// Runs an action after a delay. Injected so delays are testable.
public protocol Scheduler: AnyObject {
    @discardableResult
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ScheduledAction
}

/// Production scheduler backed by `Task.sleep`.
public final class TaskScheduler: Scheduler {
    public init() {}

    @discardableResult
    public func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ScheduledAction {
        var task: Task<Void, Never>?
        let handle = ScheduledAction { task?.cancel() }
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, !handle.isCancelled else { return }
            action()
        }
        return handle
    }
}
