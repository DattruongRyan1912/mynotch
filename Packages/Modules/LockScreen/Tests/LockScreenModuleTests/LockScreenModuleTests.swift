import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import LockScreenModule

/// One log for the shim and the windows, so tests can check the order across both.
final class EventLog {
    var entries: [String] = []
}

/// Records instead of calling SkyLight: no space is created and no private function is called.
final class FakeSkyLightShim: SkyLightShim {
    var isAvailable = true
    let log: EventLog
    init(log: EventLog) { self.log = log }
    func makeLockScreenSpace() { log.entries.append("makeSpace") }
    func attach(windowNumber: Int) { log.entries.append("attach \(windowNumber)") }
    func detach(windowNumber: Int) { log.entries.append("detach \(windowNumber)") }
}

final class FakeLockScreenWindow: LockScreenWindow {
    let windowNumber: Int
    let log: EventLog
    /// What the module asked the window to draw.
    let content: AnyView
    /// Click-through until the module says otherwise, like the real panel.
    var takesClicks = false
    /// The heights of the card the module has fitted the window to, in order.
    private(set) var fitted: [CGFloat] = []
    init(windowNumber: Int, log: EventLog, content: AnyView = AnyView(EmptyView())) {
        self.windowNumber = windowNumber
        self.log = log
        self.content = content
    }
    func fit(toCardHeight card: CGFloat) { fitted.append(card) }
    func show() { log.entries.append("show \(windowNumber)") }
    func dismiss() { log.entries.append("dismiss \(windowNumber)") }
}

final class WindowFactory {
    let log: EventLog
    /// False plays a Mac with no screen to put the window on.
    var hasScreen = true
    private(set) var windows: [FakeLockScreenWindow] = []
    init(log: EventLog) { self.log = log }

    func make(content: AnyView = AnyView(EmptyView())) -> (any LockScreenWindow)? {
        guard hasScreen else { return nil }
        let window = FakeLockScreenWindow(windowNumber: 100 + windows.count + 1, log: log, content: content)
        windows.append(window)
        return window
    }
}

/// Stands in for `CGSessionCopyCurrentDictionary`, which tests never call.
final class FakeSession {
    var isLocked = false
}

/// A private center that counts how many observers were removed from it.
nonisolated final class CountingNotificationCenter: NotificationCenter, @unchecked Sendable {
    nonisolated(unsafe) private(set) var removals = 0

    override func removeObserver(_ observer: Any) {
        removals += 1
        super.removeObserver(observer)
    }
}

final class Counter {
    var count = 0
}

@MainActor
struct LockScreenFixture {
    let log = EventLog()
    let shim: FakeSkyLightShim
    let factory: WindowFactory
    let session = FakeSession()
    /// How many times the module asked for a shim.
    let shimsMade = Counter()
    let distributed = CountingNotificationCenter()
    let workspace = CountingNotificationCenter()
    let module: LockScreenModule
    let harness: RegistryHarness

    init() {
        let shim = FakeSkyLightShim(log: log), factory = WindowFactory(log: log), session = session, shimsMade = shimsMade
        self.shim = shim
        self.factory = factory
        module = LockScreenModule(
            makeShim: {
                shimsMade.count += 1
                return shim
            },
            makeWindow: { factory.make(content: $0) },
            distributedCenter: distributed,
            workspaceCenter: workspace,
            isScreenLocked: { session.isLocked }
        )
        harness = RegistryHarness([module])
    }

    var settings: ModuleSettings { harness.settingsEnvironment(for: "lockscreen")!.settings }
    var keys: LockScreenKeys { LockScreenKeys(settings) }

    func enable() async { await harness.registry.setEnabled(true, for: "lockscreen") }

    /// What a contributor module would publish; the views are placeholders.
    func offer(_ module: ModuleID, priority: ActivityPriority = .normal, isInteractive: Bool = false) {
        harness.lockScreen.set(AnyView(Text(module.rawValue)), priority: priority, isInteractive: isInteractive, from: module)
    }

    /// The notification and the session dictionary agree, as they do on a real Mac.
    func lock() async {
        session.isLocked = true
        distributed.post(name: LockStateObserver.screenIsLocked, object: nil)
        await drainMainQueue()
    }

    func unlock() async {
        session.isLocked = false
        distributed.post(name: LockStateObserver.screenIsUnlocked, object: nil)
        await drainMainQueue()
    }

    func sleepDisplay() async {
        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        await drainMainQueue()
    }

    func wakeDisplay() async {
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        await drainMainQueue()
    }
}

