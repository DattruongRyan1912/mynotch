import AppKit
import ScreenCaptureKit
import Synchronization

/// Records with an `SCStream`: the region of one display at its own pixel size, 60 frames a second with the cursor drawn in,
/// the microphone that was chosen and, when asked, what the system plays. MyNotch's own windows are left out of the picture.
/// Needs Screen Recording; the microphone needs its permission too. Nothing here asks: `RecordingSession` has checked.
final class ScreenCaptureKitSource: RecordingSource {
    private(set) var captureClockOffset: TimeInterval = 0
    private var stream: SCStream?
    private var handler: StreamHandler?

    func start(_ configuration: RecordingSourceConfiguration, sink: any RecordingSampleSink) async throws(RecordingError) {
        do {
            // Off-screen windows count too: MyNotch may have none on screen right now (a hidden notch) and one a moment later.
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == configuration.region.display.id }) else {
                throw RecordingError.noDisplay
            }
            // The whole application, not the windows there are now: the countdown, a toast or the editor that opens next
            // are MyNotch's too, and none of them belongs in the video.
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let handler = StreamHandler(sink: sink)
            let stream = SCStream(filter: filter, configuration: Self.makeConfiguration(for: configuration), delegate: handler)
            try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: handler.queue)
            if configuration.options.microphone != nil {
                try stream.addStreamOutput(handler, type: .microphone, sampleHandlerQueue: handler.queue)
            }
            if configuration.options.systemAudio {
                try stream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: handler.queue)
            }
            try await stream.startCapture()
            self.stream = stream
            self.handler = handler
            captureClockOffset = RecordingClock.offset(of: stream.synchronizationClock)
        } catch {
            throw RecordingError(error)
        }
    }

    func stop() async {
        guard let stream, let handler else { return }
        handler.beginStopping()
        try? await stream.stopCapture()
        self.stream = nil
        self.handler = nil
    }

    /// The stream's settings for a region. Pure, so it is tested without a stream.
    static func makeConfiguration(for configuration: RecordingSourceConfiguration) -> SCStreamConfiguration {
        let region = configuration.region, options = configuration.options
        let stream = SCStreamConfiguration()
        stream.width = region.pixelWidth
        stream.height = region.pixelHeight
        stream.sourceRect = region.sourceRect
        stream.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        // Frames wait in a queue of this many while the encoder works, and the capture stalls when it is full.
        stream.queueDepth = 6
        stream.pixelFormat = kCVPixelFormatType_32BGRA
        stream.colorSpaceName = CGColorSpace.sRGB
        stream.captureDynamicRange = .SDR
        stream.showsCursor = true
        stream.capturesAudio = options.systemAudio
        stream.excludesCurrentProcessAudio = true
        stream.sampleRate = RecordingMedia.sampleRate
        stream.channelCount = 2
        stream.captureMicrophone = options.microphone != nil
        if case .device(let id) = options.microphone { stream.microphoneCaptureDeviceID = id }
        return stream
    }
}

/// Receives the stream's samples on the stream's queue and passes the useful ones on; it never touches the main actor.
private nonisolated final class StreamHandler: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "io.lucasvu.mynotch.recording.stream", qos: .userInteractive)
    private let sink: any RecordingSampleSink
    private let isStopping = Mutex(false)

    init(sink: any RecordingSampleSink) {
        self.sink = sink
    }

    /// A stop asked for is not a reason to tell the sink the stream ended.
    func beginStopping() {
        isStopping.withLock { $0 = true }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            // Only a frame with a picture counts; the stream also reports that nothing changed, with no pixels.
            guard Self.isComplete(sampleBuffer), let pixels = sampleBuffer.imageBuffer else { return }
            sink.receive(VideoFrame(pixelBuffer: pixels, time: sampleBuffer.presentationTimeStamp))
        case .microphone:
            sink.receive(AudioSample(buffer: sampleBuffer, kind: .microphone))
        case .audio:
            sink.receive(AudioSample(buffer: sampleBuffer, kind: .system))
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        guard !isStopping.withLock({ $0 }) else { return }
        sink.sourceStopped(RecordingError(error))
    }

    private static func isComplete(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int else { return false }
        return SCFrameStatus(rawValue: raw) == .complete
    }
}
