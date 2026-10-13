import MyNotchCore

/// Deterministic scheduler for tests: time only moves when `advance(by:)` is called.
public final class ManualScheduler: Scheduler {
    private struct Entry {
        let id: Int
        let fireAt: Duration
        let action: @MainActor () -> Void
        let handle: ScheduledAction
    }

    public private(set) var now: Duration = .zero
    private var entries: [Entry] = []
    private var nextID = 0

    public init() {}

    @discardableResult
    public func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ScheduledAction {
        let handle = ScheduledAction()
        entries.append(Entry(id: nextID, fireAt: now + delay, action: action, handle: handle))
        nextID += 1
        return handle
    }

    /// Moves time forward, running due actions in time order (ties in scheduling order).
    public func advance(by duration: Duration) {
        let target = now + duration
        while let next = entries
            .filter({ $0.fireAt <= target && !$0.handle.isCancelled })
            .min(by: { ($0.fireAt, $0.id) < ($1.fireAt, $1.id) }) {
            entries.removeAll { $0.id == next.id }
            now = next.fireAt
            next.action()
        }
        entries.removeAll { $0.handle.isCancelled }
        now = target
    }

    /// Number of scheduled actions that have neither fired nor been cancelled.
    public var pendingCount: Int { entries.filter { !$0.handle.isCancelled }.count }
}
