import CoreGraphics

/// One display at capture time, in the coordinates the selection overlay works in.
nonisolated struct DisplayInfo: Equatable, Sendable, Codable {
    var id: CGDirectDisplayID
    /// AppKit global points: origin at the bottom-left of the primary display, y grows upwards.
    var frame: CGRect
    /// Pixels per point of the display's frozen image.
    var scale: CGFloat
}
