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
    var fans: [FanReading]

    /// What the tab shows large: the hotter of the two dies.
    var soc: Double? { [cpu, gpu].compactMap { $0 }.max() }
}

nonisolated enum DieTemperature {
    /// A running Mac's die is never colder than the room and never hotter than the chip allows; the SMC reports 0.0 for a sensor
    /// that is not wired up and the odd low number for one that is not a die at all.
    static let plausible = 10.0...130.0

    /// The hottest of the readings that make sense, or nil when none does.
    static func hottest(of readings: [Double]) -> Double? {
        readings.filter(plausible.contains).max()
    }
}
