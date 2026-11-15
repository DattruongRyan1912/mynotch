import CoreAudio
import EqualizerDSP
import Foundation
import Testing

struct LoudnessCompensationTests {
    static let sampleRate = 48_000.0

    @Test func deficitIsZeroAtAndAboveTheReference() {
        #expect(LoudnessCompensation.deficit(volume: 0.6) == 0)
        #expect(LoudnessCompensation.deficit(volume: 1) == 0)
        #expect(LoudnessCompensation.deficit(volume: 0.3) == 0.5)
        #expect(LoudnessCompensation.deficit(volume: 0) == 1)
        #expect(LoudnessCompensation.deficit(volume: -1) == 1)
        #expect(LoudnessCompensation.deficit(volume: .nan) == 0)
    }

    @Test func curveRaisesOnlyTheEnds() {
        let gains = LoudnessCompensation.gains(volume: 0)
        // 32 Hz full bass, 125 Hz on the fade, 250 Hz to 4 kHz untouched, 8 kHz on the fade, 16 kHz full treble.
        #expect(gains[0] == LoudnessCompensation.maxBassDB)
        #expect(gains[2] > 0 && gains[2] < LoudnessCompensation.maxBassDB)
        #expect(gains[3...7].allSatisfy { $0 == 0 })
        #expect(gains[8] > 0 && gains[8] < LoudnessCompensation.maxTrebleDB)
        #expect(gains[9] == LoudnessCompensation.maxTrebleDB)
    }

    @Test func curveScalesWithTheDeficit() {
        let half = LoudnessCompensation.gains(volume: 0.3)
        let full = LoudnessCompensation.gains(volume: 0)
        for (h, f) in zip(half, full) { #expect(abs(h - f / 2) < 1e-9) }
        #expect(LoudnessCompensation.gains(volume: 0.8).allSatisfy { $0 == 0 })
    }

    @Test func atOrAboveTheReferenceTheProfileIsUntouched() {
        let gains = [4.0, 3, 1.5, 0, -1, -1, 0, 1.5, 3, 4]
        for volume in [nil, 0.6, 1.0] {
            let result = LoudnessCompensation.apply(volume: volume, gains: gains, preampDB: -4, sampleRate: Self.sampleRate)
            #expect(result.gains == gains)
            #expect(result.preampDB == -4)
        }
    }

    @Test func boostLowersThePreampByTheRiseOfThePeak() {
        let flat = Array(repeating: 0.0, count: 10)
        let result = LoudnessCompensation.apply(volume: 0, gains: flat, preampDB: 0, sampleRate: Self.sampleRate)
        // Neighbouring bands overlap, so the drop is more than the 8.5 dB of one band.
        #expect(result.preampDB < -LoudnessCompensation.maxBassDB)
        #expect(result.preampDB >= EQChain.preampRange.lowerBound)
        #expect(result.gains[0] == LoudnessCompensation.maxBassDB)
    }

    @Test func boostedBandsStayInRange() {
        let loud = Array(repeating: 12.0, count: 10)
        let result = LoudnessCompensation.apply(volume: 0, gains: loud, preampDB: -12, sampleRate: Self.sampleRate)
        #expect(result.gains.allSatisfy { EQChain.gainRange.contains($0) })
        #expect(result.preampDB == -12)

        // Extreme gains (20 dB) plus loudness boost (+8.5 dB) must clamp at +24 dB
        let extreme = Array(repeating: 20.0, count: 10)
        let extremeResult = LoudnessCompensation.apply(volume: 0, gains: extreme, preampDB: -12, sampleRate: Self.sampleRate)
        #expect(extremeResult.gains.allSatisfy { EQChain.gainRange.contains($0) })
        #expect(extremeResult.gains[0] == EQChain.gainRange.upperBound)
        #expect(extremeResult.preampDB == EQChain.preampRange.lowerBound)
    }

    /// The tap hands the chain a full-scale mix whatever the device volume is, so the boost must not drive bass into the clamp.
    @Test func fullScaleBassDoesNotClipAtSilenceLevelCompensation() {
        let settings = LoudnessCompensation.apply(volume: 0, gains: Array(repeating: 0, count: 10), preampDB: 0, sampleRate: Self.sampleRate)
        for frequency in [32.0, 45, 64, 13_000, 16_000] {
            let chain = EQChain(channels: 1)
            chain.setParameters(gains: settings.gains, preampDB: settings.preampDB, sampleRate: Self.sampleRate)
            let peak = renderPeak(chain, frequency: frequency, amplitude: 1)
            #expect(peak < 0.999, "\(frequency) Hz peaks at \(peak)")
            // And it is still a boost relative to the middle, which is what the user hears as fuller sound: well over 3.5 dB in the
            // bass, over 1.2 dB in the treble (ten bands an octave apart reach the 4 dB of the curve only near 16 kHz).
            let middle = EQChain(channels: 1)
            middle.setParameters(gains: settings.gains, preampDB: settings.preampDB, sampleRate: Self.sampleRate)
            let lift: Float = frequency < 1000 ? 1.5 : 1.15
            #expect(peak > renderPeak(middle, frequency: 1000, amplitude: 1) * lift, "\(frequency) Hz")
        }
    }

    /// Steady-state peak of a sine after the filters settle (two seconds in).
    private func renderPeak(_ chain: EQChain, frequency: Double, amplitude: Double) -> Float {
        let frames = 4800
        let data = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { data.deallocate() }
        let list = AudioBufferList.allocate(maximumBuffers: 1)
        defer { list.unsafeMutablePointer.deallocate() }
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: data)
        var peak: Float = 0
        for block in 0..<20 {
            for frame in 0..<frames {
                let t = Double(block * frames + frame) / Self.sampleRate
                data[frame] = Float(amplitude * sin(2 * .pi * frequency * t))
            }
            chain.process(list, frames: frames)
            if block >= 10 { for frame in 0..<frames { peak = max(peak, abs(data[frame])) } }
        }
        return peak
    }
}
