import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import BatteryModule

final class FlakySMCWriter: SMCChargeWriting, @unchecked Sendable {
    private let lock = NSLock()
    var succeed: Bool = true
    var status: SMCHelperStatus = .enabled
    var registerCalls: Int = 0
    var writes: [(key: String, value: UInt8)] = []

    var helperStatus: SMCHelperStatus {
        lock.withLock { status }
    }

    func registerHelper() throws {
        lock.withLock {
            registerCalls += 1
        }
    }

    func writeByte(key: String, value: UInt8) -> Bool {
        lock.withLock {
            guard succeed else { return false }
            writes.append((key, value))
            return true
        }
    }

    func setChargeInhibit(inhibit: Bool) -> Bool {
        lock.withLock {
            guard succeed else { return false }
            writes.append((BatteryChargeLimiter.chargeInhibitKey, inhibit ? 1 : 0))
            return true
        }
    }

    func setChargeLimit(limit: Int) -> Bool {
        lock.withLock {
            guard succeed else { return false }
            writes.append((BatteryChargeLimiter.chargeLimitMaxKey, UInt8(clamping: limit)))
            return true
        }
    }

    func lastValue(for key: String) -> UInt8? {
        lock.withLock {
            writes.last(where: { $0.key == key })?.value
        }
    }

    func clearWrites() {
        lock.withLock {
            writes.removeAll()
        }
    }
}

private final class MinimalFakeWriter: SMCChargeWriting, @unchecked Sendable {
    func writeByte(key: String, value: UInt8) -> Bool { true }
}

@Suite @MainActor struct BatteryHelperTests {
    @Test func inhibitIsNotCommittedWhenTheWriteFails() {
        let flaky = FlakySMCWriter()
        flaky.succeed = false
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, smcWriter: flaky)

