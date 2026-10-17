import Foundation

/// One named EQ curve: ten band gains and a preamp. Pure value, so the audio side can take a copy.
nonisolated public struct EQProfile: Codable, Equatable, Identifiable, Sendable {
    /// Centre of each band, in Hz.
    public static let frequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    /// Applies to every band and to the preamp.
    public static let gainRange: ClosedRange<Double> = -12...12
    /// Allowed length of a name, after trimming.
    static let nameLengths = 1...40

    public var id: UUID
    public var name: String
    /// dB per band, in the order of `frequencies`. Always ten values once `clamped()`.
    public var gains: [Double]
    public var preamp: Double

    public static func flat(named name: String) -> EQProfile {
        EQProfile(id: UUID(), name: name, gains: Array(repeating: 0, count: frequencies.count), preamp: 0)
    }

    /// The three profiles of a first run: music, film and meetings.
    public static func defaults() -> [EQProfile] {
        func make(_ name: String, _ gains: [Double], _ preamp: Double) -> EQProfile {
            EQProfile(id: UUID(), name: name, gains: gains, preamp: preamp)
        }
        return [
            make("Nhạc", [4, 3, 1.5, 0, -1, -1, 0, 1.5, 3, 4], -4),
            make("Phim", [5, 4, 2, 0, 0, 1.5, 2.5, 2, 1, 0], -4),
            make("Họp", [-6, -4, -2, 0, 1, 2.5, 4, 3.5, 1, 0], -2),
        ]
    }

    /// Stored or edited data can be wrong, and the filters must never see it: ten bands, every value in range.
    public func clamped() -> EQProfile {
        var copy = self
        let bands = Self.frequencies.count
        copy.gains = (0..<bands).map { $0 < gains.count ? Self.clamp(gains[$0]) : 0 }
        copy.preamp = Self.clamp(preamp)
        return copy
    }

    /// `min`/`max` pass a NaN through, which would reach the filters; it becomes 0 dB instead.
    static func clamp(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, gainRange.lowerBound), gainRange.upperBound)
    }

    /// The name as it would be stored, or nil when it is empty or longer than 40 characters.
    static func validName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return nameLengths.contains(trimmed.count) ? trimmed : nil
    }
}
