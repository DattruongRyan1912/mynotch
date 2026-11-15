import IOKit

/// The battery's own entry in the I/O Registry. It publishes cycles, capacities and current, which the power-source
/// API leaves out. Readable by any process, so it never asks for a permission.
enum AppleSmartBatteryRegistry {
    /// Nil on a Mac without a battery, or when the entry cannot be read.
    static func properties() -> [String: Any]? {
        guard var merged = fetchProperties(serviceName: "AppleSmartBattery") else { return nil }

        // On Apple Silicon, gas gauge calibration (such as FccComp1, the exact calibrated full charge
        // capacity matching macOS System Settings) is published by AppleSmartBatteryPack.
        if let packProps = fetchProperties(serviceName: "AppleSmartBatteryPack") {
            if let baseData = merged["BatteryData"] as? [String: Any],
               let packData = packProps["BatteryData"] as? [String: Any] {
                merged["BatteryData"] = baseData.merging(packData) { (_, packVal) in packVal }
            } else if merged["BatteryData"] == nil, let packData = packProps["BatteryData"] {
                merged["BatteryData"] = packData
            }
        }

        return merged
    }

    private static func fetchProperties(serviceName: String) -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(serviceName))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return properties?.takeRetainedValue() as? [String: Any]
    }
}
