import FanHelperKit

/// The category of a thermal sensor on Apple Silicon or Intel Macs.
nonisolated enum SensorCategory: String, CaseIterable, Sendable {
    case cpu = "CPU"
    case gpu = "GPU"
    case hotspot = "Hotspot"
    case ssd = "SSD"
    case battery = "Pin"
    case other = "Khác"
}

/// A single named temperature reading from an individual physical sensor.
nonisolated struct SensorReading: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let temperature: Double
    let category: SensorCategory
}

/// One fan: how fast it turns and the range it turns in.
nonisolated struct FanReading: Equatable, Identifiable, Sendable {
    let index: Int
    let rpm: Double
    let minRPM: Double
    let maxRPM: Double

    var id: Int { index }

    /// Where the speed is between the fan's minimum and maximum, 0 to 1; 0 when there is no range to be in.
    var fraction: Double {
        guard maxRPM > minRPM else { return 0 }
        return min(max((rpm - minRPM) / (maxRPM - minRPM), 0), 1)
    }
}

/// Die temperatures and fan speeds at one moment.
nonisolated struct ThermalSnapshot: Equatable, Sendable {
    /// The hottest CPU die sensor, in degrees Celsius; nil when none could be read.
    var cpu: Double?
    var gpu: Double?
    var hotspot: Double?
    var ssd: Double?
    var battery: Double?
    var sensors: [SensorReading]
    var fans: [FanReading]

    init(
        cpu: Double? = nil,
        gpu: Double? = nil,
        hotspot: Double? = nil,
        ssd: Double? = nil,
        battery: Double? = nil,
        sensors: [SensorReading] = [],
        fans: [FanReading] = []
    ) {
        self.cpu = cpu
        self.gpu = gpu
        self.hotspot = hotspot
        self.ssd = ssd
        self.battery = battery
        self.sensors = sensors
        self.fans = fans
    }

    /// What the tab shows large: the hottest among CPU, GPU, and hotspot dies.
    var soc: Double? { [cpu, gpu, hotspot].compactMap { $0 }.max() }
}
