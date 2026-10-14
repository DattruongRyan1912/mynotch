import Foundation
import Testing
@testable import BatteryModule

@Suite struct BatteryDetailsParserTests {
    /// Shaped like the AppleSmartBattery registry entry, with synthetic numbers.
    private func entry(_ overrides: [String: Any?] = [:]) -> [String: Any] {
        var entry: [String: Any] = [
            "CycleCount": 312,
            "DesignCapacity": 6000,
            "AppleRawMaxCapacity": 5520,
            "NominalChargeCapacity": 5400,
            "MaxCapacity": 100,
            "Voltage": 12000,
            "Amperage": 1000,
            "InstantAmperage": 1100,
            "AdapterDetails": ["Watts": 96, "Current": 4700, "AdapterVoltage": 20000],
        ]
        for (key, value) in overrides { entry[key] = value }
        return entry
    }

    @Test func parsesATypicalEntry() {
        #expect(BatteryDetailsParser.parse(entry()) == BatteryDetails(cycleCount: 312, healthPercent: 92, batteryWatts: 12, adapterWatts: 96))
    }

    @Test func parsesValuesBridgedFromTheRegistry() {
        let bridged = BatteryDetailsParser.parse([
            "CycleCount": NSNumber(value: 40), "DesignCapacity": NSNumber(value: 5000), "AppleRawMaxCapacity": NSNumber(value: 4500),
            "Voltage": NSNumber(value: 11000), "Amperage": NSNumber(value: -2000),
            "AdapterDetails": ["Watts": NSNumber(value: 67)] as NSDictionary,
        ])
        #expect(bridged == BatteryDetails(cycleCount: 40, healthPercent: 90, batteryWatts: -22, adapterWatts: 67))
    }

    @Test func anEmptyOrUnrelatedEntryHasNoDetails() {
        #expect(BatteryDetailsParser.parse([:]) == BatteryDetails())
        #expect(BatteryDetailsParser.parse(["Serial": "x", "IsCharging": true]) == BatteryDetails())
    }

    // MARK: Maximum capacity

    @Test func healthIsMaximumOverDesignCapacityRoundedAndClamped() {
        #expect(BatteryDetailsParser.parse(entry(["AppleRawMaxCapacity": 5969])).healthPercent == 99)
        #expect(BatteryDetailsParser.parse(entry(["AppleRawMaxCapacity": 5970])).healthPercent == 100)
        #expect(BatteryDetailsParser.parse(entry(["AppleRawMaxCapacity": 6100])).healthPercent == 100)
        #expect(BatteryDetailsParser.parse(entry(["AppleRawMaxCapacity": 3000])).healthPercent == 50)
    }

    @Test func healthFallsBackToTheNominalCapacityWhenTheRawOneIsMissingOrEmpty() {
        #expect(BatteryDetailsParser.parse(entry(["AppleRawMaxCapacity": nil])).healthPercent == 90)
        #expect(BatteryDetailsParser.parse(entry(["AppleRawMaxCapacity": 0])).healthPercent == 90)
        #expect(BatteryDetailsParser.parse(entry(["AppleRawMaxCapacity": "5520"])).healthPercent == 90)
    }

    @Test func maxCapacityCountsOnlyWhenItIsInMilliampHours() {
        let withoutRawOrNominal: [String: Any?] = ["AppleRawMaxCapacity": nil, "NominalChargeCapacity": nil]
        // 100 is the percent some Macs report in this key: it says nothing about health.
        #expect(BatteryDetailsParser.parse(entry(withoutRawOrNominal.merging(["MaxCapacity": 100]) { $1 })).healthPercent == nil)
        #expect(BatteryDetailsParser.parse(entry(withoutRawOrNominal.merging(["MaxCapacity": 87]) { $1 })).healthPercent == nil)
        #expect(BatteryDetailsParser.parse(entry(withoutRawOrNominal.merging(["MaxCapacity": 5400]) { $1 })).healthPercent == 90)
    }

    @Test func healthNeedsADesignCapacity() {
        #expect(BatteryDetailsParser.parse(entry(["DesignCapacity": nil])).healthPercent == nil)
        #expect(BatteryDetailsParser.parse(entry(["DesignCapacity": 0])).healthPercent == nil)
        #expect(BatteryDetailsParser.parse(entry(["DesignCapacity": -6000])).healthPercent == nil)
    }

