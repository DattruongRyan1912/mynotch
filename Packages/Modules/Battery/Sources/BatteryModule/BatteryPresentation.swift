import Foundation

/// What the fill of the battery means, following the colours macOS uses for its own battery.
nonisolated enum BatteryFillTone: Equatable, Sendable {
    case normal
    case charging
    case lowPower
    case low
}

/// One column of the facts under the battery.
nonisolated public struct BatteryFact: Equatable, Identifiable, Sendable {
    public enum Kind: Sendable {
        case time, source, power, capacity, cycles, lowPowerMode
        case voltage, capacityMah, temperature
    }

    public let kind: Kind
    public let value: String
    public let label: String

    public var id: Kind { kind }
    public var accessibilityLabel: String { "\(label): \(value)" }

    public init(kind: Kind, value: String, label: String) {
        self.kind = kind
        self.value = value
        self.label = label
    }
}

/// Real-time dual-branch power flow representation (Adapter IN -> Mac System & Battery Cell).
nonisolated public struct BatteryPowerFlow: Equatable, Sendable {
    public let adapterWatts: Int?          // Rated power of adapter (e.g. 94 W)
    public let adapterInputWatts: Double?  // Real-time electrical input power (e.g. 89.2 W)
    public let systemWatts: Double         // Power delivered to Mac logic board & screen
    public let batteryWatts: Double        // Power charging the battery cell (0.0 W if bypass)
    public let isOnAC: Bool
    public let isBypassActive: Bool
    public let isDischargeActive: Bool
    public let targetLimit: Int?

    public init(
        adapterWatts: Int? = nil,
        adapterInputWatts: Double? = nil,
        systemWatts: Double,
        batteryWatts: Double,
        isOnAC: Bool,
        isBypassActive: Bool,
        isDischargeActive: Bool = false,
        targetLimit: Int? = nil
    ) {
        self.adapterWatts = adapterWatts
        self.adapterInputWatts = adapterInputWatts
        self.systemWatts = systemWatts
        self.batteryWatts = batteryWatts
        self.isOnAC = isOnAC
        self.isBypassActive = isBypassActive
        self.isDischargeActive = isDischargeActive
        self.targetLimit = targetLimit
    }
}

