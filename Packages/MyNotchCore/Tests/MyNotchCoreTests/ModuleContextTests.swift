import SwiftUI
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

private final class StubPresenter: NotchPresenter {
    func open(tab: ModuleID) {}
    func showToast(_ content: AnyView, duration: Duration) {}
    func close() {}
}

private final class StubPermissions: PermissionCenter {
    func status(of permission: Permission) -> PermissionStatus { .granted }
    func openSystemSettings(for permission: Permission) {}
}

@Suite struct ModuleContextTests {
    func makeContext(activities: ActivityCenter) -> ModuleContext {
        ModuleContext(
            id: "m",
            settings: ModuleSettings(store: SettingsStore(defaults: makeIsolatedDefaults()), module: "m"),
            activities: ActivityPublisher(center: activities, module: "m"),
            presenter: StubPresenter(),
            hotkeys: ModuleHotkeys(registry: HotkeyRegistry(), module: "m"),
            permissions: StubPermissions()
        )
    }

    @Test func finishedTasksAreForgotten() async {
        let context = makeContext(activities: ActivityCenter(scheduler: ManualScheduler()))
        await withCheckedContinuation { continuation in
            context.run { continuation.resume() }
        }
        await Task.yield()
        #expect(context.runningTaskCount == 0)
    }

    @Test func cancelAllCancelsRunningWorkAndIgnoresLateRuns() async {
        let activities = ActivityCenter(scheduler: ManualScheduler())
        let context = makeContext(activities: activities)
        context.activities.set(activity("live"))
        var observedCancellation = false
        context.run {
            while !Task.isCancelled { await Task.yield() }
            observedCancellation = true
        }
        context.cancelAll()
        for _ in 0..<100 where !observedCancellation { await Task.yield() }
        #expect(observedCancellation)
        #expect(activities.current == nil)
        var lateRan = false
        context.run { lateRan = true }
        await Task.yield()
        #expect(!lateRan)
        #expect(context.runningTaskCount == 0)
    }
}
