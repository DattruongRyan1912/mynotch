import CoreMedia
import CoreVideo
import Dispatch
import Foundation
import Synchronization

/// Writes what a source delivers into the segment files of one recording.
///
/// A source calls it from its own threads, many times a second, so everything runs on one serial queue the engine owns; the
/// main actor is never involved and nothing here is shared with it except `timeline`. A pause closes the segment being
/// written and the next resume opens a new one, so the video has no hole where the pause was.
actor RecordingEngine: RecordingSampleSink {
    struct Options: Sendable {
        var fragmentInterval: TimeInterval = 2
        var requireHardwareEncoder = true
        var backpressure: WriterBackpressure = .drop
    }

    /// Something happened that the session has to act on.
    enum Event: Sendable {
        /// Writing failed, for example because the disk is full. What was written stays.
        case failed(RecordingError)
        /// The source ended on its own.
        case sourceStopped(RecordingError?)
    }

    struct ClosedSegment: Equatable, Sendable {
        var fileName: String
        var summary: SegmentWriter.Summary
    }

    private enum Phase {
        case idle
        case running(SegmentWriter)
        case closing
        case paused
        case failed
        case ended
    }

    private nonisolated let queue = DispatchSerialQueue(label: "io.lucasvu.mynotch.recording", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let folder: URL
    private let region: RecordingRegion
    private let fps: Int
    private let audioKinds: [AudioTrackKind]
    private let options: Options
    private let onEvent: @Sendable (Event) -> Void
    private var phase: Phase = .idle
    private var nextIndex = 1
    private var lastFrame: CVPixelBuffer?
    private var openStartPublished = false
    private(set) var closed: [ClosedSegment] = []
    private nonisolated let published = Mutex<[RecordingTimeline.Segment]>([])

    /// `audio` is the tracks every segment carries besides the picture.
    init(
        folder: URL, region: RecordingRegion, fps: Int, audio: [AudioTrackKind], options: Options = Options(),
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.folder = folder
        self.region = region
        self.fps = fps
        audioKinds = audio
        self.options = options
        self.onEvent = onEvent
    }

    /// Where each segment so far sits on the capture clock; the last one has no duration while it is still being written.
    nonisolated var timeline: RecordingTimeline { RecordingTimeline(segments: published.withLock { $0 }) }

    // MARK: Control

    /// Opens the first segment. Nothing is recorded until a frame arrives.
    func begin() throws(RecordingError) {
        guard case .idle = phase else { return }
        phase = .running(try openSegment())
    }

    /// Closes the segment being written, ending its video at `end` on the capture clock. Returns it, or nil when it never got a
    /// frame (its file is removed) or could not be closed.
    func pause(at end: TimeInterval) async -> ClosedSegment? {
        guard case .running(let writer) = phase else { return nil }
        let segment = await close(writer, end: end)
        if case .closing = phase { phase = .paused }
        return segment
    }

    /// Opens the next segment. The picture the pause left on screen is written first, so the segment starts now and the
    /// sound is not lost while the screen stays as it is.
    func resume(at now: TimeInterval) throws(RecordingError) {
        guard case .paused = phase else { return }
        let writer = try openSegment()
        phase = .running(writer)
        if let lastFrame, writer.appendVideo(lastFrame, at: CMTime(seconds: now, preferredTimescale: 1_000_000_000)) {
            publishStart(of: writer)
        }
    }

    /// Closes the segment being written, if any, and returns every segment that was written.
    func finish(at end: TimeInterval) async -> [ClosedSegment] {
        if case .running(let writer) = phase {
            _ = await close(writer, end: end)
        }
        if case .failed = phase {} else { phase = .ended }
        return closed
    }

    /// Throws away the segment being written: for a recording that could not start.
    func abort() {
        if case .running(let writer) = phase { writer.cancel() }
        phase = .ended
        published.withLock { $0.removeAll() }
    }

    /// Keeps the files flowing while nothing happens: see `SegmentWriter.keepAudioFlowing` and `repeatLastFrame`.
    func tick(at now: TimeInterval) {
        guard case .running(let writer) = phase, writer.start != nil else { return }
        writer.keepAudioFlowing(upTo: now)
        writer.repeatLastFrame(at: now, after: 0.5)
        checkFailure(of: writer)
    }

    /// Returns once everything the sources delivered before this call has been handled.
    func drain() {}

    // MARK: Samples

    nonisolated func receive(_ frame: VideoFrame) {
        queue.async { self.assumeIsolated { $0.handle(frame) } }
    }

    nonisolated func receive(_ audio: AudioSample) {
        queue.async { self.assumeIsolated { $0.handle(audio) } }
    }

    nonisolated func sourceStopped(_ error: RecordingError?) {
        queue.async { self.assumeIsolated { $0.onEvent(.sourceStopped(error)) } }
    }

    private func handle(_ frame: VideoFrame) {
        guard case .running(let writer) = phase else { return }
        if writer.appendVideo(frame.pixelBuffer, at: frame.time) {
            publishStart(of: writer)
        } else {
            checkFailure(of: writer)
        }
    }

    private func handle(_ audio: AudioSample) {
        guard case .running(let writer) = phase else { return }
        if !writer.appendAudio(audio.buffer, kind: audio.kind) { checkFailure(of: writer) }
    }

    // MARK: Segments

    private func openSegment() throws(RecordingError) -> SegmentWriter {
        let name = String(format: "segment-%03d.mov", nextIndex)
        let writer = try SegmentWriter(
            url: folder.appending(path: name), width: region.pixelWidth, height: region.pixelHeight, fps: fps, audio: audioKinds,
            fragmentInterval: options.fragmentInterval, requireHardwareEncoder: options.requireHardwareEncoder,
            backpressure: options.backpressure
        )
        nextIndex += 1
        openStartPublished = false
        return writer
    }

    /// The segment's start is the stamp of its first frame, known only once that frame is written.
    private func publishStart(of writer: SegmentWriter) {
        guard !openStartPublished, let start = writer.start else { return }
        openStartPublished = true
        published.withLock { $0.append(.init(start: start, duration: nil)) }
    }

    private func close(_ writer: SegmentWriter, end: TimeInterval) async -> ClosedSegment? {
        phase = .closing
        lastFrame = writer.lastFrame ?? lastFrame
        guard writer.start != nil else {
            writer.cancel()
            return nil
        }
        let result: Result<SegmentWriter.Summary, RecordingError> = await withCheckedContinuation { continuation in
            writer.finish(endingAt: end) { continuation.resume(returning: $0) }
        }
        switch result {
        case .success(let summary):
            published.withLock { segments in
                if !segments.isEmpty { segments[segments.count - 1].duration = summary.duration }
            }
            let segment = ClosedSegment(fileName: writer.url.lastPathComponent, summary: summary)
            closed.append(segment)
            return segment
        case .failure(let error):
            phase = .failed
            onEvent(.failed(error))
            return nil
        }
    }

    private func checkFailure(of writer: SegmentWriter) {
        guard let error = writer.failure else { return }
        // The file stays as far as it got: it is written in fragments, and the rescue opens it.
        phase = .failed
        onEvent(.failed(error))
    }
}
