import Foundation
import Testing
@testable import BatteryModule

@Suite struct PowerSourceParserTests {
    @Test func parsesInternalBattery() {
        let snapshot = PowerSourceParser.parse([[
            "Type": "InternalBattery",
            "Current Capacity": 41, "Max Capacity": 50,
            "Is Charging": true, "Power Source State": "AC Power",
            "Time to Empty": -1, "Time to Full Charge": 35,
        ]])
        #expect(snapshot == PowerSourceSnapshot(percent: 82, isCharging: true, isOnAC: true, minutesToEmpty: nil, minutesToFull: 35))
    }

    @Test func returnsNilWithoutInternalBattery() {
        #expect(PowerSourceParser.parse([]) == nil)
        #expect(PowerSourceParser.parse([["Type": "UPS", "Current Capacity": 10, "Max Capacity": 100]]) == nil)
    }

    @Test func chargeLimitOnACHasNoTimes() {
        let snapshot = PowerSourceParser.parse([[
            "Type": "InternalBattery",
            "Current Capacity": NSNumber(value: 80), "Max Capacity": NSNumber(value: 100),
            "Is Charging": kCFBooleanFalse as Any, "Power Source State": "AC Power",
            "Time to Empty": NSNumber(value: 0), "Time to Full Charge": NSNumber(value: 0),
        ]])
        #expect(snapshot == PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true, minutesToEmpty: nil, minutesToFull: nil))
    }

    @Test func onBatteryReportsTimeToEmptyFromBridgedValues() {
        let snapshot = PowerSourceParser.parse([
            ["Type": "UPS", "Current Capacity": NSNumber(value: 10), "Max Capacity": NSNumber(value: 100)],
            ["Type": "InternalBattery", "Current Capacity": NSNumber(value: 55), "Max Capacity": NSNumber(value: 100),
             "Is Charging": kCFBooleanFalse as Any, "Power Source State": "Battery Power",
             "Time to Empty": NSNumber(value: 190), "Time to Full Charge": NSNumber(value: 0)],
        ])
        #expect(snapshot == PowerSourceSnapshot(percent: 55, isCharging: false, isOnAC: false, minutesToEmpty: 190, minutesToFull: nil))
    }

    @Test func invalidCapacitiesAreRejectedOrClamped() {
        #expect(PowerSourceParser.parse([["Type": "InternalBattery", "Current Capacity": 10, "Max Capacity": 0]]) == nil)
        #expect(PowerSourceParser.parse([["Type": "InternalBattery", "Current Capacity": 110, "Max Capacity": 100]])?.percent == 100)
    }
}
