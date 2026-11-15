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
            "BatteryData": ["FccComp1": 5580, "FccComp2": 5520, "CycleCount": 312, "DesignCapacity": 6000, "MaxCapacity": 100],
            "Voltage": 12000,
            "Amperage": 1000,
            "InstantAmperage": 1100,
            "AdapterDetails": ["Watts": 96, "Current": 4700, "AdapterVoltage": 20000],
        ]
        for (key, value) in overrides {
            entry[key] = value
            if var bdata = entry["BatteryData"] as? [String: Any], bdata[key] != nil {
                bdata[key] = value
                entry["BatteryData"] = bdata
            }
        }
        return entry
    }

    @Test func parsesATypicalEntry() {
        #expect(BatteryDetailsParser.parse(entry()) == BatteryDetails(
            cycleCount: 312, healthPercent: 93, batteryWatts: 12, adapterWatts: 96,
            voltageMillivolts: 12000, amperageMilliamps: 1000,
            designCapacityMah: 6000, maxCapacityMah: 5580
        ))
    }

    @Test func parsesValuesBridgedFromTheRegistry() {
        let bridged = BatteryDetailsParser.parse([
            "CycleCount": NSNumber(value: 40), "DesignCapacity": NSNumber(value: 5000), "AppleRawMaxCapacity": NSNumber(value: 4500),
            "Voltage": NSNumber(value: 11000), "Amperage": NSNumber(value: -2000),
            "AdapterDetails": ["Watts": NSNumber(value: 67)] as NSDictionary,
        ])
        #expect(bridged == BatteryDetails(
            cycleCount: 40, healthPercent: 90, batteryWatts: -22, adapterWatts: 67,
            voltageMillivolts: 11000, amperageMilliamps: -2000,
            designCapacityMah: 5000, maxCapacityMah: 4500
        ))
    }

    @Test func anEmptyOrUnrelatedEntryHasNoDetails() {
        #expect(BatteryDetailsParser.parse([:]) == BatteryDetails())
        #expect(BatteryDetailsParser.parse(["Serial": "x", "IsCharging": true]) == BatteryDetails())
    }

    @Test func parsesTemperature() {
        #expect(BatteryDetailsParser.parse(["Temperature": 30515]).temperatureCelsius == 32.0)
        #expect(BatteryDetailsParser.parse(["Temperature": 3150]).temperatureCelsius == 31.5)
        #expect(BatteryDetailsParser.parse(["Temperature": 28]).temperatureCelsius == 28.0)
        #expect(BatteryDetailsParser.parse(["Temperature": -500]).temperatureCelsius == nil)
    }

    @Test func parsesSystemWattsAndAdapterInputWatts() {
        let withPowerData: [String: Any] = [
            "PowerTelemetryData": ["SystemPowerIn": 45506],
            "PowerDistribution": ["IPDInputPower": 89200]
        ]
        let details = BatteryDetailsParser.parse(withPowerData)
        #expect(details.systemWatts == 45.5)
        #expect(details.adapterInputWatts == 89.2)
    }

    @Test func ignoresZeroOrMalformedPowerDistributionData() {
        let zeroData: [String: Any] = [
            "PowerTelemetryData": ["SystemPowerIn": 500],
            "PowerDistribution": ["IPDInputPower": 0]
        ]
        let details = BatteryDetailsParser.parse(zeroData)
        #expect(details.systemWatts == nil)
        #expect(details.adapterInputWatts == nil)
    }

    @Test func parsesNativeHoldAndChargerDataFields() {
        let holdData: [String: Any] = [
            "ChargerData": ["NotChargingReason": 16777216],
            "PowerDistribution": ["IPDChargingAllowed": 0],
            "Voltage": 12000,
            "Amperage": 0
        ]
        let details = BatteryDetailsParser.parse(holdData)
        #expect(details.notChargingReason == 16777216)
        #expect(details.isSystemChargingAllowed == false)
        #expect(details.isNativeChargeHoldActive == true)

        let chargingData: [String: Any] = [
            "ChargerData": ["NotChargingReason": 0],
            "PowerDistribution": ["IPDChargingAllowed": 1],
            "Voltage": 12000,
            "Amperage": 2000
        ]
        let chargingDetails = BatteryDetailsParser.parse(chargingData)
        #expect(chargingDetails.notChargingReason == 0)
        #expect(chargingDetails.isSystemChargingAllowed == true)
        #expect(chargingDetails.isNativeChargeHoldActive == false)
    }

    // MARK: Maximum capacity

    /// Numbers of a Mac whose Battery Health says 79 %: the registry has no percent, so this is the only way to the figure.
    private let realShapedCapacities: [String: Any?] = [
        "DesignCapacity": 6075, "AppleRawMaxCapacity": 4578, "NominalChargeCapacity": 4728, "MaxCapacity": 100,
        "BatteryData": ["FccComp1": 4831, "FccComp2": 4578, "DesignCapacity": 6075, "MaxCapacity": 100],
    ]

    @Test func healthIsTheFullChargeCapacityOverTheDesignCapacityAsMacOSShowsIt() {
        // 4831 / 6075 is 79.5 %: macOS shows 79, so the division truncates (rounding would say 80).
        #expect(BatteryDetailsParser.parse(entry(realShapedCapacities)).healthPercent == 79)
    }

    @Test func healthIsTruncatedAndClamped() {
        func health(_ fcc: Int) -> Int? { BatteryDetailsParser.parse(entry(["BatteryData": ["FccComp1": fcc]])).healthPercent }
        #expect(health(5999) == 99)
        #expect(health(6000) == 100)
        #expect(health(6100) == 100)
        #expect(health(3000) == 50)
        #expect(health(3059) == 50)
    }

    @Test func healthFallsBackToTheNominalThenTheRawCapacity() {
        let withoutFullCharge = realShapedCapacities.merging(["BatteryData": nil]) { $1 }
        #expect(BatteryDetailsParser.parse(entry(withoutFullCharge)).healthPercent == 77)   // 4728 / 6075
        let withoutNominal = withoutFullCharge.merging(["NominalChargeCapacity": nil]) { $1 }
        #expect(BatteryDetailsParser.parse(entry(withoutNominal)).healthPercent == 75)      // 4578 / 6075
    }

    @Test func aMissingEmptyOrOddFullChargeCapacityFallsBack() {
        func health(_ batteryData: Any?) -> Int? {
            BatteryDetailsParser.parse(entry(realShapedCapacities.merging(["BatteryData": batteryData]) { $1 })).healthPercent
        }
        #expect(health(["FccComp2": 4578]) == 77)
        #expect(health(["FccComp1": 0]) == 77)
        #expect(health(["FccComp1": -5]) == 77)
        #expect(health(["FccComp1": "4831"]) == 77)
        #expect(health(["FccComp1": true]) == 77)
        #expect(health([4831]) == 77)
        #expect(health("4831") == 77)
    }

    @Test func maxCapacityCountsOnlyWhenItIsInMilliampHours() {
        let onlyMaxCapacity: [String: Any?] = ["BatteryData": nil, "AppleRawMaxCapacity": nil, "NominalChargeCapacity": nil]
        // 100 is the percent some Macs report in this key: it says nothing about health.
        #expect(BatteryDetailsParser.parse(entry(onlyMaxCapacity.merging(["MaxCapacity": 100]) { $1 })).healthPercent == nil)
        #expect(BatteryDetailsParser.parse(entry(onlyMaxCapacity.merging(["MaxCapacity": 87]) { $1 })).healthPercent == nil)
        #expect(BatteryDetailsParser.parse(entry(onlyMaxCapacity.merging(["MaxCapacity": 5400]) { $1 })).healthPercent == 90)
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

    // MARK: Apple Silicon Nested BatteryData Tests (NC-MYN-044)

    @Test func testAppleSiliconNestedBatteryDataHealthCalculation() {
        let appleSiliconEntry: [String: Any] = [
            "CycleCount": 339,
            "Voltage": 12250,
            "Amperage": 1200,
            // CHÚ Ý: Không có "DesignCapacity" ở top-level!
            "BatteryData": [
                "DesignCapacity": 6075,
                "FccComp1": 4830,
                "FccComp2": 4577,
                "NominalChargeCapacity": 4727,
                "FullChargeCapacity": 4577,
                "AppleRawMaxCapacity": 4577,
                "AppleRawCurrentCapacity": 4120,
                "MaxCapacity": 100
            ]
        ]
        let details = BatteryDetailsParser.parse(appleSiliconEntry)
        #expect(details.designCapacityMah == 6075)
        #expect(details.maxCapacityMah == 4830)
        #expect(details.healthPercent == 79) // 4830 * 100 / 6075 = 79.5% -> truncated thành 79%
        #expect(details.cycleCount == 339)
        #expect(details.currentCapacityMah == 4120)
    }

    @Test func testAppleSiliconHealthCalculationBoundariesAndFallbacks() {
        // Sub-case 2.1 (Truncation vs Rounding)
        let entryTruncate: [String: Any] = [
            "BatteryData": [
                "DesignCapacity": 6075,
                "FccComp1": 4831 // 4831 / 6075 = 79.52% -> 79
            ]
        ]
        #expect(BatteryDetailsParser.parse(entryTruncate).healthPercent == 79)

        // Sub-case 2.2 (Clamped to 100)
        let entryClamp: [String: Any] = [
            "BatteryData": [
                "DesignCapacity": 6000,
                "FccComp1": 6150
            ]
        ]
        #expect(BatteryDetailsParser.parse(entryClamp).healthPercent == 100)

        // Sub-case 2.3 (Nested Fallback Chain: no FccComp1, use NominalChargeCapacity)
        let entryFallback: [String: Any] = [
            "BatteryData": [
                "DesignCapacity": 6075,
                "NominalChargeCapacity": 4728 // 4728 * 100 / 6075 = 77
            ]
        ]
        #expect(BatteryDetailsParser.parse(entryFallback).healthPercent == 77)
    }

    @Test func testAppleSiliconMissingDesignCapacityReturnsNilHealth() {
        // Sub-case 3.1: Hoàn toàn thiếu DesignCapacity
        let missingDesign: [String: Any] = [
            "BatteryData": [
                "FccComp1": 4830
            ]
        ]
        let detailsMissing = BatteryDetailsParser.parse(missingDesign)
        #expect(detailsMissing.designCapacityMah == nil)
        #expect(detailsMissing.healthPercent == nil)

        // Sub-case 3.2: Malformed hoặc Zero DesignCapacity
        let zeroDesign: [String: Any] = [
            "BatteryData": [
                "DesignCapacity": 0,
                "FccComp1": 4830
            ]
        ]
        #expect(BatteryDetailsParser.parse(zeroDesign).healthPercent == nil)
    }

    @Test func testNestedZeroKeyFallsBackToValidTopLevelKey() {
        // Sub-case 1: BatteryData có DesignCapacity = 0 (invalid) nhưng top-level có DesignCapacity = 6000 (hợp lệ)
        let entry: [String: Any] = [
            "BatteryData": [
                "DesignCapacity": 0,
                "FccComp1": 4800
            ],
            "DesignCapacity": 6000
        ]
        let details = BatteryDetailsParser.parse(entry)
        #expect(details.designCapacityMah == 6000)
        #expect(details.maxCapacityMah == 4800)
        #expect(details.healthPercent == 80) // 4800 * 100 / 6000 = 80%

        // Sub-case 2: BatteryData có NominalChargeCapacity = 0 (invalid) nhưng top-level có 5800
        let entryNominal: [String: Any] = [
            "BatteryData": [
                "DesignCapacity": 6000,
                "NominalChargeCapacity": 0,
                "CycleCount": 0
            ],
            "NominalChargeCapacity": 5800
        ]
        let detailsNominal = BatteryDetailsParser.parse(entryNominal)
        #expect(detailsNominal.designCapacityMah == 6000)
        #expect(detailsNominal.maxCapacityMah == 5800)
        #expect(detailsNominal.healthPercent == 96) // 5800 * 100 / 6000 = 96%
        #expect(detailsNominal.cycleCount == 0)
    }
}
