import MyNotchCore
import MyNotchTestSupport
import Observation
import SwiftUI
import Testing
@testable import BatteryModule

final class FakePowerSource: PowerSourceReading {
    var snapshot: PowerSourceSnapshot?
    private var onChange: (@MainActor () -> Void)?

    init(_ snapshot: PowerSourceSnapshot?) { self.snapshot = snapshot }

    var isObserving: Bool { onChange != nil }

    func read() -> PowerSourceSnapshot? { snapshot }
    func startObserving(_ onChange: @escaping @MainActor () -> Void) -> Bool {
        self.onChange = onChange
        return true
    }
    func stopObserving() { onChange = nil }

    func emit(_ snapshot: PowerSourceSnapshot) {
        self.snapshot = snapshot
        onChange?()
    }
}

/// Battery module that records the environment the registry passes to its Settings rows.
final class SettingsEnvironmentRecorder: FeatureModule {
    let base: BatteryModule
    private(set) var environment: ModuleSettingsEnvironment?

    init(_ base: BatteryModule) { self.base = base }

    var descriptor: ModuleDescriptor { base.descriptor }
    func start(_ context: ModuleContext) async throws(ModuleError) { try await base.start(context) }
    func stop() async { await base.stop() }
    func makeTab() -> NotchTab? { base.makeTab() }
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        self.environment = environment
        return base.makeSettingsView(environment)
    }
}

@Suite struct BatteryModuleTests {
    @Test func desktopMacReportsUnavailable() async {
        let harness = RegistryHarness([BatteryModule(reader: FakePowerSource(nil))])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "battery") == .unavailable(reason: "Máy không có pin"))
    }

    @Test func pluggingInPublishesChargingActivityThatExpires() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "battery") == .running)
        #expect(harness.activities.current == nil)

        source.emit(PowerSourceSnapshot(percent: 60, isCharging: true, isOnAC: true))
        #expect(harness.activities.current?.id == "battery/charging")
        harness.scheduler.advance(by: .seconds(4))
        #expect(harness.activities.current == nil)
    }

    @Test func lowBatteryActivityClearsWhenPluggedIn() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 15, isCharging: false, isOnAC: false))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        await harness.registry.bootstrap()
        #expect(harness.activities.current?.id == "battery/low")
        source.emit(PowerSourceSnapshot(percent: 15, isCharging: true, isOnAC: true))
        #expect(harness.activities.entries.map(\.id) == ["battery/charging"])
    }

    @Test func disablingRemovesActivitiesAndStopsObserving() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 15, isCharging: false, isOnAC: false))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        await harness.registry.bootstrap()
        await harness.registry.setEnabled(false, for: "battery")
        #expect(harness.activities.current == nil)
        source.emit(PowerSourceSnapshot(percent: 10, isCharging: false, isOnAC: false))
        #expect(harness.activities.current == nil)
    }

    @Test func unpluggingWithinTheToastWindowClearsCharging() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 50, isCharging: false, isOnAC: false))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        await harness.registry.bootstrap()
        source.emit(PowerSourceSnapshot(percent: 50, isCharging: true, isOnAC: true))
        #expect(harness.activities.current?.id == "battery/charging")
        source.emit(PowerSourceSnapshot(percent: 50, isCharging: false, isOnAC: false))
        #expect(harness.activities.current == nil)
    }

    @Test func lowIsOnlyRepublishedWhenThePercentChanges() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 15, isCharging: false, isOnAC: false, minutesToEmpty: 40))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        await harness.registry.bootstrap()
        // onChange is @Sendable but runs synchronously on the writing (main) thread in this test.
        nonisolated(unsafe) var changes = 0
        withObservationTracking { _ = harness.activities.current } onChange: { changes += 1 }
        source.emit(PowerSourceSnapshot(percent: 15, isCharging: false, isOnAC: false, minutesToEmpty: 39))
        #expect(changes == 0)
        source.emit(PowerSourceSnapshot(percent: 14, isCharging: false, isOnAC: false, minutesToEmpty: 37))
        #expect(changes == 1)
        #expect(harness.activities.current?.id == "battery/low")
    }

    @Test func loweringTheThresholdInSettingsDismissesLow() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 18, isCharging: false, isOnAC: false))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        await harness.registry.bootstrap()
        #expect(harness.activities.current?.id == "battery/low")
        harness.settings.set(15, for: SettingKey("module.battery.lowThreshold", default: 20, clampedTo: 5...50))
        for _ in 0..<100 where harness.activities.current != nil { await Task.yield() }
        #expect(harness.activities.current == nil)
    }

    @Test func settingsRowsExistBeforeTheModuleEverStarts() {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        #expect(harness.registry.state(of: "battery") == .disabled)
        #expect(harness.registry.settingsView(for: "battery") != nil)
    }

    @Test func raisingTheThresholdThroughTheSettingsRowsShowsLow() async throws {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 25, isCharging: false, isOnAC: false))
        let recorder = SettingsEnvironmentRecorder(BatteryModule(reader: source))
        let harness = RegistryHarness([recorder])
        await harness.registry.bootstrap()
        #expect(harness.activities.current == nil)

        _ = harness.registry.settingsView(for: "battery")
        let environment = try #require(recorder.environment)
        #expect(environment.isRunning)
        environment.settings.binding(BatteryModule.keys(environment.settings).lowThreshold).wrappedValue = 30
        for _ in 0..<100 where harness.activities.current == nil { await Task.yield() }
        #expect(harness.activities.current?.id == "battery/low")
    }

    @Test func disableStopsObservingAndReenableRestarts() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 15, isCharging: false, isOnAC: false))
        let module = BatteryModule(reader: source)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()
        #expect(source.isObserving)
        await harness.registry.setEnabled(false, for: "battery")
        #expect(!source.isObserving)
        #expect(module.state.snapshot == nil)
        await harness.registry.setEnabled(true, for: "battery")
        #expect(source.isObserving)
        #expect(harness.activities.current?.id == "battery/low")
    }

    @Test func durationFormatting() {
        #expect(BatteryTabView.format(45) == "45 phút")
        #expect(BatteryTabView.format(60) == "1 giờ")
        #expect(BatteryTabView.format(135) == "2 giờ 15 phút")
    }
}