/// Everything the Battery tab says, decided in one place from the readings.
nonisolated struct BatteryPresentation: Equatable, Sendable {
    let tone: BatteryFillTone
    /// In display order; a column whose value is unknown is not there.
    let facts: [BatteryFact]
    let powerFlow: BatteryPowerFlow?
    let accessibilityLabel: String

    init(
        snapshot: PowerSourceSnapshot,
        details: BatteryDetails?,
        isLowPowerMode: Bool,
        lowThreshold: Int,
        isDischargeActive: Bool = false,
        targetLimit: Int? = nil
    ) {
        let isLow = snapshot.percent <= lowThreshold && !snapshot.isAttachedToAdapter
        tone = if snapshot.isCharging {
            .charging
        } else if isLow {
            .low   // wins over Low Power Mode's yellow
        } else if isLowPowerMode {
            .lowPower
        } else {
            .normal
        }

        let time = Self.time(snapshot)

        let voltageFact: BatteryFact? = {
            guard let mv = details?.voltageMillivolts else { return nil }
            let volts = Double(mv) / 1000.0
            let vStr = String(format: "%.1f V", volts)
            if let ma = details?.amperageMilliamps, ma != 0 {
                let aStr = "\(abs(ma)) mA"
                return BatteryFact(kind: .voltage, value: "\(vStr) • \(aStr)", label: ma > 0 ? "Điện áp / Nạp" : "Điện áp / Xả")
            }
            return BatteryFact(kind: .voltage, value: vStr, label: "Điện áp cell")
        }()

        let capacityMahFact: BatteryFact? = {
            if let current = details?.currentCapacityMah, let max = details?.maxCapacityMah {
                return BatteryFact(kind: .capacityMah, value: "\(current) / \(max) mAh", label: "Dung lượng cell")
            }
            if let max = details?.maxCapacityMah {
                return BatteryFact(kind: .capacityMah, value: "\(max) mAh", label: "Dung lượng thực tế")
            }
            return nil
        }()

        let tempFact: BatteryFact? = {
            guard let temp = details?.temperatureCelsius else { return nil }
            return BatteryFact(kind: .temperature, value: String(format: "%.1f°C", temp), label: "Nhiệt độ pin")
        }()

        let facts = [
            BatteryFact(kind: .time, value: time.value, label: time.label),
            BatteryFact(kind: .source, value: Self.source(snapshot, adapterWatts: details?.adapterWatts), label: "Nguồn"),
            Self.power(details?.batteryWatts),
            details?.healthPercent.map { BatteryFact(kind: .capacity, value: "\($0)%", label: "Dung lượng tối đa") },
            details?.cycleCount.map { BatteryFact(kind: .cycles, value: "\($0)", label: "Chu kỳ sạc") },
            voltageFact,
            capacityMahFact,
            tempFact,
            isLowPowerMode ? BatteryFact(kind: .lowPowerMode, value: "Đang bật", label: "Nguồn điện thấp") : nil,
        ]
        self.facts = facts.compactMap { $0 }
        accessibilityLabel = Self.accessibilityLabel(snapshot)

        if snapshot.isOnAC || snapshot.isAttachedToAdapter {
            let rawWatts = details?.batteryWatts ?? 0.0
            let isDischargingFromBattery = rawWatts < -0.5 || (details?.amperageMilliamps ?? 0) < -80
            let bWatts: Double = {
                if isDischargingFromBattery {
                    if abs(rawWatts) > 0.5 {
                        return (rawWatts * 10).rounded() / 10 // Giữ nguyên số âm khi xả
                    }
                    if let ma = details?.amperageMilliamps, let mv = details?.voltageMillivolts {
                        return ((Double(ma) * Double(mv) / 1_000_000.0) * 10).rounded() / 10
                    }
                    return -1.0
                }
                if (snapshot.isCharging || rawWatts > 0.5), rawWatts > 0.5 {
                    return (rawWatts * 10).rounded() / 10
                }
                return 0.0
            }()

            let isBypass = snapshot.isOnAC && !snapshot.isCharging && !isDischargingFromBattery && abs(bWatts) <= 0.5

            let sysWatts: Double = {
                if let sWatts = details?.systemWatts, sWatts > 0 {
                    return sWatts
                }
                if let inWatts = details?.adapterInputWatts, inWatts > 0 {
                    return max(3.0, ((inWatts - max(0.0, bWatts)) * 10).rounded() / 10)
                }
                if let aWatts = details?.adapterWatts, aWatts > 0 {
                    return max(5.0, ((Double(aWatts) * 0.25) * 10).rounded() / 10)
                }
                return 15.0
            }()

            self.powerFlow = BatteryPowerFlow(
                adapterWatts: details?.adapterWatts,
                adapterInputWatts: details?.adapterInputWatts,
                systemWatts: sysWatts,
                batteryWatts: bWatts,
                isOnAC: snapshot.isOnAC,
                isBypassActive: isBypass,
                isDischargeActive: isDischargeActive,
                targetLimit: targetLimit
            )
        } else {
            self.powerFlow = nil
        }
    }

    /// Four concise hardware facts designed to fit underneath the PowerFlowBar in a single 31pt row.
    var technicalFacts: [BatteryFact] {
        let preferred: [BatteryFact.Kind] = [.voltage, .temperature, .capacity, .cycles, .capacityMah, .time]
        var result: [BatteryFact] = []
        for kind in preferred {
            if let fact = facts.first(where: { $0.kind == kind }) {
                result.append(fact)
            }
            if result.count == 4 { break }
        }
        return result
    }

    /// "45 phút", "1 giờ", "2 giờ 15 phút".
    static func duration(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) phút" }
        return minutes % 60 == 0 ? "\(minutes / 60) giờ" : "\(minutes / 60) giờ \(minutes % 60) phút"
    }

    private static let estimating = "Đang ước tính…"

    private static func time(_ snapshot: PowerSourceSnapshot) -> (value: String, label: String) {
        if snapshot.isCharging {
            return (snapshot.minutesToFull.map { "Đầy sau \(duration($0))" } ?? estimating, "Đang sạc")
        }
        if snapshot.isOnAC || snapshot.isAttachedToAdapter { return ("Không sạc thêm", "Đã cắm sạc") }
        return (snapshot.minutesToEmpty.map { "Còn khoảng \(duration($0))" } ?? estimating, "Dùng pin")
    }

    /// The registry keeps describing the adapter for a moment after it is unplugged, so it only counts on AC or when attached.
    private static func source(_ snapshot: PowerSourceSnapshot, adapterWatts: Int?) -> String {
        guard snapshot.isOnAC || snapshot.isAttachedToAdapter else { return "Pin" }
        return adapterWatts.map { "Bộ sạc \($0) W" } ?? "Bộ sạc"
    }

    /// Below a watt the number is noise, so the column goes.
    private static func power(_ watts: Double?) -> BatteryFact? {
        guard let watts, abs(watts) >= 1 else { return nil }
        return BatteryFact(kind: .power, value: "\(Int(abs(watts).rounded())) W", label: watts > 0 ? "Đang nạp" : "Đang tiêu thụ")
    }

    private static func accessibilityLabel(_ snapshot: PowerSourceSnapshot) -> String {
        var parts = ["Pin \(snapshot.percent) phần trăm"]
        if snapshot.isCharging {
            parts.append("đang sạc")
            if let minutes = snapshot.minutesToFull { parts.append("đầy sau \(duration(minutes))") }
        } else if snapshot.isOnAC {
            parts += ["đã cắm sạc", "không sạc thêm"]
        } else {
            parts.append("dùng pin")
            if let minutes = snapshot.minutesToEmpty { parts.append("còn khoảng \(duration(minutes))") }
        }
        return parts.joined(separator: ", ")
    }
}
