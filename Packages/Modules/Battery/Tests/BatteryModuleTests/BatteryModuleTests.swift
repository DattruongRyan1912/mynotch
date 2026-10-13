import MyNotchCore
import MyNotchTestSupport
import Observation
import Testing
@testable import BatteryModule

final class FakePowerSource: PowerSourceReading {
    var snapshot: PowerSourceSnapshot?
    private var onChange: (@MainActor () -> Void)?

    init(_ snapshot: PowerSourceSnapshot?) { self.snapshot = snapshot }

    func read() -> PowerSourceSnapshot? { snapshot }
    func startObserving(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    func stopObserving() { onChange = nil }

    func emit(_ snapshot: PowerSourceSnapshot) {
        self.snapshot = snapshot
        onChange?()
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
}
