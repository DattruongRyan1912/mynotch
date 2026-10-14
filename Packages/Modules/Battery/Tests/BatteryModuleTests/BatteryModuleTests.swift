import MyNotchCore
import MyNotchTestSupport
import Observation
import SwiftUI
import Testing
@testable import BatteryModule

final class FakePowerSource: PowerSourceReading {
    var snapshot: PowerSourceSnapshot?
    var details: BatteryDetails?
    var isLowPowerModeEnabled = false
    /// How often the module asked for the registry details, to see when it polls and when it does not.
    private(set) var detailReads = 0
    private var onChange: (@MainActor () -> Void)?

    init(_ snapshot: PowerSourceSnapshot?, details: BatteryDetails? = nil) {
        self.snapshot = snapshot
        self.details = details
    }

    var isObserving: Bool { onChange != nil }

    func read() -> PowerSourceSnapshot? { snapshot }
    func readDetails() -> BatteryDetails? {
        detailReads += 1
        return details
    }
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

@Suite struct BatteryModuleTests {
    @Test func desktopMacReportsUnavailable() async {
        let harness = RegistryHarness([BatteryModule(reader: FakePowerSource(nil))])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "battery") == .unavailable(reason: "Máy không có pin"))
    }

    @Test func offersThePercentToTheLockScreenWhileRunning() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        await harness.registry.bootstrap()
        #expect(harness.lockScreen.current?.module == "battery")
        #expect(harness.lockScreen.current?.priority == .low)

        await harness.registry.setEnabled(false, for: "battery")
        #expect(harness.lockScreen.current == nil)
    }

    @Test func aMacWithoutABatteryOffersNothingToTheLockScreen() async {
        let harness = RegistryHarness([BatteryModule(reader: FakePowerSource(nil))])
        await harness.registry.bootstrap()
        #expect(harness.lockScreen.current == nil)
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

    @Test func settingsRowsExistBeforeTheModuleEverStarts() throws {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        #expect(harness.registry.state(of: "battery") == .disabled)
        let view = try #require(harness.registry.settingsView(for: "battery"))
        #expect(String(describing: view).hasPrefix("AnyView(BatterySettingsView("))
    }

    @Test func thresholdSetBeforeTheFirstStartAppliesWhenItStarts() async throws {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 25, isCharging: false, isOnAC: false))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        let environment = try #require(harness.settingsEnvironment(for: "battery"))
        #expect(!environment.isRunning)
        environment.settings.binding(BatteryModule.keys(environment.settings).lowThreshold).wrappedValue = 30
        await harness.registry.bootstrap()
        #expect(harness.activities.current?.id == "battery/low")
    }

    @Test func raisingTheThresholdThroughTheSettingsRowsShowsLow() async throws {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 25, isCharging: false, isOnAC: false))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        await harness.registry.bootstrap()
        #expect(harness.activities.current == nil)

        let environment = try #require(harness.settingsEnvironment(for: "battery"))
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

    // MARK: Details, Low Power Mode and polling

    private static let details = BatteryDetails(cycleCount: 312, healthPercent: 92, batteryWatts: 12, adapterWatts: 96)

    @Test func startsWithTheDetailsAndLowPowerModeTheReaderReports() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false), details: Self.details)
        source.isLowPowerModeEnabled = true
        let module = BatteryModule(reader: source)
        await RegistryHarness([module]).registry.bootstrap()
        #expect(module.state.details == Self.details)
        #expect(module.state.isLowPowerMode)
    }

    @Test func aPowerSourceChangeReadsTheDetailsAndLowPowerModeAgain() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false))
        let module = BatteryModule(reader: source)
        await RegistryHarness([module]).registry.bootstrap()
        #expect(module.state.details == nil)
        #expect(!module.state.isLowPowerMode)

        source.details = Self.details
        source.isLowPowerModeEnabled = true
        source.emit(PowerSourceSnapshot(percent: 59, isCharging: false, isOnAC: false))
        #expect(module.state.snapshot?.percent == 59)
        #expect(module.state.details == Self.details)
        #expect(module.state.isLowPowerMode)

        // Switching Low Power Mode off arrives as a change with the same battery reading.
        source.isLowPowerModeEnabled = false
        source.emit(PowerSourceSnapshot(percent: 59, isCharging: false, isOnAC: false))
        #expect(!module.state.isLowPowerMode)
    }

    @Test func detailsDisappearWhenTheRegistryEntryCannotBeRead() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false), details: Self.details)
        let module = BatteryModule(reader: source)
        await RegistryHarness([module]).registry.bootstrap()
        source.details = nil
        source.emit(PowerSourceSnapshot(percent: 59, isCharging: false, isOnAC: false))
        #expect(module.state.details == nil)
    }

    @Test func anOpenTabReadsFreshNumbersAndThenEveryThirtySeconds() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false), details: Self.details)
        let module = BatteryModule(reader: source)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()
        let atStart = source.detailReads

        module.actions.appeared()
        #expect(module.state.isTabVisible)
        #expect(source.detailReads == atStart + 1)

        harness.scheduler.advance(by: .seconds(29))
        #expect(source.detailReads == atStart + 1)
        harness.scheduler.advance(by: .seconds(1))
        #expect(source.detailReads == atStart + 2)

        source.details = BatteryDetails(cycleCount: 313, healthPercent: 92, batteryWatts: 8, adapterWatts: 96)
        harness.scheduler.advance(by: .seconds(30))
        #expect(source.detailReads == atStart + 3)
        #expect(module.state.details?.cycleCount == 313)
    }

    @Test func aHiddenTabDoesNotPoll() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false), details: Self.details)
        let module = BatteryModule(reader: source)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()
        let atStart = source.detailReads
        harness.scheduler.advance(by: .seconds(300))
        #expect(source.detailReads == atStart)
        #expect(!module.state.isTabVisible)
    }

    @Test func leavingTheTabStopsThePolling() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false), details: Self.details)
        let module = BatteryModule(reader: source)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()
        module.actions.appeared()
        harness.scheduler.advance(by: .seconds(30))
        module.actions.disappeared()
        #expect(!module.state.isTabVisible)
        let afterLeaving = source.detailReads

        harness.scheduler.advance(by: .seconds(300))
        #expect(source.detailReads == afterLeaving)

        module.actions.appeared()
        #expect(source.detailReads == afterLeaving + 1)
        harness.scheduler.advance(by: .seconds(30))
        #expect(source.detailReads == afterLeaving + 2)
    }

    @Test func showingTheTabTwiceKeepsOneTimer() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false), details: Self.details)
        let module = BatteryModule(reader: source)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()
        module.actions.appeared()
        module.actions.appeared()
        let before = source.detailReads
        harness.scheduler.advance(by: .seconds(30))
        #expect(source.detailReads == before + 1)
    }

    @Test func stoppingTheModuleStopsThePollingAndForgetsTheTab() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false), details: Self.details)
        let module = BatteryModule(reader: source)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()
        module.actions.appeared()
        await harness.registry.setEnabled(false, for: "battery")
        #expect(module.state.details == nil)
        #expect(!module.state.isLowPowerMode)
        #expect(!module.state.isTabVisible)
        let afterStop = source.detailReads

        harness.scheduler.advance(by: .seconds(300))
        // A tab view that outlives the module for a moment must not bring the polling back.
        module.actions.appeared()
        module.actions.disappeared()
        harness.scheduler.advance(by: .seconds(300))
        #expect(source.detailReads == afterStop)
        #expect(!module.state.isTabVisible)
    }

    @Test func theTabDeclaresTheHeightOfItsLayout() throws {
        let module = BatteryModule(reader: FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false)))
        #expect(try #require(module.makeTab()).preferredHeight == BatteryTabView.preferredHeight)
    }
}
