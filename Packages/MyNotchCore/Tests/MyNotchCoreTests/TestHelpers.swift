import SwiftUI
@testable import MyNotchCore
import MyNotchTestSupport

/// `summary` is the stand-in for "the content changed" in tests that must not move an activity in the order: views can't
/// be compared, and a priority or an expiry would change the order itself.
func activity(_ id: String, _ priority: ActivityPriority = .normal, expiresAfter: Duration? = nil, summary: String? = nil) -> LiveActivity {
    LiveActivity(
        id: id, priority: priority, expiresAfter: expiresAfter, leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()),
        summary: summary
    )
}

/// Ignores cancellation, standing in for a timer that fires even though a later `set` rescheduled it.
final class UncancellableScheduler: Scheduler {
    let base = ManualScheduler()

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ScheduledAction {
        base.schedule(after: delay, action)
        return ScheduledAction()
    }
}
