import Foundation

/// One second-order section, normalised so that a0 = 1: `y = b0·x + z1`, `z1 = b1·x − a1·y + z2`, `z2 = b2·x − a2·y`.
/// Computed and stored in `Double` (64-bit floating point) for pristine precision and identical parity with Apple CoreAudio.
nonisolated public struct BiquadCoefficients: Equatable, Sendable {
    public var b0, b1, b2, a1, a2: Double

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    public init(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        self.b0 = Double(b0)
        self.b1 = Double(b1)
        self.b2 = Double(b2)
        self.a1 = Double(a1)
        self.a2 = Double(a2)
    }

    /// Passes the signal through untouched.
    public static let identity = BiquadCoefficients(b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0)

    /// Past this share of the sample rate the cookbook's peak degenerates (its poles reach the unit circle at Nyquist), so no band is built there.
    public static let highestCentre = 0.45

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
            b0: (1 + alpha * amplitude) / a0,
            b1: -2 * cosine / a0,
            b2: (1 - alpha * amplitude) / a0,
            a1: -2 * cosine / a0,
            a2: (1 - alpha / amplitude) / a0
        )
    }

    /// Decodes the 5 raw `Float64` values from Apple CoreAudio `kAUNBandEQProperty_BiquadCoefficients` (Property ID 2203).
    /// Empirical mapping proven down to -142.41 dB RMS residual:
    /// `b0 = v[2], b1 = v[0], b2 = v[4], a1 = v[3], a2 = v[1]`
    /// Follows Direct Form II Transposed negative feedback convention:
    /// `y = b0 * x + z1`
    /// `z1 = b1 * x - a1 * y + z2`
    /// `z2 = b2 * x - a2 * y`
    public static func fromAppleAUNBandEQ(raw: [Double]) -> BiquadCoefficients {
        guard raw.count >= 5 else { return .identity }
        let (v0, v1, v2, v3, v4) = (raw[0], raw[1], raw[2], raw[3], raw[4])
        guard v0.isFinite, v1.isFinite, v2.isFinite, v3.isFinite, v4.isFinite else { return .identity }
        return BiquadCoefficients(b0: v2, b1: v0, b2: v4, a1: v3, a2: v1)
    }

    /// The response in dB at `frequency`, from the 64-bit coefficients.
    public func magnitudeDB(at frequency: Double, sampleRate: Double) -> Double {
        guard frequency.isFinite, frequency > 0, sampleRate.isFinite, sampleRate > 0 else { return 0 }
        let omega = 2 * Double.pi * frequency / sampleRate
        let (cos1, sin1, cos2, sin2) = (cos(omega), sin(omega), cos(2 * omega), sin(2 * omega))
        let numeratorReal = b0 + b1 * cos1 + b2 * cos2
        let numeratorImaginary = -(b1 * sin1 + b2 * sin2)
        let denominatorReal = 1 + a1 * cos1 + a2 * cos2
        let denominatorImaginary = -(a1 * sin1 + a2 * sin2)
        let numMag = hypot(numeratorReal, numeratorImaginary)
        let denMag = hypot(denominatorReal, denominatorImaginary)
        guard denMag > 0 else { return 0 }
        return 20 * log10(numMag / denMag)
    }

    /// The highest point of the cascade's frequency response between 20 Hz and 20 kHz (or up to 0.45 * sampleRate).
    public static func cascadePeakDB(_ bands: [BiquadCoefficients], sampleRate: Double) -> Double {
        guard sampleRate.isFinite, sampleRate > 0 else { return 0 }
        let top = min(20_000, sampleRate * highestCentre)
        var peak = -Double.infinity
        var frequency = 20.0
        while frequency <= top {
            let mag = bands.reduce(0.0) { $0 + $1.magnitudeDB(at: frequency, sampleRate: sampleRate) }
            peak = max(peak, mag)
            frequency *= pow(2, 1.0 / 24)
        }
        return peak.isFinite ? peak : 0
    }
}
