import CoreAudio
import Darwin
import EqualizerDSP
import Foundation
import Synchronization
import Testing

/// Serialised: `processDoesNotAllocate` reads process-wide malloc statistics, so no other test may run beside it.
@Suite(.serialized)
struct EQChainTests {
    static let sampleRate = 48_000.0
    static let blockFrames = 512

    // MARK: Biquad maths

    @Test func bandFrequenciesAreTheTenOfTheSpec() {
        #expect(EQChain.frequencies == [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
    }

    @Test func peakingHitsGainAtCentre() {
        for frequency in EQChain.frequencies {
            for gain in [12.0, -12.0, 24.0, -24.0] {
                let coefficients = BiquadCoefficients.peaking(
                    frequency: frequency, gainDB: gain, q: EQChain.q, sampleRate: Self.sampleRate
                )
                let measured = coefficients.magnitudeDB(at: frequency, sampleRate: Self.sampleRate)
                #expect(abs(measured - gain) <= 0.5, "\(frequency) Hz at \(gain) dB measured \(measured) dB")
            }
        }
    }

    @Test func peakingIsFlatFarFromItsCentre() {
        let coefficients = BiquadCoefficients.peaking(frequency: 1000, gainDB: 12, q: EQChain.q, sampleRate: Self.sampleRate)
        #expect(abs(coefficients.magnitudeDB(at: 20, sampleRate: Self.sampleRate)) < 0.5)
        #expect(abs(coefficients.magnitudeDB(at: 20_000, sampleRate: Self.sampleRate)) < 1)
    }

    @Test func zeroGainIsTheIdentity() {
        let coefficients = BiquadCoefficients.peaking(frequency: 1000, gainDB: 0, q: EQChain.q, sampleRate: Self.sampleRate)
        #expect(coefficients == .identity)
        #expect(BiquadCoefficients.identity.magnitudeDB(at: 1000, sampleRate: Self.sampleRate) == 0)
    }

    @Test func bandsThatDoNotFitTheSampleRateAreTheIdentity() {
        // A Bluetooth headset in a call runs at 16 kHz: the 8 kHz band sits on Nyquist, and the cookbook's poles land on the unit circle.
        for (frequency, rate) in [(8000.0, 16_000.0), (16000, 16_000), (16000, 24_000), (1000, 0), (1000, -48_000), (1000, .nan)] {
            let coefficients = BiquadCoefficients.peaking(frequency: frequency, gainDB: 12, q: EQChain.q, sampleRate: rate)
            #expect(coefficients == .identity, "\(frequency) Hz at \(rate) Hz")
        }
    }

    // MARK: Chain

    @Test func flatIsBitExact() {
        var noise = SeededNoise(seed: 1)
        let totalFrames = Self.blockFrames * 3
        let safeInput = noise.samples(2 * totalFrames, amplitude: 0.1)
        let untouched = EQChain(channels: 2)
        let zeroed = EQChain(channels: 2)
        zeroed.setParameters(gains: Array(repeating: 0, count: 10), preampDB: 0, sampleRate: Self.sampleRate)
        for chain in [untouched, zeroed] {
            let latency = chain.latency
            var outSamples = [Float]()
            for b in 0..<3 {
                let block = AudioBlock(channels: 2, frames: Self.blockFrames)
                let chunk = Array(safeInput[(b * 2 * Self.blockFrames)..<((b + 1) * 2 * Self.blockFrames)])
                block.load(chunk)
                chain.process(block.list, frames: Self.blockFrames)
                outSamples.append(contentsOf: block.samples())
            }
            var matchCount = 0
            let testFrames = Self.blockFrames * 2
            for f in 0..<testFrames {
                let inLeft = safeInput[f * 2]
                let inRight = safeInput[f * 2 + 1]
                let outLeft = outSamples[(f + latency) * 2]
                let outRight = outSamples[(f + latency) * 2 + 1]
                if inLeft.bitPattern == outLeft.bitPattern && inRight.bitPattern == outRight.bitPattern {
                    matchCount += 1
                }
            }
            #expect(matchCount == testFrames, "Safe noise must match bit-exactly after latency")
        }
    }

    @Test func flatDoesNotClampOrAlterLoudInput() {
        // Under Option 2 True-Peak protection, loud input is clamped to ceiling
        let chain = EQChain(channels: 1)
        let totalFrames = chain.latency + 4
        let block = AudioBlock(channels: 1, frames: totalFrames)
        var input: [Float] = [1.5, -2, 0.25, 1]
        input += Array(repeating: 0.0, count: chain.latency)
        block.load(input)
        chain.process(block.list, frames: totalFrames)
        let ceilingLinear = pow(10.0, EQChain.limiterCeilingDB / 20.0)
        let out = block.samples()
        let aligned = Array(out[chain.latency..<(chain.latency + 4)])
        for s in aligned {
            #expect(Double(abs(s)) <= ceilingLinear + 1e-4)
        }
    }

    @Test func returningToFlatIsBitExactAgain() {
        var noise = SeededNoise(seed: 2)
        let chain = EQChain(channels: 2)
        chain.setParameters(gains: [12, 6, -3, 0, 0, 4, 0, -12, 0, 8], preampDB: -3, sampleRate: Self.sampleRate)
        let warmUp = AudioBlock(channels: 2, frames: Self.blockFrames)
        for _ in 0..<3 {
            warmUp.load(noise.samples(2 * Self.blockFrames, amplitude: 0.1))
            chain.process(warmUp.list, frames: Self.blockFrames)
        }
        chain.setParameters(gains: Array(repeating: 0, count: 10), preampDB: 0, sampleRate: Self.sampleRate)
        for _ in 0..<3 {
            warmUp.load(noise.samples(2 * Self.blockFrames, amplitude: 0.1))
            chain.process(warmUp.list, frames: Self.blockFrames)
        }
        let totalFrames = Self.blockFrames * 3
        let safeInput = noise.samples(2 * totalFrames, amplitude: 0.1)
        let latency = chain.latency
        var outSamples = [Float]()
        for b in 0..<3 {
            let block = AudioBlock(channels: 2, frames: Self.blockFrames)
            let chunk = Array(safeInput[(b * 2 * Self.blockFrames)..<((b + 1) * 2 * Self.blockFrames)])
            block.load(chunk)
            chain.process(block.list, frames: Self.blockFrames)
            outSamples.append(contentsOf: block.samples())
        }
        var matchCount = 0
        let testFrames = Self.blockFrames * 2
        for f in 0..<testFrames {
            let inLeft = safeInput[f * 2]
            let inRight = safeInput[f * 2 + 1]
            let outLeft = outSamples[(f + latency) * 2]
            let outRight = outSamples[(f + latency) * 2 + 1]
            if inLeft.bitPattern == outLeft.bitPattern && inRight.bitPattern == outRight.bitPattern {
                matchCount += 1
            }
        }
        #expect(matchCount == testFrames, "Returning to flat must match bit-exactly after latency")
    }

    @Test func preampMinus6Halves() {
        let chain = EQChain(channels: 1)
        chain.setParameters(gains: Array(repeating: 0, count: 10), preampDB: -6, sampleRate: Self.sampleRate)
        var position = 0
        var peak: Float = 0
        for blockIndex in 0..<3 {
            let block = AudioBlock(channels: 1, frames: Self.blockFrames)
            block.load(sine(frames: Self.blockFrames, from: position, frequency: 1000, amplitude: 0.5))
            position += Self.blockFrames
            chain.process(block.list, frames: Self.blockFrames)
            if blockIndex == 2 { peak = block.samples().map { abs($0) }.max() ?? 0 }
        }
        #expect(abs(peak - 0.25) <= 0.01, "peak \(peak)")
    }

    @Test func allBandsMaxNeverExceedsUnity() {
        var noise = SeededNoise(seed: 3)
        let chain = EQChain(channels: 2)
        chain.setParameters(gains: Array(repeating: 12, count: 10), preampDB: 0, sampleRate: Self.sampleRate)
        var peak: Float = 0
        for _ in 0..<8 {
            let block = AudioBlock(channels: 2, frames: Self.blockFrames)
            block.load(noise.samples(2 * Self.blockFrames, amplitude: 0.9))
            chain.process(block.list, frames: Self.blockFrames)
            peak = max(peak, block.samples().map { abs($0) }.max() ?? 0)
        }
        #expect(peak <= Float(EQChain.limiterCeiling) + 1e-5)
        // Not vacuous: ten +12 dB bands on loud noise do reach the ceiling.
        #expect(peak >= Float(EQChain.limiterCeiling * 0.80))
    }

