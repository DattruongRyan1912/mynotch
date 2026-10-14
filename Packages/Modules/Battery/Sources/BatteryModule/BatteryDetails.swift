/// What the battery's own registry entry reports beyond the power-source API. Every field is optional:
/// Macs and macOS versions differ in what they publish, and a missing value simply hides its column.
nonisolated public struct BatteryDetails: Equatable, Sendable {
    public var cycleCount: Int?
    /// Maximum capacity as a share of the design capacity, 0...100.
    public var healthPercent: Int?
    /// Power through the battery, in watts: positive while it charges, negative while it supplies the Mac.
    public var batteryWatts: Double?
    /// Rated power of the plugged-in adapter, when it reports one.
    public var adapterWatts: Int?

    public init(cycleCount: Int? = nil, healthPercent: Int? = nil, batteryWatts: Double? = nil, adapterWatts: Int? = nil) {
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
        self.batteryWatts = batteryWatts
        self.adapterWatts = adapterWatts
    }
}
