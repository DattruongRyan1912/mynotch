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
}
