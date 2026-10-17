import CoreAudio
import EqualizerDSP
import Foundation
import Testing
@testable import EqualizerAudio

/// The IO block's work, run on buffers the test builds: no device, no tap.
@Suite struct PipelineIOTests {
    private let frames = 512

    private func ramp(_ count: Int, from start: Float = 0.1) -> [Float] {
        (0..<count).map { start + Float($0) * 0.0005 }
    }

    private func makeIO(tapChannels: Int = 2, inputs: [Int] = [2], outputs: [Int] = [2], chain: EQChain? = nil) throws -> PipelineIO {
        let layout = try StreamLayout.resolve(tapChannels: tapChannels, isInterleaved: true, inputStreams: inputs, outputStreams: outputs)
        return PipelineIO(chain: chain ?? EQChain(channels: 8), layout: layout)
    }

    @Test func tapAudioReachesTheOutputOnceOpen() throws {
        let io = try makeIO()
        io.open()
        let input = TestBufferList([.init(channels: 2, frames: frames)])
        let output = TestBufferList([.init(channels: 2, frames: frames)])
        let samples = ramp(2 * frames)
        input.fill(0, with: samples)
        io.process(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        // A flat chain changes nothing, so the replay is the tap bit for bit.
        #expect(output.samples(0) == samples)
        #expect(input.samples(0) == samples)
    }

    @Test func staysSilentUntilOpened() throws {
        let io = try makeIO()
        let input = TestBufferList([.init(channels: 2, frames: frames)])
        let output = TestBufferList([.init(channels: 2, frames: frames)])
        input.fill(0, with: ramp(2 * frames))
        output.fill(0, with: [Float](repeating: 0.7, count: 2 * frames))
        io.process(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        #expect(output.samples(0).allSatisfy { $0 == 0 })
        io.open()
        io.process(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        #expect(output.samples(0) == input.samples(0))
    }

    @Test func theChainShapesWhatIsReplayed() throws {
        let chain = EQChain(channels: 8)
        chain.setParameters(gains: [], preampDB: -6, sampleRate: 48_000)
        let io = try makeIO(chain: chain)
        io.open()
        let input = TestBufferList([.init(channels: 2, frames: frames)])
        let output = TestBufferList([.init(channels: 2, frames: frames)])
        var peak: Float = 0
        for _ in 0..<3 {
            input.fill(0, with: [Float](repeating: 0.5, count: 2 * frames))
            io.process(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
            peak = output.samples(0).map(abs).max() ?? 0
        }
        #expect(abs(peak - 0.25) < 0.01)
    }

    @Test func aMicrophoneStreamBeforeTheTapIsNeverReplayed() throws {
        // A headset's output device also lists its microphone among the aggregate device's inputs.
        let io = try makeIO(inputs: [1, 2], outputs: [2])
        io.open()
        let input = TestBufferList([.init(channels: 1, frames: frames), .init(channels: 2, frames: frames)])
        let output = TestBufferList([.init(channels: 2, frames: frames)])
        let voice = [Float](repeating: 0.9, count: frames)
        let tap = ramp(2 * frames)
        input.fill(0, with: voice)
        input.fill(1, with: tap)
        io.process(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        #expect(output.samples(0) == tap)
    }

    @Test func aSwitchedOffStreamHasNoDataAndIsNotTouched() throws {
        let io = try makeIO(inputs: [1, 2], outputs: [2])
        io.open()
        let input = TestBufferList([.init(channels: 1, frames: nil), .init(channels: 2, frames: frames)])
        let output = TestBufferList([.init(channels: 2, frames: frames)])
        let tap = ramp(2 * frames)
        input.fill(1, with: tap)
        io.process(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        #expect(output.samples(0) == tap)
    }

    @Test func aShortTapZeroesTheRestOfTheOutput() throws {
        let io = try makeIO()
        io.open()
        let input = TestBufferList([.init(channels: 2, frames: 100)])
        let output = TestBufferList([.init(channels: 2, frames: frames)])
        output.fill(0, with: [Float](repeating: 0.7, count: 2 * frames))
        let tap = ramp(200)
        input.fill(0, with: tap)
        io.process(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        let out = output.samples(0)
        #expect(Array(out[0..<200]) == tap)
        #expect(out[200...].allSatisfy { $0 == 0 })
    }

    @Test func extraOutputStreamsStaySilent() throws {
        let io = try makeIO(inputs: [2], outputs: [2, 2])
        io.open()
        let input = TestBufferList([.init(channels: 2, frames: frames)])
        let output = TestBufferList([.init(channels: 2, frames: frames), .init(channels: 2, frames: frames)])
        output.fill(1, with: [Float](repeating: 0.7, count: 2 * frames))
        input.fill(0, with: ramp(2 * frames))
        io.process(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        #expect(output.samples(0) == input.samples(0))
        #expect(output.samples(1).allSatisfy { $0 == 0 })
    }

    @Test func buffersThatDoNotMatchBecomeSilenceNotNoise() throws {
        let io = try makeIO()
        io.open()
        // The layout said stereo; this callback brings a mono buffer (a format change not yet noticed).
        let input = TestBufferList([.init(channels: 1, frames: frames)])
        let output = TestBufferList([.init(channels: 2, frames: frames)])
        input.fill(0, with: ramp(frames))
        output.fill(0, with: [Float](repeating: 0.7, count: 2 * frames))
        io.process(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        #expect(output.samples(0).allSatisfy { $0 == 0 })
    }

    @Test func missingInputStreamsBecomeSilence() throws {
        let io = try makeIO()
        io.open()
        let input = TestBufferList([])
        let output = TestBufferList([.init(channels: 2, frames: frames)])
        output.fill(0, with: [Float](repeating: 0.7, count: 2 * frames))
        io.process(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        #expect(output.samples(0).allSatisfy { $0 == 0 })
    }

    @Test func peakIsTheLoudestTapSampleSinceTheLastLookAndIgnoresGlitches() throws {
        let io = try makeIO()
        io.open()
        let input = TestBufferList([.init(channels: 2, frames: 4)])
        let output = TestBufferList([.init(channels: 2, frames: 4)])
        #expect(io.takePeak() == 0)
        input.fill(0, with: [0.1, -0.4, 0.2, .nan, 0.3, 0, 0, 0])
        io.process(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        input.fill(0, with: [0.05, 0, 0, 0, 0, 0, 0, 0])
        io.process(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        #expect(io.takePeak() == 0.4)
        #expect(io.takePeak() == 0)
    }

    @Test func aTapThatIsSilentEvenWhileClosedStillShowsAsSilent() throws {
        let io = try makeIO()
        let input = TestBufferList([.init(channels: 2, frames: 4)])
        let output = TestBufferList([.init(channels: 2, frames: 4)])
        io.process(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        #expect(io.takePeak() == 0)
    }

    // MARK: Layout

    @Test func layoutFindsTheTapAfterTheMicrophone() throws {
        let layout = try StreamLayout.resolve(tapChannels: 2, isInterleaved: true, inputStreams: [1, 2], outputStreams: [2])
        #expect(layout == StreamLayout(firstInput: 1, streams: 1))
    }

    @Test func layoutOfANonInterleavedTapIsOneStreamPerChannel() throws {
        let layout = try StreamLayout.resolve(tapChannels: 2, isInterleaved: false, inputStreams: [1, 1, 1], outputStreams: [1, 1])
        #expect(layout == StreamLayout(firstInput: 1, streams: 2))
    }

    @Test func layoutRefusesWhatItCannotMatch() {
        // Tap stereo but the stream it should sit in is mono: not safe to copy bytes across.
        #expect(throws: (any Error).self) {
            try StreamLayout.resolve(tapChannels: 2, isInterleaved: true, inputStreams: [2, 1], outputStreams: [2])
        }
        // The device has no stream to play the tap on.
        #expect(throws: (any Error).self) {
            try StreamLayout.resolve(tapChannels: 2, isInterleaved: true, inputStreams: [2], outputStreams: [])
        }
        // The device's stream has another channel count.
        #expect(throws: (any Error).self) {
            try StreamLayout.resolve(tapChannels: 2, isInterleaved: true, inputStreams: [2], outputStreams: [6])
        }
        // No tap stream at all.
        #expect(throws: (any Error).self) {
            try StreamLayout.resolve(tapChannels: 2, isInterleaved: true, inputStreams: [], outputStreams: [2])
        }
        #expect(throws: (any Error).self) {
            try StreamLayout.resolve(tapChannels: 0, isInterleaved: true, inputStreams: [2], outputStreams: [2])
        }
    }
}
