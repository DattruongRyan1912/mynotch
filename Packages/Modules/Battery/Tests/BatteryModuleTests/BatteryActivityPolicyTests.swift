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
    }
}
