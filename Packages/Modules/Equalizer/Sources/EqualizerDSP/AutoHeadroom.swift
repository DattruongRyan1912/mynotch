import Foundation

/// Calculates required negative headroom offset from a cascade of biquad filter coefficients
/// so that boosted frequencies do not trigger wideband True-Peak limiter ducking.
public enum AutoHeadroom {
    /// Minimum positive peak required before headroom attenuation is engaged.
    /// Preserves bit-exact transparent bypass on flat or infinitesimal EQ curves.
    public static let minimumPeakDB: Double = 0.05

    /// Maximum headroom attenuation clamp (-48 dB).
    public static let maxHeadroomDB: Double = 48.0

    /// Returns negative headroom in decibels (e.g. -14.1 dB) for the given filter cascade.
    /// Cut-only curves or flat responses return exactly 0.0 dB.
    public static func headroomDB(coefficients: [BiquadCoefficients], sampleRate: Double) -> Double {
        guard sampleRate.isFinite, sampleRate > 0, !coefficients.isEmpty else {
            return 0.0
        }
        let peakDB = BiquadCoefficients.cascadePeakDB(coefficients, sampleRate: sampleRate)
        guard peakDB.isFinite, peakDB >= minimumPeakDB else {
            return 0.0
        }
        let headroom = -min(peakDB, maxHeadroomDB)
        return headroom.isFinite ? headroom : 0.0
    }
}
