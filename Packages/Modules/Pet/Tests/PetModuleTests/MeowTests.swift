import Foundation
import Testing
@testable import PetModule

@Suite struct MeowSynthTests {
    @Test func theMeowIsHalfASecondOfSoundThatIsNeitherSilentNorClipped() {
        let samples = MeowSynth.samples()
        #expect(samples.count == MeowSynth.sampleRate / 2)
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        #expect(peak > 3000, "audible")
        #expect(peak < Int(Int16.max) * 9 / 10, "never clipped")
        // It starts and ends in silence, so it does not click.
        #expect(abs(Int(samples[0])) < 200)
        #expect(abs(Int(samples[samples.count - 1])) < 200)
    }

    @Test func itIsAWaveFileTheSystemCanPlay() {
        let data = MeowSynth.wav()
        let bytes = [UInt8](data)
        #expect(String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: bytes[8..<16], as: UTF8.self) == "WAVEfmt ")
        #expect(String(decoding: bytes[36..<40], as: UTF8.self) == "data")
        func le32(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 }
        func le16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        #expect(le16(20) == 1, "PCM")
        #expect(le16(22) == 1, "mono")
        #expect(le32(24) == MeowSynth.sampleRate)
        #expect(le16(34) == 16)
        #expect(le32(40) == MeowSynth.samples().count * 2)
        #expect(le32(4) == data.count - 8)
        #expect(data.count == 44 + MeowSynth.samples().count * 2)
    }

    @Test func itRisesAndFallsInPitch() {
        // Zero crossings in the first and the middle of the sound: the note goes up from where it begins.
        let samples = MeowSynth.samples()
        func crossings(_ range: Range<Int>) -> Int {
            zip(samples[range], samples[range].dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
        }
        let window = MeowSynth.sampleRate / 20
        let early = crossings(MeowSynth.sampleRate / 50..<MeowSynth.sampleRate / 50 + window)
        let peak = crossings(Int(Double(MeowSynth.sampleRate) * 0.17)..<Int(Double(MeowSynth.sampleRate) * 0.17) + window)
        #expect(peak > early)
    }
}
