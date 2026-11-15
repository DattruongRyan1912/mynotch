import FanHelperKit
import Foundation
import IOKit

/// Reads 30+ physical thermal sensors on Apple Silicon via IOHID (PMU sensors),
/// falling back to SMC for Intel Macs and querying SMC for fan RPMs.
actor IOHIDThermalReader: ThermalReading {
    typealias SensorProvider = @Sendable () -> [SensorReading]

    private let sensorProvider: SensorProvider
    private let smcFallback: any ThermalReading
    private var isClosed = false

    init(
        sensorProvider: SensorProvider? = nil,
        smcFallback: (any ThermalReading)? = nil
    ) {
        self.sensorProvider = sensorProvider ?? { Self.readNativeSensors() }
        self.smcFallback = smcFallback ?? SMCThermalReader()
    }

    func isAvailable() async -> Bool {
        if isClosed { return false }
        let sensors = sensorProvider()
        if !sensors.isEmpty { return true }
        return await smcFallback.isAvailable()
    }

    func read() async -> ThermalSnapshot? {
        guard !isClosed else { return nil }

        let sensors = sensorProvider()
        let smcSnapshot = await smcFallback.read()
        let fans = smcSnapshot?.fans ?? []

        guard !sensors.isEmpty else {
            return smcSnapshot
        }

        let cpu = hottest(in: sensors, for: .cpu) ?? smcSnapshot?.cpu
        let gpu = hottest(in: sensors, for: .gpu) ?? smcSnapshot?.gpu
        let hotspot = hottest(in: sensors, for: .hotspot)
        let ssd = hottest(in: sensors, for: .ssd)
        let battery = hottest(in: sensors, for: .battery)

        return ThermalSnapshot(
            cpu: cpu,
            gpu: gpu,
            hotspot: hotspot,
            ssd: ssd,
            battery: battery,
            sensors: sensors,
            fans: fans
        )
    }

    func shutdown() async {
        isClosed = true
        await smcFallback.shutdown()
    }

    private func hottest(in sensors: [SensorReading], for category: SensorCategory) -> Double? {
        DieTemperature.hottest(of: sensors.filter { $0.category == category }.map(\.temperature))
    }

    // MARK: - Sensor Categorization

    static func categorize(sensorName: String) -> SensorCategory {
        let lower = sensorName.lowercased()

        if lower.contains("battery") || lower.contains("batt") || lower.contains("gas gauge") || lower.contains("charger") {
            return .battery
        }
        if lower.contains("nand") || lower.contains("ssd") || lower.contains("nvme") || lower.contains("storage") {
            return .ssd
        }
        if lower.contains("soc") || lower.contains("hotspot") || lower.contains("ane") || lower.contains("npu")
            || lower.contains("isp") || lower.contains("neural") || lower.contains("tcal") {
            return .hotspot
        }
        if lower.contains("gpu") || lower.contains("gtr") || lower.contains("graphics")
            || lower.contains("tp0s") || lower.contains("tp1s") || lower.contains("tp2s") || lower.contains("tp3g")
            || lower.contains("tp0g") || lower.contains("tp1g") || lower.contains("tp2g") || lower.hasPrefix("tg") {
            return .gpu
        }
        if lower.contains("cpu") || lower.contains("pacc") || lower.contains("eacc") || lower.contains("p-core")
            || lower.contains("e-core") || lower.contains("pcore") || lower.contains("ecore") || lower.contains("tdie")
            || lower.hasPrefix("tp") || lower.hasPrefix("te") {
            return .cpu
        }

        return .other
    }

    // MARK: - Native IOHID PMU Sensor Reading

    private typealias IOHIDEventSystemClientCreateWithType = @convention(c) (CFAllocator?, UInt32, UInt32) -> Unmanaged<AnyObject>?
    private typealias IOHIDEventSystemClientSetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias IOHIDEventSystemClientCopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias IOHIDServiceClientCopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias IOHIDServiceClientCopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias IOHIDEventGetFloatValue = @convention(c) (AnyObject, UInt32) -> Double

    private static func readNativeSensors() -> [SensorReading] {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
            return []
        }
        defer { dlclose(handle) }

        guard let createSym = dlsym(handle, "IOHIDEventSystemClientCreateWithType"),
              let setMatchingSym = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let copyServicesSym = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let copyPropertySym = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let copyEventSym = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let getFloatSym = dlsym(handle, "IOHIDEventGetFloatValue")
        else {
            return []
        }

        let clientCreate = unsafeBitCast(createSym, to: IOHIDEventSystemClientCreateWithType.self)
        let clientSetMatching = unsafeBitCast(setMatchingSym, to: IOHIDEventSystemClientSetMatching.self)
        let clientCopyServices = unsafeBitCast(copyServicesSym, to: IOHIDEventSystemClientCopyServices.self)
        let serviceCopyProperty = unsafeBitCast(copyPropertySym, to: IOHIDServiceClientCopyProperty.self)
        let serviceCopyEvent = unsafeBitCast(copyEventSym, to: IOHIDServiceClientCopyEvent.self)
        let eventGetFloat = unsafeBitCast(getFloatSym, to: IOHIDEventGetFloatValue.self)

        guard let clientObj = clientCreate(kCFAllocatorDefault, 1, 0)?.takeRetainedValue() else {
            return []
        }

        let matching: [String: Any] = [
            "PrimaryUsagePage": 0xff00,
            "PrimaryUsage": 5
        ]
        clientSetMatching(clientObj, matching as CFDictionary)

        guard let servicesArray = clientCopyServices(clientObj)?.takeRetainedValue() as? [AnyObject] else {
            return []
        }

        var results: [SensorReading] = []
        // kIOHIDEventTypeTemperature = 15, IOHIDEventFieldBase(15) = 15 << 16 = 983040
        let tempEventType: Int64 = 15
        let tempField: UInt32 = 983040

        for (index, service) in servicesArray.enumerated() {
            let name = (serviceCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? "Sensor \(index + 1)"
            guard let event = serviceCopyEvent(service, tempEventType, 0, 0)?.takeRetainedValue() else {
                continue
            }
            let temp = eventGetFloat(event, tempField)
            if DieTemperature.plausible.contains(temp) {
                let category = categorize(sensorName: name)
                let sensorId = "\(name)-\(index)"
                results.append(SensorReading(id: sensorId, name: name, temperature: temp, category: category))
            }
        }

        return results
    }
}
