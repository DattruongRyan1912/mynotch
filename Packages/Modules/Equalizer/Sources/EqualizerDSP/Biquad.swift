import Foundation

/// One second-order section, normalised so that a0 = 1: `y = b0·x + z1`, `z1 = b1·x − a1·y + z2`, `z2 = b2·x − a2·y`.
/// Computed in `Double` and stored as `Float`, the width the audio thread runs at.
nonisolated public struct BiquadCoefficients: Equatable, Sendable {
    public var b0, b1, b2, a1, a2: Float

    public init(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    /// Passes the signal through untouched.
    public static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    /// Past this share of the sample rate the cookbook's peak degenerates (its poles reach the unit circle at Nyquist), so no band is built there.
    static let highestCentre = 0.45

    /// A peaking filter from the RBJ Audio EQ Cookbook: `gainDB` at `frequency`, flat far from it.
    /// The identity when there is nothing to do (0 dB) or nothing sensible to build: a centre at or above 0.45 × the sample rate
    /// (a Bluetooth headset in a call runs at 16 kHz, where the top bands do not fit) or an unusable argument.
    public static func peaking(frequency: Double, gainDB: Double, q: Double, sampleRate: Double) -> BiquadCoefficients {
        guard gainDB.isFinite, gainDB != 0, q.isFinite, q > 0, sampleRate.isFinite, sampleRate > 0,
              frequency.isFinite, frequency > 0, frequency < sampleRate * highestCentre
        else { return .identity }
        let amplitude = pow(10, gainDB / 40)
        let omega = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosine = cos(omega)
        let a0 = 1 + alpha / amplitude
        return BiquadCoefficients(
            b0: Float((1 + alpha * amplitude) / a0),
            b1: Float(-2 * cosine / a0),
            b2: Float((1 - alpha * amplitude) / a0),
            a1: Float(-2 * cosine / a0),
            a2: Float((1 - alpha / amplitude) / a0)
        )
    }

    /// The response in dB at `frequency`, from the coefficients as stored (already rounded to `Float`), so it is what the audio thread does.
    public func magnitudeDB(at frequency: Double, sampleRate: Double) -> Double {
        let omega = 2 * Double.pi * frequency / sampleRate
        let (cos1, sin1, cos2, sin2) = (cos(omega), sin(omega), cos(2 * omega), sin(2 * omega))
        let numeratorReal = Double(b0) + Double(b1) * cos1 + Double(b2) * cos2
        let numeratorImaginary = -(Double(b1) * sin1 + Double(b2) * sin2)
        let denominatorReal = 1 + Double(a1) * cos1 + Double(a2) * cos2
        let denominatorImaginary = -(Double(a1) * sin1 + Double(a2) * sin2)
        return 20 * log10(hypot(numeratorReal, numeratorImaginary) / hypot(denominatorReal, denominatorImaginary))
    }
}