    @Test func sampleRateChangeRecomputes() {
        // The plan's check: still about +12 dB at 1 kHz after 44.1 kHz becomes 48 kHz.
        var gains = Array(repeating: 0.0, count: 10)
        gains[5] = 12
        let chain = EQChain(channels: 1)
        chain.setParameters(gains: gains, preampDB: 0, sampleRate: 44_100)
        chain.setParameters(gains: gains, preampDB: 0, sampleRate: Self.sampleRate)
        #expect(abs(measuredGainDB(chain, frequency: 1000) - 12) <= 0.5)

        // A sharper one. Stale 44.1 kHz coefficients on a 48 kHz clock move 1 kHz to 1088 Hz, which still reads
        // about +11.6 dB at 1 kHz, so the 16 kHz band (centre 17.4 kHz when stale) is the one that tells.
        gains = Array(repeating: 0, count: 10)
        gains[9] = 12
        let fresh = BiquadCoefficients.peaking(frequency: 16_000, gainDB: 12, q: EQChain.q, sampleRate: Self.sampleRate)
        let stale = BiquadCoefficients.peaking(frequency: 16_000, gainDB: 12, q: EQChain.q, sampleRate: 44_100)
        let expected = fresh.magnitudeDB(at: 16_000, sampleRate: Self.sampleRate)
        #expect(abs(stale.magnitudeDB(at: 16_000, sampleRate: Self.sampleRate) - expected) > 0.5, "the stale curve must be told apart")
        let highChain = EQChain(channels: 1)
        highChain.setParameters(gains: gains, preampDB: 0, sampleRate: 44_100)
        highChain.setParameters(gains: gains, preampDB: 0, sampleRate: Self.sampleRate)
        #expect(abs(measuredGainDB(highChain, frequency: 16_000) - expected) <= 0.15)
    }

    @Test func lowSampleRateSkipsBandsAboveNyquist() {
        var noise = SeededNoise(seed: 4)
        let chain = EQChain(channels: 1)
        chain.setParameters(gains: Array(repeating: 12, count: 10), preampDB: -12, sampleRate: 16_000)
        var peak: Float = 0
        for _ in 0..<4 {
            let block = AudioBlock(channels: 1, frames: Self.blockFrames)
            block.load(noise.samples(Self.blockFrames, amplitude: 0.1))
            chain.process(block.list, frames: Self.blockFrames)
            let out = block.samples()
            #expect(out.allSatisfy { $0.isFinite })
            peak = max(peak, out.map { abs($0) }.max() ?? 0)
        }
        #expect(peak <= Float(EQChain.limiterCeiling) + 1e-5)
    }

    @Test func unusableSampleRateLeavesTheSoundAlone() {
        var noise = SeededNoise(seed: 5)
        let totalFrames = Self.blockFrames * 2
        let input = noise.samples(totalFrames, amplitude: 0.1)
        for rate in [0.0, -1, Double.nan, Double.infinity] {
            let chain = EQChain(channels: 1)
            chain.setParameters(gains: Array(repeating: 12, count: 10), preampDB: 0, sampleRate: rate)
            let latency = chain.latency
            var outSamples = [Float]()
            for b in 0..<2 {
                let block = AudioBlock(channels: 1, frames: Self.blockFrames)
                let chunk = Array(input[(b * Self.blockFrames)..<((b + 1) * Self.blockFrames)])
                block.load(chunk)
                chain.process(block.list, frames: Self.blockFrames)
                outSamples.append(contentsOf: block.samples())
            }
            var matchCount = 0
            let testCount = Self.blockFrames
            for f in 0..<testCount {
                if input[f].bitPattern == outSamples[f + latency].bitPattern {
                    matchCount += 1
                }
            }
            #expect(matchCount == testCount, "rate \(rate) must leave sound alone after latency")
        }
    }

    @Test func wrongGainCountAndWildValuesAreTolerated() {
        var noise = SeededNoise(seed: 6)
        let chain = EQChain(channels: 1)
        // Too few, too many, not a number and out of range: no crash, finite output within the ceiling.
        chain.setParameters(gains: [99, .nan, -99], preampDB: .infinity, sampleRate: Self.sampleRate)
        chain.setParameters(gains: Array(repeating: 5, count: 14), preampDB: .nan, sampleRate: Self.sampleRate)
        for _ in 0..<3 {
            let block = AudioBlock(channels: 1, frames: Self.blockFrames)
            block.load(noise.samples(Self.blockFrames, amplitude: 0.5))
            chain.process(block.list, frames: Self.blockFrames)
            #expect(block.samples().allSatisfy { $0.isFinite && Double(abs($0)) <= EQChain.limiterCeiling + 1e-5 })
        }
    }

    @Test func parameterChangeHasNoJump() {
        // 0.5 as the plan wrote it cannot pass: +12 dB makes it 2.0, whose own step between two samples is 0.26.
        // 0.1 stays at 0.4 (step 0.052) after the change, where an instant switch away from +12 dB jumps by about 0.3.
        let flat = Array(repeating: 0.0, count: 10)
        var boost = flat
        boost[5] = 12
        var cut = flat
        cut[5] = -12
        for (from, to) in [(flat, boost), (boost, flat), (boost, cut), (cut, boost)] {
            let chain = EQChain(channels: 1)
            chain.setParameters(gains: from, preampDB: 0, sampleRate: Self.sampleRate)
            var position = 0
            var outputs: [Float] = []
            func run(blocks: Int) {
                for _ in 0..<blocks {
                    let block = AudioBlock(channels: 1, frames: Self.blockFrames)
                    block.load(sine(frames: Self.blockFrames, from: position, frequency: 1000, amplitude: 0.1))
                    position += Self.blockFrames
                    chain.process(block.list, frames: Self.blockFrames)
                    outputs += block.samples()
                }
            }
            run(blocks: 4)
            let settledAt = outputs.count
            chain.setParameters(gains: to, preampDB: 0, sampleRate: Self.sampleRate)
            run(blocks: 4)
            let steps = zip(outputs.dropFirst(settledAt - 1), outputs.dropFirst(settledAt)).map { abs($1 - $0) }
            #expect((steps.max() ?? 0) <= 0.1, "largest step \(steps.max() ?? 0) going from \(from[5]) to \(to[5]) dB")
        }
    }

    @Test func aChangeInTheMiddleOfAChangeHasNoJump() {
        let flat = Array(repeating: 0.0, count: 10)
        var boost = flat
        boost[5] = 12
        var cut = flat
        cut[5] = -12
        let chain = EQChain(channels: 1)
        var position = 0
        var outputs: [Float] = []
        func run(frames: Int) {
            let block = AudioBlock(channels: 1, frames: frames)
            block.load(sine(frames: frames, from: position, frequency: 1000, amplitude: 0.1))
            position += frames
            chain.process(block.list, frames: frames)
            outputs += block.samples()
        }
        chain.setParameters(gains: boost, preampDB: 0, sampleRate: Self.sampleRate)
        for _ in 0..<8 { run(frames: Self.blockFrames) }
        // Small buffers, so the changes land while the earlier ramp is still running.
        chain.setParameters(gains: cut, preampDB: 0, sampleRate: Self.sampleRate)
        for _ in 0..<3 { run(frames: 32) }
        chain.setParameters(gains: flat, preampDB: -3, sampleRate: Self.sampleRate)
        for _ in 0..<3 { run(frames: 32) }
        chain.setParameters(gains: boost, preampDB: 0, sampleRate: Self.sampleRate)
        for _ in 0..<40 { run(frames: 32) }
        let steps = zip(outputs, outputs.dropFirst()).map { abs($1 - $0) }
        #expect((steps.max() ?? 0) <= 0.1, "largest step \(steps.max() ?? 0)")
    }

