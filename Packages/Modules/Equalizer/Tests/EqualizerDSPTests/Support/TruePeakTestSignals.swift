import Foundation

public enum TruePeakTestSignals {
    /// Intersample overload test vector conforming to ITU-R BS.1770-5:
    /// x[n] = 1.2 * sin(pi*n/2 + pi/4)
    /// 4-sample repeating cycle: [+0.8485281374, +0.8485281374, -0.8485281374, -0.8485281374]
    /// Sample peak ~0.848528 (< 1.0, sub-threshold on sample-peak meters),
    /// but analytical continuous true peak is 1.2 (+1.5836 dBTP).
    public static func intersampleOverloadVector(frameCount: Int) -> [Float] {
        let a = Float(1.2 * sin(Double.pi / 4.0)) // ~0.84852814
        let cycle = [a, a, -a, -a]
        var samples = [Float]()
        samples.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            samples.append(cycle[i % 4])
        }
        return samples
    }

    /// Control signal: 1.0 * sin(pi*n/2)
    /// Cycle: [0.0, 1.0, 0.0, -1.0]
    /// Both sample peak and true peak are exactly 1.0 (0.0 dBTP).
    public static func controlSineNoOverload(frameCount: Int) -> [Float] {
        let cycle: [Float] = [0.0, 1.0, 0.0, -1.0]
        var samples = [Float]()
        samples.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            samples.append(cycle[i % 4])
        }
        return samples
    }

    /// Safe noise / low-level test signal (amplitude 0.1, -20 dBFS)
    public static func safeLowAmplitudeSine(frameCount: Int, sampleRate: Double = 48_000) -> [Float] {
        var samples = [Float]()
        samples.reserveCapacity(frameCount)
        let freq = 997.0
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            samples.append(Float(0.1 * sin(2.0 * Double.pi * freq * t)))
        }
        return samples
    }

    /// Over-unity input sequence to test clamp on flat bypass: [1.5, -2.0, 0.25, 1.0]
    public static let loudOverUnitySamples: [Float] = [1.5, -2.0, 0.25, 1.0]

    // MARK: - EBU Tech 3341 (2023) Table 1 Test Cases 15 to 23

    /// 10 ms raised cosine taper for EBU Tech 3341 test signals at start and end
    public static func applyRaisedCosineFade(_ amp: Double, i: Int, frameCount: Int, sampleRate: Double) -> Double {
        let fadeFrames = Int((0.010 * sampleRate).rounded()) // 480 frames at 48 kHz (exactly 10.0 ms)
        guard fadeFrames > 0, frameCount >= 2 * fadeFrames else { return amp }
        if i < fadeFrames {
            return amp * 0.5 * (1.0 - cos(Double.pi * Double(i) / Double(fadeFrames)))
        } else if i >= frameCount - fadeFrames {
            let rem = Double(frameCount - 1 - i)
            return amp * 0.5 * (1.0 - cos(Double.pi * rem / Double(fadeFrames)))
        }
        return amp
    }

    /// Verification helper returning the exact fade duration in frames and milliseconds
    public static func fadeDurationInfo(sampleRate: Double = 48_000.0) -> (frames: Int, milliseconds: Double) {
        let frames = Int((0.010 * sampleRate).rounded())
        return (frames, Double(frames) / sampleRate * 1000.0)
    }

    /// EBU Tech 3341 Case 15: Stereo sine wave fs/4, amplitude 0.50 FFS, phase 0.0°
    /// Expected max true-peak: -6.0 dBTP (+0.2 / -0.4 dBTP)
    public static func ebuCase15(frameCount: Int, sampleRate: Double = 48_000, applyFade: Bool = true) -> [Float] {
        var samples = [Float]()
        samples.reserveCapacity(frameCount)
        let freq = sampleRate / 4.0
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let baseAmp = 0.50
            let amp = applyFade ? applyRaisedCosineFade(baseAmp, i: i, frameCount: frameCount, sampleRate: sampleRate) : baseAmp
            samples.append(Float(amp * sin(2.0 * Double.pi * freq * t)))
        }
        return samples
    }

    /// EBU Tech 3341 Case 16: Stereo sine wave fs/4, amplitude 0.50 FFS, phase 45.0°
    /// Expected max true-peak: -6.0 dBTP (+0.2 / -0.4 dBTP)
    public static func ebuCase16(frameCount: Int, sampleRate: Double = 48_000, applyFade: Bool = true) -> [Float] {
        var samples = [Float]()
        samples.reserveCapacity(frameCount)
        let freq = sampleRate / 4.0
        let phase = Double.pi / 4.0
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let baseAmp = 0.50
            let amp = applyFade ? applyRaisedCosineFade(baseAmp, i: i, frameCount: frameCount, sampleRate: sampleRate) : baseAmp
            samples.append(Float(amp * sin(2.0 * Double.pi * freq * t + phase)))
        }
        return samples
    }

    /// EBU Tech 3341 Case 17: Stereo sine wave fs/6, amplitude 0.50 FFS, phase 60.0°
    /// Expected max true-peak: -6.0 dBTP (+0.2 / -0.4 dBTP)
    public static func ebuCase17(frameCount: Int, sampleRate: Double = 48_000, applyFade: Bool = true) -> [Float] {
        var samples = [Float]()
        samples.reserveCapacity(frameCount)
        let freq = sampleRate / 6.0
        let phase = Double.pi / 3.0 // 60 deg
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let baseAmp = 0.50
            let amp = applyFade ? applyRaisedCosineFade(baseAmp, i: i, frameCount: frameCount, sampleRate: sampleRate) : baseAmp
            samples.append(Float(amp * sin(2.0 * Double.pi * freq * t + phase)))
        }
        return samples
    }

    /// EBU Tech 3341 Case 18: Stereo sine wave fs/8, amplitude 0.50 FFS, phase 67.5°
    /// Expected max true-peak: -6.0 dBTP (+0.2 / -0.4 dBTP)
    public static func ebuCase18(frameCount: Int, sampleRate: Double = 48_000, applyFade: Bool = true) -> [Float] {
        var samples = [Float]()
        samples.reserveCapacity(frameCount)
        let freq = sampleRate / 8.0
        let phase = 67.5 * Double.pi / 180.0 // 3pi/8
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let baseAmp = 0.50
            let amp = applyFade ? applyRaisedCosineFade(baseAmp, i: i, frameCount: frameCount, sampleRate: sampleRate) : baseAmp
            samples.append(Float(amp * sin(2.0 * Double.pi * freq * t + phase)))
        }
        return samples
    }

    /// EBU Tech 3341 Case 19: Stereo sine wave fs/4, amplitude 1.41 FFS (sqrt(2)), phase 45.0°
    /// Expected max true-peak: +3.0 dBTP (+0.2 / -0.4 dBTP)
    public static func ebuCase19(frameCount: Int, sampleRate: Double = 48_000, applyFade: Bool = true) -> [Float] {
        var samples = [Float]()
        samples.reserveCapacity(frameCount)
        let freq = sampleRate / 4.0
        let phase = Double.pi / 4.0
        let baseAmp = sqrt(2.0)
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let amp = applyFade ? applyRaisedCosineFade(baseAmp, i: i, frameCount: frameCount, sampleRate: sampleRate) : baseAmp
            samples.append(Float(amp * sin(2.0 * Double.pi * freq * t + phase)))
        }
        return samples
    }

    // MARK: - EBU Tech 3341 Cases 20 to 23 (4x synthesized burst + anti-alias FIR + downsampled)

    private static let antiAliasTaps: [Double] = [
        -0.0, 1.308e-05, 8.833e-05, 0.0002049, 0.00021481, -9.63e-05, -0.00083106, -0.00176236,
        -0.00224027, -0.00139782, 0.0013026, 0.00539106, 0.00902078, 0.00936847, 0.00395639,
        -0.00751033, -0.02171339, -0.03173139, -0.02902488, -0.00695982, 0.03553972, 0.09201923,
        0.14949816, 0.19246032, 0.2083795, 0.19246032, 0.14949816, 0.09201923, 0.03553972,
        -0.00695982, -0.02902488, -0.03173139, -0.02171339, -0.00751033, 0.00395639, 0.00936847,
        0.00902078, 0.00539106, 0.0013026, -0.00139782, -0.00224027, -0.00176236, -0.00083106,
        -9.63e-05, 0.00021481, 0.0002049, 8.833e-05, 1.308e-05, -0.0
    ]

    /// Generates EBU Cases 20-23: Background fs/6 (0.50 FFS) + 1 period burst of fs/4 (1.00 FFS)
    /// synthesized at 4*fs, continuous phase, filtered with anti-alias FIR, downsampled with specified offset (0..3).
    /// Expected max true-peak: 0.0 dBTP (+0.2 / -0.4 dBTP).
    public static func ebuCases20to23(offset: Int, frameCount: Int, sampleRate: Double = 48_000) -> [Float] {
        let fs4 = sampleRate * 4.0
        let total4x = max(frameCount * 4 + 256, 4 * 512)
        let t0 = 4 * 128 // burst start at frame 128

        let omegaBG = 2.0 * Double.pi * (sampleRate / 6.0) / fs4
        let omegaBurst = 2.0 * Double.pi * (sampleRate / 4.0) / fs4

        var highRate = [Double]()
        highRate.reserveCapacity(total4x)

        for i in 0..<total4x {
            if i < t0 {
                highRate.append(0.50 * sin(omegaBG * Double(i)))
            } else if i < t0 + 16 {
                let phi0 = omegaBG * Double(t0)
                highRate.append(1.00 * sin(phi0 + omegaBurst * Double(i - t0)))
            } else {
                let phi0 = omegaBG * Double(t0)
                highRate.append(0.50 * sin(phi0 + omegaBG * Double(i - (t0 + 16))))
            }
        }

        // Apply anti-alias FIR filter
        let taps = antiAliasTaps
        let tapCount = taps.count
        var filtered4x = [Double](repeating: 0.0, count: total4x)
        for i in 0..<total4x {
            var sum = 0.0
            for k in 0..<tapCount {
                if i - k >= 0 {
                    sum += taps[k] * highRate[i - k]
                }
            }
            filtered4x[i] = sum
        }

        // Downsample with given offset
        let safeOffset = max(0, min(offset, 3))
        var downsampled = [Float]()
        downsampled.reserveCapacity(frameCount)

        var idx = safeOffset
        while idx < total4x && downsampled.count < frameCount {
            downsampled.append(Float(filtered4x[idx]))
            idx += 4
        }

        return downsampled
    }

    public static func ebuCase20(frameCount: Int, sampleRate: Double = 48_000) -> [Float] {
        ebuCases20to23(offset: 0, frameCount: frameCount, sampleRate: sampleRate)
    }

    public static func ebuCase21(frameCount: Int, sampleRate: Double = 48_000) -> [Float] {
        ebuCases20to23(offset: 1, frameCount: frameCount, sampleRate: sampleRate)
    }

    public static func ebuCase22(frameCount: Int, sampleRate: Double = 48_000) -> [Float] {
        ebuCases20to23(offset: 2, frameCount: frameCount, sampleRate: sampleRate)
    }

    public static func ebuCase23(frameCount: Int, sampleRate: Double = 48_000) -> [Float] {
        ebuCases20to23(offset: 3, frameCount: frameCount, sampleRate: sampleRate)
    }
}
