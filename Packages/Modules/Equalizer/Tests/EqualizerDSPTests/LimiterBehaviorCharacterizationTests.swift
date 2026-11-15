import Foundation
import Testing
@testable import EqualizerDSP

/// TC-0: Diagnostic Characterization of TruePeakLimiter under heavy sub-bass boost (32 Hz + 1 kHz carrier).
/// Validates whether wideband ducking matches static ceiling/peak ratio or exhibits excess latching distortion.
@Suite("Limiter Behavior Characterization Suite (TC-0)")
struct LimiterBehaviorCharacterizationTests {

    @Test("TC-0: Two-tone 32 Hz + 1 kHz characterization across +12 dB to +24 dB band 0 gain")
    func twoToneLimiterCharacterization() {
        let sampleRate: Double = 48_000.0
        let blockSize = 256
        let totalBlocks = 190 // 190 * 256 = 48,640 samples (~1.013 s)
        let totalFrames = totalBlocks * blockSize
        let analysisFrames = 24_000 // Exactly 0.5 s: 16 cycles of 32 Hz, 500 cycles of 1000 Hz

        let thresholdLinear = pow(10.0, (-0.5 - 0.70) / 20.0) // 0.8709635899458814
        let ceilingLinear = pow(10.0, EQChain.limiterCeilingDB / 20.0) // 0.9440608762859234

        // 1. Measure baseline 1 kHz amplitude at 0 dB gain
        let refChain = EQChain(channels: 1)
        refChain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: sampleRate)
        let refSamples = runTwoToneSignal(chain: refChain, totalFrames: totalFrames, blockSize: blockSize, sampleRate: sampleRate)
        let refTail = Array(refSamples[(refSamples.count - analysisFrames)...])
        let refMid = measureToneAmplitude(samples: refTail, targetFrequency: 1000.0, sampleRate: sampleRate)
        #expect(abs(refMid - 0.1) < 0.005, "Baseline 1 kHz tone at 0.1 amplitude must measure ~0.10, got \(refMid)")

        var reductions: [Double: Double] = [:]
        var expecteds: [Double: Double] = [:]

        Swift.print("================ TC-0 CHARACTERIZATION TABLE ================")
        Swift.print(" Gain(dB) | Slider% | Measured Duck | Expected Duck | Residual")
        Swift.print("-------------------------------------------------------------")

        let testGains: [Double] = [12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0]

        for g in testGains {
            let chain = EQChain(channels: 1)
            var gains = Array(repeating: 0.0, count: 10)
            gains[0] = g
            chain.setParameters(gains: gains, preampDB: 0.0, sampleRate: sampleRate)

            let outputSamples = runTwoToneSignal(chain: chain, totalFrames: totalFrames, blockSize: blockSize, sampleRate: sampleRate)
            let tailSamples = Array(outputSamples[(outputSamples.count - analysisFrames)...])

            // Check (d): Peak clamping
            let maxOut = outputSamples.map { abs($0) }.max() ?? 0.0
            #expect(Double(maxOut) <= ceilingLinear + 1e-4, "Peak output at G=\(g) dB must be <= ceilingLinear + 1e-4, got \(maxOut)")

            let midAmp = measureToneAmplitude(samples: tailSamples, targetFrequency: 1000.0, sampleRate: sampleRate)
            let safeMid = max(midAmp, 1e-7)
            let reduction = 20.0 * log10(refMid / safeMid)
            reductions[g] = reduction

            // Expected ducking based on linear sum of peak biquad magnitude responses vs threshold
            let c32 = BiquadCoefficients.peaking(frequency: 32.0, gainDB: g, q: EQChain.q, sampleRate: sampleRate)
            let m32 = c32.magnitudeDB(at: 32.0, sampleRate: sampleRate)
            let m1k = c32.magnitudeDB(at: 1000.0, sampleRate: sampleRate)

            let peakIn = 0.1 * (pow(10.0, m32 / 20.0) + pow(10.0, m1k / 20.0))
            let expected = max(0.0, 20.0 * log10(peakIn / thresholdLinear))
            expecteds[g] = expected

            let sliderPercent = (g + 24.0) / 48.0 * 100.0
            let residual = reduction - expected
            Swift.print(String(format: " %+7.1f | %6.1f%% | %11.2f dB | %11.2f dB | %+7.2f dB", g, sliderPercent, reduction, expected, residual))

            // Assertion (a): reduction(G) <= expected(G) + 1.5 dB (no excessive hold latch ducking)
            #expect(reduction <= expected + 1.5, "Reduction at \(g) dB (\(reduction) dB) exceeded expected (\(expected) dB) by > 1.5 dB")

            // Assertion (b): reduction(G) >= expected(G) - 1.5 dB (sanity check: limiter works)
            #expect(reduction >= expected - 1.5, "Reduction at \(g) dB (\(reduction) dB) is less than expected (\(expected) dB) by > 1.5 dB")
        }
        Swift.print("=============================================================")

        // Assertion (c): No cliff between adjacent 1 dB steps (step delta <= 1.25 dB)
        for i in 1..<testGains.count {
            let prevG = testGains[i - 1]
            let currG = testGains[i]
            let rPrev = reductions[prevG]!
            let rCurr = reductions[currG]!
            let stepDelta = abs(rCurr - rPrev)
            #expect(stepDelta <= 1.25, "Step delta between \(prevG) dB and \(currG) dB was \(stepDelta) dB (must be <= 1.25 dB)")
        }

        // Assertion (e): Below knee at +12 dB, reduction must be < 0.3 dB
        let r12 = reductions[12.0]!
        #expect(r12 < 0.3, "Ducking at +12 dB must be minimal (< 0.3 dB), got \(r12) dB")
    }

    private func runTwoToneSignal(chain: EQChain, totalFrames: Int, blockSize: Int, sampleRate: Double) -> [Float] {
        var result = [Float]()
        result.reserveCapacity(totalFrames)

        var frameIndex = 0
        while frameIndex < totalFrames {
            let currentBlockFrames = min(blockSize, totalFrames - frameIndex)
            var inputBlock = [Float](repeating: 0, count: currentBlockFrames)
            for i in 0..<currentBlockFrames {
                let t = Double(frameIndex + i) / sampleRate
                let s32 = 0.1 * sin(2.0 * Double.pi * 32.0 * t)
                let s1k = 0.1 * sin(2.0 * Double.pi * 1000.0 * t)
                inputBlock[i] = Float(s32 + s1k)
            }

            let block = AudioBlock(channels: 1, frames: currentBlockFrames)
            block.load(inputBlock)
            chain.process(block.list, frames: currentBlockFrames)
            result.append(contentsOf: block.samples())

            frameIndex += currentBlockFrames
        }

        return result
    }

    /// Exact DFT amplitude calculation at a single bin without window leakage (because length is an exact multiple of periods).
    private func measureToneAmplitude(samples: [Float], targetFrequency: Double, sampleRate: Double) -> Double {
        let n = samples.count
        guard n > 0 else { return 0.0 }

        var realSum: Double = 0.0
        var imagSum: Double = 0.0
        let omega = 2.0 * Double.pi * targetFrequency / sampleRate

        for i in 0..<n {
            let val = Double(samples[i])
            let angle = omega * Double(i)
            realSum += val * cos(angle)
            imagSum += val * sin(angle)
        }

        let mag = hypot(realSum, imagSum)
        return (mag * 2.0) / Double(n)
    }
}
