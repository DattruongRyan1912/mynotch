import Foundation

/// One named EQ curve: ten band gains and a preamp. Pure value, so the audio side can take a copy.
nonisolated public struct EQProfile: Codable, Equatable, Identifiable, Sendable {
    /// Centre of each band, in Hz.
    public static let frequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    /// Applies to every band.
    public static let gainRange: ClosedRange<Double> = -24...24
    /// Applies to the preamp.
    public static let preampRange: ClosedRange<Double> = -12...12
    /// Allowed length of a name, after trimming.
    static let nameLengths = 1...40

    public var id: UUID
    public var name: String
    /// dB per band, in the order of `frequencies`. Always ten values once `clamped()`.
    public var gains: [Double]
    public var preamp: Double
    /// True when this profile is one of the built-in system presets (Nhạc, Phim, Họp, Deep Bass).
    public var isSystem: Bool

    public init(id: UUID = UUID(), name: String, gains: [Double], preamp: Double = 0, isSystem: Bool = false) {
        self.id = id
        self.name = name
        self.gains = gains
        self.preamp = preamp
        self.isSystem = isSystem
    }

    enum CodingKeys: String, CodingKey {
        case id, name, gains, preamp, isSystem
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        gains = try container.decode([Double].self, forKey: .gains)
        preamp = try container.decode(Double.self, forKey: .preamp)
        isSystem = try container.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(gains, forKey: .gains)
        try container.encode(preamp, forKey: .preamp)
        try container.encode(isSystem, forKey: .isSystem)
    }

    public static func flat(named name: String = "Phẳng") -> EQProfile {
        EQProfile(id: UUID(), name: name, gains: Array(repeating: 0, count: frequencies.count), preamp: 0, isSystem: false)
    }

    /// The default profiles of a first run: music, film, meetings and Deep Bass (eqMac).
    public static func defaults() -> [EQProfile] {
        func make(_ name: String, _ gains: [Double], _ preamp: Double) -> EQProfile {
            EQProfile(id: UUID(), name: name, gains: gains, preamp: preamp, isSystem: true)
        }
        return [
            make("Nhạc", [4, 3, 1.5, 0, -1, -1, 0, 1.5, 3, 4], 0),
            make("Phim", [5, 4, 2, 0, 0, 1.5, 2.5, 2, 1, 0], 0),
            make("Họp", [-6, -4, -2, 0, 1, 2.5, 4, 3.5, 1, 0], 0),
            make("Deep Bass (eqMac)", [14.0, 10.0, 7.2, 2.7, 0.4, 0.7, -0.5, 0.0, 1.7, 1.4], 0),
        ]
    }

    /// Stored or edited data can be wrong, and the filters must never see it: ten bands, every value in range.
    public func clamped() -> EQProfile {
        var copy = self
        let bands = Self.frequencies.count
        copy.gains = (0..<bands).map { $0 < gains.count ? Self.clamp(gains[$0]) : 0 }
        copy.preamp = Self.clampPreamp(preamp)
        return copy
    }

    /// `min`/`max` pass a NaN through, which would reach the filters; it becomes 0 dB instead.
    public static func clamp(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, gainRange.lowerBound), gainRange.upperBound)
    }

    public static func clampPreamp(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, preampRange.lowerBound), preampRange.upperBound)
    }

    /// The name as it would be stored, or nil when it is empty or longer than 40 characters.
    static func validName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return nameLengths.contains(trimmed.count) ? trimmed : nil
    }
}
