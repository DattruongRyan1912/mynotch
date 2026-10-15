import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct PermissionRefreshLoopTests {
    private final class Rig {
        let scheduler = ManualScheduler()
        var wanted = false
        var onRefresh: () -> Void = {}
        private(set) var refreshes = 0
        private(set) var loop: PermissionRefreshLoop!

        init(interval: Duration = .seconds(3)) {
            loop = PermissionRefreshLoop(scheduler: scheduler, interval: interval, shouldRun: { [unowned self] in wanted }) { [unowned self] in
                refreshes += 1
                onRefresh()
            }
        }
    }

    @Test func staysIdleWhileNothingIsWanted() {
        let rig = Rig()
        rig.loop.update()
        rig.scheduler.advance(by: .seconds(60))
        #expect(rig.refreshes == 0)
        #expect(!rig.loop.isRunning)
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func refreshesAtOnceWhenItBecomesWantedThenEveryThreeSeconds() {
        let rig = Rig()
        rig.wanted = true
        rig.loop.update()
        #expect(rig.refreshes == 1)
        #expect(rig.loop.isRunning)
        rig.scheduler.advance(by: .milliseconds(2_999))
        #expect(rig.refreshes == 1)
        rig.scheduler.advance(by: .milliseconds(1))
        #expect(rig.refreshes == 2)
        rig.scheduler.advance(by: .seconds(6))
        #expect(rig.refreshes == 4)
        #expect(rig.scheduler.pendingCount == 1)
    }

    @Test func keepsOneTimerHoweverOftenItIsToldToLook() {
        let rig = Rig()
        rig.wanted = true
        rig.loop.update()
        rig.loop.update()
        rig.loop.update()
        #expect(rig.refreshes == 1)
        #expect(rig.scheduler.pendingCount == 1)
    }

    @Test func stopsTheMomentItIsNoLongerWanted() {
        let rig = Rig()
        rig.wanted = true
        rig.loop.update()
        rig.wanted = false
        rig.loop.update()
        #expect(!rig.loop.isRunning)
        #expect(rig.scheduler.pendingCount == 0)
        rig.scheduler.advance(by: .seconds(60))
        #expect(rig.refreshes == 1)
    }

    @Test func aTickThatFindsNothingWantedEndsWithoutRefreshing() {
        let rig = Rig()
        rig.wanted = true
        rig.loop.update()
        rig.wanted = false
        rig.scheduler.advance(by: .seconds(3))
        #expect(rig.refreshes == 1)
        #expect(!rig.loop.isRunning)
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func aRefreshThatSettlesEverythingEndsTheLoopWithoutAnotherTimer() {
        let rig = Rig()
        rig.wanted = true
        rig.loop.update()
        rig.onRefresh = { rig.wanted = false }
        rig.scheduler.advance(by: .seconds(3))
        #expect(rig.refreshes == 2)
        #expect(!rig.loop.isRunning)
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func startsAgainWithAFreshRefreshWhenWantedAgain() {
        let rig = Rig()
        rig.wanted = true
        rig.loop.update()
        rig.wanted = false
        rig.loop.update()
        rig.wanted = true
        rig.loop.update()
        #expect(rig.refreshes == 2)
        rig.scheduler.advance(by: .seconds(3))
        #expect(rig.refreshes == 3)
    }

    @Test func theIntervalCanBeChosen() {
        let rig = Rig(interval: .seconds(1))
        rig.wanted = true
        rig.loop.update()
        rig.scheduler.advance(by: .seconds(2))
        #expect(rig.refreshes == 3)
    }

    @Test func aRefreshThatAsksTheLoopAgainDoesNotDoubleTheTimer() {
        let rig = Rig()
        rig.wanted = true
        rig.onRefresh = { rig.loop.update() }
        rig.loop.update()
        rig.scheduler.advance(by: .seconds(3))
        #expect(rig.scheduler.pendingCount == 1)
    }

    // MARK: when it is wanted

    @Test func wantedOnlyWhileSomethingOptionalIsMissingAndSomeoneCanSeeIt() {
        #expect(PermissionRefreshLoop.isWanted(missingOptional: 1, settingsVisible: true, notchOpen: false))
        #expect(PermissionRefreshLoop.isWanted(missingOptional: 2, settingsVisible: false, notchOpen: true))
        #expect(PermissionRefreshLoop.isWanted(missingOptional: 1, settingsVisible: true, notchOpen: true))
        #expect(!PermissionRefreshLoop.isWanted(missingOptional: 0, settingsVisible: true, notchOpen: true))
        #expect(!PermissionRefreshLoop.isWanted(missingOptional: 3, settingsVisible: false, notchOpen: false))
    }
}

@Suite struct SystemSettingsReturnTests {
    private let own = "io.lucasvu.mynotch"
    private let settings = SystemSettingsReturn.systemSettingsBundleID

    @Test func comingBackFromSystemSettingsToMyNotchIsTheMomentToLookAgain() {
        let watch = SystemSettingsReturn(ownBundleID: own)
        #expect(!watch.activated(settings))
        #expect(watch.activated(own))
    }

    @Test func anyOtherSwitchIsNot() {
        let watch = SystemSettingsReturn(ownBundleID: own)
        #expect(!watch.activated("com.apple.finder"))
        #expect(!watch.activated(own))
        #expect(!watch.activated(own))
        #expect(!watch.activated(settings))
        #expect(!watch.activated("com.apple.finder"))
        #expect(!watch.activated(own))
    }

    @Test func itNeedsToHaveSeenSystemSettingsFirst() {
        let watch = SystemSettingsReturn(ownBundleID: own)
        #expect(!watch.activated(own))
    }

    @Test func eachReturnIsReportedOnce() {
        let watch = SystemSettingsReturn(ownBundleID: own)
        _ = watch.activated(settings)
        #expect(watch.activated(own))
        #expect(!watch.activated(own))
        _ = watch.activated(settings)
        #expect(watch.activated(own))
    }

    @Test func anAppWithoutABundleIdentifierBreaksTheChain() {
        let watch = SystemSettingsReturn(ownBundleID: own)
        _ = watch.activated(settings)
        #expect(!watch.activated(nil))
        #expect(!watch.activated(own))
    }
}

@Suite struct MissingOptionalCountTests {
    @Test func countsEnabledModulesOptionalPermissionsThatAreDeniedOrNotAsked() async {
        let module = FakeModule("m", order: 1, permissions: [.calendars], optionalPermissions: [.pasteboard, .systemAudio, .downloadsFolder])
        let off = FakeModule("off", order: 2, defaultEnabled: false, optionalPermissions: [.screenRecording])
        let harness = Harness([module, off])
        harness.permissions.statuses = [
            .calendars: .denied, .pasteboard: .denied, .systemAudio: .unknown, .downloadsFolder: .notDetermined, .screenRecording: .denied,
        ]
        let overview = PermissionOverview(registry: harness.registry, scheduler: harness.scheduler)
        #expect(overview.missingOptionalCount == 2)
        harness.permissions.statuses[.pasteboard] = .granted
        overview.refresh()
        #expect(overview.missingOptionalCount == 1)
        harness.permissions.statuses[.downloadsFolder] = .granted
        overview.refresh()
        #expect(overview.missingOptionalCount == 0)
    }

    @Test func aPermissionAnotherModuleRequiresIsARequiredRowAndDoesNotCountHere() {
        let first = FakeModule("first", order: 1, optionalPermissions: [.calendars])
        let second = FakeModule("second", order: 2, permissions: [.calendars])
        let harness = Harness([first, second])
        harness.permissions.statuses[.calendars] = .denied
        let overview = PermissionOverview(registry: harness.registry, scheduler: harness.scheduler)
        #expect(overview.missingOptionalCount == 0)
        #expect(overview.missingRequiredCount == 1)
    }

    @Test func nothingIsCountedWhenNoModuleHasOptionalPermissions() {
        let harness = Harness([FakeModule("m", permissions: [.calendars])])
        harness.permissions.statuses[.calendars] = .denied
        #expect(PermissionOverview(registry: harness.registry, scheduler: harness.scheduler).missingOptionalCount == 0)
    }
}