        // Evaluate at 85% on AC when write fails -> isInhibited remains false
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true))
        #expect(!limiter.state.isInhibited)
        #expect(flaky.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == nil)

        // Make write succeed -> isInhibited commits to true and writes CH0I = 1
        flaky.succeed = true
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true))
        #expect(limiter.state.isInhibited)
        #expect(flaky.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func resyncHardwarePushesLimitAndInhibit() {
        let flaky = FlakySMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 75, smcWriter: flaky)

        // Prime inhibit state
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true))
        #expect(limiter.state.isInhibited)
        flaky.clearWrites()

        // Resync pushes BCLM and CH0I
        limiter.resyncHardware(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true))
        #expect(flaky.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 75)
        #expect(flaky.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func aFakeWriterReportsEnabledByDefault() {
        let minimal = MinimalFakeWriter()
        #expect(minimal.helperStatus == .enabled)
    }

    @Test func startDoesNotRegisterTheHelper() async throws {
        let flaky = FlakySMCWriter()
        flaky.status = .notFound

        let source = FakePowerSource(PowerSourceSnapshot(percent: 50, isCharging: true, isOnAC: true))
        let module = BatteryModule(reader: source, smcWriter: flaky)
        let harness = RegistryHarness([module])

        // Set limitToEighty key to true prior to bootstrap
        let environment = try #require(harness.settingsEnvironment(for: "battery"))
        environment.settings.binding(BatteryModule.keys(environment.settings).limitToEighty).wrappedValue = true

        await harness.registry.bootstrap()

        // Starting up should NOT register the helper automatically
        #expect(flaky.registerCalls == 0)
    }

    @Test func turningTheLimitOnRegistersOnce() async throws {
        let flaky = FlakySMCWriter()
        flaky.status = .notFound

        let source = FakePowerSource(PowerSourceSnapshot(percent: 50, isCharging: true, isOnAC: true))
        let module = BatteryModule(reader: source, smcWriter: flaky)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        #expect(flaky.registerCalls == 0)

        // Toggle from false -> true: registers once
        module.actions.toggleLimitToEighty()
        #expect(flaky.registerCalls == 1)

        // Toggle from true -> false: does not register
        module.actions.toggleLimitToEighty()
        #expect(flaky.registerCalls == 1)

        // Toggle from false -> true again: registers second time
        module.actions.toggleLimitToEighty()
        #expect(flaky.registerCalls == 2)

        // When helper is already enabled, toggling limit does not register again
        flaky.status = .enabled
        module.actions.toggleLimitToEighty() // to false
        module.actions.toggleLimitToEighty() // to true
        #expect(flaky.registerCalls == 2)
    }

    @Test func helperBecomingEnabledResyncs() async throws {
        let flaky = FlakySMCWriter()
        flaky.status = .requiresApproval

        let source = FakePowerSource(PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true))
        let module = BatteryModule(reader: source, smcWriter: flaky)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // Turn on limit while helper is in requiresApproval
        module.actions.toggleLimitToEighty()
        flaky.clearWrites()

        // Helper gets approved and status transitions to enabled
        flaky.status = .enabled
        module.refreshHelperStatus()

        // BCLM must have been re-synced to hardware
        #expect(flaky.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 80)
    }

    @Test func reassertsInhibitWhenHardwareDriftsBackToCharging() {
        let flaky = FlakySMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 80, smcWriter: flaky)
        limiter.reassertionCooldownSeconds = 0 // Allow immediate reassertion for test

        let initialSnap = PowerSourceSnapshot(percent: 85, isCharging: false, isOnAC: true)
        let initialDetails = BatteryDetails(cycleCount: 100, healthPercent: 100, batteryWatts: 0.0, adapterWatts: 60)
        limiter.evaluate(snapshot: initialSnap, details: initialDetails)

        #expect(limiter.state.isInhibited == true)
        #expect(flaky.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        // Clear previous write history (simulating macOS powerd secretly resetting hardware register to 0)
        flaky.clearWrites()

        // Re-evaluating while hardware is safely at 0.0 W and not charging: does NOT spam writes
        let idleSnap = PowerSourceSnapshot(percent: 85, isCharging: false, isOnAC: true)
        let idleDetails = BatteryDetails(cycleCount: 100, healthPercent: 100, batteryWatts: 0.0, adapterWatts: 60)
        limiter.evaluate(snapshot: idleSnap, details: idleDetails)
        #expect(flaky.writes.isEmpty)

        // Hardware drifts back to charging (batteryWatts > 0.5 W or isCharging == true)
        let driftSnap = PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true)
        let driftDetails = BatteryDetails(cycleCount: 100, healthPercent: 100, batteryWatts: 15.0, adapterWatts: 60)
        limiter.evaluate(snapshot: driftSnap, details: driftDetails)

        // Limiter must have re-asserted SMC inhibit and BCLM!
        #expect(flaky.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
        #expect(flaky.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 80)
    }

    @Test func reassertionCooldownSuppressesSpammingWritesWithinCooldownPeriod() {
        let flaky = FlakySMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 80, smcWriter: flaky)
        limiter.reassertionCooldownSeconds = 15.0

        let initialSnap = PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true)
        let initialDetails = BatteryDetails(cycleCount: 100, healthPercent: 100, batteryWatts: 15.0, adapterWatts: 60)
        limiter.evaluate(snapshot: initialSnap, details: initialDetails)
        #expect(limiter.state.isInhibited == true)
        #expect(flaky.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        flaky.clearWrites()

        // Immediate next tick: hardware is still charging, but within 15s cooldown -> does NOT spam write
        limiter.evaluate(snapshot: initialSnap, details: initialDetails)
        #expect(flaky.writes.isEmpty)
    }

    @Test func backgroundGuardPollsEveryTenSecondsWhileLimitIsActiveOnAC() async throws {
        let flaky = FlakySMCWriter()
        let source = FakePowerSource(PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true))
        let module = BatteryModule(reader: source, smcWriter: flaky)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // Turn on limit while plugged into AC; tab is not visible
        module.actions.toggleLimitToEighty()
        let readsBefore = source.detailReads

        // Advance by 10s (Self.guardPollInterval)
        harness.scheduler.advance(by: .seconds(10))

        #expect(source.detailReads > readsBefore)
    }

    @Test func antiFlappingCycleGuardsSMCWritesUnderAppleSiliconBehavior() {
        let flaky = FlakySMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 80, smcWriter: flaky)

        // Limiter starts on AC at 85%
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited)
        #expect(flaky.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
        flaky.clearWrites()

        // Apple Silicon drops isOnAC to false because CHIE cut off adapter input, but cable remains attached
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: false, isOnAC: false, isAttachedToAdapter: true))
        // Must NOT emit cancel inhibit (CH0I = 0)
        #expect(limiter.state.isInhibited)
        #expect(flaky.writes.isEmpty)

        // Cable is truly unplugged
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: false, isOnAC: false, isAttachedToAdapter: false))
        #expect(!limiter.state.isInhibited)
        #expect(flaky.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
    }

    @Test func adaptiveGuardIntervalPacesWatchdogPolls() {
        let baseLimiterState = BatteryChargeState(
            isLimitEnabled: true,
            chargeLimit: 60,
            isSailingEnabled: true,
            sailingDelta: 5,
            isAllowDischargeEnabled: false,
            isDischargeActive: false,
            isTopUpOnceActive: false,
            isInhibited: false,
            calibrationStage: .idle
        )

        // 1. Approaching target (59%, limit 60) while charging -> 2 seconds fast poll
        let snap59 = PowerSourceSnapshot(percent: 59, isCharging: true, isOnAC: true, isAttachedToAdapter: true)
        let interval59 = BatteryModule.guardInterval(
            snapshot: snap59,
            details: nil,
            isLimitToEightyEnabled: true,
            isTopUpOnceActive: false,
            calibrationStage: .idle,
            limiterState: baseLimiterState
        )
        #expect(interval59 == BatteryModule.fastGuardPollInterval)
        #expect(interval59 == Duration.seconds(2))

        // 2. Far from target (50%, limit 60) -> standard 10 seconds
        let snap50 = PowerSourceSnapshot(percent: 50, isCharging: true, isOnAC: true, isAttachedToAdapter: true)
        let interval50 = BatteryModule.guardInterval(
            snapshot: snap50,
            details: nil,
            isLimitToEightyEnabled: true,
            isTopUpOnceActive: false,
            calibrationStage: .idle,
            limiterState: baseLimiterState
        )
        #expect(interval50 == BatteryModule.guardPollInterval)
        #expect(interval50 == Duration.seconds(10))

        // 3. At or above target (60%, limit 60) -> standard 10 seconds (avoids fast spamming on hardware failure)
        let snap60 = PowerSourceSnapshot(percent: 60, isCharging: true, isOnAC: true, isAttachedToAdapter: true)
        let interval60 = BatteryModule.guardInterval(
            snapshot: snap60,
            details: nil,
            isLimitToEightyEnabled: true,
            isTopUpOnceActive: false,
            calibrationStage: .idle,
            limiterState: baseLimiterState
        )
        #expect(interval60 == BatteryModule.guardPollInterval)

        // 4. Already inhibited -> standard 10 seconds
        var inhibitedState = baseLimiterState
        inhibitedState.isInhibited = true
        let intervalInhibited = BatteryModule.guardInterval(
            snapshot: snap59,
            details: nil,
            isLimitToEightyEnabled: true,
            isTopUpOnceActive: false,
            calibrationStage: .idle,
            limiterState: inhibitedState
        )
        #expect(intervalInhibited == BatteryModule.guardPollInterval)

        // 5. Not charging (e.g. discharging or AC idle) -> standard 10 seconds
        let snapNotCharging = PowerSourceSnapshot(percent: 59, isCharging: false, isOnAC: true, isAttachedToAdapter: true)
        let intervalNotCharging = BatteryModule.guardInterval(
            snapshot: snapNotCharging,
            details: nil,
            isLimitToEightyEnabled: true,
            isTopUpOnceActive: false,
            calibrationStage: .idle,
            limiterState: baseLimiterState
        )
        #expect(intervalNotCharging == BatteryModule.guardPollInterval)
    }
}
