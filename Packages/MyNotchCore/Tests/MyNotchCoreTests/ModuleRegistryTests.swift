import Foundation
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct ModuleRegistryTests {
    @Test func bootstrapStartsOnlyEnabledModules() async {
        let on = FakeModule("on", order: 1)
        let off = FakeModule("off", order: 2, defaultEnabled: false)
        let harness = Harness([off, on])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "on") == .running)
        #expect(harness.registry.state(of: "off") == .disabled)
        #expect(harness.registry.tabs.map(\.id) == ["on"])
        #expect(harness.registry.modules.map(\.descriptor.id) == ["on", "off"])
    }

    @Test func failingModuleIsIsolatedAndCleanedUp() async {
        let broken = FakeModule("broken", order: 1)
        broken.startError = .failed(reason: "boom")
        broken.activityOnStart = activity("x")
        let healthy = FakeModule("healthy", order: 2)
        let harness = Harness([broken, healthy])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "broken") == .failed(reason: "boom"))
        #expect(harness.registry.state(of: "healthy") == .running)
        #expect(harness.activities.entries.isEmpty)
        #expect(harness.registry.tabs.map(\.id) == ["healthy"])
    }

    @Test func missingPermissionSkipsStartUntilGranted() async {
        let module = FakeModule("needy", permissions: [.accessibility])
        let harness = Harness([module])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "needy") == .needsPermission(.accessibility))
        #expect(module.startCount == 0)
        harness.permissions.statuses[.accessibility] = .granted
        await harness.registry.refreshPermissions()
        #expect(harness.registry.state(of: "needy") == .running)
    }

    @Test func grantRequestsAnUndeterminedPermissionAndStartsTheModule() async {
        let module = FakeModule("needy", permissions: [.calendars])
        let harness = Harness([module])
        harness.permissions.statuses[.calendars] = .notDetermined
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "needy") == .needsPermission(.calendars))
        await harness.registry.grant(.calendars)
        #expect(harness.permissions.requested == [.calendars])
        #expect(harness.permissions.openedSettings.isEmpty)
        #expect(harness.registry.state(of: "needy") == .running)
        #expect(module.startCount == 1)
    }

    @Test func grantLeavesSettingsClosedWhenTheUserDeniesThePrompt() async {
        let module = FakeModule("needy", permissions: [.calendars])
        let harness = Harness([module])
        harness.permissions.statuses[.calendars] = .notDetermined
        harness.permissions.requestResult = .denied
        await harness.registry.bootstrap()
        await harness.registry.grant(.calendars)
        #expect(harness.permissions.requested == [.calendars])
        #expect(harness.permissions.openedSettings.isEmpty)
        #expect(harness.registry.state(of: "needy") == .needsPermission(.calendars))
        #expect(module.startCount == 0)
    }

    @Test func grantOpensSystemSettingsForADeniedPermission() async {
        let module = FakeModule("needy", permissions: [.calendars])
        let harness = Harness([module])
        await harness.registry.bootstrap()
        await harness.registry.grant(.calendars)
        #expect(harness.permissions.openedSettings == [.calendars])
        #expect(harness.permissions.requested.isEmpty)
        #expect(harness.registry.state(of: "needy") == .needsPermission(.calendars))
        #expect(module.startCount == 0)
    }

    @Test func grantRequestsThenOpensSettingsForASettingsOnlyPermission() async {
        let module = FakeModule("needy", permissions: [.accessibility])
        let harness = Harness([module])
        harness.permissions.requestResult = .denied
        await harness.registry.bootstrap()
        await harness.registry.grant(.accessibility)
        #expect(harness.permissions.requested == [.accessibility])
        #expect(harness.permissions.openedSettings == [.accessibility])
        #expect(harness.registry.state(of: "needy") == .needsPermission(.accessibility))
        #expect(module.startCount == 0)
    }

    @Test func grantSkipsSettingsWhenASettingsOnlyRequestSucceeds() async {
        let module = FakeModule("needy", permissions: [.screenRecording])
        let harness = Harness([module])
        await harness.registry.bootstrap()
        await harness.registry.grant(.screenRecording)
        #expect(harness.permissions.requested == [.screenRecording])
        #expect(harness.permissions.openedSettings.isEmpty)
        #expect(harness.registry.state(of: "needy") == .running)
        #expect(module.startCount == 1)
    }

    @Test func deniedOptionalPermissionsDoNotBlockStart() async {
        let module = FakeModule("m", optionalPermissions: [.microphone, .bluetooth])
        let harness = Harness([module])
        await harness.registry.bootstrap()
        #expect(harness.permissions.status(of: .microphone) == .denied)
        #expect(harness.registry.state(of: "m") == .running)
        #expect(!harness.registry.needsPermissionPolling)
    }

    @Test func pollsForPermissionsOnlyWhileAModuleWaitsForOne() async {
        let module = FakeModule("needy", permissions: [.bluetooth])
        let harness = Harness([module])
        #expect(!harness.registry.needsPermissionPolling)
        await harness.registry.bootstrap()
        #expect(harness.registry.needsPermissionPolling)
        harness.permissions.statuses[.bluetooth] = .granted
        await harness.registry.refreshPermissions()
        #expect(harness.registry.state(of: "needy") == .running)
        #expect(!harness.registry.needsPermissionPolling)
    }

    @Test func disablingStopsAndRemovesActivitiesAndTab() async {
        let module = FakeModule("m")
        module.activityOnStart = activity("live")
        let harness = Harness([module])
        await harness.registry.bootstrap()
        #expect(harness.activities.current?.id == "m/live")
        await harness.registry.setEnabled(false, for: "m")
        #expect(module.stopCount == 1)
        #expect(harness.registry.state(of: "m") == .disabled)
        #expect(harness.activities.current == nil)
        #expect(harness.registry.tabs.isEmpty)
        #expect(harness.registry.isEnabled("m") == false)
    }

    @Test func retryRestartsAFailedModule() async {
        let module = FakeModule("m")
        module.startError = .unavailable(reason: "nope")
        let harness = Harness([module])
        await harness.registry.bootstrap()
        module.startError = nil
        await harness.registry.retry("m")
        #expect(harness.registry.state(of: "m") == .running)
        #expect(module.startCount == 2)
    }

    @Test func pauseStopsEverythingWithoutChangingEnabledSetting() async {
        let module = FakeModule("m")
        let harness = Harness([module])
        await harness.registry.bootstrap()
        await harness.registry.pauseAll()
        #expect(harness.registry.state(of: "m") == .disabled)
        #expect(harness.registry.isEnabled("m"))
        await harness.registry.resumeAll()
        #expect(harness.registry.state(of: "m") == .running)
    }

    @Test func shutdownStopsEveryModuleWithoutChangingEnabledSettings() async {
        let on = FakeModule("on", order: 1)
        let off = FakeModule("off", order: 2, defaultEnabled: false)
        let needy = FakeModule("needy", order: 3, permissions: [.accessibility])
        let harness = Harness([on, off, needy])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "needy") == .needsPermission(.accessibility))
        await harness.registry.shutdown()
        #expect(on.stopCount == 1)
        #expect(off.stopCount == 0)
        #expect(needy.stopCount == 0)
        for id: ModuleID in ["on", "off", "needy"] { #expect(harness.registry.state(of: id) == .disabled) }
        #expect(harness.registry.isEnabled("on"))
        #expect(!harness.registry.isEnabled("off"))
        #expect(harness.registry.isEnabled("needy"))
        #expect(harness.registry.tabs.isEmpty)
        #expect(!harness.registry.needsPermissionPolling)
    }

    @Test func nothingStartsAfterShutdown() async {
        let on = FakeModule("on", order: 1)
        let off = FakeModule("off", order: 2, defaultEnabled: false)
        let harness = Harness([on, off])
        await harness.registry.bootstrap()
        await harness.registry.shutdown()

        await harness.registry.setEnabled(true, for: "off")
        #expect(harness.registry.isEnabled("off"))
        await harness.registry.bootstrap()
        await harness.registry.retry("on")
        await harness.registry.resumeAll()
        await harness.registry.refreshPermissions()
        #expect(on.startCount == 1)
        #expect(off.startCount == 0)
        #expect(harness.registry.state(of: "on") == .disabled)
        #expect(harness.registry.state(of: "off") == .disabled)
        #expect(harness.registry.tabs.isEmpty)
    }

    @Test func grantAfterShutdownDoesNotStartTheModule() async {
        let needy = FakeModule("needy", permissions: [.calendars])
        let harness = Harness([needy])
        harness.permissions.statuses[.calendars] = .notDetermined
        await harness.registry.bootstrap()
        await harness.registry.shutdown()
        await harness.registry.grant(.calendars)
        #expect(harness.permissions.requested == [.calendars])
        #expect(needy.startCount == 0)
        #expect(harness.registry.state(of: "needy") == .disabled)
    }

    @Test func retryOfFailedModuleDoesNotCallStop() async {
        let module = FakeModule("m")
        module.startError = .failed(reason: "boom")
        let harness = Harness([module])
        await harness.registry.bootstrap()
        module.startError = nil
        await harness.registry.retry("m")
        #expect(harness.registry.state(of: "m") == .running)
        #expect(module.stopCount == 0)
    }

    @Test func contextCarriesTheModuleStorageAndScheduler() async throws {
        let module = FakeModule("m")
        let harness = Harness([module])
        await harness.registry.bootstrap()
        let context = try #require(module.context)
        let expected = harness.storageRoot.storage(for: "m")
        #expect(context.storage.directory == expected.directory)
        #expect(context.storage.cachesDirectory == expected.cachesDirectory)
        #expect(!FileManager.default.fileExists(atPath: expected.directory.path(percentEncoded: false)))

        var fired = false
        context.scheduler.schedule(after: .seconds(1)) { fired = true }
        #expect(!fired)
        harness.scheduler.advance(by: .seconds(1))
        #expect(fired)
    }

    @Test func stoppingCancelsPendingScheduledActions() async throws {
        let module = FakeModule("m")
        let harness = Harness([module])
        await harness.registry.bootstrap()
        let context = try #require(module.context)
        var fired = false
        let handle = context.scheduler.schedule(after: .seconds(1)) { fired = true }
        await harness.registry.setEnabled(false, for: "m")
        #expect(handle.isCancelled)
        harness.scheduler.advance(by: .seconds(1))
        #expect(!fired)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func schedulingAfterStopReturnsACancelledHandleThatNeverFires() async throws {
        let module = FakeModule("m")
        let harness = Harness([module])
        await harness.registry.bootstrap()
        let context = try #require(module.context)
        await harness.registry.setEnabled(false, for: "m")
        var fired = false
        let handle = context.scheduler.schedule(after: .seconds(1)) { fired = true }
        #expect(handle.isCancelled)
        harness.scheduler.advance(by: .seconds(1))
        #expect(!fired)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func runningModuleHandlesItsServiceUntilItStops() async throws {
        let module = FakeModule("m")
        module.serviceOnStart = "translate"
        let harness = Harness([module])
        await harness.registry.bootstrap()
        #expect(harness.services.handle(name: "translate", text: "xin chào"))
        #expect(module.serviceTexts == ["xin chào"])

        let context = try #require(module.context)
        await harness.registry.setEnabled(false, for: "m")
        #expect(harness.services.handle(name: "translate", text: "late"))
        var lateTexts: [String] = []
        context.services.register("late") { lateTexts.append($0) }
        #expect(harness.services.handle(name: "late", text: "late"))
        harness.scheduler.advance(by: .seconds(10))
        #expect(module.serviceTexts == ["xin chào"])
        #expect(lateTexts.isEmpty)
    }

    @Test func serviceRegisteredByAFailedStartIsRemoved() async {
        let module = FakeModule("m")
        module.serviceOnStart = "translate"
        module.startError = .failed(reason: "boom")
        let harness = Harness([module])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "m") == .failed(reason: "boom"))
        #expect(harness.services.handle(name: "translate", text: "x"))
        harness.scheduler.advance(by: .seconds(10))
        #expect(module.serviceTexts.isEmpty)
    }

    @Test func aServicesRequestBeforeTheModuleStartsReachesItOnceItRuns() async {
        let module = FakeModule("m")
        module.serviceOnStart = "translate"
        let harness = Harness([module])
        #expect(harness.services.handle(name: "translate", text: "early"))
        await harness.registry.bootstrap()
        #expect(module.serviceTexts.isEmpty)
        #expect(harness.registry.state(of: "m") == .running)
        #expect(harness.registry.tabs.map(\.id) == ["m"])
        harness.scheduler.advance(by: .zero)
        #expect(module.serviceTexts == ["early"])
    }

    @Test func actionScheduledByAFailedStartNeverFires() async {
        let module = FakeModule("m")
        var fired = false
        module.actionOnStart = { fired = true }
        module.startError = .failed(reason: "boom")
        let harness = Harness([module])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "m") == .failed(reason: "boom"))
        harness.scheduler.advance(by: .seconds(1))
        #expect(!fired)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func settingsViewIsBuiltWhileTheModuleIsDisabled() async throws {
        let module = FakeModule("m", defaultEnabled: false)
        let harness = Harness([module])
        await harness.registry.bootstrap()
        #expect(harness.registry.settingsView(for: "m") != nil)
        let disabled = try #require(module.settingsEnvironment)
        #expect(!disabled.isRunning)
        #expect(module.startCount == 0)
        #expect(disabled.storage.directory == harness.storageRoot.storage(for: "m").directory)
        #expect(disabled.permissions === harness.permissions)

        await harness.registry.setEnabled(true, for: "m")
        #expect(harness.registry.settingsView(for: "m") != nil)
        #expect(module.settingsEnvironment?.isRunning == true)
    }

    @Test func settingsViewSharesTheRunningModuleSettings() async throws {
        let module = FakeModule("m")
        let harness = Harness([module])
        await harness.registry.bootstrap()
        _ = harness.registry.settingsView(for: "m")
        let environment = try #require(module.settingsEnvironment)
        environment.settings.set(7, for: environment.settings.key("volume", default: 1))

        let context = try #require(module.context)
        #expect(context.settings.value(context.settings.key("volume", default: 1)) == 7)
    }

    @Test func tabsFollowDescriptorOrder() async {
        let late = FakeModule("late", order: 2)
        let early = FakeModule("early", order: 1)
        let harness = Harness([late, early])
        await harness.registry.bootstrap()
        #expect(harness.registry.tabs.map(\.id) == ["early", "late"])
        await harness.registry.setEnabled(false, for: "early")
        await harness.registry.setEnabled(true, for: "early")
        #expect(harness.registry.tabs.map(\.id) == ["early", "late"])
    }
}
