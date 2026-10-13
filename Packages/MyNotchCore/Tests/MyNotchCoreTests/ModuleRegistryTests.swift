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
