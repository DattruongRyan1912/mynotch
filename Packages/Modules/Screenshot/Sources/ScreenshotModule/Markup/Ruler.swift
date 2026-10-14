import CoreGraphics
import Foundation

/// The measuring tool's maths: distances in the capture's pixels, ⇧ snapping and where the label goes.
nonisolated enum Ruler {
    static func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    /// `end` moved onto the horizontal or vertical line through `start`, whichever the drag follows more closely.
    /// A diagonal exactly halfway goes horizontal, so it does not flicker between axes.
    static func snapped(_ end: CGPoint, from start: CGPoint) -> CGPoint {
        abs(end.x - start.x) >= abs(end.y - start.y) ? CGPoint(x: end.x, y: start.y) : CGPoint(x: start.x, y: end.y)
    }

    /// "240 px", and on a Retina capture "240 px (120 pt)". `scale` is pixels per point; anything not above 1 shows pixels only.
    /// The points come from the pixels as shown, so the two numbers always agree.
    static func label(distance: CGFloat, scale: CGFloat) -> String {
        let pixels = Int(distance.rounded())
        guard scale > 1 else { return "\(pixels) px" }
        let points = (Double(pixels) / Double(scale) * 10).rounded() / 10
        let formatted = points == points.rounded() ? String(Int(points)) : String(format: "%.1f", points)
        return "\(pixels) px (\(formatted) pt)"
    }

    /// Where the parts of a ruler go, shared by drawing and by the canvas growth maths.
    struct Layout {
        /// The two short strokes across the line at each end.
        let ticks: [(CGPoint, CGPoint)]
        let label: String
        /// The label's background; the text is centred in it.
        let labelRect: CGRect
        /// Everything the ruler inks, stroke width included.
        let bounds: CGRect
    }

    /// The label sits beside the middle of the line, above it, or to its right when the line is vertical, whichever
    /// way the line was drawn, so a ruler reads the same from both ends.
    static func layout(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat, fontSize: CGFloat, scale: CGFloat) -> Layout {
        let length = distance(from: start, to: end)
        let label = label(distance: length, scale: scale)
        let textSize = MarkupRenderer.textSize(label, fontSize: fontSize)
        let labelSize = CGSize(width: textSize.width + fontSize, height: fontSize * 1.5)
        let tick = max(lineWidth * 2, 6)

        var normal = length > 0 ? CGPoint(x: (end.y - start.y) / length, y: (start.x - end.x) / length) : CGPoint(x: 0, y: -1)
        if normal.y > 1e-9 || (abs(normal.y) <= 1e-9 && normal.x < 0) { normal = CGPoint(x: -normal.x, y: -normal.y) }
        let reach = abs(normal.x) * labelSize.width / 2 + abs(normal.y) * labelSize.height / 2 + tick + 4
        let center = CGPoint(x: (start.x + end.x) / 2 + normal.x * reach, y: (start.y + end.y) / 2 + normal.y * reach)
        let labelRect = CGRect(x: center.x - labelSize.width / 2, y: center.y - labelSize.height / 2, width: labelSize.width, height: labelSize.height)

        // The ticks run along the normal too, centred on each end; a zero-length line has none, so they are vertical.
        let ticks = [start, end].map {
            (CGPoint(x: $0.x - normal.x * tick, y: $0.y - normal.y * tick), CGPoint(x: $0.x + normal.x * tick, y: $0.y + normal.y * tick))
        }
        let points = ticks.flatMap { [$0.0, $0.1] } + [start, end]
        let bounds = points.dropFirst().reduce(CGRect(origin: points[0], size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
            .insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
            .union(labelRect)
        return Layout(ticks: ticks, label: label, labelRect: labelRect, bounds: bounds)
    }
}