    @Test func aBandSwitchedOffAndBackOnStartsClean() {
        var noise = SeededNoise(seed: 11)
        var boost = Array(repeating: 0.0, count: 10)
        boost[2] = 12
        boost[5] = 12
        let flat = Array(repeating: 0.0, count: 10)
        let used = EQChain(channels: 1)
        let fresh = EQChain(channels: 1)
        let block = AudioBlock(channels: 1, frames: Self.blockFrames)
        used.setParameters(gains: boost, preampDB: 0, sampleRate: Self.sampleRate)
        for _ in 0..<3 {
            block.load(noise.samples(Self.blockFrames, amplitude: 0.1))
            used.process(block.list, frames: Self.blockFrames)
        }
        // One buffer exactly as long as the ramp, so the bands are dropped while their state still holds the signal.
        let rampBlock = AudioBlock(channels: 1, frames: EQChain.rampFrames)
        used.setParameters(gains: flat, preampDB: 0, sampleRate: Self.sampleRate)
        for _ in 0..<3 {
            rampBlock.load(noise.samples(EQChain.rampFrames, amplitude: 0.1))
            used.process(rampBlock.list, frames: EQChain.rampFrames)
        }
        for chain in [used, fresh] {
            chain.setParameters(gains: boost, preampDB: 0, sampleRate: Self.sampleRate)
            let silenceBlock = AudioBlock(channels: 1, frames: chain.latency)
            silenceBlock.load(Array(repeating: 0.0, count: chain.latency))
            chain.process(silenceBlock.list, frames: chain.latency)
        }
        let probe = noise.samples(Self.blockFrames, amplitude: 0.1)
        let afterUse = AudioBlock(channels: 1, frames: Self.blockFrames)
        let reference = AudioBlock(channels: 1, frames: Self.blockFrames)
        afterUse.load(probe)
        reference.load(probe)
        used.process(afterUse.list, frames: Self.blockFrames)
        fresh.process(reference.list, frames: Self.blockFrames)
        #expect(afterUse.samples().map(\.bitPattern) == reference.samples().map(\.bitPattern))
    }

    @Test func nonFiniteInputResets() {
        var noise = SeededNoise(seed: 7)
        let gains = [3.0, 0, -4, 6, 0, 12, 0, -8, 2, 0]
        let dirtied = EQChain(channels: 2)
        let fresh = EQChain(channels: 2)
        for chain in [dirtied, fresh] {
            chain.setParameters(gains: gains, preampDB: -3, sampleRate: Self.sampleRate)
        }
        let silence = AudioBlock(channels: 2, frames: Self.blockFrames)
        let dirt = AudioBlock(channels: 2, frames: Self.blockFrames)
        dirt.load(noise.samples(2 * Self.blockFrames, amplitude: 0.8))
        let poison = AudioBlock(channels: 2, frames: Self.blockFrames)
        for frame in 0..<Self.blockFrames {
            poison[0, frame] = frame.isMultiple(of: 2) ? .nan : -.infinity
            poison[1, frame] = .infinity
        }
        // Both chains finish their ramp on silence; only one is then driven with noise and poisoned.
        fresh.process(silence.list, frames: Self.blockFrames)
        dirtied.process(silence.list, frames: Self.blockFrames)
        dirtied.process(dirt.list, frames: Self.blockFrames)
        dirtied.process(poison.list, frames: Self.blockFrames)
        let poisonOut = poison.samples()
        // D frames of previous queued dirt exit the FIFO, then all subsequent samples of the poison block are silenced
        #expect(poisonOut.suffix(2 * (Self.blockFrames - dirtied.latency)).allSatisfy { $0 == 0 }, "poisoned input after FIFO latency must come out as silence")
        fresh.process(silence.list, frames: Self.blockFrames)
        fresh.process(silence.list, frames: Self.blockFrames)

        let probe = noise.samples(2 * Self.blockFrames, amplitude: 0.5)
        let afterPoison = AudioBlock(channels: 2, frames: Self.blockFrames)
        let reference = AudioBlock(channels: 2, frames: Self.blockFrames)
        afterPoison.load(probe)
        reference.load(probe)
        dirtied.process(afterPoison.list, frames: Self.blockFrames)
        fresh.process(reference.list, frames: Self.blockFrames)
        #expect(afterPoison.samples().map(\.bitPattern) == reference.samples().map(\.bitPattern))
    }

    @Test func nonFiniteInputInFlatModeIsSilenced() {
        let chain = EQChain(channels: 1)
        let latency = chain.latency
        let totalFrames = latency + 4
        let block = AudioBlock(channels: 1, frames: totalFrames)
        var input: [Float] = [0.5, .nan, .infinity, -0.25]
        input += Array(repeating: 0.0, count: latency)
        block.load(input)
        chain.process(block.list, frames: totalFrames)
        let out = block.samples()
        let aligned = Array(out[latency..<(latency + 4)])
        #expect(aligned == [0.5, 0, 0, -0.25])
    }

    @Test func nanInputSanitizationPreservesDelayedValidAudio() {
        let chain = EQChain(channels: 1)
        let latency = chain.latency // 108 frames
        chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: Self.sampleRate)

        let totalFrames = 400
        let nanIndex = 200 // Well beyond initial latency
        var input = [Float](repeating: 0.1, count: totalFrames)
        input[nanIndex] = Float.nan

        let block = AudioBlock(channels: 1, frames: totalFrames)
        block.load(input)
        chain.process(block.list, frames: totalFrames)
        let out = block.samples()

        // 1. All output samples must be finite
        for s in out {
            #expect(s.isFinite, "All output samples must be sanitized to finite values")
        }

        // 2. At frame 200 (when NaN enters the pipeline), the output sample emerging from FIFO
        // is x[200 - latency] = x[92], which is 0.1. It must NOT be zeroed out.
        #expect(abs(out[nanIndex] - 0.1) <= 1e-4, "Output at frame \(nanIndex) must be delayed valid sample ~0.1, got \(out[nanIndex])")

        // 3. At frame 200 + latency = 308, the NaN sample sanitized to 0.0 emerges from the FIFO.
        let sanitizedExitIndex = nanIndex + latency
        #expect(abs(out[sanitizedExitIndex]) <= 1e-6, "Output at frame \(sanitizedExitIndex) must be sanitized 0.0, got \(out[sanitizedExitIndex])")

