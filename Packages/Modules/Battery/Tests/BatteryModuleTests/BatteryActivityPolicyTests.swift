import Testing
@testable import BatteryModule

@Suite struct BatteryActivityPolicyTests {
    let policy = BatteryActivityPolicy(lowThreshold: 20, notifyOnCharge: true)

    func onBattery(_ percent: Int) -> PowerSourceSnapshot { PowerSourceSnapshot(percent: percent, isCharging: false, isOnAC: false) }
    func onAC(_ percent: Int) -> PowerSourceSnapshot { PowerSourceSnapshot(percent: percent, isCharging: true, isOnAC: true) }

    @Test func pluggingInShowsChargingOnlyOnTransition() {
        #expect(policy.decide(previous: onBattery(50), current: onAC(50), lowActive: false).showCharging)
        #expect(!policy.decide(previous: onAC(50), current: onAC(51), lowActive: false).showCharging)
        #expect(!policy.decide(previous: nil, current: onAC(50), lowActive: false).showCharging)
        #expect(!policy.decide(previous: onAC(50), current: onBattery(50), lowActive: false).showCharging)
        let heldAtLimit = PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true)
        #expect(policy.decide(previous: onBattery(80), current: heldAtLimit, lowActive: false).showCharging)
    }

    @Test func chargingNotificationCanBeDisabled() {
        let quiet = BatteryActivityPolicy(lowThreshold: 20, notifyOnCharge: false)
        #expect(!quiet.decide(previous: onBattery(50), current: onAC(50), lowActive: false).showCharging)
    }

    @Test func lowBatteryUsesThresholdAndHysteresis() {
        #expect(policy.decide(previous: nil, current: onBattery(20), lowActive: false).lowActive)
        #expect(!policy.decide(previous: nil, current: onBattery(21), lowActive: false).lowActive)
        #expect(policy.decide(previous: nil, current: onBattery(25), lowActive: true).lowActive)
        #expect(!policy.decide(previous: nil, current: onBattery(26), lowActive: true).lowActive)
        #expect(!policy.decide(previous: nil, current: onAC(10), lowActive: true).lowActive)
        let pluggedButDraining = PowerSourceSnapshot(percent: 10, isCharging: false, isOnAC: true)
        #expect(!policy.decide(previous: nil, current: pluggedButDraining, lowActive: true).lowActive)
    }

    @Test func loweringTheThresholdDismissesLowInsideTheBand() {
        let lowered = BatteryActivityPolicy(lowThreshold: 15, notifyOnCharge: true)
        #expect(!lowered.decide(previous: nil, current: onBattery(18), lowActive: true, previousThreshold: 20).lowActive)
        #expect(lowered.decide(previous: nil, current: onBattery(18), lowActive: true, previousThreshold: 15).lowActive)
        #expect(lowered.decide(previous: nil, current: onBattery(12), lowActive: true, previousThreshold: 20).lowActive)
    }
}
