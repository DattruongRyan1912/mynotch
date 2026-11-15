import AVFoundation
import CoreMedia
import CoreVideo

/// What happens to a frame or buffer the encoder cannot take yet.
nonisolated enum WriterBackpressure: Sendable {
    /// Recording: the capture does not wait, the sample is dropped and counted.
    case drop
    /// Tests: wait for the encoder, so a run keeps every frame it was given.
    case wait
}

/// One file of a recording: a QuickTime movie with an HEVC video track and, for each audio source asked for, an AAC track.
/// The first video frame starts the file; nothing earlier is kept. Only the engine's queue may call it.
///
/// The movie is written in fragments, a new one every `fragmentInterval`: a recording cut short by a crash or a power loss can
/// be opened up to the last fragment. A finished file is an ordinary movie.
nonisolated final class SegmentWriter {
    struct Summary: Equatable {
        var frames: Int
        var droppedFrames: Int
        var droppedAudio: Int
        /// On the capture clock.
        var start: TimeInterval
        var duration: TimeInterval
    }

    /// A track that has had nothing for this long is fed silence, so the writer can keep writing (see `keepAudioFlowing`).
    static let audioGap: TimeInterval = 0.5

    private struct AudioTrack {
        let input: AVAssetWriterInput
        let normalizer: AudioNormalizer
        /// On the capture clock, where what was written so far ends.
        var end: TimeInterval
    }

    let url: URL
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var audio: [AudioTrackKind: AudioTrack] = [:]
    private let backpressure: WriterBackpressure
    /// The stamp of the first frame, once there is one.
    private(set) var start: TimeInterval?
    private(set) var lastVideoTime: TimeInterval = 0
    /// The last frame written, kept to repeat on a screen that does not change.
    private(set) var lastFrame: CVPixelBuffer?
    private(set) var frames = 0
    private(set) var droppedFrames = 0
    private(set) var droppedAudio = 0

    /// Opens the file. Nothing is on disk before this, and nothing is recorded before the first frame.
    init(
        url: URL, width: Int, height: Int, fps: Int, audio kinds: [AudioTrackKind], fragmentInterval: TimeInterval = 2,
        requireHardwareEncoder: Bool = true, backpressure: WriterBackpressure = .drop
    ) throws(RecordingError) {
        self.url = url
        self.backpressure = backpressure
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw .writerFailed(error.localizedDescription)
        }
        writer.movieFragmentInterval = CMTime(seconds: fragmentInterval, preferredTimescale: 600)
        let settings = RecordingMedia.videoSettings(width: width, height: height, fps: fps, requireHardware: requireHardwareEncoder)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw .encoderUnavailable("\(width)×\(height)") }
        writer.add(video)
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
        for kind in kinds {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: RecordingMedia.audioSettings(for: kind))
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw .encoderUnavailable("audio") }
            writer.add(input)
            audio[kind] = AudioTrack(input: input, normalizer: AudioNormalizer(kind: kind), end: 0)
        }
        guard writer.startWriting() else {
            throw .writerFailed(writer.error?.localizedDescription ?? "startWriting")
        }
    }

    /// The error that stopped the writer, if it stopped.
    var failure: RecordingError? {
        guard writer.status == .failed else { return nil }
        // Hardware that refuses the very first frame is an encoder that cannot take this size, not a disk problem.
        let reason = writer.error?.localizedDescription ?? "unknown"
        return frames == 0 ? .encoderUnavailable(reason) : .writerFailed(reason)
    }

    /// Writes a frame stamped `time` on the capture clock. The first one starts the file. Returns false when it was dropped:
    /// older than the last one, or the encoder could not take it.
    @discardableResult
    func appendVideo(_ buffer: CVPixelBuffer, at time: CMTime) -> Bool {
        let seconds = time.seconds
        if start == nil {
            writer.startSession(atSourceTime: time)
            start = seconds
            for kind in audio.keys { audio[kind]?.end = seconds }
        } else if seconds <= lastVideoTime {
            return false
        }
        guard waitUntilReady(video), adaptor.append(buffer, withPresentationTime: time) else {
            droppedFrames += 1
            return false
        }
        lastVideoTime = seconds
        lastFrame = buffer
        frames += 1
        keepAudioFlowing(upTo: seconds)
        return true
    }

    /// Writes what the microphone or the system delivered. Nothing before the first frame is kept, so the sound starts with the
    /// picture; a buffer that overlaps what is already written (after silence filled its place) is dropped.
    @discardableResult
    func appendAudio(_ sample: CMSampleBuffer, kind: AudioTrackKind) -> Bool {
        guard let start, var track = audio[kind] else { return false }
        let first = sample.presentationTimeStamp.seconds
        guard first + sample.duration.seconds > start else { return false }
        guard first >= track.end - 0.005, let converted = track.normalizer.normalized(sample) else {
            droppedAudio += 1
            return false
        }
        guard waitUntilReady(track.input), track.input.append(converted) else {
            droppedAudio += 1
            return false
        }
        track.end = converted.presentationTimeStamp.seconds + converted.duration.seconds
        audio[kind] = track
        return true
    }

    /// The writer lays the tracks out together: it holds the video back until the audio has caught up, and the other way
    /// round. A track with nothing coming (a silent system, a muted device) would hold everything in memory, and a crash would
    /// lose it all. So a track that is behind by more than `audioGap` gets silence up to `time`.
    func keepAudioFlowing(upTo time: TimeInterval, gap minimum: TimeInterval = SegmentWriter.audioGap) {
        guard start != nil else { return }
        for (kind, var track) in audio where time - track.end > minimum {
            let gap = time - track.end
            guard let silence = track.normalizer.silence(from: CMTime(seconds: track.end, preferredTimescale: 1_000_000_000), seconds: gap),
                  waitUntilReady(track.input), track.input.append(silence) else { continue }
            track.end += gap
            audio[kind] = track
        }
    }

    /// A screen that does not change sends no frames, and a file with sound but no new picture is held back the same way. So
    /// the last frame is written again when none came for `interval`.
    func repeatLastFrame(at time: TimeInterval, after interval: TimeInterval) {
        guard start != nil, let lastFrame, time - lastVideoTime >= interval else { return }
        appendVideo(lastFrame, at: CMTime(seconds: time, preferredTimescale: 1_000_000_000))
    }

    /// Closes the file with the video ending at `end` (the capture clock), so the last frame lasts until the moment the
    /// recording stopped and not for one frame. Calls `completion` on any thread when the file is complete.
    func finish(endingAt end: TimeInterval, completion: @escaping @Sendable (Result<Summary, RecordingError>) -> Void) {
        guard let start else {
            cancel()
            completion(.failure(.nothingRecorded))
            return
        }
        let endTime = max(end, lastVideoTime)
        // Each track ends with the picture, not up to half a second short of it.
        keepAudioFlowing(upTo: endTime, gap: 0.02)
        video.markAsFinished()
        for track in audio.values { track.input.markAsFinished() }
        writer.endSession(atSourceTime: CMTime(seconds: endTime, preferredTimescale: 1_000_000_000))
        let summary = Summary(frames: frames, droppedFrames: droppedFrames, droppedAudio: droppedAudio, start: start, duration: endTime - start)
        nonisolated(unsafe) let writer = writer
        writer.finishWriting {
            if writer.status == .completed {
                completion(.success(summary))
            } else {
                completion(.failure(.writerFailed(writer.error?.localizedDescription ?? "finishWriting")))
            }
        }
    }

    /// Stops writing and removes the file.
    func cancel() {
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: url)
    }

    private func waitUntilReady(_ input: AVAssetWriterInput) -> Bool {
        if input.isReadyForMoreMediaData { return true }
        guard backpressure == .wait else { return false }
        let deadline = ContinuousClock.now + .seconds(5)
        while !input.isReadyForMoreMediaData, writer.status == .writing, ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        return input.isReadyForMoreMediaData
    }
}
