import CoreGraphics

nonisolated extension Annotation {
    /// The area this annotation inks when it reaches past the capture's edge, or nil when it stays within it. A shape
    /// whose outline is on or inside the edge counts as inside even though half its stroke sticks out, so a rectangle
    /// dragged right to the edge does not add a sliver of padding. Redaction and erasing work on the pixels that
    /// are already there and never grow the canvas.
    func extent(beyond imageSize: CGSize) -> CGRect? {
        guard let footprint else { return nil }
        let image = CGRect(origin: .zero, size: imageSize).insetBy(dx: -0.5, dy: -0.5)
        return image.contains(footprint.outline) ? nil : footprint.ink
    }

    /// `outline` is the geometry the user placed; `ink` adds the stroke's width and the arrow head.
    private var footprint: (outline: CGRect, ink: CGRect)? {
        switch self {
        case .arrow(let start, let tip, let style):
            let outline = Self.bounds(of: [start, tip])
            return (outline, outline.insetBy(dx: -Self.arrowReach(style.width), dy: -Self.arrowReach(style.width)))
        case .rectangle(let rect, let style):
            return (rect.standardized, rect.standardized.insetBy(dx: -style.width / 2, dy: -style.width / 2))
        case .text(let string, let origin, let fontSize, _):
            let box = CGRect(origin: origin, size: MarkupRenderer.textSize(string, fontSize: fontSize))
            return (box, box)
        case .highlighter(let points, _, let width):
            guard !points.isEmpty else { return nil }
            let outline = Self.bounds(of: points)
            return (outline, outline.insetBy(dx: -width / 2, dy: -width / 2))
        case .step(_, let center, let radius, _):
            let box = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            return (box, box)
        case .magnifier(let center, let radius, _, let style):
            let box = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            return (box, box.insetBy(dx: -style.width / 2, dy: -style.width / 2))
        case .ruler(let start, let end, let style, let fontSize, let scale):
            let layout = Ruler.layout(from: start, to: end, lineWidth: style.width, fontSize: fontSize, scale: scale)
            return (layout.bounds, layout.bounds)
        case .redact, .erase:
            return nil
        }
    }

    /// How far an arrow's head or shaft can reach from the line between its ends: the head is the wider of the two.
    private static func arrowReach(_ width: CGFloat) -> CGFloat {
        max(width / 2, 0.55 * max(width * 4, 10))
    }

    private static func bounds(of points: [CGPoint]) -> CGRect {
        points.dropFirst().reduce(CGRect(origin: points[0], size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
}
