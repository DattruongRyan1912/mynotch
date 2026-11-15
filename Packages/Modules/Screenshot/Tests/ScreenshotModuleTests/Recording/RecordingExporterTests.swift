import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import ScreenshotModule

/// What an exported MP4 holds, read back as any player would.
enum ExportProbe {
    static func frames(of url: URL, at points: [(Int, Int)]) async throws -> [CompositionProbe.Frame] {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        reader.startReading()
        var frames: [CompositionProbe.Frame] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            frames.append(.init(time: sample.presentationTimeStamp.seconds, pixels: points.map { PixelBuffers.read(buffer, x: $0.0, y: $0.1) }))
        }
        if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadUnknown) }
        return frames
    }

    /// The sound as mono 48 kHz samples from time 0: the two channels averaged.
    static func samples(of url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
        ])
        reader.add(output)
        reader.startReading()
        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &chunk)
            samples += stride(from: 0, to: chunk.count - 1, by: 2).map { (chunk[$0] + chunk[$0 + 1]) / 2 }
        }
        if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadUnknown) }
        return samples
    }
}

/// Samples with big frames: a few distinct pictures are made once and shown over and over, so the encoder has frames to take
/// and the test does not spend its time painting.
enum BigSample {
    static func make(
        width: Int, height: Int, fps: Int = 30, seconds: Double, frameInterval: Double, noisy: Bool = false
    ) async throws -> SampleRecording {
        let pictures: [CVPixelBuffer] = (0..<4).map { index in
            noisy || width * height <= 1_000_000
                ? PixelBuffers.make(width: width, height: height) { x, y in
                    let value = UInt8(truncatingIfNeeded: (x &* 73 &+ y &* 151 &+ index &* 37) ^ (x &* y &>> 3))
                    return (value, value &+ 40, 255 &- value)
                }
                : RecordingMediaFactory.frame(width: width, height: height, index: index, detailed: false).pixelBuffer
        }
        return try await SampleRecording.make(
            parts: [.init(seconds: seconds, frameInterval: frameInterval)], width: width, height: height, fps: fps,
            picture: { pictures[Int($0 / frameInterval + 1e-6) % pictures.count] }
        )
    }
}

