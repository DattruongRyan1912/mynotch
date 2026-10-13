import CoreGraphics

/// Shows the frozen screens and returns what the user picks. A protocol so the module's tests need no panels.
protocol SelectionOverlay: AnyObject {
    /// nil when the user cancelled or `cancel()` was called. Frozen images are released once this returns.
    func run(mode: SelectionMode, frozen: [FrozenDisplay], windows: [CapturableWindow]) async -> CaptureResult?

    /// Closes the overlay if it is up, making `run` return nil.
    func cancel()
}
