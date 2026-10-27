import Foundation

/// Bass and treble added at low volume, so music keeps its body when the Mac plays quietly.
///
/// The ear loses the low and the high end faster than the middle as the level drops (the equal-loudness contours of ISO 226).
/// Below `referenceVolume` the bands under 200 Hz and over 6 kHz are raised in proportion to how far the device's volume sits
/// below it; at or above it nothing changes. A port of MyEQ's `LoudnessCompensationCalculator`, on `EQChain.frequencies`.
///
/// The tap hands the chain the full-scale mix: the device's volume is applied after it. So a boost is paid for with an equal drop
/// of the preamp (`apply`), or loud bass would be clipped at any volume.
nonisolated public enum LoudnessCompensation {
    /// The device volume (0...1, the scalar the volume keys move in sixteenths) at and above which nothing is added.
    public static let referenceVolume = 0.6
    public static let maxBassDB = 8.5
    public static let maxTrebleDB = 4.0
    static let bassFull = 55.0
    static let bassCutoff = 200.0
    static let trebleStart = 6000.0
    static let trebleFull = 13000.0

    /// 0 at or above `referenceVolume`, 1 at silence.
    public static func deficit(volume: Double) -> Double {
        guard volume.isFinite, volume < referenceVolume else { return 0 }
        return (referenceVolume - max(volume, 0)) / referenceVolume
    }

    /// dB to add to each band of `frequencies`: full below 55 Hz and above 13 kHz, fading out along a half cosine to 200 Hz and 6 kHz.
    public static func gains(volume: Double, frequencies: [Double] = EQChain.frequencies) -> [Double] {
        let deficit = deficit(volume: volume)
        guard deficit > 0 else { return Array(repeating: 0, count: frequencies.count) }
        let bass = maxBassDB * deficit
        let treble = maxTrebleDB * deficit
        return frequencies.map { frequency in
            switch frequency {
            case ...bassFull: bass
            case ..<bassCutoff: bass * 0.5 * (1 + cos(.pi * (frequency - bassFull) / (bassCutoff - bassFull)))
            case ...trebleStart: 0
            case ..<trebleFull: treble * 0.5 * (1 - cos(.pi * (frequency - trebleStart) / (trebleFull - trebleStart)))
            default: treble
            }
        }
    }

    /// The profile with the compensation for `volume` added, and its preamp lowered by however much the boost raises the curve's
    /// peak. Unchanged, value for value, when `volume` is nil (a device without a volume) or at or above `referenceVolume`, so a flat
    /// profile still passes through bit for bit.
    public static func apply(volume: Double?, gains: [Double], preampDB: Double, sampleRate: Double) -> (gains: [Double], preampDB: Double) {
        guard let volume, deficit(volume: volume) > 0 else { return (gains, preampDB) }
        let base = EQChain.frequencies.indices.map { $0 < gains.count && gains[$0].isFinite ? gains[$0] : 0 }
        let boosted = zip(base, Self.gains(volume: volume)).map { min($0 + $1, EQChain.gainRange.upperBound) }
        let lift = max(0, peakDB(boosted, sampleRate: sampleRate) - max(0, peakDB(base, sampleRate: sampleRate)))
        return (boosted, max(preampDB - lift, EQChain.gainRange.lowerBound))
    }

    /// The highest point of the cascade's response between 20 Hz and 20 kHz (or just under the highest band that fits), in dB.
    /// The bands overlap, so this is above the largest single gain: two neighbours at +8.5 dB peak higher between them.
    static func peakDB(_ gains: [Double], sampleRate: Double) -> Double {
        let bands = zip(EQChain.frequencies, gains).map {
            BiquadCoefficients.peaking(frequency: $0, gainDB: $1, q: EQChain.q, sampleRate: sampleRate)
        }
        let top = min(20_000, sampleRate * 0.45)
        var peak = -Double.infinity
        var frequency = 20.0
        while frequency <= top {
            peak = max(peak, bands.reduce(0) { $0 + $1.magnitudeDB(at: frequency, sampleRate: sampleRate) })
            frequency *= pow(2, 1.0 / 24)
        }
        return peak
    }
}
