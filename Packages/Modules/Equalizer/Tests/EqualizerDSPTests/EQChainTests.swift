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
            for gain in [12.0, -12.0] {
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
        let input = noise.samples(2 * Self.blockFrames)
        let untouched = EQChain(channels: 2)
        let zeroed = EQChain(channels: 2)
        zeroed.setParameters(gains: Array(repeating: 0, count: 10), preampDB: 0, sampleRate: Self.sampleRate)
        for chain in [untouched, zeroed] {
            let block = AudioBlock(channels: 2, frames: Self.blockFrames)
            block.load(input)
            chain.process(block.list, frames: Self.blockFrames)
            #expect(block.samples().map(\.bitPattern) == input.map(\.bitPattern))
        }
    }

    @Test func flatDoesNotClampOrAlterLoudInput() {
        let chain = EQChain(channels: 1)
        let block = AudioBlock(channels: 1, frames: 4)
        block.load([1.5, -2, 0.25, 1])
        chain.process(block.list, frames: 4)
        #expect(block.samples() == [1.5, -2, 0.25, 1])
    }

    @Test func returningToFlatIsBitExactAgain() {
        var noise = SeededNoise(seed: 2)
        let chain = EQChain(channels: 2)
        chain.setParameters(gains: [12, 6, -3, 0, 0, 4, 0, -12, 0, 8], preampDB: -3, sampleRate: Self.sampleRate)
        let warmUp = AudioBlock(channels: 2, frames: Self.blockFrames)
        for _ in 0..<3 {
            warmUp.load(noise.samples(2 * Self.blockFrames, amplitude: 0.5))
            chain.process(warmUp.list, frames: Self.blockFrames)
        }
        chain.setParameters(gains: Array(repeating: 0, count: 10), preampDB: 0, sampleRate: Self.sampleRate)
        for _ in 0..<3 {
            warmUp.load(noise.samples(2 * Self.blockFrames, amplitude: 0.5))
            chain.process(warmUp.list, frames: Self.blockFrames)
        }
        let input = noise.samples(2 * Self.blockFrames)
        let block = AudioBlock(channels: 2, frames: Self.blockFrames)
        block.load(input)
        chain.process(block.list, frames: Self.blockFrames)
        #expect(block.samples().map(\.bitPattern) == input.map(\.bitPattern))
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
        #expect(peak <= 1.0)
        // Not vacuous: ten +12 dB bands on loud noise do reach the ceiling.
        #expect(peak == 1.0)
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
        #expect(peak <= 1.0)
    }

    @Test func unusableSampleRateLeavesTheSoundAlone() {
        var noise = SeededNoise(seed: 5)
        let input = noise.samples(Self.blockFrames)
        for rate in [0.0, -1, .nan, .infinity] {
            let chain = EQChain(channels: 1)
            chain.setParameters(gains: Array(repeating: 12, count: 10), preampDB: 0, sampleRate: rate)
            let block = AudioBlock(channels: 1, frames: Self.blockFrames)
            block.load(input)
            chain.process(block.list, frames: Self.blockFrames)
            #expect(block.samples().map(\.bitPattern) == input.map(\.bitPattern), "rate \(rate)")
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
            #expect(block.samples().allSatisfy { $0.isFinite && abs($0) <= 1 })
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
        #expect(poison.samples().allSatisfy { $0 == 0 }, "poisoned input must come out as silence")
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
        let block = AudioBlock(channels: 1, frames: 4)
        block.load([0.5, .nan, .infinity, -0.25])
        chain.process(block.list, frames: 4)
        #expect(block.samples() == [0.5, 0, 0, -0.25])
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

    @Test func processDoesNotAllocate() {
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
        if let allocations { #expect(allocations == 0, "process allocated or freed \(allocations) times") }

        // The plan's check: no block still allocated after 10,000 calls.
        // That count is for the whole process, so a block freed on another thread (a test's dispatch work finishing) can
        // fall inside a reading. Real growth shows in every try, so passing needs one try with none.
        let curves: [(gains: [Double], preamp: Double, rate: Double)] = [
            ([-6, -4, -2, 0, 1, 2.5, 4, 3.5, 1, 0], -2, 44_100),
            ([4, 3, 1.5, 0, -1, -1, 0, 1.5, 3, 4], -4, 48_000),
            ([5, 4, 2, 0, 0, 1.5, 2.5, 2, 1, 0], -4, 44_100),
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
