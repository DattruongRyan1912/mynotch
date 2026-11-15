import Observation

/// What the tray shows, kept apart from `CaptureStore` (which is not observable) and updated by the module.
@Observable
final class ScreenshotState {
    /// Newest first.
    var records: [CaptureRecord] = []
    /// Where a recording is, for the tab, the notch and the menu.
    var recordingPhase = RecordingPhase.idle
    /// The recordings on disk, newest first.
    var recordings: [RecordingSummary] = []
    /// Whether the microphone is active for recordings.
    var isMicrophoneEnabled = true
    /// Whether a scrolling capture session is currently active.
    var isScrollingCaptureActive = false
    /// Current total stitched height of the active scrolling capture session.
    var scrollingCaptureHeight = 0
}