        // 4. Immediately after frame 308, audio returns to 0.1
        #expect(abs(out[sanitizedExitIndex + 1] - 0.1) <= 1e-4, "Output at frame \(sanitizedExitIndex + 1) must return to 0.1, got \(out[sanitizedExitIndex + 1])")
    }

    @Test func separateBuffersPerChannelMatchOneInterleavedBuffer() {
        var noise = SeededNoise(seed: 8)
        let gains = [4.0, 0, 0, 0, -6, 0, 3, 0, 0, 5]
        let interleavedChain = EQChain(channels: 2)
        let planarChain = EQChain(channels: 2)
        for chain in [interleavedChain, planarChain] {
            chain.setParameters(gains: gains, preampDB: -2, sampleRate: Self.sampleRate)
        }
        for _ in 0..<4 {
            let input = noise.samples(2 * Self.blockFrames, amplitude: 0.5)
            let interleaved = AudioBlock(channels: 2, frames: Self.blockFrames, interleaved: true)
            let planar = AudioBlock(channels: 2, frames: Self.blockFrames, interleaved: false)
            interleaved.load(input)
            planar.load(input)
            interleavedChain.process(interleaved.list, frames: Self.blockFrames)
            planarChain.process(planar.list, frames: Self.blockFrames)
            #expect(planar.samples().map(\.bitPattern) == interleaved.samples().map(\.bitPattern))
        }

        // Test with +24 dB overdrive and asymmetric L/R to verify bit-exactness when limiter is actively compressing
        let maxGains = [24.0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        for chain in [interleavedChain, planarChain] {
            chain.setParameters(gains: maxGains, preampDB: 0, sampleRate: Self.sampleRate)
        }
        for _ in 0..<4 {
            let input = noise.samples(2 * Self.blockFrames, amplitude: 0.9)
            let interleaved = AudioBlock(channels: 2, frames: Self.blockFrames, interleaved: true)
            let planar = AudioBlock(channels: 2, frames: Self.blockFrames, interleaved: false)
            interleaved.load(input)
            planar.load(input)
            interleavedChain.process(interleaved.list, frames: Self.blockFrames)
            planarChain.process(planar.list, frames: Self.blockFrames)
            #expect(planar.samples().map(\.bitPattern) == interleaved.samples().map(\.bitPattern))
        }
    }

    @Test func channelsBeyondTheChainsAreLeftAlone() {
        var noise = SeededNoise(seed: 9)
        let chain = EQChain(channels: 2)
        chain.setParameters(gains: Array(repeating: 12, count: 10), preampDB: -6, sampleRate: Self.sampleRate)
        let input = noise.samples(3 * Self.blockFrames, amplitude: 0.9)
        let block = AudioBlock(channels: 3, frames: Self.blockFrames)
        block.load(input)
        chain.process(block.list, frames: Self.blockFrames)
        let output = block.samples()
        #expect(stride(from: 2, to: output.count, by: 3).allSatisfy { output[$0].bitPattern == input[$0].bitPattern })
        #expect(stride(from: 0, to: output.count, by: 3).contains { output[$0] != input[$0] })
    }

    @Test func settingsPublishedFromAnotherThreadAreAlwaysUsable() {
        // A smoke test of the hand-over, not a proof: a writer publishing as fast as it can while the IO thread
        // adopts. A torn set would show as a blow-up, so every sample must stay finite and within the ceiling.
        let chain = EQChain(channels: 2)
        let writer = DispatchGroup()
        writer.enter()
        DispatchQueue.global().async {
            var noise = SeededNoise(seed: 12)
            for _ in 0..<3000 {
                let gains = (0..<10).map { _ in Double(noise.next()) * 12 }
                chain.setParameters(gains: gains, preampDB: Double(noise.next()) * 12, sampleRate: 48_000)
            }
            writer.leave()
        }
        var noise = SeededNoise(seed: 13)
        let block = AudioBlock(channels: 2, frames: 64)
        var allUsable = true
        for _ in 0..<3000 {
            block.load(noise.samples(2 * 64, amplitude: 0.5))
            chain.process(block.list, frames: 64)
            if !block.samples().allSatisfy({ $0.isFinite && abs($0) <= 1 }) { allUsable = false }
        }
        writer.wait()
        #expect(allUsable)
    }

    @Test func processDoesNotAllocate() throws {
        var noise = SeededNoise(seed: 10)
        let chain = EQChain(channels: 2)
        let block = AudioBlock(channels: 2, frames: Self.blockFrames)
        let input = noise.samples(2 * Self.blockFrames, amplitude: 0.5)
        block.load(input)
        chain.setParameters(gains: [4, 3, 1.5, 0, -1, -1, 0, 1.5, 3, 4], preampDB: -4, sampleRate: Self.sampleRate)
        // One call first, so anything the runtime sets up lazily is not counted.
        chain.process(block.list, frames: Self.blockFrames)

        // Strict: not one allocation or free on this thread, short-lived ones included, which the plan's block count below
        // cannot see. The new settings are published first, so the calls include adopting them and the ramp to them.
        chain.setParameters(gains: [-6, -4, -2, 0, 1, 2.5, 4, 3.5, 1, 0], preampDB: -2, sampleRate: 44_100)
        let allocations = AllocationCounter.count {
            var call = 0
            while call < 10_000 {
                block.restore(input)
                chain.process(block.list, frames: Self.blockFrames)
                call += 1
            }
        }
        let measuredAllocations = try #require(allocations, "AllocationCounter malloc_logger hook must be available on macOS arm64")
        #expect(measuredAllocations == 0, "process allocated or freed \(measuredAllocations) times on IO thread")

        // The plan's check: no block still allocated after 10,000 calls.
        // That count is for the whole process, so a block freed on another thread (a test's dispatch work finishing) can
        // fall inside a reading. Real growth shows in every try, so passing needs one try with none.
        let curves: [(gains: [Double], preamp: Double, rate: Double)] = [
            ([-6, -4, -2, 0, 1, 2.5, 4, 3.5, 1, 0], -2, 44_100),
            ([4, 3, 1.5, 0, -1, -1, 0, 1.5, 3, 4], -4, 48_000),
            ([5, 4, 2, 0, 0, 1.5, 2.5, 2, 1, 0], -4, 44_100),
            ([24, 0, 0, 0, 0, 0, 0, 0, 0, 0], 0, 48_000),
        ]
        var growth = Int.max
        for curve in curves where growth > 0 {
            // Published before the first reading, so the 10,000 calls include adopting it and the ramp to it.
            chain.setParameters(gains: curve.gains, preampDB: curve.preamp, sampleRate: curve.rate)
            var before = malloc_statistics_t()
            malloc_zone_statistics(nil, &before)
            for _ in 0..<10_000 {
                block.restore(input)
                chain.process(block.list, frames: Self.blockFrames)
            }
            var after = malloc_statistics_t()
            malloc_zone_statistics(nil, &after)
            growth = Int(after.blocks_in_use) - Int(before.blocks_in_use)
        }
        #expect(growth <= 0, "\(growth) blocks still allocated after 10,000 calls")
    }

    @Test func loudBoostedSineIsLimitedWithoutOverflow() {
        let chain = EQChain(channels: 1)
        // +12 dB boost at 1000 Hz (index 5)
        chain.setParameters(gains: [0, 0, 0, 0, 0, 12, 0, 0, 0, 0], preampDB: 0, sampleRate: 48_000)
        let blockFrames = 512
        let block = AudioBlock(channels: 1, frames: blockFrames)
        var lastBlockSamples: [Float] = []

        // Feed 6 blocks of 1000 Hz sine at amplitude 0.5 (theoretical peak ~2.0, well above 1.0)
        var position = 0
        for blockIndex in 0..<6 {
            let input = (0..<blockFrames).map { i in
                0.5 * Float(sin(2 * Double.pi * 1000 * Double(position + i) / 48_000))
            }
            position += blockFrames
            block.load(input)
            chain.process(block.list, frames: blockFrames)
            if blockIndex == 5 {
                lastBlockSamples = block.samples()
            }
        }

        #expect(!lastBlockSamples.isEmpty)
        #expect(lastBlockSamples.allSatisfy { $0.isFinite && Double(abs($0)) <= EQChain.limiterCeiling + 1e-5 })
        let maxPeak = lastBlockSamples.map(abs).max() ?? 0
        #expect(Double(maxPeak) > 0.80 && Double(maxPeak) <= EQChain.limiterCeiling + 1e-5, "Expected limited peak within (0.80, limiterCeiling], got \(maxPeak)")
    }

    @Test func setCoefficientsAndPrecisionPreservation() {
        let chain = EQChain(channels: 2)
        let sampleRate = 48_000.0
        let coeffs = EQChain.frequencies.map {
            BiquadCoefficients.peaking(frequency: $0, gainDB: 3.0, q: 1.41, sampleRate: sampleRate)
        }
        chain.setCoefficients(coeffs, preampDB: -3.0)

        let block = AudioBlock(channels: 2, frames: 256)
        block.load((0..<512).map { _ in Float(0.2) })
        chain.process(block.list, frames: 256)
        let samples = block.samples()
        #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1.0 })
    }

    @Test func cascadePeakDBCalculatesExactHeadroom() {
        let sampleRate = 48_000.0
        let flat = EQChain.frequencies.map { _ in BiquadCoefficients.identity }
        #expect(abs(BiquadCoefficients.cascadePeakDB(flat, sampleRate: sampleRate)) < 1e-6)

        // Single band +6 dB boost at 1000 Hz
        let singleBoost = EQChain.frequencies.map { freq in
            freq == 1000 ? BiquadCoefficients.peaking(frequency: 1000, gainDB: 6.0, q: 1.41, sampleRate: sampleRate) : .identity
        }
        let singlePeak = BiquadCoefficients.cascadePeakDB(singleBoost, sampleRate: sampleRate)
        #expect(abs(singlePeak - 6.0) < 0.1, "Single +6 dB boost should peak at ~6 dB, got \(singlePeak)")

        // All +12 dB boost
        let allBoost = EQChain.frequencies.map {
            BiquadCoefficients.peaking(frequency: $0, gainDB: 12.0, q: 1.41, sampleRate: sampleRate)
        }
        let allPeak = BiquadCoefficients.cascadePeakDB(allBoost, sampleRate: sampleRate)
        #expect(allPeak > 15.0 && allPeak < 22.0, "All +12 dB should overlap into ~18 dB, got \(allPeak)")
    }

    @Test func subKneeSignalRemainsStrictlyLinear() {
        let testPoints: [Double] = [-0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75]
        for x in testPoints {
            #expect(EQChain.softSaturate(x) == x, "Sub-knee point \(x) must be strictly linear")
        }

        // C1 continuous slope check around knee point 0.75
        let h = 0.0001
        let slope = (EQChain.softSaturate(0.75 + h) - EQChain.softSaturate(0.75 - h)) / (2 * h)
        #expect(abs(slope - 1.0) < 0.005, "Derivative at knee must be C1 continuous (approx 1.0), got \(slope)")
    }

    @Test func limiterEnvelopeRecoversAfterOverloadAndResetsOnNonFinite() {
        let chain = EQChain(channels: 1)
        chain.setParameters(gains: [0, 0, 0, 0, 0, 12, 0, 0, 0, 0], preampDB: 0, sampleRate: 48_000)
        let blockFrames = 256
        let block = AudioBlock(channels: 1, frames: blockFrames)

        // Step 1: Overload with high-amplitude sine
        var pos = 0
        for _ in 0..<4 {
            let highSine = (0..<blockFrames).map { i in
                0.8 * Float(sin(2 * Double.pi * 1000 * Double(pos + i) / 48_000))
            }
            pos += blockFrames
            block.load(highSine)
            chain.process(block.list, frames: blockFrames)
        }

        // Step 2: Feed small-signal sine for envelope release recovery
        // Physical timing: N_hold = round(0.035 * 48000) = 1680 frames, tau = 100 ms (~4800 frames).
        // Total frames to recover 99.9% gain: ~12,098 frames -> ceil(12,098 / 256) = 48 blocks.
        // Running 50 blocks (12,800 frames = 266.7 ms) mathematically guarantees full release without arbitrary tuning.
        var recoveredSamples: [Float] = []
        for b in 0..<50 {
            let smallSine = (0..<blockFrames).map { i in
                0.05 * Float(sin(2 * Double.pi * 1000 * Double(pos + i) / 48_000))
            }
            pos += blockFrames
            block.load(smallSine)
            chain.process(block.list, frames: blockFrames)
            if b == 49 {
                recoveredSamples = block.samples()
            }
        }

        // Step 3: Reference fresh chain with identical small signal
        let freshChain = EQChain(channels: 1)
        freshChain.setParameters(gains: [0, 0, 0, 0, 0, 12, 0, 0, 0, 0], preampDB: 0, sampleRate: 48_000)
        let freshBlock = AudioBlock(channels: 1, frames: blockFrames)
        var freshSamples: [Float] = []
        var freshPos = pos - blockFrames
        for _ in 0..<4 {
            let smallSine = (0..<blockFrames).map { i in
                0.05 * Float(sin(2 * Double.pi * 1000 * Double(freshPos + i) / 48_000))
            }
            freshPos += blockFrames
            freshBlock.load(smallSine)
            freshChain.process(freshBlock.list, frames: blockFrames)
            freshSamples = freshBlock.samples()
        }

        let recoveredPeak = recoveredSamples.map(abs).max() ?? 0
        let freshPeak = freshSamples.map(abs).max() ?? 0
        #expect(abs(recoveredPeak - freshPeak) < 0.001, "Limiter envelope failed to recover clean gain: recovered=\(recoveredPeak), fresh=\(freshPeak)")

        // Step 4: Non-Finite Instant Reset Verification
        // Overload chain again:
        for _ in 0..<4 {
            let highSine = (0..<blockFrames).map { i in
                0.8 * Float(sin(2 * Double.pi * 1000 * Double(pos + i) / 48_000))
            }
            pos += blockFrames
            block.load(highSine)
            chain.process(block.list, frames: blockFrames)
        }

        // Poison with NaN block:
        let poison = [Float](repeating: Float.nan, count: blockFrames)
        block.load(poison)
        chain.process(block.list, frames: blockFrames)
        #expect(block.samples().suffix(blockFrames - chain.latency).allSatisfy { $0 == 0.0 }, "Poison block after latency must be silenced")

        // Next clean small-signal block must immediately have clean gain without waiting for hold/release:
        var cleanSamples: [Float] = []
        for _ in 0..<4 {
            let cleanSine = (0..<blockFrames).map { i in
                0.05 * Float(sin(2 * Double.pi * 1000 * Double(pos + i) / 48_000))
            }
            pos += blockFrames
            block.load(cleanSine)
            chain.process(block.list, frames: blockFrames)
            cleanSamples = block.samples()
        }
        let cleanPeak = cleanSamples.map(abs).max() ?? 0
        #expect(abs(cleanPeak - freshPeak) < 0.001, "Non-finite input must instantly reset limiter envelope without waiting for hold or release")
    }

    @Test func positivePreampDoublesSubThresholdSignalAndClampsExtremeOverdrive() {
        let chain = EQChain(channels: 1)
        let sampleRate = 48_000.0
        let flat = EQChain.frequencies.map { _ in BiquadCoefficients.identity }

        // 1. Preamp +6 dB on sub-threshold signal (0.25 amplitude) doubles it to ~0.50 without limiting
        chain.setCoefficients(flat, preampDB: 6.0)
        let frames = 480
        let block = AudioBlock(channels: 1, frames: frames)
        var pos = 0
        var subThresholdMax: Float = 0
        for _ in 0..<8 {
            let sine = (0..<frames).map { i in Float(0.25 * sin(2 * Double.pi * 1000 * Double(pos + i) / sampleRate)) }
            pos += frames
            block.load(sine)
            chain.process(block.list, frames: frames)
            subThresholdMax = block.samples().map(abs).max() ?? 0
        }
        #expect(subThresholdMax > 0.48 && subThresholdMax < 0.52, "Preamp +6 dB must double 0.25 sine to ~0.50, got \(subThresholdMax)")

        // 2. Extreme overdrive: 10 bands at +12 dB + preamp at +12 dB on SeededNoise amplitude 0.9
        let maxBoostCoeffs = EQChain.frequencies.map {
            BiquadCoefficients.peaking(frequency: $0, gainDB: 12.0, q: 1.41, sampleRate: sampleRate)
        }
        chain.setCoefficients(maxBoostCoeffs, preampDB: 12.0)
        var noise = SeededNoise(seed: 42)
        var overdriveMax: Float = 0
        for _ in 0..<12 {
            let noiseSamples = noise.samples(frames, amplitude: 0.9)
            block.load(noiseSamples)
            chain.process(block.list, frames: frames)
            let outSamples = block.samples()
            #expect(outSamples.allSatisfy { $0.isFinite && Double(abs($0)) <= EQChain.limiterCeiling + 1e-5 }, "All overdrive output samples must be <= limiterCeiling")
            overdriveMax = max(overdriveMax, outSamples.map(abs).max() ?? 0)
        }
        #expect(Double(overdriveMax) > EQChain.limiterCeiling * 0.85 && Double(overdriveMax) <= EQChain.limiterCeiling + 1e-5, "Limiter must clamp extreme overdrive right at ceiling, got \(overdriveMax)")
    }

    @Test func setCoefficientsSanitisesWildAndNonFinitePreamp() {
        let flat = EQChain.frequencies.map { _ in BiquadCoefficients.identity }
        let frames = 256

        // 1. NaN defaults to 0 dB (1.0x gain, so 0.5 input remains 0.5)
        do {
            let chain = EQChain(channels: 1)
            chain.setCoefficients(flat, preampDB: .nan)
            let block = AudioBlock(channels: 1, frames: frames)
            block.load((0..<frames).map { _ in Float(0.5) })
            chain.process(block.list, frames: frames)
            let samples = Array(block.samples()[chain.latency..<frames])
            #expect(samples.allSatisfy { abs($0 - 0.5) < 1e-5 }, "NaN preamp must default to 0 dB (1.0x)")
        }

        // 2. +Infinity defaults to 0 dB (1.0x gain)
        do {
            let chain = EQChain(channels: 1)
            chain.setCoefficients(flat, preampDB: .infinity)
            let block = AudioBlock(channels: 1, frames: frames)
            block.load((0..<frames).map { _ in Float(0.5) })
            chain.process(block.list, frames: frames)
            let samples = Array(block.samples()[chain.latency..<frames])
            #expect(samples.allSatisfy { abs($0 - 0.5) < 1e-5 }, "+Inf preamp must default to 0 dB (1.0x)")
        }

        // 3. -Infinity defaults to 0 dB (1.0x gain)
        do {
            let chain = EQChain(channels: 1)
            chain.setCoefficients(flat, preampDB: -.infinity)
            let block = AudioBlock(channels: 1, frames: frames)
            block.load((0..<frames).map { _ in Float(0.5) })
            chain.process(block.list, frames: frames)
            let samples = Array(block.samples()[chain.latency..<frames])
            #expect(samples.allSatisfy { abs($0 - 0.5) < 1e-5 }, "-Inf preamp must default to 0 dB (1.0x)")
        }

        // 4. Extreme positive (10,000 dB) clamped safely to +12 dB without overflow
        do {
            let chain = EQChain(channels: 1)
            chain.setCoefficients(flat, preampDB: 10_000.0)
            let block = AudioBlock(channels: 1, frames: frames)
            block.load((0..<frames).map { _ in Float(0.1) })
            chain.process(block.list, frames: frames)
            let samples = block.samples()
            #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1.0 }, "Extreme positive preamp must not overflow to Inf")
        }

        // 5. Extreme negative (-10,000 dB) clamped safely to -12 dB without underflow to NaN
        do {
            let chain = EQChain(channels: 1)
            chain.setCoefficients(flat, preampDB: -10_000.0)
            let rampFrames = 256
            let block = AudioBlock(channels: 1, frames: rampFrames)
            var lastSamples = [Float]()
            for _ in 0..<3 {
                block.load((0..<rampFrames).map { _ in Float(0.5) })
                chain.process(block.list, frames: rampFrames)
                lastSamples = block.samples()
            }
            // At -12 dB, 0.5 * 10^(-12/20) = 0.5 * 0.2511886 = 0.12559
            #expect(lastSamples.allSatisfy { $0.isFinite && abs($0 - 0.1256) < 0.01 }, "Extreme negative preamp must clamp to -12 dB")
        }
    }

    // MARK: - Mandatory Quality & Limiter Tests

    @Test func linkedLimiterEliminates32HzSquareWaveDistortionAtMaxBoost() {
        let sampleRate = 48_000.0
        let testConfigs: [([Double], String)] = [
            ([24, 0, 0, 0, 0, 0, 0, 0, 0, 0], "32Hz at +24 dB"),
            ([14.0, 10.0, 7.2, 2.7, 0.4, 0.7, -0.5, 0.0, 1.7, 1.4], "Deep Bass (eqMac)")
        ]

        for (gains, label) in testConfigs {
            let chain = EQChain(channels: 2)
            chain.setParameters(gains: gains, preampDB: 0, sampleRate: sampleRate)

            let blockFrames = 512
            let block = AudioBlock(channels: 2, frames: blockFrames)
            var pos = 0
            var allSamples = [Float]()

            // Pump 20 blocks of 32 Hz sine, amplitude 0.5
            for _ in 0..<20 {
                let interleaved = (0..<blockFrames).flatMap { i -> [Float] in
                    let val = Float(0.5 * sin(2 * Double.pi * 32.0 * Double(pos + i) / sampleRate))
                    return [val, val]
                }
                pos += blockFrames
                block.load(interleaved)
                chain.process(block.list, frames: blockFrames)
                allSamples.append(contentsOf: block.samples())
            }

            let totalFrames = allSamples.count / 2
            let startFrame = totalFrames - 3000
            var ch0Last3000 = [Float]()
            ch0Last3000.reserveCapacity(3000)
            for f in startFrame..<totalFrames {
                ch0Last3000.append(allSamples[f * 2])
            }

            #expect(ch0Last3000.allSatisfy { $0.isFinite && abs($0) <= 1.0 }, "[\(label)] All samples must be finite and <= 1.0")

            let peak = ch0Last3000.map(abs).max() ?? 0
            #expect(peak >= 0.85 && peak <= 1.0, "[\(label)] Peak must be in [0.85, 1.0], got \(peak)")

            let sumSquares = ch0Last3000.reduce(0.0) { $0 + Double($1 * $1) }
            let rms = sqrt(sumSquares / Double(ch0Last3000.count))
            let crestFactor = Double(peak) / rms
            #expect(crestFactor >= 1.35 && crestFactor <= 1.48, "[\(label)] Crest factor must be ~1.41 (sine), got \(crestFactor)")

            func dftMag(freq: Double) -> Double {
                var re = 0.0
                var im = 0.0
                let n = Double(ch0Last3000.count)
                for (i, s) in ch0Last3000.enumerated() {
                    let angle = 2.0 * Double.pi * freq * Double(i) / sampleRate
                    re += Double(s) * cos(angle)
                    im -= Double(s) * sin(angle)
                }
                return 2.0 * hypot(re, im) / n
            }

            let fundamental = dftMag(freq: 32.0)
            #expect(fundamental > 0.8, "[\(label)] Fundamental must be preserved, got \(fundamental)")

            var harmonicEnergy = 0.0
            for h in 2...7 {
                let mag = dftMag(freq: Double(h) * 32.0)
                harmonicEnergy += mag * mag
            }
            let thd = sqrt(harmonicEnergy) / fundamental
            #expect(thd < 0.01, "[\(label)] THD (harmonics 2..7) must be < 1% (-40 dB), got \(thd)")
        }
    }

    @Test func linkedLimiterPreventsBassPumpingOnHighFrequencySignal() {
        let sampleRate = 48_000.0
        let chain = EQChain(channels: 1)
        var gains = Array(repeating: 0.0, count: 10)
        gains[0] = 14.0 // 32 Hz at +14 dB
        chain.setParameters(gains: gains, preampDB: 0, sampleRate: sampleRate)

        let blockFrames = 512
        let block = AudioBlock(channels: 1, frames: blockFrames)
        var pos = 0
        var allSamples = [Float]()

        // Pump 32 blocks of composite signal: 0.5 * sin(32 Hz) + 0.15 * sin(3000 Hz)
        for _ in 0..<32 {
            let composite = (0..<blockFrames).map { i -> Float in
                let t = Double(pos + i) / sampleRate
                let bass = 0.5 * sin(2 * Double.pi * 32.0 * t)
                let treble = 0.15 * sin(2 * Double.pi * 3000.0 * t)
                return Float(bass + treble)
            }
            pos += blockFrames
            block.load(composite)
            chain.process(block.list, frames: blockFrames)
            allSamples.append(contentsOf: block.samples())
        }

        // Apply a highpass filter (fc = 1000 Hz) to eliminate spectral side-lobe leakage
        // from the massive 32 Hz fundamental (amplitude ~0.94) into the 3000 Hz DFT bin,
        // isolating the treble tone to measure purely limiter envelope pumping.
        let fc = 1000.0
        let omega = 2.0 * Double.pi * fc / sampleRate
        let alpha = sin(omega) / (2.0 * (1.0 / sqrt(2.0)))
        let cosw = cos(omega)
        let a0_hpf = 1.0 + alpha
        let b0 = ((1.0 + cosw) / 2.0) / a0_hpf
        let b1 = (-(1.0 + cosw)) / a0_hpf
        let b2 = ((1.0 + cosw) / 2.0) / a0_hpf
        let a1_coeff = (-2.0 * cosw) / a0_hpf
        let a2_coeff = (1.0 - alpha) / a0_hpf

        var x1: Double = 0, x2: Double = 0, y1: Double = 0, y2: Double = 0
        var filteredSamples = [Double](repeating: 0, count: allSamples.count)
        for i in 0..<allSamples.count {
            let x0 = Double(allSamples[i])
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1_coeff * y1 - a2_coeff * y2
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0
            filteredSamples[i] = y0
        }

        // Second pass of biquad HPF (cascaded 4th order Butterworth HPF) to eliminate 32 Hz leakage
        var x1_p2: Double = 0, x2_p2: Double = 0, y1_p2: Double = 0, y2_p2: Double = 0
        for i in 0..<filteredSamples.count {
            let x0 = filteredSamples[i]
            let y0 = b0 * x0 + b1 * x1_p2 + b2 * x2_p2 - a1_coeff * y1_p2 - a2_coeff * y2_p2
            x2_p2 = x1_p2; x1_p2 = x0
            y2_p2 = y1_p2; y1_p2 = y0
            filteredSamples[i] = y0
        }

        // Analyze last 2000 samples across sliding 128-sample periodic Blackman-Harris windows
        let analysisBuffer = Array(filteredSamples.suffix(2000))
        let windowSize = 128
        var windowAmplitudes = [Double]()

        var start = 0
        let a0 = 0.35875
        let a1 = 0.48829
        let a2 = 0.14128
        let a3 = 0.01168
        while start + windowSize <= analysisBuffer.count {
            var re = 0.0
            var im = 0.0
            var winSum = 0.0
            for i in 0..<windowSize {
                let frac = Double(i) / Double(windowSize)
                let w = a0 - a1 * cos(2.0 * Double.pi * frac) + a2 * cos(4.0 * Double.pi * frac) - a3 * cos(6.0 * Double.pi * frac)
                winSum += w
                let s = analysisBuffer[start + i] * w
                let angle = 2.0 * Double.pi * 3000.0 * Double(start + i) / sampleRate
                re += s * cos(angle)
                im -= s * sin(angle)
            }
            let mag = 2.0 * hypot(re, im) / winSum
            windowAmplitudes.append(mag)
            start += 16
        }

        let minAmp = windowAmplitudes.min() ?? 0
        let maxAmp = windowAmplitudes.max() ?? 1
        #expect(minAmp > 0.045, "3 kHz treble signal must be audible, got \(minAmp)")
        let ratio = maxAmp / minAmp
        #expect(ratio < 1.02, "Treble amplitude modulation must be < 2% (no pumping), got ratio \(ratio)")
    }

    @Test func linkedStereoLimiterPreservesChannelBalanceRatio() {
        let sampleRate = 48_000.0
        let chain = EQChain(channels: 2)
        var gains = Array(repeating: 0.0, count: 10)
        gains[5] = 12.0 // 1 kHz at +12 dB
        chain.setParameters(gains: gains, preampDB: 0, sampleRate: sampleRate)

        let blockFrames = 512
        let block = AudioBlock(channels: 2, frames: blockFrames)
        var pos = 0
        var lastBlockSamples = [Float]()

        // Pump 8 blocks: Left = 0.8 * sin(1000), Right = 0.2 * sin(1000) (4:1 ratio)
        for _ in 0..<8 {
            let interleaved = (0..<blockFrames).flatMap { i -> [Float] in
                let angle = 2 * Double.pi * 1000.0 * Double(pos + i) / sampleRate
                let left = Float(0.8 * sin(angle))
                let right = Float(0.2 * sin(angle))
                return [left, right]
            }
            pos += blockFrames
            block.load(interleaved)
            chain.process(block.list, frames: blockFrames)
            lastBlockSamples = block.samples()
        }

        #expect(lastBlockSamples.allSatisfy { $0.isFinite && Double(abs($0)) <= EQChain.limiterCeiling + 1e-5 })

        var leftPeak: Float = 0
        var rightPeak: Float = 0
        for i in 0..<blockFrames {
            leftPeak = max(leftPeak, abs(lastBlockSamples[i * 2]))
            rightPeak = max(rightPeak, abs(lastBlockSamples[i * 2 + 1]))
        }

        #expect(rightPeak > 0)
        let ratio = Double(leftPeak / rightPeak)
        #expect(abs(ratio - 4.0) < 0.15, "Linked stereo limiter must preserve 4:1 channel ratio, got \(ratio)")
    }

    @Test func gainAtPlusAndMinus24DBMatchesTarget() {
        let chainPos = EQChain(channels: 1)
        var gainsPos = Array(repeating: 0.0, count: 10)
        gainsPos[5] = 24.0 // 1000 Hz at +24 dB
        chainPos.setParameters(gains: gainsPos, preampDB: 0, sampleRate: Self.sampleRate)
        let measuredPos = measuredGainDB(chainPos, frequency: 1000, amplitude: 0.02)
        #expect(abs(measuredPos - 24.0) <= 0.5, "+24 dB at 1 kHz measured \(measuredPos) dB")

        let chainNeg = EQChain(channels: 1)
        var gainsNeg = Array(repeating: 0.0, count: 10)
        gainsNeg[5] = -24.0 // 1000 Hz at -24 dB
        chainNeg.setParameters(gains: gainsNeg, preampDB: 0, sampleRate: Self.sampleRate)
        let measuredNeg = measuredGainDB(chainNeg, frequency: 1000, amplitude: 0.02)
        #expect(abs(measuredNeg - (-24.0)) <= 0.5, "-24 dB at 1 kHz measured \(measuredNeg) dB")
    }

    @Test func limiterEnvelopeHoldsFor35msThenReleasesCleanly() {
        let sampleRate = 48_000.0
        let chain = EQChain(channels: 1)
        var gains = Array(repeating: 0.0, count: 10)
        gains[5] = 12.0 // 1000 Hz at +12 dB
        chain.setParameters(gains: gains, preampDB: 0, sampleRate: sampleRate)

        let blockFrames = 256
        let block = AudioBlock(channels: 1, frames: blockFrames)
        var pos = 0

        // 1. Overload with 1000 Hz sine at 0.8 for 4 blocks (~21 ms)
        for _ in 0..<4 {
            let high = (0..<blockFrames).map { i in
                Float(0.8 * sin(2 * Double.pi * 1000.0 * Double(pos + i) / sampleRate))
            }
            pos += blockFrames
            block.load(high)
            chain.process(block.list, frames: blockFrames)
        }

        // 2. Switch to small signal 0.05. For first 30 ms (blocks 1..4 = 1024 frames < 1680 hold frames),
        // peak must remain clamped below 0.08 due to active peak hold.
        var holdSamples = [Float]()
        for step2Block in 0..<5 {
            let small = (0..<blockFrames).map { i in
                Float(0.05 * sin(2 * Double.pi * 1000.0 * Double(pos + i) / sampleRate))
            }
            pos += blockFrames
            block.load(small)
            chain.process(block.list, frames: blockFrames)
            if step2Block > 0 {
                holdSamples.append(contentsOf: block.samples())
            }
        }
        let holdPeak = holdSamples.map(abs).max() ?? 0
        #expect(holdPeak < 0.08, "Hold (~35 ms) must hold gain down during first 30 ms (blocks 1..4), got \(holdPeak)")

        // 3. Continue running for 200 ms (38 blocks = 9728 frames)
        var finalSamples = [Float]()
        for b in 0..<38 {
            let small = (0..<blockFrames).map { i in
                Float(0.05 * sin(2 * Double.pi * 1000.0 * Double(pos + i) / sampleRate))
            }
            pos += blockFrames
            block.load(small)
            chain.process(block.list, frames: blockFrames)
            if b == 37 {
                finalSamples = block.samples()
            }
        }

        let freshChain = EQChain(channels: 1)
        freshChain.setParameters(gains: gains, preampDB: 0, sampleRate: sampleRate)
        let freshBlock = AudioBlock(channels: 1, frames: blockFrames)
        var freshSamples = [Float]()
        var freshPos = pos - blockFrames
        for _ in 0..<4 {
            let small = (0..<blockFrames).map { i in
                Float(0.05 * sin(2 * Double.pi * 1000.0 * Double(freshPos + i) / sampleRate))
            }
            freshPos += blockFrames
            freshBlock.load(small)
            freshChain.process(freshBlock.list, frames: blockFrames)
            freshSamples = freshBlock.samples()
        }

        let recoveredPeak = finalSamples.map(abs).max() ?? 0
        let freshPeak = freshSamples.map(abs).max() ?? 0
        #expect(abs(recoveredPeak - freshPeak) < 0.001, "Limiter envelope must fully recover after 200 ms: recovered=\(recoveredPeak), fresh=\(freshPeak)")
    }

    @Test func zeroOvershootOnSuddenOverdriveTransient() {
        let chain = EQChain(channels: 1)
        let allBoost = EQChain.frequencies.map {
            BiquadCoefficients.peaking(frequency: $0, gainDB: 24.0, q: 1.41, sampleRate: 48_000)
        }
        chain.setCoefficients(allBoost, preampDB: 12.0)

        let frames = 256
        let block = AudioBlock(channels: 1, frames: frames)

        var input = [Float](repeating: 0.0, count: 64)
        input.append(contentsOf: [Float](repeating: 1.0, count: frames - 64))
        block.load(input)
        chain.process(block.list, frames: frames)

        let out = block.samples()
        #expect(out.allSatisfy { $0.isFinite && Double(abs($0)) <= EQChain.limiterCeiling + 1e-5 }, "Sudden transient step with +24 dB boost must have zero overshoot (all <= limiterCeiling)")
    }

    @Test func sampleRateAffectsLimiterTimingViaSetCoefficients() {
        let sampleRate = 96_000.0
        let chain = EQChain(channels: 1)
        var gains = Array(repeating: 0.0, count: 10)
        gains[5] = 12.0
        chain.setParameters(gains: gains, preampDB: 0, sampleRate: sampleRate)

        let blockFrames = 512
        let block = AudioBlock(channels: 1, frames: blockFrames)
        var pos = 0

        for _ in 0..<4 {
            let high = (0..<blockFrames).map { i in
                Float(0.8 * sin(2 * Double.pi * 1000.0 * Double(pos + i) / sampleRate))
            }
            pos += blockFrames
            block.load(high)
            chain.process(block.list, frames: blockFrames)
        }

        var holdSamples = [Float]()
        for step2Block in 0..<5 {
            let small = (0..<blockFrames).map { i in
                Float(0.05 * sin(2 * Double.pi * 1000.0 * Double(pos + i) / sampleRate))
            }
            pos += blockFrames
            block.load(small)
            chain.process(block.list, frames: blockFrames)
            if step2Block > 0 {
                holdSamples.append(contentsOf: block.samples())
            }
        }

        let holdPeak = holdSamples.map(abs).max() ?? 0
        #expect(holdPeak < 0.08, "Hold must adapt to 96 kHz sample rate, got peak \(holdPeak)")
    }

    @Test func setCoefficientsClampsPreampTo12WhileAccepting24dBBands() {
        let chain = EQChain(channels: 1)
        let flat = EQChain.frequencies.map { _ in BiquadCoefficients.identity }
        chain.setCoefficients(flat, preampDB: 24.0)

        let frames = 480
        let block = AudioBlock(channels: 1, frames: frames)
        let sine = (0..<frames).map { i in
            Float(0.1 * sin(2 * Double.pi * 1000.0 * Double(i) / 48_000))
        }
        block.load(sine)
        chain.process(block.list, frames: frames)

        let peak = block.samples().map(abs).max() ?? 0
        #expect(peak > 0.38 && peak < 0.42, "Preamp +24 dB must be clamped to +12 dB (peak ~0.398), got \(peak)")
    }

    @Test func nonFiniteOnOneStereoChannelDoesNotPoisonOtherChannel() {
        let chain = EQChain(channels: 2)
        var gains = Array(repeating: 0.0, count: 10)
        gains[5] = 12.0
        chain.setParameters(gains: gains, preampDB: 0, sampleRate: 48_000)

        let frames = 256
        let block = AudioBlock(channels: 2, frames: frames)

        let interleaved = (0..<frames).flatMap { i -> [Float] in
            let ch0 = Float.nan
            let ch1 = Float(0.8 * sin(2 * Double.pi * 1000.0 * Double(i) / 48_000))
            return [ch0, ch1]
        }
        block.load(interleaved)
        chain.process(block.list, frames: frames)

        let out = block.samples()
        for i in 0..<frames {
            let ch0 = out[i * 2]
            let ch1 = out[i * 2 + 1]
            #expect(ch0 == 0.0, "Channel 0 with NaN input must output 0.0")
            #expect(ch1.isFinite && Double(abs(ch1)) <= EQChain.limiterCeiling + 1e-5, "Channel 1 must not be poisoned by Channel 0 NaN")
        }
    }

    @Test func nullBufferDataDoesNotReuseStalePointersOrOverflowChannelCapacity() {
        let chain = EQChain(channels: 2)
        var gains = Array(repeating: 0.0, count: 10)
        gains[5] = 6.0
        chain.setParameters(gains: gains, preampDB: 0, sampleRate: 48_000)

        let frames = 128
        // Call 1: valid allocated buffer
        do {
            let block = AudioBlock(channels: 2, frames: frames)
            let sine = (0..<frames).flatMap { i -> [Float] in
                let s = Float(0.5 * sin(2 * Double.pi * 1000.0 * Double(i) / 48_000))
                return [s, s]
            }
            block.load(sine)
            chain.process(block.list, frames: frames)
            // block deallocates here
        }

        // Call 2: buffers with nil mData and exceeding widths (buffers[0] width=1 nil, buffers[1] width=2 nil)
        let listPtr = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(listPtr.unsafeMutablePointer) }
        listPtr[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil)
        listPtr[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 0, mData: nil)

        // Must not crash, must not reuse stale pointers, must not overflow channel capacity
        chain.process(listPtr, frames: frames)
    }

    @Test func limiterCeilingTruePeakHeadroomMeasurement() {
        let sampleRate = 48_000.0
        let chain = EQChain(channels: 1)
        var gains = Array(repeating: 0.0, count: 10)
        gains[5] = 12.0 // 1000 Hz at +12 dB
        chain.setParameters(gains: gains, preampDB: 0, sampleRate: sampleRate)

        let blockFrames = 512
        let block = AudioBlock(channels: 1, frames: blockFrames)
        var pos = 0
        var lastBlockSamples = [Float]()

        for _ in 0..<8 {
            let sine = (0..<blockFrames).map { i in
                Float(0.8 * sin(2 * Double.pi * 1000.0 * Double(pos + i) / sampleRate))
            }
            pos += blockFrames
            block.load(sine)
            chain.process(block.list, frames: blockFrames)
            lastBlockSamples = block.samples()
        }

        #expect(lastBlockSamples.allSatisfy { $0.isFinite && Double(abs($0)) <= EQChain.limiterCeiling + 1e-5 })
        let measuredPeak = lastBlockSamples.map(abs).max() ?? 0
        #expect(Double(measuredPeak) <= EQChain.limiterCeiling + 1e-5 && Double(measuredPeak) >= EQChain.limiterCeiling * 0.85, "Peak phải bị khống chế chuẩn xác tại trần True-Peak -0.5 dBFS (~0.944), đo được \(measuredPeak)")
    }

    // MARK: Helpers

    /// RMS gain of a steady sine through the chain, in dB: after 100 ms to settle, over 100 ms,
    /// which holds a whole number of cycles for any multiple of 10 Hz.
    private func measuredGainDB(_ chain: EQChain, frequency: Double, amplitude: Float = 0.05) -> Double {
        var position = 0
        var inputEnergy = 0.0
        var outputEnergy = 0.0
        for blockIndex in 0..<20 {
            let frames = 480
            let input = sine(frames: frames, from: position, frequency: frequency, amplitude: amplitude)
            position += frames
            let block = AudioBlock(channels: 1, frames: frames)
            block.load(input)
            chain.process(block.list, frames: frames)
            guard blockIndex >= 10 else { continue }
            for (x, y) in zip(input, block.samples()) {
                inputEnergy += Double(x * x)
                outputEnergy += Double(y * y)
            }
        }
        return 10 * log10(outputEnergy / inputEnergy)
    }

    private func sine(frames: Int, from start: Int, frequency: Double, amplitude: Float) -> [Float] {
        (0..<frames).map { index in
            amplitude * Float(sin(2 * Double.pi * frequency * Double(start + index) / Self.sampleRate))
        }
    }
}

