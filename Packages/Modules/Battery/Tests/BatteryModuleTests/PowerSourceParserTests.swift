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
}
