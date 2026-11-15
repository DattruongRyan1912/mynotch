import Foundation

/// Converts the properties of the `AppleSmartBattery` registry entry into details. Defensive about types and units:
/// what is not a plausible number is left out rather than guessed.
nonisolated enum BatteryDetailsParser {
    /// A laptop pack runs between about 5 and 25 V; anything outside this is not millivolts.
    private static let voltageRange = 1_000...100_000
    private static let maxMilliamps = 100_000

    static func parse(_ registry: [String: Any]) -> BatteryDetails {
        let cycle = nonNegativeInt(registry["CycleCount"])
            ?? (registry["BatteryData"] as? [String: Any]).flatMap { nonNegativeInt($0["CycleCount"]) }
        return BatteryDetails(
            cycleCount: cycle,
            healthPercent: healthPercent(registry),
            batteryWatts: batteryWatts(registry),
            adapterWatts: adapterWatts(registry),
            temperatureCelsius: temperatureCelsius(registry),
            voltageMillivolts: voltageMillivolts(registry),
            amperageMilliamps: amperageMilliamps(registry),
            designCapacityMah: designCapacityMah(registry),
            maxCapacityMah: maxCapacityMah(registry),
            currentCapacityMah: currentCapacityMah(registry),
            systemWatts: systemWatts(registry),
            adapterInputWatts: adapterInputWatts(registry),
            notChargingReason: notChargingReason(registry),
            isSystemChargingAllowed: isSystemChargingAllowed(registry)
        )
    }

    /// macOS publishes no percent for Battery Health in the registry or in the power-source description, so it is
    /// computed. The full-charge capacity the gauge reports (`BatteryData.FccComp1`) over the design capacity,
    /// truncated, gives the figure System Settings shows on the Mac this was checked against (4831 of 6075 is
    /// 79.5 %, shown as 79 %). The two older keys follow for Macs that lack it: they read 78 % and 75 % there.
    private static func healthPercent(_ registry: [String: Any]) -> Int? {
        guard let design = designCapacityMah(registry), design > 0 else { return nil }
        guard let maximum = maxCapacityMah(registry) else { return nil }
        return min(maximum * 100 / design, 100)
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let n = integer(value), n > 0 else { return nil }
        return n
    }

    private static func nonNegativeInt(_ value: Any?) -> Int? {
        guard let n = integer(value), n >= 0 else { return nil }
        return n
    }

    private static func designCapacityMah(_ registry: [String: Any]) -> Int? {
        let batteryData = registry["BatteryData"] as? [String: Any]
        return batteryData.flatMap { positiveInt($0["DesignCapacity"]) }
            ?? positiveInt(registry["DesignCapacity"])
    }

    private static func maxCapacityMah(_ registry: [String: Any]) -> Int? {
        let batteryData = registry["BatteryData"] as? [String: Any]
        let fcc1 = batteryData.flatMap { positiveInt($0["FccComp1"]) }
        let nominal = batteryData.flatMap { positiveInt($0["NominalChargeCapacity"]) }
            ?? positiveInt(registry["NominalChargeCapacity"])
        let rawMax = batteryData.flatMap { positiveInt($0["AppleRawMaxCapacity"]) }
            ?? positiveInt(registry["AppleRawMaxCapacity"])
        let fullChargeCap = batteryData.flatMap { positiveInt($0["FullChargeCapacity"]) }
            ?? positiveInt(registry["FullChargeCapacity"])
        // Current Macs report a percent (100) in `MaxCapacity`: it only counts when it is clearly milliamp-hours.
        let milliampHours = integer(registry["MaxCapacity"]).flatMap { $0 > 100 ? $0 : nil }
        let candidates = [fcc1, nominal, rawMax, fullChargeCap, milliampHours]
        return candidates.compactMap({ $0 }).first
    }

    private static func currentCapacityMah(_ registry: [String: Any]) -> Int? {
        let batteryData = registry["BatteryData"] as? [String: Any]
        let rawCurrent = batteryData.flatMap { nonNegativeInt($0["AppleRawCurrentCapacity"]) }
            ?? nonNegativeInt(registry["AppleRawCurrentCapacity"])
        let remaining = batteryData.flatMap { nonNegativeInt($0["RemainingCapacity"]) }
        let currentCap = integer(registry["CurrentCapacity"]).flatMap { $0 > 100 ? $0 : nil }
        let reported = [rawCurrent, remaining, currentCap, nonNegativeInt(registry["CurrentCapacity"])]
        return reported.compactMap({ $0 }).first
    }

    private static func temperatureCelsius(_ registry: [String: Any]) -> Double? {
        guard let raw = integer(registry["Temperature"]) else { return nil }
        // If centi-Kelvin (e.g. 30515 = 305.15 K = 32.0 °C)
        if raw > 20_000 {
            let degC = (Double(raw) / 100.0) - 273.15
            return (degC >= 0 && degC <= 100) ? (degC * 10).rounded() / 10 : nil
        }
        // If centi-Celsius (e.g. 3150 = 31.5 °C)
        if raw >= 100 && raw <= 10_000 {
            let degC = Double(raw) / 100.0
            return (degC * 10).rounded() / 10
        }
        // Direct Celsius (e.g. 32)
        if raw >= 0 && raw < 100 {
            return Double(raw)
        }
        return nil
    }

    private static func voltageMillivolts(_ registry: [String: Any]) -> Int? {
        guard let millivolts = integer(registry["Voltage"]), voltageRange.contains(millivolts) else { return nil }
        return millivolts
    }

    private static func amperageMilliamps(_ registry: [String: Any]) -> Int? {
        guard let milliamps = integer(registry["Amperage"], signed: true) ?? integer(registry["InstantAmperage"], signed: true),
              abs(milliamps) <= maxMilliamps else { return nil }
        return milliamps
    }

    private static func batteryWatts(_ registry: [String: Any]) -> Double? {
        guard let millivolts = voltageMillivolts(registry),
              let milliamps = amperageMilliamps(registry) else { return nil }
        return Double(millivolts) * Double(milliamps) / 1_000_000
    }

    private static func adapterWatts(_ registry: [String: Any]) -> Int? {
        guard let adapter = registry["AdapterDetails"] as? [String: Any],
              let watts = integer(adapter["Watts"]), watts > 0 else { return nil }
        return watts
    }

    private static func systemWatts(_ registry: [String: Any]) -> Double? {
        guard let telemetry = registry["PowerTelemetryData"] as? [String: Any],
              let milliwatts = integer(telemetry["SystemPowerIn"]),
              milliwatts > 1_000 else { return nil }
        let watts = Double(milliwatts) / 1000.0
        return (watts * 10).rounded() / 10
    }

    private static func adapterInputWatts(_ registry: [String: Any]) -> Double? {
        guard let powerDist = registry["PowerDistribution"] as? [String: Any],
              let milliwatts = integer(powerDist["IPDInputPower"]),
              milliwatts > 1_000 else { return nil }
        let watts = Double(milliwatts) / 1000.0
        return (watts * 10).rounded() / 10
    }

    private static func notChargingReason(_ registry: [String: Any]) -> Int? {
        guard let chargerData = registry["ChargerData"] as? [String: Any] else { return nil }
        return integer(chargerData["NotChargingReason"])
    }

    private static func isSystemChargingAllowed(_ registry: [String: Any]) -> Bool? {
        guard let powerDist = registry["PowerDistribution"] as? [String: Any] else { return nil }
        if let raw = powerDist["IPDChargingAllowed"] {
            if let boolVal = raw as? Bool { return boolVal }
            if let num = raw as? NSNumber { return num.intValue != 0 }
        }
        return nil
    }

    /// Booleans are numbers to Foundation, but never a count or a capacity.
    /// - Parameter signed: the registry stores a negative current as a 64-bit wrap-around on some Macs.
    private static func integer(_ value: Any?, signed: Bool = false) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        if let exact = Int(exactly: number) { return exact }
        guard signed, let wrapped = UInt64(exactly: number) else { return nil }
        return Int(Int64(bitPattern: wrapped))
    }
}