/// Counts the allocations and frees one thread makes, through libmalloc's `malloc_logger` hook (what malloc stack logging uses).
/// It watches one thread so that the test runner's other threads cannot disturb the count. The hook runs inside every malloc and free,
/// so it touches only atomics and `pthread_self`.
enum AllocationCounter {
    typealias Hook = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

    private static let watchedThread = Atomic<UInt>(0)
    private static let events = Atomic<Int>(0)

    /// What `body` allocated and freed on the calling thread; nil where this macOS does not expose the hook.
    static func count(_ body: () -> Void) -> Int? {
        // RTLD_DEFAULT
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else { return nil }
        let slot = symbol.assumingMemoryBound(to: Hook?.self)
        let previous = slot.pointee
        watchedThread.store(UInt(bitPattern: pthread_self()), ordering: .relaxed)
        events.store(0, ordering: .relaxed)
        slot.pointee = { _, _, _, _, _, _ in
            if UInt(bitPattern: pthread_self()) == AllocationCounter.watchedThread.load(ordering: .relaxed) {
                AllocationCounter.events.add(1, ordering: .relaxed)
            }
        }
        body()
        slot.pointee = previous
        return events.load(ordering: .relaxed)
    }
}

/// Reproducible noise (SplitMix64), so a failure comes back the same on every run.
struct SeededNoise {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next(amplitude: Float = 1) -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        let unit = Double(z >> 11) / Double(1 << 53)
        return amplitude * Float(unit * 2 - 1)
    }

    mutating func samples(_ count: Int, amplitude: Float = 1) -> [Float] {
        (0..<count).map { _ in next(amplitude: amplitude) }
    }
}

