import IOKit

/// The battery's own entry in the I/O Registry. It publishes cycles, capacities and current, which the power-source
/// API leaves out. Readable by any process, so it never asks for a permission.
enum AppleSmartBatteryRegistry {
    /// Nil on a Mac without a battery, or when the entry cannot be read.
    static func properties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return properties?.takeRetainedValue() as? [String: Any]
    }
}
