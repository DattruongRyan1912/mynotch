import CoreGraphics

/// The only door to ScreenCaptureKit, so the module and its tests never touch it directly.
protocol CaptureService: AnyObject {
    /// Every display as it is now, without MyNotch's own windows (the notch), in SDR and without the cursor,
    /// at one pixel per point times the display's scale.
    func freezeDisplays() async throws -> [FrozenDisplay]

    /// One window on its own, whatever covers it, with or without its drop shadow.
    func captureWindow(id: CGWindowID, includeShadow: Bool) async throws -> CGImage
}
