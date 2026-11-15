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

    @Test func parsesPhysicalAdapterConnectionEvenWhenOnBatteryPowerState() {
        let snapshot = PowerSourceParser.parse([[
            "Type": "InternalBattery",
            "Current Capacity": 80, "Max Capacity": 100,
            "Is Charging": false, "Power Source State": "Battery Power",
            "ExternalConnected": true,
        ]])
        #expect(snapshot?.isOnAC == false)
        #expect(snapshot?.isAttachedToAdapter == true)
        #expect(snapshot?.isACAttached == true)
    }

    @Test func parsesUnpluggedAdapter() {
        let snapshot = PowerSourceParser.parse([[
            "Type": "InternalBattery",
            "Current Capacity": 80, "Max Capacity": 100,
            "Is Charging": false, "Power Source State": "Battery Power",
            "ExternalConnected": false,
        ]])
        #expect(snapshot?.isOnAC == false)
        #expect(snapshot?.isAttachedToAdapter == false)
    }

    @Test func parsesPhysicalAdapterFromRegistryPropertiesWhenIOPSDescriptionsLackKey() {
        // Exactly reproduces the real production bug: IOPS dictionary has NO ExternalConnected key and reports Battery Power
        let iopsDescriptions: [[String: Any]] = [[
            "Type": "InternalBattery",
            "Current Capacity": 80, "Max Capacity": 100,
            "Is Charging": false, "Power Source State": "Battery Power",
        ]]
        let registry: [String: Any] = [
            "AppleRawExternalConnected": 1,
            "ExternalConnected": 1,
        ]
        let snapshot = PowerSourceParser.parse(iopsDescriptions, registryProperties: registry, hasExternalAdapterDetails: true)
        #expect(snapshot?.isOnAC == false)
        #expect(snapshot?.isAttachedToAdapter == true)
    }

    @Test func parsesPhysicalAdapterFromExternalAdapterDetailsWhenRegistryNil() {
        let iopsDescriptions: [[String: Any]] = [[
            "Type": "InternalBattery",
            "Current Capacity": 80, "Max Capacity": 100,
            "Is Charging": false, "Power Source State": "Battery Power",
        ]]
        let snapshot = PowerSourceParser.parse(iopsDescriptions, registryProperties: nil, hasExternalAdapterDetails: true)
        #expect(snapshot?.isOnAC == false)
        #expect(snapshot?.isAttachedToAdapter == true)
    }

    @Test func parsesAttachedWhenAppleRawExternalConnectedDropsToZeroUnderCHIEButAdapterDetailsPresent() {
        // Crucial edge-case: Under Apple Silicon SMC CHIE = 0x08, PMU disables charger input,
        // causing AppleSmartBattery to report AppleRawExternalConnected = 0 and ExternalConnected = 0,
        // but the physical USB-C power adapter is still plugged in (hasExternalAdapterDetails = true).
        let iopsDescriptions: [[String: Any]] = [[
            "Type": "InternalBattery",
            "Current Capacity": 80, "Max Capacity": 100,
            "Is Charging": false, "Power Source State": "Battery Power",
        ]]
        let registry: [String: Any] = [
            "AppleRawExternalConnected": 0,
            "ExternalConnected": 0,
        ]
        let snapshot = PowerSourceParser.parse(iopsDescriptions, registryProperties: registry, hasExternalAdapterDetails: true)
        #expect(snapshot?.isOnAC == false)
        #expect(snapshot?.isAttachedToAdapter == true)
    }

    @Test func parsesUnpluggedWhenRegistryReportsDisconnected() {
        let iopsDescriptions: [[String: Any]] = [[
            "Type": "InternalBattery",
            "Current Capacity": 80, "Max Capacity": 100,
            "Is Charging": false, "Power Source State": "Battery Power",
        ]]
        let registry: [String: Any] = [
            "AppleRawExternalConnected": 0,
            "ExternalConnected": 0,
        ]
        let snapshot = PowerSourceParser.parse(iopsDescriptions, registryProperties: registry, hasExternalAdapterDetails: false)
        #expect(snapshot?.isOnAC == false)
        #expect(snapshot?.isAttachedToAdapter == false)
    }
}
