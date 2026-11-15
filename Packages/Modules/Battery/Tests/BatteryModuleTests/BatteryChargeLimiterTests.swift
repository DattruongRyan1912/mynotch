import Foundation
import Testing
@testable import BatteryModule

private final class MockSMCWriter: SMCChargeWriting, @unchecked Sendable {
    private let lock = NSLock()
    var writes: [(key: String, value: UInt8)] = []
    var shouldFailKeys: Set<String> = []
    var onInhibitStateChanged: (@Sendable (Bool) -> Void)?
    var onDischargeStateChanged: (@Sendable (Bool) -> Void)?

    func writeByte(key: String, value: UInt8) -> Bool {
        lock.withLock {
            if shouldFailKeys.contains(key) {
                return false
            }
            writes.append((key, value))
            return true
        }
    }

    func lastValue(for key: String) -> UInt8? {
        lock.withLock {
            writes.last(where: { $0.key == key })?.value
        }
    }
}

@Suite @MainActor struct BatteryChargeLimiterTests {
    @Test func doesNotLimitWhenDisabled() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: false, smcWriter: mockWriter)

        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true))

        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.writes.isEmpty)
    }

    @Test func inhibitsChargingWhenAtOrAboveEightyPercentOnAC() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, smcWriter: mockWriter)

        // Starting from below lower bound (50%) to simulate upward charging cycle
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 50, isCharging: true, isOnAC: true))
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.writes.isEmpty)

        // 79% on AC while charging up -> Continues charging (no early inhibit)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 79, isCharging: true, isOnAC: true))
        #expect(!limiter.state.isInhibited)

        // 80% on AC -> Inhibit active, writes CH0I = 1
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true))
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        // 85% on AC -> Stays inhibited
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true))
        #expect(limiter.state.isInhibited)
    }

    @Test func topUpOnceBypassesInhibitAndResetsAtFull() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, smcWriter: mockWriter)

        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true))
        #expect(limiter.state.isInhibited)

        // Activate Top-Up Once (Boost mode)
        limiter.toggleTopUpOnce(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true))
        #expect(limiter.state.isTopUpOnceActive)
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)

        // Reach 100% -> Auto resets top-up and restores inhibit
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 100, isCharging: false, isOnAC: true))
        #expect(!limiter.state.isTopUpOnceActive)
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func unpluggingFromACResetsInhibitAndTopUp() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, smcWriter: mockWriter)

        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 82, isCharging: true, isOnAC: true))
        #expect(limiter.state.isInhibited)

        // Unplug charger
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 82, isCharging: false, isOnAC: false))
        #expect(!limiter.state.isInhibited)
        #expect(!limiter.state.isTopUpOnceActive)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
    }

    @Test func bypassModeInhibitsImmediatelyAtCurrentBatteryPercentRegardlessOfUpperLimit() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: false,
            chargeLimit: 80,
            isBypassEnabled: false,
            smcWriter: mockWriter
        )

        let snapshot = PowerSourceSnapshot(percent: 76, isCharging: true, isOnAC: true)
        limiter.setBypassEnabled(true, snapshot: snapshot)

        #expect(limiter.state.isBypassEnabled == true)
        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 76)

        limiter.setChargeLimit(65, snapshot: snapshot)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 65)
        #expect(limiter.state.isInhibited == true)
    }

    @Test func bypassModeRespectsTwentyPercentSafetyFloorAndReleasesInhibit() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: false,
            chargeLimit: 80,
            isBypassEnabled: true,
            smcWriter: mockWriter
        )

        // At 76% on AC, bypass mode is active and inhibiting
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 76, isCharging: true, isOnAC: true))
        #expect(limiter.state.isInhibited == true)

        // Battery discharges down to 25% on AC -> stays inhibited
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 25, isCharging: false, isOnAC: true))
        #expect(limiter.state.isInhibited == true)

        // Pin chạm ngưỡng sàn an toàn 20% (bypassSafetyFloorPercent) -> Nhả inhibit để sạc lại
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 20, isCharging: false, isOnAC: true))
        #expect(limiter.state.isInhibited == false)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)

        // Pin chạm ngưỡng khẩn cấp 15% (emergencySafetyFloorPercent) -> Hủy bypass mode và phục hồi 100%
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 15, isCharging: false, isOnAC: true))
        #expect(limiter.state.isBypassEnabled == false)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 100)
    }

    @Test func failedSMCWritePreservesForceReassertFlagAndDoesNotLockOutUserChanges() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            smcWriter: mockWriter
        )

        mockWriter.shouldFailKeys = [BatteryChargeLimiter.chargeInhibitKey]
        limiter.handleWake()
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true))

        #expect(limiter.state.isInhibited == false)

        mockWriter.shouldFailKeys = []
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true))

        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func bypassModeReleasesWhenUnpluggedAndReappliesWhenPluggedIn() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 80, isBypassEnabled: true, smcWriter: mockWriter)

        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true))
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        // Unplug -> Release inhibit
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: false))
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)

        // Plug back in at 80% -> Re-apply inhibit
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true))
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func testEmergencySafetyFloorReleasesAllInhibitsAtOrBelowFifteenPercent() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isAllowDischargeEnabled: true,
            isBypassEnabled: true,
            smcWriter: mockWriter
        )

        // Put in forced discharge / inhibit state at 85%
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: false, isOnAC: true))
        #expect(!limiter.state.isInhibited)
        #expect(limiter.state.isDischargeActive)

        // Battery drops to emergency safety floor (15%)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 15, isCharging: false, isOnAC: true))
        #expect(!limiter.state.isInhibited)
        #expect(!limiter.state.isDischargeActive)
        #expect(!limiter.state.isBypassEnabled)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x00)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 100)

        // Battery drops further to critical 8% (same as user bug report)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 8, isCharging: false, isOnAC: true))
        #expect(!limiter.state.isInhibited)
        #expect(!limiter.state.isDischargeActive)
        #expect(!limiter.state.isBypassEnabled)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x00)
    }

    @Test func testBypassModeRefusesActivationAtEightPercent() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 60, smcWriter: mockWriter)

        let snapEight = PowerSourceSnapshot(percent: 8, isCharging: false, isOnAC: true)
        limiter.setBypassEnabled(true, snapshot: snapEight)
        #expect(!limiter.state.isBypassEnabled)
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) != 1)
    }

    @Test func testBypassModeCyclesSafelyWithSailingWindow() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isSailingEnabled: true,
            sailingDelta: 5,
            isBypassEnabled: true,
            smcWriter: mockWriter
        )

        // At 80%: Reached target limit, activates inhibit
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true))
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        // Pure Bypass Mode: at 76% and 74%: still > safety floor (20), maintains hardware bypass inhibit
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 76, isCharging: false, isOnAC: true))
        #expect(limiter.state.isInhibited)

        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 74, isCharging: false, isOnAC: true))
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        // Safety floor reached at 20%: releases inhibit to prevent battery death
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 20, isCharging: false, isOnAC: true))
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
    }

    @Test func gentleChargingTriggersAt34CelsiusAndResumesAt31Celsius() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: false, isBypassEnabled: false, isGentleChargingEnabled: true, smcWriter: mockWriter
        )

        // 30.0°C on AC -> Safe temperature, no inhibit
        let normalDetails = BatteryDetails(temperatureCelsius: 30.0)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 50, isCharging: true, isOnAC: true), details: normalDetails)
        #expect(!limiter.state.isThermalThrottled)
        #expect(!limiter.state.isInhibited)

        // 34.5°C on AC -> Exceeds thermal ceiling, throttles and inhibits charging
        let hotDetails = BatteryDetails(temperatureCelsius: 34.5)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 51, isCharging: true, isOnAC: true), details: hotDetails)
        #expect(limiter.state.isThermalThrottled)
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        // 32.5°C on AC -> Hysteresis zone (between 31°C and 34°C): remains throttled
        let coolingDetails = BatteryDetails(temperatureCelsius: 32.5)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 51, isCharging: true, isOnAC: true), details: coolingDetails)
        #expect(limiter.state.isThermalThrottled)
        #expect(limiter.state.isInhibited)

        // 30.5°C on AC -> Below resume threshold (<= 31.0°C): clears throttle and resumes charging
        let safeDetails = BatteryDetails(temperatureCelsius: 30.5)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 51, isCharging: true, isOnAC: true), details: safeDetails)
        #expect(!limiter.state.isThermalThrottled)
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
    }

    @Test func thermalGuardOverridesTopUpOnceForSafety() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, isGentleChargingEnabled: true, smcWriter: mockWriter)

        let safeDetails = BatteryDetails(temperatureCelsius: 30.0)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true), details: safeDetails)
        #expect(limiter.state.isInhibited)

        // Turn on Top-Up Once -> Un-inhibits to charge to 100%
        limiter.toggleTopUpOnce(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true), details: safeDetails)
        #expect(limiter.state.isTopUpOnceActive)
        #expect(!limiter.state.isInhibited)

        // Temperature rises to 34.2°C -> Thermal guard MUST override top-up once for hardware safety
        let hotDetails = BatteryDetails(temperatureCelsius: 34.2)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 82, isCharging: true, isOnAC: true), details: hotDetails)
        #expect(limiter.state.isThermalThrottled)
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        // Temperature cools to 30.8°C -> Resumes top-up boost
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 82, isCharging: true, isOnAC: true), details: safeDetails)
        #expect(!limiter.state.isThermalThrottled)
        #expect(limiter.state.isTopUpOnceActive)
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
    }

    @Test func flexibleChargeLimitWritesBCLM() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 80, smcWriter: mockWriter)

        limiter.setChargeLimit(70)
        #expect(limiter.state.chargeLimit == 70)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 70)

        limiter.setChargeLimit(85)
        #expect(limiter.state.chargeLimit == 85)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 85)

        limiter.setChargeLimit(90)
        #expect(limiter.state.chargeLimit == 90)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 90)
    }

    @Test func allowDischargeTriggersCHIEWhenOverLimit() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isAllowDischargeEnabled: true,
            smcWriter: mockWriter
        )

        // 90% on AC -> Over 80% limit with Allow Discharge enabled -> Discharging active (CHIE = 0x08)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 90, isCharging: true, isOnAC: true))
        #expect(limiter.state.isDischargeActive)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x08)

        // 85% on AC -> Still above 80% -> Discharging remains active
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: false, isOnAC: true))
        #expect(limiter.state.isDischargeActive)

        // 80% on AC -> Reached target limit -> Discharge shuts off (CHIE = 0x00) and Inhibit takes over
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true))
        #expect(!limiter.state.isDischargeActive)
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x00)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func sailingModePreventsMicroCharging() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isSailingEnabled: true,
            sailingDelta: 5,
            smcWriter: mockWriter
        )

        // Initial state at 80% -> Inhibit active (targetUpper reached)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true))
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        // Drifts down to 79%, 78%, 76% (within sailing range 75%..80%) -> Inhibit remains ON
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 79, isCharging: false, isOnAC: true))
        #expect(limiter.state.isInhibited)

        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 76, isCharging: false, isOnAC: true))
        #expect(limiter.state.isInhibited)

        // Drops below sailing floor (< 75%) -> Inhibit turns OFF to recharge back to 80%
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 74, isCharging: true, isOnAC: true))
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)

        // Recharges to 77% -> In hysteresis zone while charging, continues charging (Inhibit remains OFF)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 77, isCharging: true, isOnAC: true))
        #expect(!limiter.state.isInhibited)

        // Reaches 80% again -> Inhibit turns ON again
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true))
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func unplugClearsDischargeImmediately() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isAllowDischargeEnabled: true,
            smcWriter: mockWriter
        )

        // Over limit on AC -> Discharge active
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 92, isCharging: true, isOnAC: true))
        #expect(limiter.state.isDischargeActive)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x08)

        // Unplug AC -> Discharges cleared immediately to 0x00
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 92, isCharging: false, isOnAC: false))
        #expect(!limiter.state.isDischargeActive)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x00)
    }

    @Test func fullCalibrationCycleWalksThroughAllThreeStages() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            smcWriter: mockWriter
        )

        // Start calibration at 70% on AC -> Stage: .topUp, SMC limit set to 100
        limiter.startCalibration(snapshot: PowerSourceSnapshot(percent: 70, isCharging: true, isOnAC: true))
        #expect(limiter.state.calibrationStage == .topUp)
        #expect(!limiter.state.isDischargeActive)
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 100)

        // Reach 100% -> Automatically enters Step 2 (.discharging, CHIE = 0x08)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 100, isCharging: true, isOnAC: true))
        #expect(limiter.state.calibrationStage == .discharging)
        #expect(limiter.state.isDischargeActive)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x08)

        // Battery discharges down to 50%, then 16% -> Still in .discharging
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 50, isCharging: false, isOnAC: true))
        #expect(limiter.state.calibrationStage == .discharging)
        #expect(limiter.state.isDischargeActive)

        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 16, isCharging: false, isOnAC: true))
        #expect(limiter.state.calibrationStage == .discharging)

        // Battery reaches floor (15%) -> Automatically enters Step 3 (.recharging, CHIE = 0x00, limit = 80)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 15, isCharging: true, isOnAC: true))
        #expect(limiter.state.calibrationStage == .recharging)
        #expect(!limiter.state.isDischargeActive)
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x00)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 80)

        // Charges up to 50%, 75% -> Still in .recharging
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 50, isCharging: true, isOnAC: true))
        #expect(limiter.state.calibrationStage == .recharging)

        // Reaches target limit (80%) -> Calibration completes! Returns to .idle, records timestamp, Inhibit becomes active
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true))
        #expect(limiter.state.calibrationStage == .idle)
        #expect(limiter.state.lastCalibrationTimestamp > 0)
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func startCalibrationAlreadyAtHundredStartsDischargingDirectly() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            smcWriter: mockWriter
        )

        limiter.startCalibration(snapshot: PowerSourceSnapshot(percent: 100, isCharging: false, isOnAC: true))
        #expect(limiter.state.calibrationStage == .discharging)
        #expect(limiter.state.isDischargeActive)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x08)
    }

    @Test func cancelCalibrationMidwayRestoresSafetyAndOriginalLimit() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            smcWriter: mockWriter
        )

        limiter.startCalibration(snapshot: PowerSourceSnapshot(percent: 100, isCharging: false, isOnAC: true))
        #expect(limiter.state.calibrationStage == .discharging)
        #expect(limiter.state.isDischargeActive)

        // User clicks cancel
        limiter.cancelCalibration(snapshot: PowerSourceSnapshot(percent: 90, isCharging: false, isOnAC: true))
        #expect(limiter.state.calibrationStage == .idle)
        #expect(!limiter.state.isDischargeActive)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x00)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 80)
    }

    @Test func unpluggingDuringCalibrationCancelsStageAndStopsDischarge() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            smcWriter: mockWriter
        )

        limiter.startCalibration(snapshot: PowerSourceSnapshot(percent: 100, isCharging: false, isOnAC: true))
        #expect(limiter.state.calibrationStage == .discharging)

        // Unplug charger
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 95, isCharging: false, isOnAC: false))
        #expect(limiter.state.calibrationStage == .idle)
        #expect(!limiter.state.isDischargeActive)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x00)
    }

    @Test func thermalGuardInhibitsChargingDuringCalibrationTopUp() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            isGentleChargingEnabled: true,
            smcWriter: mockWriter
        )

        let safeDetails = BatteryDetails(temperatureCelsius: 30.0)
        limiter.startCalibration(snapshot: PowerSourceSnapshot(percent: 50, isCharging: true, isOnAC: true), details: safeDetails)
        #expect(limiter.state.calibrationStage == .topUp)
        #expect(!limiter.state.isInhibited)

        // Cell overheats (34.5°C) -> Thermal guard must pause charging even in calibration
        let hotDetails = BatteryDetails(temperatureCelsius: 34.5)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 55, isCharging: true, isOnAC: true), details: hotDetails)
        #expect(limiter.state.isThermalThrottled)
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        // Cooled down (30.5°C) -> Resumes top-up charging
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 55, isCharging: true, isOnAC: true), details: safeDetails)
        #expect(!limiter.state.isThermalThrottled)
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
    }

    @Test func doesNotFlapOrResetInhibitWhenAppleSiliconCHIEDropsOnACToFalse() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 80, smcWriter: mockWriter)

        // Step 1: 85% on AC (isOnAC: true, isAttachedToAdapter: true) -> Inhibit active, writes CH0I = 1
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        // Step 2: Apple Silicon hardware drops isOnAC to false because CHIE cut off charger input,
        // but adapter is still physically attached (isAttachedToAdapter: true)
        mockWriter.writes.removeAll()
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: false, isOnAC: false, isAttachedToAdapter: true))
        // Must stay inhibited and must NOT call applySMCInhibit(false)
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.writes.isEmpty)

        // Step 3: Physically unplugged from adapter (isOnAC: false, isAttachedToAdapter: false)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: false, isOnAC: false, isAttachedToAdapter: false))
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
    }

    @Test func allowDischargePersistsThroughCHIEOnACDropUntilTargetReachedOrUnplugged() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 80, isAllowDischargeEnabled: true, smcWriter: mockWriter)

        // 85% on AC -> Triggers forced discharge (writes CHIE = 0x08)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isDischargeActive)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x08)

        // Next cycle: Hardware switches power source state to Battery Power (isOnAC: false), but cable is still attached
        mockWriter.writes.removeAll()
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 84, isCharging: false, isOnAC: false, isAttachedToAdapter: true))
        // Discharge must remain active, not cancelled!
        #expect(limiter.state.isDischargeActive)
        #expect(mockWriter.writes.isEmpty)

        // Down to 80% (target reached) -> Discharge stops and transitions to inhibit
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: false, isAttachedToAdapter: true))
        #expect(!limiter.state.isDischargeActive)
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x00)
    }

    @Test func reachesEightyPercentAssertsSMCInhibitDirectly() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 80, smcWriter: mockWriter)

        let holdDetails = BatteryDetails(
            batteryWatts: 0.0,
            amperageMilliamps: 0,
            notChargingReason: 16777216,
            isSystemChargingAllowed: false
        )

        let snap = PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true, isAttachedToAdapter: true)
        limiter.evaluate(snapshot: snap, details: holdDetails)

        // SMC Inhibit asserted directly regardless of macOS hold signal
        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func sailingWatchdogActivatesSMCInhibitWhenMacOSSlowlyChargesPastTarget() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 80, isSailingEnabled: true, sailingDelta: 5, smcWriter: mockWriter)

        // Charging past 80% without native hold signal
        let chargingDetails = BatteryDetails(batteryWatts: 15.0, amperageMilliamps: 1200)
        let snap80 = PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true, isAttachedToAdapter: true)
        limiter.evaluate(snapshot: snap80, details: chargingDetails)

        // Watchdog triggers SMC inhibit
        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        // Draining within sailing zone (78%) -> Inhibit remains on
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 78, isCharging: false, isOnAC: false, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == true)

        // Dips to 75% (lower bound reached) -> Releases inhibit to recharge
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 75, isCharging: false, isOnAC: false, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == false)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
    }

    @Test func unstuckHardwareCHIEWhenReleasingInhibitOrAtSafetyFloor() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 80, smcWriter: mockWriter)

        // Simulate isolated adapter (isOnAC: false, isAttachedToAdapter: true) with percent dropping to safety floor 20%
        let floorSnap = PowerSourceSnapshot(percent: 20, isCharging: false, isOnAC: false, isAttachedToAdapter: true)
        limiter.evaluate(snapshot: floorSnap)

        // Must forcefully release CHIE inhibit
        #expect(limiter.state.isInhibited == false)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
    }

    @Test func testAllowDischargeDoesNotTriggerInhibitSimultaneously() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 60,
            isAllowDischargeEnabled: true,
            smcWriter: mockWriter
        )

        // 80% on AC with 60% limit and allowDischarge = true
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true, isAttachedToAdapter: true))

        #expect(limiter.state.isDischargeActive == true)
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x08)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == nil)
    }

    @Test func testTransitionFromDischargeToInhibitWhenTargetReached() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 60,
            isAllowDischargeEnabled: true,
            smcWriter: mockWriter
        )

        // Step 1: Discharging down from 80%
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isDischargeActive == true)
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x08)

        // Step 2: Drops to exactly target 60%
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isDischargeActive == false)
        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x00)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func testDischargeReassertsWhenHardwareStaysOnAC() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 60,
            isAllowDischargeEnabled: true,
            smcWriter: mockWriter
        )
        limiter.reassertionCooldownSeconds = 0.01

        // First assertion
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isDischargeActive == true)
        let initialWrites = mockWriter.writes.filter { $0.key == BatteryChargeLimiter.chargeDischargeKey }.count
        #expect(initialWrites >= 1)

        // Second evaluation immediately: cooldown has not passed, no extra discharge write
        limiter.reassertionCooldownSeconds = 100.0
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
        let sameWrites = mockWriter.writes.filter { $0.key == BatteryChargeLimiter.chargeDischargeKey }.count
        #expect(sameWrites == initialWrites)

        // Reset cooldown to negative: forces reassertion
        limiter.reassertionCooldownSeconds = -1.0
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
        let afterReassert = mockWriter.writes.filter { $0.key == BatteryChargeLimiter.chargeDischargeKey }.count
        #expect(afterReassert > initialWrites)
    }

    @Test func testThermalCollisionCancelsDischargeAndInhibitsSafely() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 60,
            isAllowDischargeEnabled: true,
            smcWriter: mockWriter
        )

        // 1. Initially discharging (70% on AC with limit 60%, allow discharge enabled)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 70, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isDischargeActive == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0x08)

        // 2. Overheating occurs (35.0 C >= 34.0 C threshold)
        let hotDetails = BatteryDetails(
            cycleCount: 50,
            temperatureCelsius: 35.0
        )
        limiter.evaluate(
            snapshot: PowerSourceSnapshot(percent: 70, isCharging: false, isOnAC: true, isAttachedToAdapter: true),
            details: hotDetails
        )

        // 3. Discharge MUST be cancelled, inhibit MUST be engaged, CHIE MUST be cleared to 0
        #expect(limiter.state.isThermalThrottled == true)
        #expect(limiter.state.isDischargeActive == false)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0)
        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func testThermalThrottlePreventsDischargeActivation() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 60,
            isAllowDischargeEnabled: true,
            smcWriter: mockWriter
        )

        let hotDetails = BatteryDetails(
            cycleCount: 50,
            temperatureCelsius: 36.0
        )

        limiter.evaluate(
            snapshot: PowerSourceSnapshot(percent: 75, isCharging: true, isOnAC: true, isAttachedToAdapter: true),
            details: hotDetails
        )

        #expect(limiter.state.isThermalThrottled == true)
        #expect(limiter.state.isDischargeActive == false)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) != 0x08)
        #expect(limiter.state.isInhibited == true)
    }

    @Test func testReleaseHardwareOnTerminationClearsAllSMCRegisters() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 60,
            isAllowDischargeEnabled: true,
            smcWriter: mockWriter
        )

        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 70, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isDischargeActive == true)

        limiter.releaseHardwareOnTermination()

        #expect(limiter.state.isDischargeActive == false)
        #expect(limiter.state.isInhibited == false)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) == 0)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 100)
    }

    @Test func testDischargeDesyncHandledWhenSMCWriteFails() {
        let mockWriter = MockSMCWriter()
        mockWriter.shouldFailKeys.insert(BatteryChargeLimiter.chargeDischargeKey)

        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 60,
            isAllowDischargeEnabled: true,
            smcWriter: mockWriter
        )

        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 70, isCharging: true, isOnAC: true, isAttachedToAdapter: true))

        // When SMC write fails, state.isDischargeActive must NOT be set to true
        #expect(limiter.state.isDischargeActive == false)
    }

    @Test func testStartCalibrationResetsIsInhibitedFlag() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            smcWriter: mockWriter
        )

        // Force inhibit first
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == true)

        // Starting calibration at <100% enters .topUp phase and resets isInhibited
        limiter.startCalibration(snapshot: PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.calibrationStage == .topUp)
        #expect(limiter.state.isInhibited == false)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)

        // Transition from .topUp to .discharging at 100%
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 100, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.calibrationStage == .discharging)
        #expect(limiter.state.isInhibited == false)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)
    }

    @Test func limit60_inhibitsAtTarget() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 60, smcWriter: mockWriter)
        let chargingDetails = BatteryDetails(batteryWatts: 15.0, amperageMilliamps: 1200)

        limiter.evaluate(
            snapshot: PowerSourceSnapshot(percent: 60, isCharging: true, isOnAC: true, isAttachedToAdapter: true),
            details: chargingDetails
        )

        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func limit60_ignoresNativeHoldSignalBelow80() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 60, smcWriter: mockWriter)
        let holdDetails = BatteryDetails(
            batteryWatts: 0.0,
            amperageMilliamps: 0,
            notChargingReason: 16777216,
            isSystemChargingAllowed: false
        )

        limiter.evaluate(
            snapshot: PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: true, isAttachedToAdapter: true),
            details: holdDetails
        )

        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func selfInhibitNotReleasedByHoldSignal() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 60, smcWriter: mockWriter)

        // Tick 1: Limit 60 reached while charging -> Inhibit must activate
        let chargingDetails = BatteryDetails(batteryWatts: 12.0, amperageMilliamps: 1000)
        limiter.evaluate(
            snapshot: PowerSourceSnapshot(percent: 60, isCharging: true, isOnAC: true, isAttachedToAdapter: true),
            details: chargingDetails
        )
        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        // Tick 2: Next tick PMU responds with not-charging hold signal.
        // It must NOT un-inhibit itself!
        mockWriter.writes.removeAll()
        let holdDetails = BatteryDetails(
            batteryWatts: 0.0,
            amperageMilliamps: 0,
            notChargingReason: 16777216,
            isSystemChargingAllowed: false
        )
        limiter.evaluate(
            snapshot: PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: true, isAttachedToAdapter: true),
            details: holdDetails
        )
        #expect(limiter.state.isInhibited == true)
        // Must not have written 0 (un-inhibit)
        #expect(mockWriter.writes.isEmpty)
    }

    @Test func rawCapacityTriggersInhibitBeforeRoundedPercent() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 60, smcWriter: mockWriter)

        // 3000 / 5000 = 60.0%, but rounded snapshot percent is still 59%
        let details = BatteryDetails(
            batteryWatts: 15.0,
            amperageMilliamps: 1200,
            maxCapacityMah: 5000,
            currentCapacityMah: 3000
        )
        limiter.evaluate(
            snapshot: PowerSourceSnapshot(percent: 59, isCharging: true, isOnAC: true, isAttachedToAdapter: true),
            details: details
        )

        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func rawCapacityIgnoredWhenValuesArePercent() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 60, isSailingEnabled: true, sailingDelta: 2, smcWriter: mockWriter)

        // On some Macs, current and max are reported as <= 100 (percentage), not raw mAh
        let details = BatteryDetails(
            batteryWatts: 15.0,
            amperageMilliamps: 1200,
            maxCapacityMah: 100,
            currentCapacityMah: 60
        )
        limiter.evaluate(
            snapshot: PowerSourceSnapshot(percent: 55, isCharging: true, isOnAC: true, isAttachedToAdapter: true),
            details: details
        )

        // Should NOT trigger early inhibit based on 60/100 because maxCapacity <= 100
        #expect(limiter.state.isInhibited == false)
        #expect(mockWriter.writes.isEmpty)
    }

    @Test func hardwareFailureRollsBackIsInhibitedStateAndAllowsRetry() async {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 60, smcWriter: mockWriter)

        // Snapshot triggers inhibit
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 60, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == true)

        // Hardware asynchronously reports failure
        mockWriter.onInhibitStateChanged?(false)

        // Allow MainActor Task in callback to complete
        await Task.yield()

        // State is rolled back to false
        #expect(limiter.state.isInhibited == false)

        // Next evaluation retry works because isInhibited is false
        mockWriter.writes.removeAll()
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 60, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    // MARK: - Sailing Wide Range (60% - 80%) Tests (Phase A)

    @Test func sailingModeWideRangeDelta20Hysteresis() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isSailingEnabled: true,
            sailingDelta: 20,
            smcWriter: mockWriter
        )

        // 1. Initial state at 80% -> Reaches upper limit, Inhibit turns ON
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)

        // 2. Drifts down within sailing zone (79%, 75%, 70%, 65%, 61%) -> Inhibit remains ON
        for pct in [79, 75, 70, 65, 61] {
            limiter.evaluate(snapshot: PowerSourceSnapshot(percent: pct, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
            #expect(limiter.state.isInhibited, "Inhibit must remain ON at \(pct)%")
        }

        // 3. Drops to targetLower (60% = 80 - 20) -> Inhibit turns OFF to recharge back to 80%
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 60, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(!limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)

        // 4. Recharging through 65%, 70%, 75% -> Continues charging in hysteresis zone
        for pct in [65, 70, 75] {
            limiter.evaluate(snapshot: PowerSourceSnapshot(percent: pct, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
            #expect(!limiter.state.isInhibited, "Inhibit must remain OFF while recharging at \(pct)%")
        }

        // 5. Reaches 80% again -> Inhibit turns ON again
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func sailingDeltaClampUpTo20() {
        let limiter = BatteryChargeLimiter(isLimitEnabled: true, chargeLimit: 80)

        // Delta 25 should clamp to 20
        limiter.setSailingEnabled(true, delta: 25)
        #expect(limiter.state.sailingDelta == 20)

        // Delta 1 should clamp to 2
        limiter.setSailingEnabled(true, delta: 1)
        #expect(limiter.state.sailingDelta == 2)

        // Delta 15 should stay 15
        limiter.setSailingEnabled(true, delta: 15)
        #expect(limiter.state.sailingDelta == 15)
    }

    @Test func sailingDelta20AssertsSMCInhibitDirectly() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isSailingEnabled: true,
            sailingDelta: 20,
            smcWriter: mockWriter
        )

        let details = BatteryDetails(
            batteryWatts: 0.0,
            amperageMilliamps: 0,
            notChargingReason: 16777216,
            isSystemChargingAllowed: false
        )

        // Snapshot at 80% with native hold signal -> Directly asserts SMC Inhibit
        limiter.evaluate(
            snapshot: PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true, isAttachedToAdapter: true),
            details: details
        )
        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func sailingWideRangeNeverWritesCHIE0x08WhenAllowDischargeDisabled() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isSailingEnabled: true,
            sailingDelta: 20,
            smcWriter: mockWriter
        )
        limiter.setAllowDischargeEnabled(false)

        // Across all levels in sailing range (60..80%), force discharge must never be called
        for pct in [80, 78, 75, 70, 65, 61, 60] {
            limiter.evaluate(snapshot: PowerSourceSnapshot(percent: pct, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
            #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeDischargeKey) != 0x08)
            #expect(!limiter.state.isDischargeActive)
        }
    }

    @Test func sailingWriterReturnsFalseMaintainsSafeState() {
        let failingWriter = MockSMCWriter()
        failingWriter.shouldFailKeys.insert(BatteryChargeLimiter.chargeInhibitKey)

        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isSailingEnabled: true,
            sailingDelta: 20,
            smcWriter: failingWriter
        )

        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        // Since writer returned false, state.isInhibited must stay false
        #expect(limiter.state.isInhibited == false)
        #expect(limiter.state.isDischargeActive == false)
    }

    @Test func pluggedInWithinSailingWindowInhibitsImmediately() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isSailingEnabled: true,
            sailingDelta: 20,
            smcWriter: mockWriter
        )

        // Plugged in at 70% within sailing window (60..80%)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 70, isCharging: false, isOnAC: true, isAttachedToAdapter: true))

        // Must inhibit immediately instead of charging up to 80%
        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func handleWakeTriggersImmediateReassertion() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isSailingEnabled: true,
            sailingDelta: 20,
            smcWriter: mockWriter
        )

        // Tick 1: active at 75%
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 75, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == true)
        mockWriter.writes.removeAll()

        // Wake occurs
        limiter.handleWake()

        // Evaluate immediately without charging signal
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 75, isCharging: false, isOnAC: true, isAttachedToAdapter: true))

        // Force reassertion must have fired
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func sailingRechargesOnlyWhenAtOrBelowFloor() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isSailingEnabled: true,
            sailingDelta: 20,
            smcWriter: mockWriter
        )

        // 1. Inhibit engaged at 75%
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 75, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == true)

        // 2. Drifts down to 65%, 61% -> Still inhibited
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 61, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == true)

        // 3. Dips to 60% (floor) -> Releases inhibit to recharge
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 60, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == false)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 0)

        // 4. Recharges to 65%, 75% -> Continues recharging (does not inhibit early)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 75, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == false)

        // 5. Hits 80% -> Inhibits again!
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func unpluggingAndRepluggingInSailingWindowInhibitsImmediately() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isSailingEnabled: true,
            sailingDelta: 20,
            smcWriter: mockWriter
        )

        // 1. Unplugged on battery
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 65, isCharging: false, isOnAC: false, isAttachedToAdapter: false))
        #expect(limiter.state.isInhibited == false)

        // 2. Re-plugged at 65% in sailing range
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 65, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func writerFailurePreservesForceReassertFlagForSubsequentRetry() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            isSailingEnabled: true,
            sailingDelta: 20,
            smcWriter: mockWriter
        )

        // 1. Fail inhibit write
        mockWriter.shouldFailKeys.insert(BatteryChargeLimiter.chargeInhibitKey)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 78, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == false)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == nil)

        // 2. Writer recovers; next evaluation re-asserts because forceReassertOnNextEvaluation was preserved
        mockWriter.shouldFailKeys.remove(BatteryChargeLimiter.chargeInhibitKey)
        limiter.evaluate(snapshot: PowerSourceSnapshot(percent: 78, isCharging: false, isOnAC: true, isAttachedToAdapter: true))
        #expect(limiter.state.isInhibited == true)
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeInhibitKey) == 1)
    }

    @Test func handleWakeReassertsChargeLimitImmediately() {
        let mockWriter = MockSMCWriter()
        let limiter = BatteryChargeLimiter(
            isLimitEnabled: true,
            chargeLimit: 80,
            smcWriter: mockWriter
        )

        mockWriter.writes.removeAll()
        limiter.handleWake()
        #expect(mockWriter.lastValue(for: BatteryChargeLimiter.chargeLimitMaxKey) == 80)
    }
}
