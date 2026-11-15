import CoreMedia
import CoreVideo

/// One screen frame and the moment it was shown, on the capture clock.
nonisolated struct VideoFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let time: CMTime
}

/// A buffer of sound from one source.
nonisolated struct AudioSample: @unchecked Sendable {
    let buffer: CMSampleBuffer
    let kind: AudioTrackKind
}

/// Where a source delivers what it captures. Called on the source's own threads, never on the main actor.
nonisolated protocol RecordingSampleSink: AnyObject, Sendable {
    func receive(_ frame: VideoFrame)
    func receive(_ audio: AudioSample)
    /// The stream ended without being asked to: the system stopped it, the permission went away, or the display did.
    func sourceStopped(_ error: RecordingError?)
}

nonisolated enum MicrophoneSelection: Equatable, Sendable {
    case systemDefault
    /// By `AVCaptureDevice.uniqueID`.
    case device(String)
}

/// What a recording captures.
nonisolated struct RecordingOptions: Equatable, Sendable {
    /// Nil records no microphone.
    var microphone: MicrophoneSelection? = .systemDefault
    var systemAudio = false
    var fps = 60
}

nonisolated struct RecordingSourceConfiguration: Equatable, Sendable {
    var region: RecordingRegion
    var options: RecordingOptions
}

/// The only door to ScreenCaptureKit for recording, so the session and its tests never touch the screen or the microphone.
protocol RecordingSource: AnyObject {
    /// Seconds to add to the host clock to get the clock the samples are stamped with. Read after `start`.
    var captureClockOffset: TimeInterval { get }
    /// Starts delivering frames and sound to `sink`. Throws `screenRecordingDenied` or `microphoneDenied` when the system refuses.
    func start(_ configuration: RecordingSourceConfiguration, sink: any RecordingSampleSink) async throws(RecordingError)
    /// Stops delivering. Nothing arrives at the sink once this returns.
    func stop() async
}