    // MARK: Cycles

    @Test func cyclesMayBeZeroButNeverNegative() {
        #expect(BatteryDetailsParser.parse(entry(["CycleCount": 0])).cycleCount == 0)
        #expect(BatteryDetailsParser.parse(entry(["CycleCount": -1])).cycleCount == nil)
        #expect(BatteryDetailsParser.parse(entry(["CycleCount": nil])).cycleCount == nil)
    }

    // MARK: Power

    @Test func powerIsVoltageTimesCurrentAndKeepsItsSign() {
        #expect(BatteryDetailsParser.parse(entry(["Voltage": 12000, "Amperage": 1500])).batteryWatts == 18)
        #expect(BatteryDetailsParser.parse(entry(["Voltage": 12000, "Amperage": -1500])).batteryWatts == -18)
        #expect(BatteryDetailsParser.parse(entry(["Voltage": 11000, "Amperage": 50])).batteryWatts == 0.55)
        #expect(BatteryDetailsParser.parse(entry(["Amperage": 0])).batteryWatts == 0)
    }

    @Test func aNegativeCurrentReportedAsAnUnsignedWrapAroundIsStillNegative() {
        let wrapped = UInt64.max - 1499   // -1500 as 64 bits
        #expect(BatteryDetailsParser.parse(entry(["Voltage": 12000, "Amperage": wrapped])).batteryWatts == -18)
        #expect(BatteryDetailsParser.parse(entry(["Voltage": 12000, "Amperage": NSNumber(value: wrapped)])).batteryWatts == -18)
    }

    @Test func theInstantCurrentIsUsedWhenTheOrdinaryOneIsMissing() {
        #expect(BatteryDetailsParser.parse(entry(["Amperage": nil, "InstantAmperage": 2000])).batteryWatts == 24)
        #expect(BatteryDetailsParser.parse(entry(["Amperage": nil, "InstantAmperage": nil])).batteryWatts == nil)
    }

    @Test func powerNeedsAPlausibleVoltageAndCurrent() {
        #expect(BatteryDetailsParser.parse(entry(["Voltage": nil])).batteryWatts == nil)
        #expect(BatteryDetailsParser.parse(entry(["Voltage": 0])).batteryWatts == nil)
        // Volts instead of millivolts: scaling it would be off by a factor of 1000.
        #expect(BatteryDetailsParser.parse(entry(["Voltage": 12])).batteryWatts == nil)
        #expect(BatteryDetailsParser.parse(entry(["Voltage": 12_000_000])).batteryWatts == nil)
        #expect(BatteryDetailsParser.parse(entry(["Amperage": 5_000_000])).batteryWatts == nil)
    }

    // MARK: Adapter

    @Test func adapterWattsComeFromTheAdapterDetails() {
        #expect(BatteryDetailsParser.parse(entry(["AdapterDetails": ["Watts": 140]])).adapterWatts == 140)
        #expect(BatteryDetailsParser.parse(entry(["AdapterDetails": ["Current": 4700]])).adapterWatts == nil)
        #expect(BatteryDetailsParser.parse(entry(["AdapterDetails": ["Watts": 0]])).adapterWatts == nil)
        #expect(BatteryDetailsParser.parse(entry(["AdapterDetails": nil])).adapterWatts == nil)
    }

    @Test func adapterDetailsOfTheWrongTypeAreIgnored() {
        #expect(BatteryDetailsParser.parse(entry(["AdapterDetails": [["Watts": 96]]])).adapterWatts == nil)
        #expect(BatteryDetailsParser.parse(entry(["AdapterDetails": "96 W"])).adapterWatts == nil)
        #expect(BatteryDetailsParser.parse(entry(["AdapterDetails": ["Watts": "96"]])).adapterWatts == nil)
    }

    // MARK: Odd values

    @Test func valuesOfTheWrongTypeAreIgnored() {
        let odd = BatteryDetailsParser.parse([
            "CycleCount": "312", "DesignCapacity": true, "AppleRawMaxCapacity": [5520],
            "Voltage": 12.5, "Amperage": "1000", "AdapterDetails": ["Watts": true],
        ])
        #expect(odd == BatteryDetails())
    }
}