/// An `AudioBufferList` of 32-bit float PCM, either one interleaved buffer or one buffer per channel.
final class AudioBlock {
    let channels: Int
    let frames: Int
    let interleaved: Bool
    let list: UnsafeMutableAudioBufferListPointer

    init(channels: Int, frames: Int, interleaved: Bool = true) {
        self.channels = channels
        self.frames = frames
        self.interleaved = interleaved
        let bufferCount = interleaved ? 1 : channels
        let width = interleaved ? channels : 1
        list = AudioBufferList.allocate(maximumBuffers: bufferCount)
        for index in 0..<bufferCount {
            let data = UnsafeMutablePointer<Float>.allocate(capacity: frames * width)
            data.initialize(repeating: 0, count: frames * width)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(width), mDataByteSize: UInt32(frames * width * MemoryLayout<Float>.size), mData: data
            )
        }
    }

    deinit {
        for buffer in list { buffer.mData?.deallocate() }
        free(list.unsafeMutablePointer)
    }

    subscript(channel: Int, frame: Int) -> Float {
        get { pointer(channel, frame).pointee }
        set { pointer(channel, frame).pointee = newValue }
    }

    /// Takes frame-major, channel-minor samples whatever the layout of the buffers.
    func load(_ samples: [Float]) {
        precondition(samples.count == channels * frames)
        for frame in 0..<frames {
            for channel in 0..<channels { self[channel, frame] = samples[frame * channels + channel] }
        }
    }

    /// `load` for the interleaved layout as one copy, for a measured loop that must not allocate.
    func restore(_ samples: [Float]) {
        precondition(interleaved && samples.count == channels * frames)
        samples.withUnsafeBytes { source in
            _ = memcpy(list[0].mData!, source.baseAddress!, source.count)
        }
    }

    func samples() -> [Float] {
        var result: [Float] = []
        for frame in 0..<frames {
            for channel in 0..<channels { result.append(self[channel, frame]) }
        }
        return result
    }

    private func pointer(_ channel: Int, _ frame: Int) -> UnsafeMutablePointer<Float> {
        if interleaved {
            return list[0].mData!.assumingMemoryBound(to: Float.self) + frame * channels + channel
        }
        return list[channel].mData!.assumingMemoryBound(to: Float.self) + frame
    }
}
