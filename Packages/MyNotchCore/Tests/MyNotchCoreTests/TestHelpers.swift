import SwiftUI
@testable import MyNotchCore
import MyNotchTestSupport

func activity(_ id: String, _ priority: ActivityPriority = .normal, expiresAfter: Duration? = nil) -> LiveActivity {
    LiveActivity(id: id, priority: priority, expiresAfter: expiresAfter, leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()))
}

/// Ignores cancellation, standing in for a timer that fires even though a later `set` rescheduled it.
final class UncancellableScheduler: Scheduler {
    let base = ManualScheduler()

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ScheduledAction {
        base.schedule(after: delay, action)
        return ScheduledAction()
    }
}
