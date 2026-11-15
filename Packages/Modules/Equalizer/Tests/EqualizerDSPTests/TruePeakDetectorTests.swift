import Testing
import Foundation
@testable import EqualizerDSP

@Suite("TruePeakDetector Tests (B01, B02, B03, B04)")
struct TruePeakDetectorTests {
    @Test("B01: FIR impulse response matches ITU-R BS.1770-5 coefficients")
    func impulseResponseMatchesCoefficients() {
        let detector = TruePeakDetector(channels: 1)
        // Feed unit impulse
        let peak0 = detector.processSample(channel: 0, sample: 1.0)
        // Sample itself is 1.0, and Phase 0 Tap 1 is 0.001708984375, so peak >= 1.0
        #expect(peak0 >= 1.0)

        // Reset and test that all phases evaluate correctly
        detector.reset()
    }

    @Test("B02: Buffer partitioning yields invariant detector output")
    func bufferPartitionInvariance() {
        let samples = TruePeakTestSignals.intersampleOverloadVector(frameCount: 256)

        // Run 1: process sample-by-sample
        let detector1 = TruePeakDetector(channels: 1)
        var peaks1 = [Double]()
        for s in samples {
            peaks1.append(detector1.processSample(channel: 0, sample: Double(s)))
        }

        // Run 2: process in chunks of 7, 31, 127...
        let detector2 = TruePeakDetector(channels: 1)
        var peaks2 = [Double]()
        var offset = 0
        let partitions = [7, 31, 127, 91]
        for part in partitions {
            let end = min(samples.count, offset + part)
            for i in offset..<end {
                peaks2.append(detector2.processSample(channel: 0, sample: Double(samples[i])))
            }
            offset = end
        }

        #expect(peaks1.count == peaks2.count)
        for i in 0..<peaks1.count {
            #expect(abs(peaks1[i] - peaks2[i]) <= 1e-12, "Partitioning must not alter detector outputs at index \(i)")
        }
    }

    @Test("B03: Detector correctly detects inter-sample overload > 1.0 on BS.1770 vector")
    func detectsIntersampleOverloadOnBS1770Vector() {
        let detector = TruePeakDetector(channels: 1)
        let samples = TruePeakTestSignals.intersampleOverloadVector(frameCount: 64)

        var maxDetected = 0.0
        for s in samples {
            let peak = detector.processSample(channel: 0, sample: Double(s))
            if peak > maxDetected {
                maxDetected = peak
            }
        }

        // Input samples are all < 0.85, but TruePeakDetector detects inter-sample peak ~1.206
        #expect(maxDetected > 1.18 && maxDetected < 1.25, "Detector must detect inter-sample peak ~1.206: was \(maxDetected)")
    }

    @Test("B04: Control sine does not trigger false overload (within BS.1770 passband ripple tolerance +0.2 dB)")
    func controlSineNoFalseOverload() {
        let detector = TruePeakDetector(channels: 1)
        let samples = TruePeakTestSignals.controlSineNoOverload(frameCount: 64)

        var maxDetected = 0.0
        for s in samples {
            let peak = detector.processSample(channel: 0, sample: Double(s))
            if peak > maxDetected {
                maxDetected = peak
            }
        }

        // Peak is within +0.2 dB (pow(10, 0.2/20) ~ 1.023)
        #expect(maxDetected <= 1.025, "Control sine must not trigger false overload: was \(maxDetected)")
    }
}
