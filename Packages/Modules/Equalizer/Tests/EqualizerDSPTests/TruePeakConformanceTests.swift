import Testing
import Foundation
@testable import EqualizerDSP

@Suite("Oracle Calibration Suite (Analytical Precision <= 0.02 dBTP)")
struct TruePeakOracleCalibrationTests {
    @Test("Oracle Calibration Case 15: fs/4, 0.50 FFS, phase 0.0° steady-state <= 0.02 dBTP")
    func oracleCase15() {
        let expectedDB = 20.0 * log10(0.50) // -6.0206 dBTP
        let samples = TruePeakTestSignals.ebuCase15(frameCount: 1024, applyFade: false)
        let oracleDB = TruePeakReference.measureTruePeakDBTP(samples, excludeTransientFrames: 16)
        #expect(abs(oracleDB - expectedDB) <= 0.02, "Case 15 oracle must be calibrated within <= 0.02 dB: expected \(expectedDB), got \(oracleDB)")
    }

    @Test("Oracle Calibration Case 16: fs/4, 0.50 FFS, phase 45.0° steady-state <= 0.02 dBTP")
    func oracleCase16() {
        let expectedDB = 20.0 * log10(0.50) // -6.0206 dBTP
        let samples = TruePeakTestSignals.ebuCase16(frameCount: 1024, applyFade: false)
        let oracleDB = TruePeakReference.measureTruePeakDBTP(samples, excludeTransientFrames: 16)
        #expect(abs(oracleDB - expectedDB) <= 0.02, "Case 16 oracle must be calibrated within <= 0.02 dB: expected \(expectedDB), got \(oracleDB)")
    }

    @Test("Oracle Calibration Case 17: fs/6, 0.50 FFS, phase 60.0° steady-state <= 0.02 dBTP")
    func oracleCase17() {
        let expectedDB = 20.0 * log10(0.50) // -6.0206 dBTP
        let samples = TruePeakTestSignals.ebuCase17(frameCount: 1024, applyFade: false)
        let oracleDB = TruePeakReference.measureTruePeakDBTP(samples, excludeTransientFrames: 16)
        #expect(abs(oracleDB - expectedDB) <= 0.02, "Case 17 oracle must be calibrated within <= 0.02 dB: expected \(expectedDB), got \(oracleDB)")
    }

    @Test("Oracle Calibration Case 18: fs/8, 0.50 FFS, phase 67.5° steady-state <= 0.02 dBTP")
    func oracleCase18() {
        let expectedDB = 20.0 * log10(0.50) // -6.0206 dBTP
        let samples = TruePeakTestSignals.ebuCase18(frameCount: 1024, applyFade: false)
        let oracleDB = TruePeakReference.measureTruePeakDBTP(samples, excludeTransientFrames: 16)
        #expect(abs(oracleDB - expectedDB) <= 0.02, "Case 18 oracle must be calibrated within <= 0.02 dB: expected \(expectedDB), got \(oracleDB)")
    }

    @Test("Oracle Calibration Case 19: fs/4, 1.414 FFS, phase 45.0° steady-state <= 0.02 dBTP")
    func oracleCase19() {
        let expectedDB = 20.0 * log10(sqrt(2.0)) // +3.0103 dBTP
        let samples = TruePeakTestSignals.ebuCase19(frameCount: 1024, applyFade: false)
        let oracleDB = TruePeakReference.measureTruePeakDBTP(samples, excludeTransientFrames: 16)
        #expect(abs(oracleDB - expectedDB) <= 0.02, "Case 19 oracle must be calibrated within <= 0.02 dB: expected \(expectedDB), got \(oracleDB)")
    }
}

@Suite("EBU Tech 3341 (2023) Table 1 Conformance Suite (10 ms Raised Cosine Fade)")
struct TruePeakEBUConformanceTests {
    // EBU Tech 3341 Table 1 Tolerance Range: [Expected - 0.4, Expected + 0.2] dBTP
    // Signals 15 to 19 must feature a 10 ms raised cosine taper at beginning and end.

    @Test("Verify 10 ms Raised Cosine Taper Duration (480 frames at 48 kHz)")
    func verifyTaperDuration() {
        let info = TruePeakTestSignals.fadeDurationInfo(sampleRate: 48_000.0)
        #expect(info.frames == 480, "10 ms at 48 kHz must be exactly 480 frames, got \(info.frames)")
        #expect(abs(info.milliseconds - 10.0) < 1e-6, "Fade duration must be 10.0 ms, got \(info.milliseconds) ms")
    }

