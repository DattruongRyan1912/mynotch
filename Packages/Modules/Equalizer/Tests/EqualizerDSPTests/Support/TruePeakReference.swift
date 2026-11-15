import Foundation

/// Independent True-Peak Reference Oracle
/// Uses 32x windowed-sinc interpolation across audio samples to measure
/// inter-sample continuous peaks independently of production DSP code.
public enum TruePeakReference {
    public static let oversampleFactor = 32
    public static let filterRadius = 16 // 16 samples on either side = 32 original samples support

    /// Evaluates the true-peak linear maximum across audio samples using 32x sinc interpolation.
    /// - Parameters:
    ///   - samples: Raw linear PCM samples.
    ///   - excludeTransientFrames: Number of frames at the start/end to exclude (for steady-state calibration).
    public static func measureTruePeakLinear(_ samples: [Float], excludeTransientFrames: Int = 0) -> Double {
        guard !samples.isEmpty else { return 0.0 }
        let count = samples.count

        let start = max(0, min(excludeTransientFrames, count / 2))
        let end = max(start, count - start)

        var maxPeak: Double = 0.0

        // 1. Initial pass: sample peaks within measurement window
        for i in start..<end {
            let absVal = abs(Double(samples[i]))
            if absVal > maxPeak {
                maxPeak = absVal
            }
        }

        // 2. 32x Sinc interpolation for inter-sample peaks
        guard end > start + 1 else { return maxPeak }

        let nSub = oversampleFactor
        let radius = filterRadius

        for i in start..<(end - 1) {
            for sub in 1..<nSub {
                let fractional = Double(sub) / Double(nSub)
                let t = Double(i) + fractional
                var interpolated = 0.0

                let kMin = max(0, i - radius)
                let kMax = min(count - 1, i + radius + 1)

                for k in kMin...kMax {
                    let diff = t - Double(k)
                    let sincVal = lanczosSinc(diff, a: Double(radius))
                    interpolated += Double(samples[k]) * sincVal
                }

                let absInterp = abs(interpolated)
                if absInterp > maxPeak {
                    maxPeak = absInterp
                }
            }
        }

        return maxPeak
    }

    /// Evaluates True-Peak in dBTP (20 * log10(maxLinear))
    public static func measureTruePeakDBTP(_ samples: [Float], excludeTransientFrames: Int = 0) -> Double {
        let linear = measureTruePeakLinear(samples, excludeTransientFrames: excludeTransientFrames)
        guard linear > 1e-9 else { return -180.0 }
        return 20.0 * log10(linear)
    }

    private static func lanczosSinc(_ x: Double, a: Double) -> Double {
        if abs(x) < 1e-9 { return 1.0 }
        if abs(x) >= a { return 0.0 }
        let piX = Double.pi * x
        let sinc = sin(piX) / piX
        let window = sin(piX / a) / (piX / a)
        return sinc * window
    }
}
