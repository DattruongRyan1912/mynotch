import Foundation
import Testing
@testable import EqualizerDSP

/// TC-1 & TC-2: Unit tests for AutoHeadroom calculation and EQChain headroom attenuation.
@Suite("AutoHeadroom Tests")
struct AutoHeadroomTests {

    let sampleRate: Double = 48_000.0

    // MARK: - TC-1: Happy Path & Pure Calculation

    @Test("Flat profile (all identity) returns exactly 0.0 dB headroom")
    func flatProfileReturnsZeroHeadroom() {
        let flat = Array(repeating: BiquadCoefficients.identity, count: 10)
        let headroom = AutoHeadroom.headroomDB(coefficients: flat, sampleRate: sampleRate)
        #expect(headroom == 0.0)
    }

    @Test("Single band 0 boost (+14 dB) returns negative headroom matching cascade peak within 0.01 dB")
    func singleBand14dBHeadroom() {
        var coeffs = Array(repeating: BiquadCoefficients.identity, count: 10)
        coeffs[0] = .peaking(frequency: 32.0, gainDB: 14.0, q: EQChain.q, sampleRate: sampleRate)

        let peak = BiquadCoefficients.cascadePeakDB(coeffs, sampleRate: sampleRate)
        let headroom = AutoHeadroom.headroomDB(coefficients: coeffs, sampleRate: sampleRate)

        #expect(abs(headroom - (-peak)) < 0.01, "Headroom (\(headroom)) must match -cascadePeakDB (\(-peak))")
        #expect(headroom <= -13.9 && headroom >= -14.5, "Headroom must be within [-14.5, -13.9], got \(headroom)")
    }

    @Test("All bands cut-only (-6 dB) returns 0.0 dB headroom")
    func cutOnlyReturnsZeroHeadroom() {
        let cuts = (0..<10).map { i in
            BiquadCoefficients.peaking(frequency: EQChain.frequencies[i], gainDB: -6.0, q: EQChain.q, sampleRate: sampleRate)
        }
        let headroom = AutoHeadroom.headroomDB(coefficients: cuts, sampleRate: sampleRate)
        #expect(headroom == 0.0, "Cut-only curve must not introduce negative headroom")
    }

    @Test("All bands maximum boost (+24 dB) returns headroom clamped to range [-48, -24]")
    func maxBoostHeadroomClamped() {
        let boosts = (0..<10).map { i in
            BiquadCoefficients.peaking(frequency: EQChain.frequencies[i], gainDB: 24.0, q: EQChain.q, sampleRate: sampleRate)
        }
        let headroom = AutoHeadroom.headroomDB(coefficients: boosts, sampleRate: sampleRate)
        #expect(headroom >= -48.0 && headroom < -24.0, "All +24 dB bands headroom must be in [-48, -24), got \(headroom)")
    }

    // MARK: - TC-2: Edge & Boundary Cases

    @Test("Invalid sample rate (NaN, 0, negative) returns 0.0 dB")
    func invalidSampleRateReturnsZero() {
        let coeffs = [BiquadCoefficients.peaking(frequency: 32.0, gainDB: 12.0, q: EQChain.q, sampleRate: 48_000)]
        #expect(AutoHeadroom.headroomDB(coefficients: coeffs, sampleRate: .nan) == 0.0)
        #expect(AutoHeadroom.headroomDB(coefficients: coeffs, sampleRate: 0.0) == 0.0)
        #expect(AutoHeadroom.headroomDB(coefficients: coeffs, sampleRate: -48_000.0) == 0.0)
    }

    @Test("Empty coefficients array returns 0.0 dB")
    func emptyCoefficientsReturnsZero() {
        #expect(AutoHeadroom.headroomDB(coefficients: [], sampleRate: sampleRate) == 0.0)
    }

    @Test("Peak below minimum threshold 0.05 dB returns exactly 0.0 dB (preserves bit-exact bypass)")
    func peakBelowThresholdReturnsZero() {
        // Very tiny gain ~0.04 dB
        let tiny = [BiquadCoefficients.peaking(frequency: 1000.0, gainDB: 0.04, q: EQChain.q, sampleRate: sampleRate)]
        let peak = BiquadCoefficients.cascadePeakDB(tiny, sampleRate: sampleRate)
        #expect(peak < 0.05)
        #expect(AutoHeadroom.headroomDB(coefficients: tiny, sampleRate: sampleRate) == 0.0)
    }

    @Test("Peak above minimum threshold 0.05 dB returns non-zero headroom")
    func peakAboveThresholdReturnsHeadroom() {
        let small = [BiquadCoefficients.peaking(frequency: 1000.0, gainDB: 0.06, q: EQChain.q, sampleRate: sampleRate)]
        let peak = BiquadCoefficients.cascadePeakDB(small, sampleRate: sampleRate)
        #expect(peak >= 0.05)
        let headroom = AutoHeadroom.headroomDB(coefficients: small, sampleRate: sampleRate)
        #expect(headroom < 0.0)
    }

