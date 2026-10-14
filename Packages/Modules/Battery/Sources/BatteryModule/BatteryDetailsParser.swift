import Foundation

/// Converts the properties of the `AppleSmartBattery` registry entry into details. Defensive about types and units:
/// what is not a plausible number is left out rather than guessed.
nonisolated enum BatteryDetailsParser {
    /// A laptop pack runs between about 5 and 25 V; anything outside this is not millivolts.
    private static let voltageRange = 1_000...100_000
    private static let maxMilliamps = 100_000

    static func parse(_ registry: [String: Any]) -> BatteryDetails {
        BatteryDetails(
            cycleCount: integer(registry["CycleCount"]).flatMap { $0 >= 0 ? $0 : nil },
            healthPercent: healthPercent(registry),
            batteryWatts: batteryWatts(registry),
            adapterWatts: adapterWatts(registry)
        )
    }

    /// macOS publishes no percent for Battery Health in the registry or in the power-source description, so it is
    /// computed. The full-charge capacity the gauge reports (`BatteryData.FccComp1`) over the design capacity,
    /// truncated, gives the figure System Settings shows on the Mac this was checked against (4831 of 6075 is
    /// 79.5 %, shown as 79 %). The two older keys follow for Macs that lack it: they read 78 % and 75 % there.
    private static func healthPercent(_ registry: [String: Any]) -> Int? {
        guard let design = integer(registry["DesignCapacity"]), design > 0 else { return nil }
        let fullCharge = (registry["BatteryData"] as? [String: Any]).flatMap { integer($0["FccComp1"]) }
        let reported = [fullCharge, integer(registry["NominalChargeCapacity"]), integer(registry["AppleRawMaxCapacity"])]
        // Current Macs report a percent (100) in `MaxCapacity`: it only counts when it is clearly milliamp-hours.
        let milliampHours = integer(registry["MaxCapacity"]).flatMap { $0 > 100 ? $0 : nil }
        guard let maximum = (reported + [milliampHours]).compactMap({ $0 }).first(where: { $0 > 0 }) else { return nil }
        return min(maximum * 100 / design, 100)
    }

    private static func batteryWatts(_ registry: [String: Any]) -> Double? {
        guard let millivolts = integer(registry["Voltage"]), voltageRange.contains(millivolts),
              let milliamps = integer(registry["Amperage"], signed: true) ?? integer(registry["InstantAmperage"], signed: true),
              abs(milliamps) <= maxMilliamps else { return nil }
        return Double(millivolts) * Double(milliamps) / 1_000_000
    }

    private static func adapterWatts(_ registry: [String: Any]) -> Int? {
        guard let adapter = registry["AdapterDetails"] as? [String: Any],
              let watts = integer(adapter["Watts"]), watts > 0 else { return nil }
        return watts
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
