import Foundation

/// How hot the SoC is, for the colour of its number's marker, the sparkline and the strip. Round numbers a person can reason about:
/// Apple does not publish the temperatures at which an M1 Pro slows down.
nonisolated enum TemperatureTone: Equatable, Sendable {
    case normal
    case warm
    case hot

    static let warmFrom = 70.0
    static let hotFrom = 90.0

    init(celsius: Double) {
        self = celsius >= Self.hotFrom ? .hot : celsius >= Self.warmFrom ? .warm : .normal
    }
}

nonisolated enum ThermalFormat {
    static func degrees(_ celsius: Double?) -> String {
        celsius.map { "\(Int($0.rounded()))°" } ?? "—"
    }

    static func rpm(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }
}

nonisolated struct FanRow: Equatable, Identifiable, Sendable {
    let id: Int
    let title: String
    let rpm: String
    let range: String
    let fraction: Double
    let accessibilityLabel: String
}

/// Everything the temperature half of the tab says, decided in one place.
nonisolated struct ThermalPresentation: Equatable, Sendable {
    let soc: String
    let cpu: String
    let gpu: String
    /// Nil until something has been read.
    let tone: TemperatureTone?
    let fans: [FanRow]
    let accessibilityLabel: String

    init(_ snapshot: ThermalSnapshot?) {
        soc = ThermalFormat.degrees(snapshot?.soc)
        cpu = ThermalFormat.degrees(snapshot?.cpu)
        gpu = ThermalFormat.degrees(snapshot?.gpu)
        tone = snapshot?.soc.map(TemperatureTone.init(celsius:))
        fans = (snapshot?.fans ?? []).map { fan in
            let (rpm, low, high) = (ThermalFormat.rpm(fan.rpm), ThermalFormat.rpm(fan.minRPM), ThermalFormat.rpm(fan.maxRPM))
            return FanRow(
                id: fan.index, title: "Quạt \(fan.index + 1)", rpm: rpm, range: "\(low)–\(high)", fraction: fan.fraction,
                accessibilityLabel: "Quạt \(fan.index + 1): \(rpm) vòng/phút, từ \(low) đến \(high)"
            )
        }
        guard let snapshot, snapshot.soc != nil else {
            accessibilityLabel = "Chưa đọc được nhiệt độ"
            return
        }
        let parts = [
            ("SoC", snapshot.soc), ("CPU", snapshot.cpu), ("GPU", snapshot.gpu),
        ].compactMap { name, value in value.map { "\(name) \(Int($0.rounded())) độ" } }
        accessibilityLabel = "Nhiệt độ " + parts.joined(separator: ", ")
    }
}
