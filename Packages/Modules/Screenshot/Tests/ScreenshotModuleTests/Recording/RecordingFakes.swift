import AVFoundation
import CoreMedia
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ScreenshotModule

/// A source that delivers what a test gives it, from a background queue as the real stream does, and never touches the screen
/// or a microphone.
final class FakeRecordingSource: RecordingSource {
    var captureClockOffset: TimeInterval = 0
    var startError: RecordingError?
    private(set) var configurations: [RecordingSourceConfiguration] = []
    private(set) var stopCount = 0
    private var sink: (any RecordingSampleSink)?
    private let queue = DispatchQueue(label: "FakeRecordingSource")

    func start(_ configuration: RecordingSourceConfiguration, sink: any RecordingSampleSink) async throws(RecordingError) {
        configurations.append(configuration)
        if let startError { throw startError }
        self.sink = sink
    }

    func stop() async {
        stopCount += 1
        // Whatever was already on its way arrives; nothing does afterwards.
        await settle()
        sink = nil
    }

    var isRunning: Bool { sink != nil }

    func deliver(_ frame: VideoFrameBuffer, at time: TimeInterval) {
        guard let sink else { return }
        let frame = VideoFrame(pixelBuffer: frame.pixelBuffer, time: RecordingMediaFactory.time(time))
        queue.async { sink.receive(frame) }
    }

    func deliver(_ sample: CMSampleBuffer, kind: AudioTrackKind) {
        guard let sink else { return }
        let audio = AudioSample(buffer: sample, kind: kind)
        queue.async { sink.receive(audio) }
    }

    /// The stream ends on its own.
    func end(with error: RecordingError?) {
        guard let sink else { return }
        queue.async { sink.sourceStopped(error) }
    }

    func settle() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
}

/// Events a test gives, in place of the system's monitors.
final class FakeActivityEvents: ActivityEventSource {
    private(set) var sink: (any ActivityEventSink)?
    private(set) var includesKeys: Bool?
    private(set) var stopCount = 0

    func start(sink: any ActivityEventSink, includesKeys: Bool) {
        self.sink = sink
        self.includesKeys = includesKeys
    }

    func stop() {
        stopCount += 1
        sink = nil
    }

    func move(to point: CGPoint) { sink?.pointerMoved(toAppKit: point) }
    func click(_ button: ClickButton = .left, at point: CGPoint) { sink?.click(button, atAppKit: point) }
    func key() { sink?.keyPressed() }
}

/// A recording session wired to fakes, with a display of 128×72 points (scale 1) so frames are small. Time is the test's clock,
/// and a frame is stamped with the moment the test says it is.
@MainActor final class RecordingFixture {
    static let width = 128, height = 72
    static let display = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: width, height: height), scale: 1)

    let folder: TestFolder
    let source = FakeRecordingSource()
    let events = FakeActivityEvents()
    let permissions = FakePermissionCenter()
    let scheduler = ManualScheduler()
    let clock = TestClock(1000)
    let store: RecordingStore
    let session: RecordingSession
    let region: RecordingRegion
    private var frameIndex = 0

    init(fragmentInterval: TimeInterval = 2) throws {
        folder = try TestFolder("session")
        store = RecordingStore(root: folder.file("Recordings"))
        permissions.statuses = [.screenRecording: .granted, .microphone: .granted, .accessibility: .granted]
        region = try #require(RecordingRegion(fullScreen: Self.display))
        session = RecordingSession(
            source: source, events: events, permissions: permissions, store: store, scheduler: scheduler, clock: clock.closure,
            engineOptions: .init(fragmentInterval: fragmentInterval, requireHardwareEncoder: true, backpressure: .wait)
        )
    }

    var recordingFolders: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: store.root, includingPropertiesForKeys: nil)) ?? []).filter { UUID(uuidString: $0.lastPathComponent) != nil }
    }

    /// `seconds` of frames at `fps`, with the microphone's sound for the same stretch, the clock moving with them.
    func play(_ seconds: Double, fps: Int = 30, microphone: Bool = true) async {
        for _ in 0..<Int((seconds * Double(fps)).rounded()) {
            let time = clock.now + source.captureClockOffset
            source.deliver(RecordingMediaFactory.frame(width: Self.width, height: Self.height, index: frameIndex), at: time)
            if microphone {
                source.deliver(RecordingMediaFactory.audio(start: time, frames: 48_000 / fps, channels: 1), kind: .microphone)
            }
            frameIndex += 1
            clock.advance(by: 1 / Double(fps))
        }
        await settle()
    }

    /// One frame, then `seconds` of a screen that never changes while the microphone speaks and the timer ticks.
    func playStill(_ seconds: Double) async {
        source.deliver(RecordingMediaFactory.frame(width: Self.width, height: Self.height), at: clock.now + source.captureClockOffset)
        await settle()
        for _ in 0..<Int((seconds * 2).rounded()) {
            let start = clock.now + source.captureClockOffset
            for chunk in 0..<15 {
                source.deliver(RecordingMediaFactory.audio(start: start + Double(chunk) / 30, frames: 1_600, channels: 1), kind: .microphone)
            }
            clock.advance(by: 0.5)
            scheduler.advance(by: .milliseconds(500))
            await settle()
        }
    }

    func settle() async {
        await source.settle()
        await session.settle()
    }
}
