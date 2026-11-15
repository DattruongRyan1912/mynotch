import Foundation
import MyNotchCore
import MyNotchTestSupport
@testable import TodoModule

/// A module wired to fakes: no EventKit, no real clock, no notification of the system. "Now" is Wednesday 14 October 2026,
/// 09:00, in Ho Chi Minh City, and Reminders access is granted unless a test takes it away.
struct ModuleFixture {
    /// The wait for a status that lags the prompt, shrunk so a test that never sees it change takes 40 ms, not 2 s.
    static let recheck = (interval: Duration.milliseconds(2), limit: Duration.milliseconds(40))

    let calendar = fixedCalendar()
    let clock: TestClock
    let source: FakeTodoDataSource
    let dayCenter = NotificationCenter()
    let wakeCenter = NotificationCenter()
    let activeCenter = NotificationCenter()
    let module: TodoModule
    let harness: RegistryHarness

    init(_ reminders: [TodoReminder] = []) {
        let calendar = fixedCalendar()
        let clock = TestClock(calendar.on(14, at: 9))
        self.clock = clock
        source = FakeTodoDataSource(reminders: reminders, now: clock.now)
        module = TodoModule(
            dataSource: source, now: { clock.now }, calendar: calendar, dayChangeCenter: dayCenter, wakeCenter: wakeCenter,
            activeCenter: activeCenter, accessRecheck: Self.recheck, accessWatchInterval: .milliseconds(5)
        )
        harness = RegistryHarness([module])
        harness.permissions.statuses[.reminders] = .granted
    }

    var keys: TodoSettingsKeys { TodoSettingsKeys(harness.settingsEnvironment(for: "todo")!.settings) }
    var settings: ModuleSettings { harness.settingsEnvironment(for: "todo")!.settings }
    var state: TodoState { module.state }
    var rowIDs: [String] { state.rows.map(\.id) }
    var itemIDs: [String] { state.items.map(\.id) }
    var activityEntry: ActivityCenter.Entry? { harness.activities.entries.first { $0.id == "todo/remaining" } }

    /// Starts the module and waits for its first list.
    func start() async {
        await harness.registry.bootstrap()
        await settle { module.appliedRefreshes >= 1 }
    }

    /// Runs `trigger`, then waits until the module has seen it and queued a refresh.
    func trigger(_ action: () -> Void) async {
        let before = module.refreshRequests
        action()
        await settle { module.refreshRequests > before }
    }

    /// Waits for the refresh a change has started to be applied.
    func refreshed(after action: () -> Void) async {
        let before = module.appliedRefreshes
        action()
        await settle { module.appliedRefreshes > before }
    }

    /// A day's reminders: one overdue, two today (one timed), one undated in the default list, one for later, and one
    /// of another list; and one done earlier today.
    static func aTypicalDay(_ calendar: Calendar) -> [TodoReminder] {
        [
            todo("overdue", due: due(12)),
            todo("lunch", due: due(14, 12)),
            todo("report", due: due(14), priority: .high),
            todo("idea"),
            todo("later", due: due(20)),
            todo("meeting", due: due(14, 10), list: "work"),
            todo("shower", due: due(14), done: calendar.on(14, at: 7)),
        ]
    }
}
