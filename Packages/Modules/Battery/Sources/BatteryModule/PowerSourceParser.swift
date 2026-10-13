/// Converts IOKit power source descriptions (string keys from IOPSKeys.h) into snapshots.
nonisolated enum PowerSourceParser {
    /// Returns the internal battery, or nil when the Mac has none.
    static func parse(_ descriptions: [[String: Any]]) -> PowerSourceSnapshot? {
        guard let battery = descriptions.first(where: { ($0["Type"] as? String) == "InternalBattery" }),
              let current = battery["Current Capacity"] as? Int,
              let max = battery["Max Capacity"] as? Int, max > 0 else { return nil }
        return PowerSourceSnapshot(
            percent: Int((Double(current) / Double(max) * 100).rounded()),
            isCharging: battery["Is Charging"] as? Bool ?? false,
            isOnAC: (battery["Power Source State"] as? String) == "AC Power",
            minutesToEmpty: positive(battery["Time to Empty"]),
            minutesToFull: positive(battery["Time to Full Charge"])
        )
    }

    /// IOKit reports -1 while estimating.
    private static func positive(_ value: Any?) -> Int? {
        guard let minutes = value as? Int, minutes >= 0 else { return nil }
        return minutes
    }
}