/// The big frames are encoded by the hardware, which the tests share with nothing else, so these run one at a time.
@Suite(.serialized) struct RecordingExporterTests {
    func export(
        _ recording: SampleRecording, _ level: ExportLevel, into folder: TestFolder, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> RecordingExportResult {
        try await RecordingExporter.export(
            project: recording.project, folder: recording.folder.url, activity: recording.activity, level: level,
            into: folder.url, progress: progress
        )
    }

    /// Time between each frame and the next: a constant frame rate has all of them equal.
    func gaps(_ times: [Double]) -> [Double] { zip(times, times.dropFirst()).map { $1 - $0 } }

    // MARK: The levels

    @Test func chatMakesA1080p30H264Mp4WithAAC() async throws {
        let recording = try await BigSample.make(width: 2560, height: 1440, fps: 60, seconds: 1, frameInterval: 1.0 / 15)
        let out = try TestFolder("export-out")
        let result = try await export(recording, .chat, into: out)

        let probe = try await MediaProbe.read(result.url)
        #expect(result.url.pathExtension == "mp4")
        #expect(result.url.deletingLastPathComponent().standardizedFileURL == out.url.standardizedFileURL)
        #expect(probe.isPlayable)
        #expect(probe.videoSize == CGSize(width: 1920, height: 1080))
        #expect(probe.videoCodec == kCMVideoCodecType_H264)
        #expect(result.plan.size == CGSize(width: 1920, height: 1080))
        #expect(result.plan.frameRate == 30)
        #expect(abs(probe.videoFrames - 30) <= 1, "frames \(probe.videoFrames)")
        #expect(abs(probe.duration - 1) < 0.1)
        #expect(!(try await Self.hasPartialFile(in: out)))
    }

    @Test func highKeepsTheRecordingsSizeAndItsSixtyFramesASecond() async throws {
        let recording = try await BigSample.make(width: 1280, height: 720, fps: 60, seconds: 1.5, frameInterval: 1.0 / 20)
        let out = try TestFolder("export-out")
        let result = try await export(recording, .high, into: out)

        let probe = try await MediaProbe.read(result.url)
        #expect(probe.videoSize == CGSize(width: 1280, height: 720))
        #expect(probe.videoCodec == kCMVideoCodecType_H264)
        #expect(abs(probe.videoFrames - 90) <= 1, "frames \(probe.videoFrames)")
        for gap in gaps(probe.videoTimes) { #expect(abs(gap - 1.0 / 60) < 0.0005) }
    }

    @Test func highScalesAWiderThan4096RegionDownTo4096AndTheHardwareEncoderTakesIt() async throws {
        // An ultrawide region, 4224 pixels across: the file must come out 4096 across, with real frames in it (REC1 found that an
        // encoder can say yes to a size and then fail at the first frame). Few pixels in all, so that the test does not keep the
        // hardware encoder, which every other test shares, for long; the 5K display itself is in `ExportLevelTests`.
        let recording = try await BigSample.make(width: 4224, height: 1188, seconds: 0.5, frameInterval: 0.25)
        #expect(recording.project.region.pixelWidth == 4224)
        let out = try TestFolder("export-out")
        let result = try await export(recording, .high, into: out)

        let probe = try await MediaProbe.read(result.url)
        #expect(probe.videoSize == CGSize(width: 4096, height: 1152))
        #expect(probe.videoCodec == kCMVideoCodecType_H264)
        #expect(abs(probe.videoFrames - 15) <= 1, "frames \(probe.videoFrames)")
    }

    @Test func aRegionInsideTheLimitsIsNotScaled() async throws {
        let recording = try await BigSample.make(width: 1000, height: 600, seconds: 0.5, frameInterval: 0.1)
        let out = try TestFolder("export-out")
        #expect(try await export(recording, .chat, into: out).plan.size == CGSize(width: 1000, height: 600))
        #expect(try await MediaProbe.read(try await export(recording, .high, into: out).url).videoSize == CGSize(width: 1000, height: 600))
    }

    // MARK: Constant frame rate

    @Test func aScreenThatStoodStillStillGivesAFrameEveryThirtiethOfASecond() async throws {
        // The raw file holds a frame every half second; the export must not copy that.
        let recording = try await BigSample.make(width: 320, height: 180, seconds: 3, frameInterval: 0.5)
        let out = try TestFolder("export-out")
        let result = try await export(recording, .chat, into: out)

        let probe = try await MediaProbe.read(result.url)
        #expect(abs(probe.videoFrames - 90) <= 1, "frames \(probe.videoFrames)")
        let spacing = gaps(probe.videoTimes)
        #expect(!spacing.isEmpty)
        for gap in spacing { #expect(abs(gap - 1.0 / 30) < 0.0005, "gap \(gap)") }
        #expect(abs(probe.videoTimes[0]) < 0.001, "the first frame is at \(probe.videoTimes[0])")
        // Read the way a player decodes it too: the first picture at 0, a picture every thirtieth of a second.
        let decoded = try await ExportProbe.frames(of: result.url, at: [(0, 0)])
        #expect(abs(decoded[0].time) < 0.001)
        for gap in gaps(decoded.map(\.time)) { #expect(abs(gap - 1.0 / 30) < 0.0005, "decoded gap \(gap)") }
    }

    // MARK: Bitrate

    @Test func theBitrateOfBusyContentStaysNearTheLevelsTarget() async throws {
        let recording = try await BigSample.make(width: 640, height: 360, seconds: 2, frameInterval: 1.0 / 30, noisy: true)
        let out = try TestFolder("export-out")
        let result = try await export(recording, .chat, into: out)

        // An encoder may undershoot, and on noise, which cannot be compressed, overshoots a little; it never goes far over.
        let rate = Double(try await MediaProbe.read(result.url).videoDataRate)
        #expect(result.plan.videoBitrate == 4_000_000)
        #expect(rate > 0)
        #expect(rate < Double(result.plan.videoBitrate) * 2, "\(rate) bit/s against \(result.plan.videoBitrate)")
    }

    // MARK: Sound and picture

    @Test func theExportedSoundAndPictureStillMatchAfterACutThatSpansAPause() async throws {
        // Seconds 0-5 of the recording, a pause in the middle, and the stretch (1.5 s to 4.5 s) cut out.
        var recording = try await RecordingCompositionTests.sample(parts: [.init(seconds: 3), .init(seconds: 3)])
        recording.project.cuts = [CutRange(start: 1.5, end: 4.5)]
        let out = try TestFolder("export-out")
        let result = try await export(recording, .chat, into: out)

        let probe = try await MediaProbe.read(result.url)
        #expect(probe.audioCodecs == [kAudioFormatMPEG4AAC])
        #expect(probe.audioChannels == [2])
        #expect(abs(probe.duration - 3) < 0.1)

        let frames = try await ExportProbe.frames(of: result.url, at: [(80, 45)])
        let sound = try await ExportProbe.samples(of: result.url)
        // The edited video, in seconds: 0-1 second 0, 1-1.5 second 1, 1.5-2 second 4 (its second half), 2-3 second 5.
        let edges: [(at: Double, before: Int, after: Int)] = [(1, 0, 1), (1.5, 1, 4), (2, 4, 5)]
        for edge in edges {
            let before = try #require(frames.first { abs($0.time - (edge.at - 1.0 / 30)) < 0.002 })
            let after = try #require(frames.first { abs($0.time - edge.at) < 0.002 })
            let grey = { (second: Int) in Int(RecordingCompositionTests.level(of: second)) }
            #expect(abs(Int(before.pixels[0].g) - grey(edge.before)) <= 12, "before \(edge.at): \(before.pixels[0].g)")
            #expect(abs(Int(after.pixels[0].g) - grey(edge.after)) <= 12, "after \(edge.at): \(after.pixels[0].g)")
            for (from, to, second) in [(edge.at - 0.17, edge.at - 0.06, edge.before), (edge.at + 0.06, edge.at + 0.17, edge.after)] {
                let expected = RecordingCompositionTests.loudness(of: second) / 2.0.squareRoot()
                let measured = CompositionProbe.rms(sound, from: from, to: to)
                #expect(abs(measured - expected) < expected * 0.25 + 0.01, "\(from)-\(to): \(measured), wanted about \(expected) (second \(second))")
            }
        }
        #expect(abs(Double(sound.count) / 48_000 - 3) < 0.15)
    }

    @Test func aRecordingWithoutSoundHasNoAudioTrack() async throws {
        let recording = try await RecordingCompositionTests.sample(parts: [.init(seconds: 1)], sound: false)
        let out = try TestFolder("export-out")
        let result = try await export(recording, .chat, into: out)
        let probe = try await MediaProbe.read(result.url)
        #expect(probe.audioDurations.isEmpty)
        #expect(probe.videoFrames > 0)
    }

    @Test func theVoiceAndTheSystemsSoundAreMixedIntoOneTrackWithTheVoiceOnTop() async throws {
        let recording = try await SampleRecording.make(
            parts: [.init(seconds: 1.5)], picture: { _ in PixelBuffers.solid(width: 160, height: 90, grey: 90) },
            amplitude: { _ in 0.3 }, systemAmplitude: { _ in 0.3 }
        )
        #expect(recording.project.hasMicrophone && recording.project.hasSystemAudio)
        let out = try TestFolder("export-out")
        let result = try await export(recording, .chat, into: out)

        let probe = try await MediaProbe.read(result.url)
        #expect(probe.audioDurations.count == 1, "one track for both sources")
        let sound = Array(try await ExportProbe.samples(of: result.url).dropFirst(24_000).prefix(36_000))
        let voice = Self.strength(of: 440, in: sound), system = Self.strength(of: 880, in: sound)
        // Both are there, at the same level in the sources: the system's is the quieter by the mix's 0.6.
        #expect(voice > 0.1 && system > 0.05, "voice \(voice), system \(system)")
        #expect(abs(system / voice - 0.6) < 0.12, "system \(system) against voice \(voice)")
    }

    /// The size of the sine at `frequency` in `samples` (48 kHz): a Goertzel filter, which sees one frequency only.
    static func strength(of frequency: Double, in samples: [Float]) -> Double {
        let coefficient = 2 * cos(2 * .pi * frequency / 48_000)
        var previous = 0.0, beforeThat = 0.0
        for sample in samples {
            let next = Double(sample) + coefficient * previous - beforeThat
            beforeThat = previous
            previous = next
        }
        let power = previous * previous + beforeThat * beforeThat - coefficient * previous * beforeThat
        return 2 * power.squareRoot() / Double(samples.count)
    }

    @Test func theSoundOfSeveralSourcesIsMixedWithTheVoiceOnTop() {
        #expect(RecordingExporter.volumes(for: [.microphone]) == [1])
        #expect(RecordingExporter.volumes(for: [.system]) == [1])
        #expect(RecordingExporter.volumes(for: [.microphone, .system]) == [1, 0.6])
        #expect(RecordingExporter.volumes(for: []).isEmpty)
    }

    // MARK: What the export applies

    @Test func theExportHasTheZoomAndTheCutsOfThePreview() async throws {
        // Dark on the left, light on the right. A zoom on the right edge, from 0 s to 2.5 s, shows only light at the left of the
        // output once the camera has settled.
        let width = 160, height = 90
        var recording = try await SampleRecording.make(
            parts: [.init(seconds: 3)], width: width, height: height,
            picture: { _ in PixelBuffers.make(width: width, height: height) { x, _ in x < width / 2 ? (30, 30, 30) : (230, 230, 230) } }
        )
        recording.project.zoomSegments = [ZoomSegment(start: 0, end: 2.5, scale: 2, focus: [.init(t: 0, x: 150, y: 45)])]
        let out = try TestFolder("export-out")
        let result = try await export(recording, .chat, into: out)

        let frames = try await ExportProbe.frames(of: result.url, at: [(10, 45)])
        let early = try #require(frames.first { $0.time >= 0 })
        let settled = try #require(frames.first { $0.time >= 1.5 })
        #expect(early.pixels[0].g < 100, "before the zoom: \(early.pixels[0].g)")
        #expect(settled.pixels[0].g > 170, "zoomed on the light side: \(settled.pixels[0].g)")
    }

    // MARK: The file

    @Test func progressGoesUpFromNothingToOneAndNeverBack() async throws {
        let recording = try await BigSample.make(width: 320, height: 180, seconds: 2, frameInterval: 0.1)
        let out = try TestFolder("export-out")
        let seen = Locked<[Double]>([])
        _ = try await export(recording, .chat, into: out) { fraction in seen.mutate { $0.append(fraction) } }

        let values = seen.value
        #expect(values.count >= 5)
        #expect(values.last == 1)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(values.allSatisfy { (0...1).contains($0) })
    }

    @Test func cancellingMidwayThrowsCancelledAndLeavesNoFileAtAll() async throws {
        let recording = try await BigSample.make(width: 640, height: 360, seconds: 3, frameInterval: 1.0 / 30, noisy: true)
        let out = try TestFolder("export-out")
        let box = TaskBox()
        let last = Locked(0.0)
        let task = Task { @MainActor in
            try await RecordingExporter.export(
                project: recording.project, folder: recording.folder.url, activity: recording.activity, level: .chat, into: out.url,
                progress: { fraction in
                    last.mutate { $0 = fraction }
                    // Deterministic: it is the export's own report, a tenth of the way in, that cancels.
                    if fraction >= 0.1 { box.cancel() }
                }
            )
        }
        box.task = task
        let outcome = await task.result
        guard case .failure(let error) = outcome else { Issue.record("the export finished"); return }
        #expect(error as? RecordingExportError == .cancelled)
        #expect(last.value < 1)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: out.url.path(percentEncoded: false))
        #expect(leftovers.isEmpty, "left behind: \(leftovers)")
    }

    @Test func aTaskCancelledBeforeItStartsGivesNothing() async throws {
        let recording = try await BigSample.make(width: 320, height: 180, seconds: 1, frameInterval: 0.1)
        let out = try TestFolder("export-out")
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await RecordingExporter.export(
                project: recording.project, folder: recording.folder.url, activity: recording.activity, level: .chat, into: out.url
            )
        }
        let outcome = await task.result
        guard case .failure(let error) = outcome else { Issue.record("the export finished"); return }
        #expect(error as? RecordingExportError == .cancelled)
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.url.path(percentEncoded: false)).isEmpty)
    }

    @Test func aFolderThatCannotBeMadeIsReportedAndLeavesNothing() async throws {
        let recording = try await BigSample.make(width: 320, height: 180, seconds: 1, frameInterval: 0.1)
        let out = try TestFolder("export-out")
        // A plain file where the folder should go.
        let blocker = out.file("blocker")
        try Data("x".utf8).write(to: blocker)
        do {
            _ = try await RecordingExporter.export(
                project: recording.project, folder: recording.folder.url, activity: recording.activity, level: .chat,
                into: blocker.appending(path: "Movies")
            )
            Issue.record("the export finished")
        } catch let error as RecordingExportError {
            guard case .cannotWrite = error else { Issue.record("wrong error \(error)"); return }
            #expect(error.message.contains("Movies"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.url.path(percentEncoded: false)) == ["blocker"])
    }

    @Test func aRecordingWithNothingLeftIsReportedAsSuchAndLeavesNothing() async throws {
        var recording = try await BigSample.make(width: 320, height: 180, seconds: 1, frameInterval: 0.1)
        recording.project.cuts = [CutRange(start: 0, end: 1)]
        let out = try TestFolder("export-out")
        do {
            _ = try await export(recording, .chat, into: out)
            Issue.record("the export finished")
        } catch let error as RecordingExportError {
            #expect(error == .composition(.nothingLeft))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.url.path(percentEncoded: false)).isEmpty)
    }

    @Test func aFileThatIsAlreadyThereIsNeverReplaced() async throws {
        let recording = try await BigSample.make(width: 320, height: 180, seconds: 1, frameInterval: 0.1)
        let out = try TestFolder("export-out")
        let first = try await export(recording, .chat, into: out)
        let firstBytes = try Data(contentsOf: first.url)
        let second = try await export(recording, .chat, into: out)
        let third = try await export(recording, .chat, into: out)

        #expect(second.url != first.url && third.url != first.url && third.url != second.url)
        #expect(second.url.lastPathComponent == first.url.deletingPathExtension().lastPathComponent + " 2.mp4")
        #expect(third.url.lastPathComponent == first.url.deletingPathExtension().lastPathComponent + " 3.mp4")
        #expect(try Data(contentsOf: first.url) == firstBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.url.path(percentEncoded: false)).count == 3)
    }

    @Test func anExportThatWasKilledHalfwayIsClearedAwayLaterButNothingElseIs() throws {
        let out = try TestFolder("export-out")
        let manager = FileManager.default
        let now = Date()
        let old = now.addingTimeInterval(-7_200)
        func work(_ name: String, touched: Date) throws {
            let folder = out.file(name)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 1_000).write(to: folder.appending(path: "export.mp4"))
            try manager.setAttributes([.modificationDate: touched], ofItemAtPath: folder.appending(path: "export.mp4").path(percentEncoded: false))
            try manager.setAttributes([.modificationDate: touched], ofItemAtPath: folder.path(percentEncoded: false))
        }
        try work(".MyNotch-export-OLD", touched: old)
        try work(".MyNotch-export-RUNNING", touched: old)
        // The folder's own date is old, but the file in it is being written now: an export in progress.
        try manager.setAttributes([.modificationDate: now], ofItemAtPath: out.file(".MyNotch-export-RUNNING/export.mp4").path(percentEncoded: false))
        try work(".MyNotch-export-NEW", touched: now)
        try work("Something else", touched: old)
        try Data("x".utf8).write(to: out.file("Bản quay MyNotch 2026-10-18 10.00.00.mp4"))

        RecordingExporter.removeAbandonedWork(in: out.url, now: now)

        let left = Set(try manager.contentsOfDirectory(atPath: out.url.path(percentEncoded: false)))
        #expect(left == [".MyNotch-export-RUNNING", ".MyNotch-export-NEW", "Something else", "Bản quay MyNotch 2026-10-18 10.00.00.mp4"])
    }

    @Test func theFileIsNamedAfterWhenTheRecordingWasMade() async throws {
        var recording = try await BigSample.make(width: 160, height: 90, seconds: 0.2, frameInterval: 0.1)
        recording.project.createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(
            RecordingExporter.fileName(for: recording.project, timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!)
                == "Bản quay MyNotch 2027-01-15 15.00.00.mp4"
        )
    }

    @Test func theDefaultFolderIsMyNotchInMovies() {
        #expect(RecordingExporter.defaultDirectory.lastPathComponent == "MyNotch")
        #expect(RecordingExporter.defaultDirectory.deletingLastPathComponent().lastPathComponent == "Movies")
    }

    static func hasPartialFile(in folder: TestFolder) async throws -> Bool {
        try FileManager.default.contentsOfDirectory(atPath: folder.url.path(percentEncoded: false)).contains { $0.hasSuffix(".partial") }
    }
}

/// A task a callback running on another thread may cancel.
nonisolated final class TaskBox: @unchecked Sendable {
    var task: Task<RecordingExportResult, any Error>?
    func cancel() { task?.cancel() }
}

/// A value a background callback writes and the test reads afterwards.
nonisolated final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func mutate(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
}