    @Test("EBU Case 15 Conformance: fs/4, 0.50 FFS, phase 0.0° with 10 ms taper measures in [-0.4, +0.2] dBTP")
    func ebuCase15_conformance() {
        let expectedDB = 20.0 * log10(0.50) // -6.0206 dBTP
        let samples = TruePeakTestSignals.ebuCase15(frameCount: 2048, applyFade: true)

        let detector = TruePeakDetector(channels: 1)
        var detPeak = 0.0
        for s in samples {
            let p = detector.processSample(channel: 0, sample: Double(s))
            detPeak = max(detPeak, p)
        }
        let detDB = 20.0 * log10(detPeak)
        #expect(detDB >= expectedDB - 0.4 && detDB <= expectedDB + 0.2, "Detector Case 15 must be within EBU [-0.4, +0.2] dBTP, got \(detDB)")
    }

    @Test("EBU Case 16 Conformance: fs/4, 0.50 FFS, phase 45.0° with 10 ms taper measures in [-0.4, +0.2] dBTP")
    func ebuCase16_conformance() {
        let expectedDB = 20.0 * log10(0.50) // -6.0206 dBTP
        let samples = TruePeakTestSignals.ebuCase16(frameCount: 2048, applyFade: true)

        let detector = TruePeakDetector(channels: 1)
        var detPeak = 0.0
        for s in samples {
            let p = detector.processSample(channel: 0, sample: Double(s))
            detPeak = max(detPeak, p)
        }
        let detDB = 20.0 * log10(detPeak)
        #expect(detDB >= expectedDB - 0.4 && detDB <= expectedDB + 0.2, "Detector Case 16 must be within EBU [-0.4, +0.2] dBTP, got \(detDB)")
    }

    @Test("EBU Case 17 Conformance: fs/6, 0.50 FFS, phase 60.0° with 10 ms taper measures in [-0.4, +0.2] dBTP")
    func ebuCase17_conformance() {
        let expectedDB = 20.0 * log10(0.50) // -6.0206 dBTP
        let samples = TruePeakTestSignals.ebuCase17(frameCount: 2048, applyFade: true)

        let detector = TruePeakDetector(channels: 1)
        var detPeak = 0.0
        for s in samples {
            let p = detector.processSample(channel: 0, sample: Double(s))
            detPeak = max(detPeak, p)
        }
        let detDB = 20.0 * log10(detPeak)
        #expect(detDB >= expectedDB - 0.4 && detDB <= expectedDB + 0.2, "Detector Case 17 must be within EBU [-0.4, +0.2] dBTP, got \(detDB)")
    }

    @Test("EBU Case 18 Conformance: fs/8, 0.50 FFS, phase 67.5° with 10 ms taper measures in [-0.4, +0.2] dBTP")
    func ebuCase18_conformance() {
        let expectedDB = 20.0 * log10(0.50) // -6.0206 dBTP
        let samples = TruePeakTestSignals.ebuCase18(frameCount: 2048, applyFade: true)

        let detector = TruePeakDetector(channels: 1)
        var detPeak = 0.0
        for s in samples {
            let p = detector.processSample(channel: 0, sample: Double(s))
            detPeak = max(detPeak, p)
        }
        let detDB = 20.0 * log10(detPeak)
        #expect(detDB >= expectedDB - 0.4 && detDB <= expectedDB + 0.2, "Detector Case 18 must be within EBU [-0.4, +0.2] dBTP, got \(detDB)")
    }

    @Test("EBU Case 19 Conformance: fs/4, 1.414 FFS, phase 45.0° with 10 ms taper measures in [-0.4, +0.2] dBTP")
    func ebuCase19_conformance() {
        let expectedDB = 20.0 * log10(sqrt(2.0)) // +3.0103 dBTP
        let samples = TruePeakTestSignals.ebuCase19(frameCount: 2048, applyFade: true)

        let detector = TruePeakDetector(channels: 1)
        var detPeak = 0.0
        for s in samples {
            let p = detector.processSample(channel: 0, sample: Double(s))
            detPeak = max(detPeak, p)
        }
        let detDB = 20.0 * log10(detPeak)
        #expect(detDB >= expectedDB - 0.4 && detDB <= expectedDB + 0.2, "Detector Case 19 must be within EBU [-0.4, +0.2] dBTP, got \(detDB)")
    }