@Suite struct LockScreenModuleTests {
    @Test func descriptor() {
        let descriptor = LockScreenFixture().module.descriptor
        #expect(descriptor.id == "lockscreen")
        #expect(descriptor.displayName == "Màn hình khoá")
        #expect(descriptor.systemImage == "lock.display")
        #expect(!descriptor.defaultEnabled)
        #expect(descriptor.order == 990)
        #expect(descriptor.permissions.isEmpty)
    }

    @Test func staysOffUntilTheUserSwitchesItOn() async {
        let fixture = LockScreenFixture()
        fixture.offer("media")
        await fixture.harness.registry.bootstrap()
        #expect(fixture.harness.registry.state(of: "lockscreen") == .disabled)
        await fixture.lock()
        #expect(fixture.log.entries.isEmpty)
    }

    @Test func missingSkyLightFunctionsReportUnavailableAndNothingIsAttached() async {
        let fixture = LockScreenFixture()
        fixture.shim.isAvailable = false
        fixture.offer("media")
        await fixture.enable()
        #expect(fixture.harness.registry.state(of: "lockscreen") == .unavailable(reason: LockScreenModule.unavailableReason))
        await fixture.lock()
        #expect(fixture.log.entries.isEmpty)
        #expect(fixture.factory.windows.isEmpty)
    }

    @Test func lockingShowsTheWindowAndAttachesIt() async {
        let fixture = LockScreenFixture()
        fixture.offer("media")
        await fixture.enable()
        #expect(fixture.harness.registry.state(of: "lockscreen") == .running)
        #expect(fixture.log.entries.isEmpty)
        await fixture.lock()
        #expect(fixture.log.entries == ["makeSpace", "show 101", "attach 101"])
    }

    @Test func lockingWithNothingToShowDoesNothing() async {
        let fixture = LockScreenFixture()
        await fixture.enable()
        await fixture.lock()
        #expect(fixture.log.entries.isEmpty)
    }

    @Test func aMacWithNoScreenShowsNothing() async {
        let fixture = LockScreenFixture()
        fixture.factory.hasScreen = false
        fixture.offer("media")
        await fixture.enable()
        await fixture.lock()
        #expect(fixture.log.entries.isEmpty)
    }

    @Test func unlockingDetachesAfterAShortDelay() async {
        let fixture = LockScreenFixture()
        fixture.offer("media")
        await fixture.enable()
        await fixture.lock()
        await fixture.unlock()
        #expect(fixture.log.entries == ["makeSpace", "show 101", "attach 101"])
        fixture.harness.scheduler.advance(by: LockScreenModule.hideDelay - .milliseconds(1))
        #expect(fixture.log.entries.count == 3)
        fixture.harness.scheduler.advance(by: .milliseconds(1))
        #expect(fixture.log.entries == ["makeSpace", "show 101", "attach 101", "detach 101", "dismiss 101"])
    }

    @Test func theDisplayGoingToSleepDetachesAndWakingShowsItAgain() async {
        let fixture = LockScreenFixture()
        fixture.offer("media")
        await fixture.enable()
        await fixture.lock()
        await fixture.sleepDisplay()
        fixture.harness.scheduler.advance(by: LockScreenModule.hideDelay)
        #expect(fixture.log.entries.suffix(2) == ["detach 101", "dismiss 101"])
        await fixture.wakeDisplay()
        #expect(fixture.log.entries.suffix(3) == ["makeSpace", "show 102", "attach 102"])
    }

    @Test func lockingAgainWithinTheDelayKeepsTheSameWindow() async {
        let fixture = LockScreenFixture()
        fixture.offer("media")
        await fixture.enable()
        await fixture.lock()
        await fixture.unlock()
        await fixture.lock()
        fixture.harness.scheduler.advance(by: .seconds(5))
        #expect(fixture.log.entries == ["makeSpace", "show 101", "attach 101"])
        #expect(fixture.factory.windows.count == 1)
    }

    @Test func alreadyLockedWhenTheModuleStartsShowsAtOnce() async {
        let fixture = LockScreenFixture()
        fixture.session.isLocked = true
        fixture.offer("media")
        await fixture.enable()
        #expect(fixture.log.entries == ["makeSpace", "show 101", "attach 101"])
    }

    @Test func contributorsTheUserSwitchedOffAreNotShown() async {
        let fixture = LockScreenFixture()
        fixture.offer("battery")
        await fixture.enable()
        await fixture.lock()
        #expect(fixture.log.entries.isEmpty)

        fixture.settings.set(true, for: fixture.keys.showBattery)
        await fixture.unlock()
        await fixture.lock()
        #expect(fixture.log.entries == ["makeSpace", "show 101", "attach 101"])
    }

