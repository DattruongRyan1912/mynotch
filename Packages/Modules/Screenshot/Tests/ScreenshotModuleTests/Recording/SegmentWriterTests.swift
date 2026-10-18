import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct SegmentWriterTests {
    let folder: TestFolder
    static let width = 128, height = 72, fps = 30
    static let t0: TimeInterval = 5_000

    init() throws { folder = try TestFolder("segment") }

    func makeWriter(audio: [AudioTrackKind] = [], name: String = "segment.mov", width: Int = width, height: Int = height) throws -> SegmentWriter {
        try SegmentWriter(url: folder.file(name), width: width, height: height, fps: Self.fps, audio: audio, backpressure: .wait)
    }

    /// `seconds` of frames at `fps` from `start`, with the sound of each asked-for track arriving a little ahead of the frame.
    func feed(_ writer: SegmentWriter, from start: TimeInterval = t0, seconds: Double, audio: [AudioTrackKind] = [], rate: Double = 48_000) {
        let frames = Int(seconds * Double(Self.fps))
        var audioFrame = 0
        for index in 0..<frames {
            let time = start + Double(index) / Double(Self.fps)
            let frame = RecordingMediaFactory.frame(width: Self.width, height: Self.height, index: index)
            writer.appendVideo(frame.pixelBuffer, at: RecordingMediaFactory.time(time))
            while Double(audioFrame) / rate < Double(index) / Double(Self.fps) + 0.05, !audio.isEmpty {
                for kind in audio {
                    writer.appendAudio(RecordingMediaFactory.audio(start: start + Double(audioFrame) / rate, frames: 1024, sampleRate: rate, channels: kind.channels), kind: kind)
                }
                audioFrame += 1024
            }
        }
    }

    func finish(_ writer: SegmentWriter, at end: TimeInterval) async throws -> SegmentWriter.Summary {
        try await withCheckedThrowingContinuation { continuation in
            writer.finish(endingAt: end) { continuation.resume(with: $0.mapError { $0 }) }
        }
    }

    @Test func writesHEVCVideoAndOneAACTrackPerSourceIntoOneMovie() async throws {
        let writer = try makeWriter(audio: [.microphone, .system])
        feed(writer, seconds: 2, audio: [.microphone, .system])

        let summary = try await finish(writer, at: Self.t0 + 2)

        #expect(summary.frames == 60)
        #expect(summary.droppedFrames == 0 && summary.droppedAudio == 0)
        #expect(summary.start == Self.t0)
        #expect(summary.duration == 2)
        let probe = try await MediaProbe.read(writer.url)
        #expect(probe.isPlayable)
        #expect(probe.videoCodec == kCMVideoCodecType_HEVC)
        #expect(probe.videoSize == CGSize(width: Self.width, height: Self.height))
        #expect(probe.videoFrames == 60)
        #expect(probe.audioDurations.count == 2)
        #expect(abs(probe.duration - 2) < 0.1)
    }

    @Test func theLastFrameLastsUntilTheMomentTheRecordingEnded() async throws {
        let writer = try makeWriter()
        feed(writer, seconds: 1)

        // Still screen: the last frame came at 0.967 s but the recording went on to 3 s.
        let summary = try await finish(writer, at: Self.t0 + 3)

        #expect(summary.duration == 3)
        let probe = try await MediaProbe.read(writer.url)
        #expect(abs(probe.duration - 3) < 0.1)
    }

    @Test func soundBeforeTheFirstFrameIsNotKeptSoSoundAndPictureStartTogether() async throws {
        let writer = try makeWriter(audio: [.microphone])

        let early = RecordingMediaFactory.audio(start: Self.t0 - 0.5, frames: 4800)
        #expect(writer.appendAudio(early, kind: .microphone) == false)
        feed(writer, seconds: 1, audio: [.microphone])
        let summary = try await finish(writer, at: Self.t0 + 1)

        let probe = try await MediaProbe.read(writer.url)
        #expect(abs((probe.audioStarts.first ?? 9) - 0) < 0.05)
        #expect(abs((probe.audioDurations.first ?? 0) - summary.duration) < 0.1)
    }

    @Test func soundInAnotherFormatIsConvertedNotRefused() async throws {
        let writer = try makeWriter(audio: [.microphone, .system])
        let frame = RecordingMediaFactory.frame(width: Self.width, height: Self.height)
        writer.appendVideo(frame.pixelBuffer, at: RecordingMediaFactory.time(Self.t0))
        var accepted = 0
        // A microphone at 44.1 kHz stereo in 16 bits, and a system mix in mono.
        for index in 0..<40 {
            let micStart = Self.t0 + Double(index) * 441 / 44_100
            if writer.appendAudio(RecordingMediaFactory.audio(start: micStart, frames: 441, sampleRate: 44_100, channels: 2, interleavedInt16: true), kind: .microphone) { accepted += 1 }
            if writer.appendAudio(RecordingMediaFactory.audio(start: Self.t0 + Double(index) * 0.01, frames: 480, channels: 1), kind: .system) { accepted += 1 }
        }
        let summary = try await finish(writer, at: Self.t0 + 0.4)

        #expect(accepted == 80)
        #expect(summary.droppedAudio == 0)
        let probe = try await MediaProbe.read(writer.url)
        #expect(probe.audioDurations.count == 2)
        #expect(probe.audioDurations.allSatisfy { abs($0 - 0.4) < 0.1 })
    }

    @Test func aTrackThatDeliversNothingIsFilledWithSilenceSoItNeverHoldsTheFileBack() async throws {
        let writer = try makeWriter(audio: [.microphone, .system])
        // The system plays nothing and the microphone is muted: neither sends a buffer for the whole recording.
        feed(writer, seconds: 3)

        let summary = try await finish(writer, at: Self.t0 + 3)

        let probe = try await MediaProbe.read(writer.url)
        #expect(probe.audioDurations.count == 2)
        #expect(probe.audioDurations.allSatisfy { abs($0 - summary.duration) < 0.1 })
    }

    @Test func realSoundThatArrivesLateAfterSilenceIsNotWrittenTwice() async throws {
        let writer = try makeWriter(audio: [.microphone])
        feed(writer, seconds: 2)
        // Silence has been written up to about 1.97 s; sound stamped before that overlaps it and is dropped, later sound is kept.
        let overlapping = RecordingMediaFactory.audio(start: Self.t0 + 1.0, frames: 4800)
        let later = RecordingMediaFactory.audio(start: Self.t0 + 2.0, frames: 4800)

        #expect(writer.appendAudio(overlapping, kind: .microphone) == false)
        #expect(writer.appendAudio(later, kind: .microphone) == true)
        let summary = try await finish(writer, at: Self.t0 + 2.2)

        #expect(summary.droppedAudio == 1)
    }

    @Test func aStillScreenWritesItsLastFrameAgainOnlyOnceTheWaitIsOver() async throws {
        let writer = try makeWriter()
        writer.appendVideo(RecordingMediaFactory.frame(width: Self.width, height: Self.height).pixelBuffer, at: RecordingMediaFactory.time(Self.t0))

        writer.repeatLastFrame(at: Self.t0 + 0.3, after: 0.5)
        #expect(writer.frames == 1)
        writer.repeatLastFrame(at: Self.t0 + 0.6, after: 0.5)
        #expect(writer.frames == 2)
        writer.repeatLastFrame(at: Self.t0 + 0.9, after: 0.5)
        #expect(writer.frames == 2)
        _ = try await finish(writer, at: Self.t0 + 1)
    }

    @Test func nothingIsRepeatedBeforeTheFirstFrame() throws {
        let writer = try makeWriter()

        writer.repeatLastFrame(at: Self.t0 + 5, after: 0.5)

        #expect(writer.frames == 0)
        writer.cancel()
    }

    @Test func aFrameNotNewerThanTheLastIsDropped() async throws {
        let writer = try makeWriter()
        let frame = RecordingMediaFactory.frame(width: Self.width, height: Self.height)

        #expect(writer.appendVideo(frame.pixelBuffer, at: RecordingMediaFactory.time(Self.t0)))
        #expect(writer.appendVideo(frame.pixelBuffer, at: RecordingMediaFactory.time(Self.t0 + 0.1)))
        #expect(writer.appendVideo(frame.pixelBuffer, at: RecordingMediaFactory.time(Self.t0 + 0.1)) == false)
        #expect(writer.appendVideo(frame.pixelBuffer, at: RecordingMediaFactory.time(Self.t0 + 0.05)) == false)
        let summary = try await finish(writer, at: Self.t0 + 0.5)

        #expect(summary.frames == 2)
    }

    @Test func aWriterThatSawNoFrameLeavesNoFileAndNoRecording() async throws {
        let writer = try makeWriter(audio: [.microphone])
        #expect(FileManager.default.fileExists(atPath: writer.url.path))

        await #expect(throws: RecordingError.nothingRecorded) { try await finish(writer, at: Self.t0 + 5) }

        #expect(!FileManager.default.fileExists(atPath: writer.url.path))
    }

    @Test func theHardwareEncoderTakesAFiveKDisplayAtItsOwnResolution() async throws {
        // Hardware H.264 stops at 4096×2304: `canApply` says yes for 5K and the first frame then fails. HEVC does not.
        let writer = try SegmentWriter(url: folder.file("5k.mov"), width: 5120, height: 2880, fps: 60, audio: [], backpressure: .wait)
        let frame = RecordingMediaFactory.frame(width: 5120, height: 2880, detailed: false)
        #expect(writer.appendVideo(frame.pixelBuffer, at: RecordingMediaFactory.time(Self.t0)))
        #expect(writer.appendVideo(frame.pixelBuffer, at: RecordingMediaFactory.time(Self.t0 + 1.0 / 60)))

        _ = try await finish(writer, at: Self.t0 + 0.05)

        let probe = try await MediaProbe.read(writer.url)
        #expect(probe.videoSize == CGSize(width: 5120, height: 2880))
        #expect(probe.videoFrames == 2)
        #expect(writer.failure == nil)
    }

    @Test func settingsAskForHEVCOnTheHardwareEncoderWithoutReordering() throws {
        let settings = RecordingMedia.videoSettings(width: 1920, height: 1080, fps: 60)
        let compression = try #require(settings[AVVideoCompressionPropertiesKey] as? [String: Any])

        #expect(settings[AVVideoCodecKey] as? AVVideoCodecType == .hevc)
        #expect(settings[AVVideoWidthKey] as? Int == 1920 && settings[AVVideoHeightKey] as? Int == 1080)
        #expect(compression[AVVideoAllowFrameReorderingKey] as? Bool == false)
        #expect(compression[AVVideoExpectedSourceFrameRateKey] as? Int == 60)
        #expect(settings[AVVideoEncoderSpecificationKey] != nil)
        #expect(RecordingMedia.videoSettings(width: 1920, height: 1080, fps: 60, requireHardware: false)[AVVideoEncoderSpecificationKey] == nil)
    }

    @Test func theBitrateGrowsWithThePicturesAndStaysInRange() {
        #expect(RecordingMedia.bitrate(width: 1920, height: 1080, fps: 60) == 9_953_280)
        #expect(RecordingMedia.bitrate(width: 128, height: 72, fps: 30) == 8_000_000)
        #expect(RecordingMedia.bitrate(width: 3840, height: 2160, fps: 60) == 39_813_120)
        #expect(RecordingMedia.bitrate(width: 7680, height: 4320, fps: 60) == 50_000_000)
    }

    @Test func audioSettingsAreAACAt48kHzWithTheTracksChannels() {
        let mic = RecordingMedia.audioSettings(for: .microphone)
        let system = RecordingMedia.audioSettings(for: .system)

        #expect(mic[AVFormatIDKey] as? AudioFormatID == kAudioFormatMPEG4AAC)
        #expect(mic[AVNumberOfChannelsKey] as? Int == 1 && system[AVNumberOfChannelsKey] as? Int == 2)
        #expect(mic[AVSampleRateKey] as? Int == 48_000)
    }
}