    // MARK: - TC-1 EQChain Headroom Attenuation

    @Test("EQChain setCoefficients with headroomDB -6.0206 on flat curve halves 1 kHz amplitude")
    func eqChainHeadroomAttenuatesFlat() {
        let chain = EQChain(channels: 1)
        let flat = Array(repeating: BiquadCoefficients.identity, count: 10)
        // -6.0206 dB is factor 0.5
        chain.setCoefficients(flat, preampDB: 0.0, sampleRate: sampleRate, headroomDB: -6.0206)

        // Process a warmup block to complete rampFrames transition
        let warmup = AudioBlock(channels: 1, frames: EQChain.rampFrames)
        chain.process(warmup.list, frames: EQChain.rampFrames)

        let frames = 1024
        let inputSine = (0..<frames).map { i in Float(0.5 * sin(2.0 * Double.pi * 1000.0 * Double(i) / sampleRate)) }
        let block = AudioBlock(channels: 1, frames: frames)
        block.load(inputSine)
        chain.process(block.list, frames: frames)
        let out = block.samples()

        // Skip latency
        let validOut = Array(out.dropFirst(chain.latency))
        let maxAmp = validOut.map { abs($0) }.max() ?? 0.0
        #expect(abs(Double(maxAmp) - 0.25) < 0.005, "Amplitude should be ~0.25, got \(maxAmp)")
    }

    @Test("EQChain preampDB +6 dB and headroomDB -6 dB cancels out to ~1.0 gain")
    func eqChainPreampAndHeadroomCancelOut() {
        let chain = EQChain(channels: 1)
        let flat = Array(repeating: BiquadCoefficients.identity, count: 10)
        chain.setCoefficients(flat, preampDB: 6.0, sampleRate: sampleRate, headroomDB: -6.0)

        // Process a warmup block to complete rampFrames transition
        let warmup = AudioBlock(channels: 1, frames: EQChain.rampFrames)
        chain.process(warmup.list, frames: EQChain.rampFrames)

        let frames = 1024
        let inputSine = (0..<frames).map { i in Float(0.2 * sin(2.0 * Double.pi * 1000.0 * Double(i) / sampleRate)) }
        let block = AudioBlock(channels: 1, frames: frames)
        block.load(inputSine)
        chain.process(block.list, frames: frames)
        let out = block.samples()

        let validOut = Array(out.dropFirst(chain.latency))
        let maxAmp = validOut.map { abs($0) }.max() ?? 0.0
        #expect(abs(Double(maxAmp) - 0.20) < 0.005, "Gain should cancel out to ~1.0 (maxAmp ~0.20), got \(maxAmp)")
    }

    @Test("EQChain setCoefficients headroom clamps to [-48, 0] and ignores positive/NaN headroom")
    func eqChainHeadroomClamping() {
        let flat = Array(repeating: BiquadCoefficients.identity, count: 10)

        // Positive headroom (+6) must be ignored / treated as 0 dB
        let chainPositive = EQChain(channels: 1)
        chainPositive.setCoefficients(flat, preampDB: 0.0, sampleRate: sampleRate, headroomDB: 6.0)
        let peakPositive = renderSinePeak(chain: chainPositive, amplitude: 0.5)
        #expect(abs(peakPositive - 0.5) < 0.005, "Positive headroom should be ignored (gain ~1.0, peak ~0.5), got \(peakPositive)")

        // NaN headroom must be treated as 0 dB
        let chainNaN = EQChain(channels: 1)
        chainNaN.setCoefficients(flat, preampDB: 0.0, sampleRate: sampleRate, headroomDB: Double.nan)
        let peakNaN = renderSinePeak(chain: chainNaN, amplitude: 0.5)
        #expect(abs(peakNaN - 0.5) < 0.005, "NaN headroom should be treated as 0 (peak ~0.5), got \(peakNaN)")

        // Infinity headroom must be treated as 0 dB
        let chainInf = EQChain(channels: 1)
        chainInf.setCoefficients(flat, preampDB: 0.0, sampleRate: sampleRate, headroomDB: Double.infinity)
        let peakInf = renderSinePeak(chain: chainInf, amplitude: 0.5)
        #expect(abs(peakInf - 0.5) < 0.005, "Infinity headroom should be treated as 0 (peak ~0.5), got \(peakInf)")

        // Underflow (-100 dB) must clamp to -48 dB
        let chainUnderflow = EQChain(channels: 1)
        chainUnderflow.setCoefficients(flat, preampDB: 0.0, sampleRate: sampleRate, headroomDB: -100.0)
        let peakUnderflow = renderSinePeak(chain: chainUnderflow, amplitude: 0.5)
        let expectedClampedPeak = 0.5 * pow(10.0, -48.0 / 20.0) // ~0.0019905
        #expect(abs(peakUnderflow - expectedClampedPeak) < 0.0002, "Headroom -100 dB must clamp to -48 dB (~0.00199), got \(peakUnderflow)")
    }

