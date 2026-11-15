import Foundation

/// Converts IOKit power source descriptions (string keys from IOPSKeys.h) into snapshots.
nonisolated enum PowerSourceParser {
    /// Returns the internal battery, or nil when the Mac has none.
    static func parse(
        _ descriptions: [[String: Any]],
        registryProperties: [String: Any]? = nil,
        hasExternalAdapterDetails: Bool = false
    ) -> PowerSourceSnapshot? {
        guard let battery = descriptions.first(where: { ($0["Type"] as? String) == "InternalBattery" }),
              let current = battery["Current Capacity"] as? Int,
              let maxCapacity = battery["Max Capacity"] as? Int, maxCapacity > 0 else { return nil }
        let isCharging = battery["Is Charging"] as? Bool ?? false
        let state = battery["Power Source State"] as? String
        let percent = Int((Double(current) / Double(maxCapacity) * 100).rounded())
        let isOnAC = state == "AC Power"
        let isExternalConnected: Bool = {
            if hasExternalAdapterDetails { return true }
            if isOnAC { return true }
            if let registry = registryProperties {
                if boolean(registry["AppleRawExternalConnected"]) == true { return true }
                if boolean(registry["ExternalConnected"]) == true { return true }
                if let fed = registry["FedDetails"] as? [[String: Any]],
                   fed.contains(where: { ($0["FedExternalConnected"] as? Int) == 1 }) {
                    return true
                }
            }
            if boolean(battery["ExternalConnected"]) == true
                || boolean(battery["External Connected"]) == true
                || boolean(battery["AppleRawExternalConnected"]) == true {
                return true
            }
            return false
        }()
        return PowerSourceSnapshot(
            percent: min(max(percent, 0), 100),
            isCharging: isCharging,
            isOnAC: isOnAC,
            isAttachedToAdapter: isExternalConnected,
            // IOPSKeys.h: time to empty is only valid on battery power while not charging,
            // time to full only while charging; otherwise IOKit reports 0 or -1.
            minutesToEmpty: state == "Battery Power" && !isCharging ? minutes(battery["Time to Empty"]) : nil,
            minutesToFull: isCharging ? minutes(battery["Time to Full Charge"]) : nil
        )
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    /// IOKit reports -1 while still estimating.
    private static func minutes(_ value: Any?) -> Int? {
        guard let minutes = value as? Int, minutes >= 0 else { return nil }
        return minutes
    }
}
