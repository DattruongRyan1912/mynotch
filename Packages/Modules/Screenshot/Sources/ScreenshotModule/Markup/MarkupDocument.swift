import CoreGraphics

/// One markup shape. Coordinates and sizes are in the capture's pixel space (origin top-left, y down),
/// so a document renders identically whatever size the editor window had.
nonisolated enum Annotation: Codable, Equatable, Sendable {
    /// Nested so it does not shadow SwiftUI's `StrokeStyle` inside this module.
    struct StrokeStyle: Codable, Equatable, Sendable {
        var color: RGBAColor
        var width: CGFloat
    }

    case arrow(from: CGPoint, to: CGPoint, style: StrokeStyle)
    case rectangle(CGRect, style: StrokeStyle)
    /// `at` is the top-left of the first line.
    case text(String, at: CGPoint, fontSize: CGFloat, color: RGBAColor)
    case highlighter(points: [CGPoint], color: RGBAColor, width: CGFloat)
    /// Pixelated when flattened, hiding whatever was drawn there before.
    case redact(CGRect)
}

/// The annotations of one capture, kept as JSON next to the original so it can be edited again.
nonisolated struct MarkupDocument: Codable, Equatable, Sendable {
    /// The pixel size the annotations were drawn on.
    var imageSize: CGSize
    /// In drawing order: later annotations cover earlier ones.
    var annotations: [Annotation] = []
}
