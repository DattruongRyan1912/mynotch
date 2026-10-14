/// What the fill of the battery means, following the colours macOS uses for its own battery.
nonisolated enum BatteryFillTone: Equatable, Sendable {
    case normal
    case charging
    case lowPower
    case low
}

/// One column of the facts under the battery.
nonisolated struct BatteryFact: Equatable, Identifiable, Sendable {
    enum Kind: Sendable {
        case time, source, power, capacity, cycles, lowPowerMode
    }

    let kind: Kind
    let value: String
    let label: String

    var id: Kind { kind }
    var accessibilityLabel: String { "\(label): \(value)" }
}

/// Everything the Battery tab says, decided in one place from the readings.
nonisolated struct BatteryPresentation: Equatable, Sendable {
    let tone: BatteryFillTone
    /// In display order; a column whose value is unknown is not there.
    let facts: [BatteryFact]
    let accessibilityLabel: String

    init(snapshot: PowerSourceSnapshot, details: BatteryDetails?, isLowPowerMode: Bool, lowThreshold: Int) {
        let isLow = snapshot.percent <= lowThreshold && !snapshot.isOnAC
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
        let facts = [
            BatteryFact(kind: .time, value: time.value, label: time.label),
            BatteryFact(kind: .source, value: Self.source(snapshot, adapterWatts: details?.adapterWatts), label: "Nguồn"),
            Self.power(details?.batteryWatts),
            details?.healthPercent.map { BatteryFact(kind: .capacity, value: "\($0)%", label: "Dung lượng tối đa") },
            details?.cycleCount.map { BatteryFact(kind: .cycles, value: "\($0)", label: "Chu kỳ sạc") },
            isLowPowerMode ? BatteryFact(kind: .lowPowerMode, value: "Đang bật", label: "Nguồn điện thấp") : nil,
        ]
        self.facts = facts.compactMap { $0 }
        accessibilityLabel = Self.accessibilityLabel(snapshot)
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
        if snapshot.isOnAC { return ("Không sạc thêm", "Đã cắm sạc") }
        return (snapshot.minutesToEmpty.map { "Còn khoảng \(duration($0))" } ?? estimating, "Dùng pin")
    }

    /// The registry keeps describing the adapter for a moment after it is unplugged, so it only counts on AC.
    private static func source(_ snapshot: PowerSourceSnapshot, adapterWatts: Int?) -> String {
        guard snapshot.isOnAC else { return "Pin" }
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
