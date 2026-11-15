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

private final class MockSMCWriter: SMCChargeWriting, @unchecked Sendable {
    private let lock = NSLock()
    var writes: [(key: String, value: UInt8)] = []

    func writeByte(key: String, value: UInt8) -> Bool {
        lock.withLock {
            writes.append((key, value))
        }
        return true
    }

    func lastValue(for key: String) -> UInt8? {
        lock.withLock {
            writes.last(where: { $0.key == key })?.value
        }
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

    @Test func twoNotchesShowingTheTabKeepItVisibleUntilBothLeave() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false), details: Self.details)
        let module = BatteryModule(reader: source)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()
        module.actions.appeared()
        module.actions.appeared()
        module.actions.disappeared()
        #expect(module.state.isTabVisible)
        let before = source.detailReads
        harness.scheduler.advance(by: .seconds(30))
        #expect(source.detailReads == before + 1)

        module.actions.disappeared()
        #expect(!module.state.isTabVisible)
        harness.scheduler.advance(by: .seconds(300))
        #expect(source.detailReads == before + 1)
    }

    @Test func aStrayDisappearDoesNotHideTheNextTab() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false), details: Self.details)
        let module = BatteryModule(reader: source)
        await RegistryHarness([module]).registry.bootstrap()
        module.actions.disappeared()
        module.actions.appeared()
        #expect(module.state.isTabVisible)
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

    @Test func stoppingTheModuleReleasesHardwareRegisters() async {
        let mockWriter = MockSMCWriter()
        let source = FakePowerSource(PowerSourceSnapshot(percent: 90, isCharging: true, isOnAC: true, isAttachedToAdapter: true), details: Self.details)
        let module = BatteryModule(reader: source, smcWriter: mockWriter)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // Set limiter state to active discharge
        module.state.chargeLimiter.setLimitEnabled(true, snapshot: source.read(), details: nil)
        module.state.chargeLimiter.setAllowDischargeEnabled(true, snapshot: source.read(), details: nil)
        module.state.chargeLimiter.evaluate(snapshot: source.read()!, details: nil)
        #expect(module.state.chargeLimiter.state.isDischargeActive == true)

        await harness.registry.setEnabled(false, for: "battery")

        #expect(module.state.chargeLimiter.state.isDischargeActive == false)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 100)
    }

    @Test func applicationWillTerminateReleasesHardwareRegisters() async {
        let mockWriter = MockSMCWriter()
        let source = FakePowerSource(PowerSourceSnapshot(percent: 90, isCharging: true, isOnAC: true, isAttachedToAdapter: true), details: Self.details)
        let module = BatteryModule(reader: source, smcWriter: mockWriter)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // Set limiter state to active discharge
        module.state.chargeLimiter.setLimitEnabled(true, snapshot: source.read(), details: nil)
        module.state.chargeLimiter.setAllowDischargeEnabled(true, snapshot: source.read(), details: nil)
        module.state.chargeLimiter.evaluate(snapshot: source.read()!, details: nil)
        #expect(module.state.chargeLimiter.state.isDischargeActive == true)

        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)

        #expect(module.state.chargeLimiter.state.isDischargeActive == false)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 100)
    }

    @Test func sailingDeltaSettingClampedTo2Through20() async throws {
        let mockWriter = MockSMCWriter()
        let source = FakePowerSource(PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true, isAttachedToAdapter: true), details: Self.details)
        let module = BatteryModule(reader: source, smcWriter: mockWriter)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        let environment = try #require(harness.settingsEnvironment(for: "battery"))
        let keys = BatteryModule.keys(environment.settings)

        // Setting delta to 25 -> clamps to 20
        environment.settings.binding(keys.sailingDelta).wrappedValue = 25
        #expect(environment.settings.value(keys.sailingDelta) == 20)

        // Setting delta to 1 -> clamps to 2
        environment.settings.binding(keys.sailingDelta).wrappedValue = 1
        #expect(environment.settings.value(keys.sailingDelta) == 2)

        // Setting delta to 20 -> accepts 20
        environment.settings.binding(keys.sailingDelta).wrappedValue = 20
        #expect(environment.settings.value(keys.sailingDelta) == 20)
    }

    @Test func allowDischargeDefaultsToTrueInSettings() async throws {
        let mockWriter = MockSMCWriter()
        let source = FakePowerSource(PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true, isAttachedToAdapter: true), details: Self.details)
        let module = BatteryModule(reader: source, smcWriter: mockWriter)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        let environment = try #require(harness.settingsEnvironment(for: "battery"))
        let keys = BatteryModule.keys(environment.settings)
        #expect(environment.settings.value(keys.allowDischarge) == true)
        #expect(module.state.isAllowDischargeEnabled == true)
    }

    @Test func adaptiveGuardIntervalPacesWatchdogPolls() {
        let limiterDischargingNearLimit = BatteryChargeState(
            isLimitEnabled: true,
            chargeLimit: 80,
            isAllowDischargeEnabled: true,
            isDischargeActive: true
        )
        // Discharging at 82% (<= 80 + 2) -> fast polling (2s)
        let snap82 = PowerSourceSnapshot(percent: 82, isCharging: false, isOnAC: true)
        let interval82 = BatteryModule.guardInterval(
            snapshot: snap82,
            details: nil,
            isLimitToEightyEnabled: true,
            isTopUpOnceActive: false,
            calibrationStage: .idle,
            limiterState: limiterDischargingNearLimit
        )
        #expect(interval82 == BatteryModule.fastGuardPollInterval)

        // Discharging at 90% (> 80 + 2) -> regular guard polling (10s)
        let snap90 = PowerSourceSnapshot(percent: 90, isCharging: false, isOnAC: true)
        let interval90 = BatteryModule.guardInterval(
            snapshot: snap90,
            details: nil,
            isLimitToEightyEnabled: true,
            isTopUpOnceActive: false,
            calibrationStage: .idle,
            limiterState: limiterDischargingNearLimit
        )
        #expect(interval90 == BatteryModule.guardPollInterval)
    }

    @Test func parsesPmsetLogEntriesIntoChronologicalHistoryPoints() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let referenceNow = formatter.date(from: "2026-11-07 12:00:00 +0700")!
        let sampleLog = """
        2026-11-05 13:04:04 +0700 Assertions \tSummary- [System: PrevIdle] Using Batt(Charge: 79)
        2026-11-05 13:05:34 +0700 Assertions \tSummary- [System: PrevIdle] Using AC(Charge: 79)
        2026-11-06 21:05:07 +0700 Assertions \tSummary- [System: PrevIdle] Using Batt(Charge: 75%)
        2026-11-06 21:07:13 +0700 Assertions \tSummary- [System: PrevIdle] Using AC(Charge: 80)
        2026-11-07 10:00:00 +0700 Noise line without charge
        """
        let points = BatteryHistoryStore.parsePmsetLog(sampleLog, now: referenceNow)
        #expect(points.count == 4)
        guard points.count == 4 else { return }
        #expect(points[0].percent == 79 && points[0].mode == .discharging)
        #expect(points[1].percent == 79 && points[1].mode == .acPassthrough)
        #expect(points[2].percent == 75 && points[2].mode == .discharging)
        #expect(points[3].percent == 80 && points[3].mode == .charging)
    }

    @Test @MainActor func historyStoreCoalescesFrequentPollsAndPrunesPointsOlderThanSevenDays() {
        let suiteName = "test.battery.history.\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        let store = BatteryHistoryStore(userDefaults: isolatedDefaults, enablePmsetSeed: false)
        let now = Date()
        let tMinus8Days = now.addingTimeInterval(-8 * 86400)
        let tMinus2Hours = now.addingTimeInterval(-2 * 3600)

        // Point 1: 8 days ago (should be pruned)
        store.record(percent: 50, mode: .discharging, watts: -10, timestamp: tMinus8Days)

        // Point 2: 2 hours ago
        store.record(percent: 80, mode: .acPassthrough, watts: 0.0, timestamp: tMinus2Hours)

        // Point 3: 2 hours ago + 10s (same percent and mode -> coalesced with point 2)
        store.record(percent: 80, mode: .acPassthrough, watts: 0.2, timestamp: tMinus2Hours.addingTimeInterval(10))

        // Point 4: 2 hours ago + 30s (different mode -> new point)
        store.record(percent: 80, mode: .discharging, watts: -12.5, timestamp: tMinus2Hours.addingTimeInterval(30))

        // Point 5: 2 hours ago + 400s (percent changed + > 300s -> new point)
        store.record(percent: 79, mode: .discharging, watts: -14.0, timestamp: tMinus2Hours.addingTimeInterval(400))

        #expect(store.points.count == 3)
        #expect(store.points[0].percent == 80 && store.points[0].mode == .acPassthrough && store.points[0].watts == 0.2)
        #expect(store.points[1].percent == 80 && store.points[1].mode == .discharging && store.points[1].watts == -12.5)
        #expect(store.points[2].percent == 79 && store.points[2].mode == .discharging && store.points[2].watts == -14.0)
    }

    @Test @MainActor func malformedPmsetLinesAndOutOfBoundsPercentagesAreSafelyHandled() {
        let suiteName = "test.battery.history.malformed.\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        let malformed = """
        invalid date Using Batt(Charge: 79)
        9999-99-99 99:99:99 +0700 Using Batt(Charge: 79)
        2026-11-05 13:04:04 +0700 Using Batt(Charge: abc)
        2026-11-05 13:05:04 +0700 Using Batt(Charge: 150%)
        """
        let parsed = BatteryHistoryStore.parsePmsetLog(malformed)
        #expect(parsed.isEmpty)

        let store = BatteryHistoryStore(userDefaults: isolatedDefaults, enablePmsetSeed: false)
        store.record(percent: 135, mode: .charging, watts: 30)
        #expect(store.points.first?.percent == 100)

        store.record(percent: -25, mode: .discharging, watts: -10, timestamp: Date().addingTimeInterval(1000))
        #expect(store.points.last?.percent == 0)
    }

    @Test @MainActor func batteryModuleRecordsHistoryOnPowerSourceChangesAndComputesSummary() async throws {
        let suiteName = "test.battery.module.history.\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        let historyStore = BatteryHistoryStore(userDefaults: isolatedDefaults, enablePmsetSeed: false)
        let source = FakePowerSource(
            PowerSourceSnapshot(percent: 75, isCharging: true, isOnAC: true, isAttachedToAdapter: true),
            details: BatteryDetails(
                cycleCount: 50,
                batteryWatts: 35.0,
                temperatureCelsius: 30.0,
                voltageMillivolts: 12500,
                amperageMilliamps: 2800,
                designCapacityMah: 6000,
                maxCapacityMah: 5800,
                currentCapacityMah: 4500
            )
        )
        let module = BatteryModule(reader: source, historyStore: historyStore)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // Point 2: transition to 80% on AC passthrough
        source.details = BatteryDetails(
            cycleCount: 50,
            batteryWatts: 0.0,
            temperatureCelsius: 29.5,
            voltageMillivolts: 12800,
            amperageMilliamps: 0,
            designCapacityMah: 6000,
            maxCapacityMah: 5800,
            currentCapacityMah: 4800
        )
        source.emit(PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true, isAttachedToAdapter: true))

        // Point 3: unplug and discharge down to 72%
        source.details = BatteryDetails(
            cycleCount: 50,
            batteryWatts: -15.0,
            temperatureCelsius: 29.0,
            voltageMillivolts: 12200,
            amperageMilliamps: -1200,
            designCapacityMah: 6000,
            maxCapacityMah: 5800,
            currentCapacityMah: 4320
        )
        source.emit(PowerSourceSnapshot(percent: 72, isCharging: false, isOnAC: false, isAttachedToAdapter: false))

        let points = module.historyStore.points(for: BatteryHistoryRange.last24Hours)
        #expect(points.count >= 3)

        let summary = module.historyStore.summary(for: BatteryHistoryRange.last24Hours)
        #expect(summary.minPercent == 72)
        #expect(summary.maxPercent == 80)
        #expect(summary.averagePercent == 76)
        #expect(summary.peakWatts == 35.0)
    }

    @Test func testCoalescingRequiresMonotonicallyForwardTimestamp() async throws {
        let store = BatteryHistoryStore(userDefaults: UserDefaults(suiteName: "test.battery.coalesce.\(UUID().uuidString)")!, enablePmsetSeed: false)
        let t1 = Date(timeIntervalSince1970: 1730000000)
        store.record(percent: 80, mode: .charging, watts: 30.0, timestamp: t1)

        // Ghi điểm ở T2 = t1 - 60s (quá khứ). Không được ghi đè t1!
        let t2 = t1.addingTimeInterval(-60)
        store.record(percent: 80, mode: .charging, watts: 25.0, timestamp: t2)

        #expect(store.points.count == 2)
        #expect(store.points[0].timestamp == t2)
        #expect(store.points[1].timestamp == t1)

        // Ghi điểm ở T3 = t1 + 60s (tương lai < 5 min). Phải coalesce cập nhật điểm t1!
        let t3 = t1.addingTimeInterval(60)
        store.record(percent: 80, mode: .charging, watts: 35.0, timestamp: t3)

        #expect(store.points.count == 2)
        #expect(store.points[1].timestamp == t3)
        #expect(store.points[1].watts == 35.0)
    }
}
