/// Converts IOKit power source descriptions (string keys from IOPSKeys.h) into snapshots.
nonisolated enum PowerSourceParser {
    /// Returns the internal battery, or nil when the Mac has none.
    static func parse(_ descriptions: [[String: Any]]) -> PowerSourceSnapshot? {
        guard let battery = descriptions.first(where: { ($0["Type"] as? String) == "InternalBattery" }),
              let current = battery["Current Capacity"] as? Int,
              let maxCapacity = battery["Max Capacity"] as? Int, maxCapacity > 0 else { return nil }
        let isCharging = battery["Is Charging"] as? Bool ?? false
        let state = battery["Power Source State"] as? String
        let percent = Int((Double(current) / Double(maxCapacity) * 100).rounded())
        return PowerSourceSnapshot(
            percent: min(max(percent, 0), 100),
            isCharging: isCharging,
            isOnAC: state == "AC Power",
            // IOPSKeys.h: time to empty is only valid on battery power while not charging,
            // time to full only while charging; otherwise IOKit reports 0 or -1.
            minutesToEmpty: state == "Battery Power" && !isCharging ? minutes(battery["Time to Empty"]) : nil,
            minutesToFull: isCharging ? minutes(battery["Time to Full Charge"]) : nil
        )
    }

    /// IOKit reports -1 while still estimating.
    private static func minutes(_ value: Any?) -> Int? {
        guard let minutes = value as? Int, minutes >= 0 else { return nil }
        return minutes
    }
}
