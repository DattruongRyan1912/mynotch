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
    /// Battery pack temperature in degrees Celsius (e.g. 31.5).
    public var temperatureCelsius: Double?
    /// Instantaneous battery voltage in millivolts (e.g. 12450 mV).
    public var voltageMillivolts: Int?
    /// Instantaneous battery amperage in milliamps (positive while charging, negative while discharging).
    public var amperageMilliamps: Int?
    /// Design capacity of the pack in milliamp-hours.
    public var designCapacityMah: Int?
    /// Current maximum usable capacity in milliamp-hours.
    public var maxCapacityMah: Int?
    /// Instantaneous charge level in milliamp-hours.
    public var currentCapacityMah: Int?
    /// Real-time power consumed by the Mac logic board, CPU, and screen in watts.
    public var systemWatts: Double?
    /// Real-time electrical power drawn from the adapter in watts.
    public var adapterInputWatts: Double?
    /// Reason code from Apple ChargerData (e.g. 16777216 = Max Charge Limit / Optimized Hold).
    public var notChargingReason: Int?
    /// Whether PowerDistribution allows charging into cell (0/false means PMU isolates charging).
    public var isSystemChargingAllowed: Bool?

    /// Whether macOS native PMU is actively holding the charge at limit (Hardware Passthrough).
    public var isNativeChargeHoldActive: Bool {
        let isHoldSignal = (isSystemChargingAllowed == false) || ((notChargingReason ?? 0) != 0)
        let isNotDischarging = (batteryWatts ?? 0) >= -0.8 && (amperageMilliamps ?? 0) >= -100
        let isNotChargingHard = (batteryWatts ?? 0) <= 0.5 && (amperageMilliamps ?? 0) <= 100
        return isHoldSignal && isNotDischarging && isNotChargingHard
    }

    public init(
        cycleCount: Int? = nil,
        healthPercent: Int? = nil,
        batteryWatts: Double? = nil,
        adapterWatts: Int? = nil,
        temperatureCelsius: Double? = nil,
        voltageMillivolts: Int? = nil,
        amperageMilliamps: Int? = nil,
        designCapacityMah: Int? = nil,
        maxCapacityMah: Int? = nil,
        currentCapacityMah: Int? = nil,
        systemWatts: Double? = nil,
        adapterInputWatts: Double? = nil,
        notChargingReason: Int? = nil,
        isSystemChargingAllowed: Bool? = nil
    ) {
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
        self.batteryWatts = batteryWatts
        self.adapterWatts = adapterWatts
        self.temperatureCelsius = temperatureCelsius
        self.voltageMillivolts = voltageMillivolts
        self.amperageMilliamps = amperageMilliamps
        self.designCapacityMah = designCapacityMah
        self.maxCapacityMah = maxCapacityMah
        self.currentCapacityMah = currentCapacityMah
        self.systemWatts = systemWatts
        self.adapterInputWatts = adapterInputWatts
        self.notChargingReason = notChargingReason
        self.isSystemChargingAllowed = isSystemChargingAllowed
    }
}
