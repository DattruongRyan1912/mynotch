import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import BatteryModule

@Suite struct BatteryStudioIntegrationTests {
    @Test func testStudioStatusReflectsPowerAndDetails() async {
        let snapshot = PowerSourceSnapshot(percent: 82, isCharging: true, isOnAC: true)
        let details = BatteryDetails(
            cycleCount: 120,
            healthPercent: 96,
            batteryWatts: 18.6,
            temperatureCelsius: 31.8,
            voltageMillivolts: 12450,
            amperageMilliamps: 1500
        )
        let reader = FakePowerSource(snapshot, details: details)
        let module = BatteryModule(reader: reader)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        let status = module.studioStatus()
        #expect(status.percent == 82)
        #expect(status.isOnAC == true)
        #expect(status.isCharging == true)
        #expect(status.tempCelsius == 31.8)
        #expect(status.batteryWatts == 18.6)
        #expect(status.healthPercent == 96)
        #expect(status.cycleCount == 120)
    }

    @Test("Contract Test 1: Force Discharge Toggle Does Not Revert When Battery Below Threshold")
    func testForceDischargeToggleDoesNotRevertWhenBatteryBelowThreshold() async {
        // Battery at 75%, on AC, limit is 80% (battery <= limit)
        let snapshot = PowerSourceSnapshot(percent: 75, isCharging: true, isOnAC: true)
        let reader = FakePowerSource(snapshot)
        let module = BatteryModule(reader: reader)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // By default, allowDischarge is true in Settings, but hardware discharge is inactive because 75 <= 80
        let status1 = module.studioStatus()
        #expect(status1.isAllowDischargeEnabled == true)
        #expect(status1.isDischargeActive == false)

        // Toggle to false
        module.toggleAllowDischarge()
        let status2 = module.studioStatus()
        #expect(status2.isAllowDischargeEnabled == false)
        #expect(status2.isDischargeActive == false)

        // Toggle back to true -> Must remain enabled and limiter must be enabled
        module.toggleAllowDischarge()
        let status3 = module.studioStatus()
        #expect(status3.isAllowDischargeEnabled == true)
        #expect(status3.isLimitToEightyEnabled == true)
        #expect(status3.isDischargeActive == false) // Still false until battery > limit
    }

    @Test("Contract Test 2: Hardware Discharge Active When Battery Above Limit on AC")
    func testHardwareDischargeActiveWhenBatteryAboveLimitOnAC() async {
        // Battery at 90%, on AC, limit is 80%
        let snapshot = PowerSourceSnapshot(percent: 90, isCharging: true, isOnAC: true)
        let reader = FakePowerSource(snapshot)
        let module = BatteryModule(reader: reader)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // Enable allow discharge
        module.setAllowDischarge(true)
        let status = module.studioStatus()
        #expect(status.isAllowDischargeEnabled == true)
        #expect(status.isLimitToEightyEnabled == true)
        #expect(status.isDischargeActive == true) // Hardware discharge is now active!
    }

    @Test("Contract Test 3: setChargeLimit Automatically Controls Limiter")
    func testSetChargeLimitAutomaticallyControlsLimiter() async {
        let snapshot = PowerSourceSnapshot(percent: 70, isCharging: true, isOnAC: true)
        let reader = FakePowerSource(snapshot)
        let module = BatteryModule(reader: reader)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // Setting limit < 100 automatically enables limiter
        module.setChargeLimit(60)
        let status60 = module.studioStatus()
        #expect(status60.chargeLimit == 60)
        #expect(status60.isLimitToEightyEnabled == true)

        // Setting limit == 100 automatically disables limiter
        module.setChargeLimit(100)
        let status100 = module.studioStatus()
        #expect(status100.chargeLimit == 100)
        #expect(status100.isLimitToEightyEnabled == false)
    }

    @Test func testChargeLimitAndTogglesControlState() async {
        let snapshot = PowerSourceSnapshot(percent: 70, isCharging: true, isOnAC: true)
        let reader = FakePowerSource(snapshot)
        let module = BatteryModule(reader: reader)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // Test Gentle Charging / Heat Protection
        #expect(module.studioStatus().isHeatProtectionEnabled == true)
        module.toggleGentleCharging()
        #expect(module.studioStatus().isHeatProtectionEnabled == false)
        module.toggleGentleCharging()
        #expect(module.studioStatus().isHeatProtectionEnabled == true)

        // Test Sailing Mode
        #expect(module.studioStatus().isSailingEnabled == true)
        module.toggleSailing()
        #expect(module.studioStatus().isSailingEnabled == false)
        module.toggleSailing()
        #expect(module.studioStatus().isSailingEnabled == true)

        // Test Top Up Once
        #expect(module.studioStatus().isTopUpActive == false)
        module.toggleTopUpOnce()
        #expect(module.studioStatus().isTopUpActive == true)

        // Test Calibration Stage
        #expect(module.studioStatus().isCalibrationActive == false)
        module.startCalibration()
        #expect(module.studioStatus().isCalibrationActive == true)
        module.cancelCalibration()
        #expect(module.studioStatus().isCalibrationActive == false)
    }

    @Test func testScheduleEngineApplicationToBatteryModule() async {
        let snapshot = PowerSourceSnapshot(percent: 85, isCharging: true, isOnAC: true)
        let reader = FakePowerSource(snapshot)
        let module = BatteryModule(reader: reader)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // Apply chargeLimit action
        module.scheduleEngine.apply(action: .chargeLimit(75), to: module)
        let status1 = module.studioStatus()
        #expect(status1.chargeLimit == 75)
        #expect(status1.isAllowDischargeEnabled == false)

        // Apply forceDischarge action
        module.scheduleEngine.apply(action: .forceDischarge(target: 65), to: module)
        let status2 = module.studioStatus()
        #expect(status2.chargeLimit == 65)
        #expect(status2.isAllowDischargeEnabled == true)

        // Apply sailing action
        module.scheduleEngine.apply(action: .sailing(lower: 70, upper: 80), to: module)
        let status3 = module.studioStatus()
        #expect(status3.chargeLimit == 80)
        #expect(status3.isSailingEnabled == true)
    }

    @Test func testScheduleBackgroundPollTimerAdvancesAndRefreshes() async {
        let snapshot = PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true)
        let reader = FakePowerSource(snapshot)
        let isolatedDefaults = makeIsolatedDefaults()
        let engine = BatteryScheduleEngine(userDefaults: isolatedDefaults)
        let module = BatteryModule(reader: reader, scheduleEngine: engine)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // Enabling schedule starts background polling guard
        module.setScheduleEnabled(true)
        #expect(module.scheduleEngine.isEnabled == true)

        // Advancing scheduler triggers poll cycle
        await harness.scheduler.advance(by: .seconds(15))
        let status = module.studioStatus()
        #expect(status.isScheduleEnabled == true)
    }
}