@Suite struct AudioNormalizerTests {
    @Test func soundAlreadyInTheTracksFormatPassesThroughUntouched() throws {
        let normalizer = AudioNormalizer(kind: .microphone)
        let sample = RecordingMediaFactory.audio(start: 1, frames: 480, channels: 1)

        let result = try #require(normalizer.normalized(sample))

        #expect(result === sample)
    }

    @Test func otherRatesChannelsAndSampleTypesAreConvertedKeepingTheStartTime() throws {
        let normalizer = AudioNormalizer(kind: .microphone)
        let sample = RecordingMediaFactory.audio(start: 12.5, frames: 441, sampleRate: 44_100, channels: 2, interleavedInt16: true)

        let result = try #require(normalizer.normalized(sample))

        #expect(result.presentationTimeStamp.seconds == 12.5)
        #expect(abs(Double(CMSampleBufferGetNumSamples(result)) - 480) <= 64)
        let format = AVAudioFormat(cmAudioFormatDescription: try #require(CMSampleBufferGetFormatDescription(result)))
        #expect(format == normalizer.format)
        #expect(format.channelCount == 1 && format.sampleRate == 48_000)
    }

    @Test func monoIsSpreadOverTheTwoChannelsOfTheSystemTrack() throws {
        let normalizer = AudioNormalizer(kind: .system)

        let result = try #require(normalizer.normalized(RecordingMediaFactory.audio(start: 0, frames: 480, channels: 1)))

        #expect(AVAudioFormat(cmAudioFormatDescription: try #require(CMSampleBufferGetFormatDescription(result))).channelCount == 2)
    }

    @Test func silenceIsZeroInTheTracksFormatAndStartsWhereAsked() throws {
        let normalizer = AudioNormalizer(kind: .system)

        let silence = try #require(normalizer.silence(from: RecordingMediaFactory.time(3), seconds: 0.25))

        #expect(silence.presentationTimeStamp.seconds == 3)
        #expect(CMSampleBufferGetNumSamples(silence) == 12_000)
        #expect(abs(silence.duration.seconds - 0.25) < 0.001)
    }

    @Test func anEmptyBufferGivesNothing() {
        let normalizer = AudioNormalizer(kind: .microphone)
        var sample: CMSampleBuffer?
        let format = normalizer.format
        CMSampleBufferCreate(
            allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: format.formatDescription, sampleCount: 0, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample
        )

        #expect(sample.flatMap { normalizer.normalized($0) } == nil)
    }
}