    @Test("EBU Case 20: 4x burst downsampled offset 0 measures in [-0.4, +0.2] dBTP")
    func ebuCase20_burstDownsampleOffset0() {
        let expectedDB = 0.0
        let samples = TruePeakTestSignals.ebuCase20(frameCount: 512)
        let oracleDB = TruePeakReference.measureTruePeakDBTP(samples, excludeTransientFrames: 16)
        #expect(oracleDB >= -0.4 && oracleDB <= 0.2, "Case 20 oracle must be within EBU [-0.4, +0.2] dBTP, got \(oracleDB)")

        let detector = TruePeakDetector(channels: 1)
        var detPeak = 0.0
        for (i, s) in samples.enumerated() {
            let p = detector.processSample(channel: 0, sample: Double(s))
            if i >= 16 {
                detPeak = max(detPeak, p)
            }
        }
        let detDB = 20.0 * log10(detPeak)
        #expect(detDB >= expectedDB - 0.4 && detDB <= expectedDB + 0.2, "Detector Case 20 must be within EBU [-0.4, +0.2] dBTP, got \(detDB)")
    }

    @Test("EBU Case 21: 4x burst downsampled offset 1 measures in [-0.4, +0.2] dBTP")
    func ebuCase21_burstDownsampleOffset1() {
        let expectedDB = 0.0
        let samples = TruePeakTestSignals.ebuCase21(frameCount: 512)
        let oracleDB = TruePeakReference.measureTruePeakDBTP(samples, excludeTransientFrames: 16)
        #expect(oracleDB >= -0.4 && oracleDB <= 0.2, "Case 21 oracle must be within EBU [-0.4, +0.2] dBTP, got \(oracleDB)")

        let detector = TruePeakDetector(channels: 1)
        var detPeak = 0.0
        for (i, s) in samples.enumerated() {
            let p = detector.processSample(channel: 0, sample: Double(s))
            if i >= 16 {
                detPeak = max(detPeak, p)
            }
        }
        let detDB = 20.0 * log10(detPeak)
        #expect(detDB >= expectedDB - 0.4 && detDB <= expectedDB + 0.2, "Detector Case 21 must be within EBU [-0.4, +0.2] dBTP, got \(detDB)")
    }

    @Test("EBU Case 22: 4x burst downsampled offset 2 measures in [-0.4, +0.2] dBTP")
    func ebuCase22_burstDownsampleOffset2() {
        let expectedDB = 0.0
        let samples = TruePeakTestSignals.ebuCase22(frameCount: 512)
        let oracleDB = TruePeakReference.measureTruePeakDBTP(samples, excludeTransientFrames: 16)
        #expect(oracleDB >= -0.4 && oracleDB <= 0.2, "Case 22 oracle must be within EBU [-0.4, +0.2] dBTP, got \(oracleDB)")

        let detector = TruePeakDetector(channels: 1)
        var detPeak = 0.0
        for (i, s) in samples.enumerated() {
            let p = detector.processSample(channel: 0, sample: Double(s))
            if i >= 16 {
                detPeak = max(detPeak, p)
            }
        }
        let detDB = 20.0 * log10(detPeak)
        #expect(detDB >= expectedDB - 0.4 && detDB <= expectedDB + 0.2, "Detector Case 22 must be within EBU [-0.4, +0.2] dBTP, got \(detDB)")
    }

    @Test("EBU Case 23: 4x burst downsampled offset 3 measures in [-0.4, +0.2] dBTP")
    func ebuCase23_burstDownsampleOffset3() {
        let expectedDB = 0.0
        let samples = TruePeakTestSignals.ebuCase23(frameCount: 512)
        let oracleDB = TruePeakReference.measureTruePeakDBTP(samples, excludeTransientFrames: 16)
        #expect(oracleDB >= -0.4 && oracleDB <= 0.2, "Case 23 oracle must be within EBU [-0.4, +0.2] dBTP, got \(oracleDB)")

        let detector = TruePeakDetector(channels: 1)
        var detPeak = 0.0
        for (i, s) in samples.enumerated() {
            let p = detector.processSample(channel: 0, sample: Double(s))
            if i >= 16 {
                detPeak = max(detPeak, p)
            }
        }
        let detDB = 20.0 * log10(detPeak)
        #expect(detDB >= expectedDB - 0.4 && detDB <= expectedDB + 0.2, "Detector Case 23 must be within EBU [-0.4, +0.2] dBTP, got \(detDB)")
    }
}