    @Test func settingsPickWhichContributorsCount() async {
        let fixture = LockScreenFixture()
        await fixture.enable()
        let keys = fixture.keys
        let settings = fixture.settings
        #expect(keys.allows("media", in: settings))
        #expect(keys.allows("timer", in: settings))
        #expect(!keys.allows("battery", in: settings))
        #expect(!keys.allows("clipboard", in: settings))

        settings.set(false, for: keys.showMedia)
        settings.set(false, for: keys.showTimer)
        settings.set(true, for: keys.showBattery)
        #expect(!keys.allows("media", in: settings))
        #expect(!keys.allows("timer", in: settings))
        #expect(keys.allows("battery", in: settings))
    }

    @Test func stoppingWhileLockedTakesTheWindowDownAtOnceAndIgnoresLaterNotifications() async {
        let fixture = LockScreenFixture()
        fixture.offer("media")
        await fixture.enable()
        await fixture.lock()
        await fixture.harness.registry.setEnabled(false, for: "lockscreen")
        #expect(fixture.log.entries == ["makeSpace", "show 101", "attach 101", "detach 101", "dismiss 101"])

        await fixture.unlock()
        await fixture.lock()
        fixture.harness.scheduler.advance(by: .seconds(5))
        #expect(fixture.log.entries.count == 5)
    }

    @Test func aDisableEnableCycleReusesTheSameShimSoTheSpaceIsMadeOnce() async {
        let fixture = LockScreenFixture()
        fixture.offer("media")
        #expect(fixture.shimsMade.count == 0)
        await fixture.enable()
        await fixture.lock()
        await fixture.harness.registry.setEnabled(false, for: "lockscreen")
        await fixture.enable()
        await fixture.lock()
        #expect(fixture.shimsMade.count == 1)
        #expect(fixture.log.entries.suffix(3) == ["makeSpace", "show 102", "attach 102"])
    }

    @Test func stoppingRemovesEveryObserverItAdded() async {
        let fixture = LockScreenFixture()
        await fixture.enable()
        #expect(fixture.distributed.removals == 0)
        #expect(fixture.workspace.removals == 0)
        await fixture.harness.registry.setEnabled(false, for: "lockscreen")
        #expect(fixture.distributed.removals == 2)
        #expect(fixture.workspace.removals == 3)
    }

    @Test func aMissedUnlockIsRecoveredWhenTheDisplayWakes() async {
        let fixture = LockScreenFixture()
        fixture.offer("media")
        await fixture.enable()
        await fixture.lock()
        // The unlock notification never arrived, but the session is no longer locked.
        fixture.session.isLocked = false
        await fixture.wakeDisplay()
        fixture.harness.scheduler.advance(by: LockScreenModule.hideDelay)
        #expect(fixture.log.entries.suffix(2) == ["detach 101", "dismiss 101"])
    }

    @Test func aPlainLockStillShowsWhenMacOSAlsoReportsTheSessionLeaving() async {
        let fixture = LockScreenFixture()
        fixture.offer("media")
        await fixture.enable()
        fixture.workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        await fixture.lock()
        fixture.workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        await drainMainQueue()
        #expect(fixture.log.entries == ["makeSpace", "show 101", "attach 101"])
    }

    @Test func enablingAgainAfterStoppingWorks() async {
        let fixture = LockScreenFixture()
        fixture.offer("media")
        await fixture.enable()
        await fixture.harness.registry.setEnabled(false, for: "lockscreen")
        await fixture.enable()
        await fixture.lock()
        #expect(fixture.log.entries == ["makeSpace", "show 101", "attach 101"])
    }

    @Test func settingsRowsExistBeforeTheModuleEverStarts() throws {
        let fixture = LockScreenFixture()
        let view = try #require(fixture.harness.registry.settingsView(for: "lockscreen"))
        #expect(String(describing: view).hasPrefix("AnyView(LockScreenSettingsView("))
        #expect(LockScreenSettingsView.warning == "Thử nghiệm — dùng API riêng của macOS")
        #expect(LockScreenSettingsView.mediaExplanation.contains("tiến trình"))
        #expect(!LockScreenSettingsView.mediaExplanation.contains("bấm"), "the warning is on the controls' switch, not here")
    }

    @Test func hasNoTab() {
        #expect(LockScreenFixture().module.makeTab() == nil)
    }
}
