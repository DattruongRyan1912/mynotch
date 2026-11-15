import SwiftUI
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

fileprivate final class StubPresenter: NotchPresenter {
    private(set) var opened: [ModuleID] = []
    private(set) var toasts = 0
    private(set) var closes = 0
    func open(tab: ModuleID) { opened.append(tab) }
    func showToast(_ content: AnyView, duration: Duration) { toasts += 1 }
    func close() { closes += 1 }
}

private final class StubPermissions: PermissionCenter {
    func status(of permission: Permission) -> PermissionStatus { .granted }
    func request(_ permission: Permission) async -> PermissionStatus { .granted }
    func openSystemSettings(for permission: Permission) {}
}

@Suite struct ModuleContextTests {
    fileprivate func makeContext(
        activities: ActivityCenter, scheduler: ManualScheduler = ManualScheduler(), presenter: StubPresenter = StubPresenter()
    ) -> ModuleContext {
        ModuleContext(
            id: "m",
            settings: ModuleSettings(store: SettingsStore(defaults: makeIsolatedDefaults()), module: "m"),
            activities: ActivityPublisher(center: activities, module: "m"),
            lockScreen: LockScreenPublisher(center: LockScreenContentCenter(), module: "m"),
            presenter: ModulePresenter(presenter: presenter, module: "m"),
            hotkeys: ModuleHotkeys(registry: HotkeyRegistry(backend: FakeHotkeyBackend()), module: "m"),
            services: ModuleServices(registry: ServiceRegistry(scheduler: scheduler), module: "m"),
            permissions: StubPermissions(),
            storage: ModuleStorage(directory: URL(filePath: "/support/m/"), cachesDirectory: URL(filePath: "/caches/m/")),
            scheduler: scheduler
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

    @Test func scheduledActionsAreForgottenOnceFiredOrCancelled() throws {
        let base = ManualScheduler()
        let context = makeContext(activities: ActivityCenter(scheduler: base), scheduler: base)
        let scheduler = try #require(context.scheduler as? ModuleScheduler)
        var fired = 0
        context.scheduler.schedule(after: .seconds(1)) { fired += 1 }
        context.scheduler.schedule(after: .seconds(5)) { fired += 10 }.cancel()
        #expect(scheduler.pendingCount == 1)
        base.advance(by: .seconds(5))
        #expect(fired == 1)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func selfReschedulingTimerKeepsOnePendingEntry() throws {
        let base = ManualScheduler()
        let context = makeContext(activities: ActivityCenter(scheduler: base), scheduler: base)
        let scheduler = try #require(context.scheduler as? ModuleScheduler)
        var ticks = 0
        func tick() {
            ticks += 1
            context.scheduler.schedule(after: .seconds(1), tick)
        }
        context.scheduler.schedule(after: .seconds(1), tick)
        for _ in 0..<50 {
            base.advance(by: .seconds(1))
            #expect(scheduler.pendingCount == 1)
        }
        #expect(ticks == 50)
    }

    @Test func cancelAllCancelsPendingScheduledActions() throws {
        let base = ManualScheduler()
        let context = makeContext(activities: ActivityCenter(scheduler: base), scheduler: base)
        let scheduler = try #require(context.scheduler as? ModuleScheduler)
        var fired = false
        context.scheduler.schedule(after: .seconds(1)) { fired = true }
        context.scheduler.schedule(after: .seconds(2)) { fired = true }
        #expect(scheduler.pendingCount == 2)
        context.cancelAll()
        #expect(scheduler.pendingCount == 0)
        base.advance(by: .seconds(2))
        #expect(!fired)
        #expect(base.pendingCount == 0)
    }

    @Test func thePresenterOpensOnlyThisModulesTabAndForwardsToastsAndClose() {
        let presenter = StubPresenter()
        let context = makeContext(activities: ActivityCenter(scheduler: ManualScheduler()), presenter: presenter)
        context.presenter.open()
        context.presenter.showToast(AnyView(EmptyView()), duration: .seconds(1))
        context.presenter.close()
        #expect(presenter.opened == ["m"])
        #expect(presenter.toasts == 1)
        #expect(presenter.closes == 1)
    }

    @Test func thePresenterIsInertAfterCancelAll() {
        let presenter = StubPresenter()
        let context = makeContext(activities: ActivityCenter(scheduler: ManualScheduler()), presenter: presenter)
        context.cancelAll()
        context.presenter.open()
        context.presenter.showToast(AnyView(EmptyView()), duration: .seconds(1))
        context.presenter.close()
        #expect(presenter.opened.isEmpty)
        #expect(presenter.toasts == 0)
        #expect(presenter.closes == 0)
    }
}
