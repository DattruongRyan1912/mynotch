import CoreGraphics

/// One markup shape. Coordinates and sizes are in the capture's pixel space (origin top-left, y down),
/// so a document renders identically whatever size the editor window had. The origin is the capture's own
/// top-left corner: a shape may sit at a negative coordinate or past the right and bottom edges, which grows the canvas.
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
    /// A numbered badge. The number is kept in step with the badges before it: see `StepBadges`.
    case step(number: Int, at: CGPoint, radius: CGFloat, color: RGBAColor)
    /// A circle showing the pixels under it, `zoom` times larger, taken when the document is flattened.
    case magnifier(center: CGPoint, radius: CGFloat, zoom: CGFloat, style: StrokeStyle)
    /// A measured line. `scale` is the capture's pixels per point, which decides whether the label also gives points.
    case ruler(from: CGPoint, to: CGPoint, style: StrokeStyle, fontSize: CGFloat, scale: CGFloat)
    /// Filled with the colour around it when flattened, or pixelated when that surround is not one colour.
    case erase(CGRect)
}

/// The annotations of one capture, kept as JSON next to the original so it can be edited again.
nonisolated struct MarkupDocument: Codable, Equatable, Sendable {
    /// The pixel size the annotations were drawn on: the capture itself, without any padding.
    var imageSize: CGSize
    /// In drawing order: later annotations cover earlier ones.
    var annotations: [Annotation] = []
    /// What the canvas's padding is filled with. It follows the Settings choice at the time of editing and is not
    /// saved with the annotations, so changing the setting also restyles captures that are edited again.
    var canvasFill: CanvasFill = .standard

    private enum CodingKeys: String, CodingKey {
        case imageSize, annotations
    }
}

nonisolated extension MarkupDocument {
    /// How far the canvas reaches past the capture: just enough to hold every annotation that sticks out. Derived
    /// from the annotations, so removing or undoing the one that grew it shrinks the canvas back.
    var canvas: CanvasInsets {
        annotations.reduce(.zero) { insets, annotation in
            annotation.extent(beyond: imageSize).map { insets.growing(toContain: $0, imageSize: imageSize) } ?? insets
        }
    }
}