    @Test("EQChain clamps preamp independently from headroom (preampDB: 24.0, headroomDB: -6.0206)")
    func eqChainPreampClampingIndependentFromHeadroom() {
        let chain = EQChain(channels: 1)
        let flat = Array(repeating: BiquadCoefficients.identity, count: 10)
        // preampDB: 24.0 is clamped to +12.0. Combined with headroomDB: -6.0206, total gain is +5.9794 dB (~1.9905x)
        chain.setCoefficients(flat, preampDB: 24.0, sampleRate: sampleRate, headroomDB: -6.0206)

        let peak = renderSinePeak(chain: chain, amplitude: 0.2)
        let expectedPeak = 0.2 * pow(10.0, (12.0 - 6.0206) / 20.0) // ~0.3981
        #expect(abs(peak - expectedPeak) < 0.01, "Expected peak ~0.3981, got \(peak)")
    }

    @Test("End-to-End No-Knee Two-Tone (32 Hz + 1000 Hz) with Auto-Headroom enabled")
    func endToEndNoKneeTwoToneWithAutoHeadroom() {
        let blockSize = 256
        let totalBlocks = 190
        let totalFrames = totalBlocks * blockSize
        let analysisFrames = 24_000

        // Baseline: flat curve (0 dB)
        let refChain = EQChain(channels: 1)
        let flat = Array(repeating: BiquadCoefficients.identity, count: 10)
        refChain.setCoefficients(flat, preampDB: 0.0, sampleRate: sampleRate, headroomDB: 0.0)
        let refSamples = runTwoTone(chain: refChain, totalFrames: totalFrames, blockSize: blockSize)
        let refTail = Array(refSamples[(refSamples.count - analysisFrames)...])
        let refMid = measureToneAmplitude(samples: refTail, targetFrequency: 1000.0, sampleRate: sampleRate)
        #expect(abs(refMid - 0.1) < 0.005)

        let testGains: [Double] = [0.0, 6.0, 12.0, 14.5, 17.0, 19.2, 24.0]
        for g in testGains {
            var coeffs = Array(repeating: BiquadCoefficients.identity, count: 10)
            if g > 0.0 {
                coeffs[0] = .peaking(frequency: 32.0, gainDB: g, q: EQChain.q, sampleRate: sampleRate)
            }
            let h = AutoHeadroom.headroomDB(coefficients: coeffs, sampleRate: sampleRate)

            let chain = EQChain(channels: 1)
            chain.setCoefficients(coeffs, preampDB: 0.0, sampleRate: sampleRate, headroomDB: h)

            let outputSamples = runTwoTone(chain: chain, totalFrames: totalFrames, blockSize: blockSize)
            let maxOut = outputSamples.map { abs($0) }.max() ?? 0.0

            // 1. maxOut < 0.8709 (below TruePeakLimiter knee at all gains!)
            #expect(Double(maxOut) < 0.87096, "Output peak (\(maxOut)) must remain below limiter knee 0.87096 at G=\(g) dB")

            // 2. 1 kHz carrier only attenuated linearly by headroom (-h), no limiter knee ducking
            let tailSamples = Array(outputSamples[(outputSamples.count - analysisFrames)...])
            let midAmp = measureToneAmplitude(samples: tailSamples, targetFrequency: 1000.0, sampleRate: sampleRate)
            let safeMid = max(midAmp, 1e-7)
            let reduction = 20.0 * log10(refMid / safeMid)

            #expect(abs(reduction - (-h)) <= 0.3, "1 kHz reduction (\(reduction) dB) must match headroom offset (\(-h) dB) within 0.3 dB at G=\(g) dB")
        }
    }

    // MARK: - Helpers

    private func renderSinePeak(chain: EQChain, amplitude: Float, frequency: Double = 1000.0) -> Double {
        let warmup = AudioBlock(channels: 1, frames: EQChain.rampFrames)
        chain.process(warmup.list, frames: EQChain.rampFrames)

        let frames = 1024
        let inputSine = (0..<frames).map { i in Float(Double(amplitude) * sin(2.0 * Double.pi * frequency * Double(i) / sampleRate)) }
        let block = AudioBlock(channels: 1, frames: frames)
        block.load(inputSine)
        chain.process(block.list, frames: frames)
        let out = block.samples()
        let validOut = Array(out.dropFirst(chain.latency))
        return Double(validOut.map { abs($0) }.max() ?? 0.0)
    }

    private func runTwoTone(chain: EQChain, totalFrames: Int, blockSize: Int) -> [Float] {
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
