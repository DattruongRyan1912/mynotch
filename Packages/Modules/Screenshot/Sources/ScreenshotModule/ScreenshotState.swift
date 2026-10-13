import Observation

/// What the tray shows, kept apart from `CaptureStore` (which is not observable) and updated by the module.
@Observable
final class ScreenshotState {
    /// Newest first.
    var records: [CaptureRecord] = []
}
