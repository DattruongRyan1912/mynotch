import CoreGraphics

/// The editor's drawing tools, in toolbar order.
nonisolated enum MarkupTool: CaseIterable, Sendable {
    case arrow, rectangle, text, highlighter, redact

    var title: String {
        switch self {
        case .arrow: "Mũi tên"
        case .rectangle: "Hình chữ nhật"
        case .text: "Chữ"
        case .highlighter: "Bút dạ quang"
        case .redact: "Che vùng"
        }
    }

    var systemImage: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .text: "textformat"
        case .highlighter: "highlighter"
        case .redact: "checkerboard.rectangle"
        }
    }

    /// The shape a drag through `points` (image pixels, first = where it started) draws, or nil for the text tool
    /// and for drags shorter than 3 view points, which are clicks rather than shapes.
    func annotation(through points: [CGPoint], color: RGBAColor, thickness: StrokeThickness, pixelsPerPoint: CGFloat) -> Annotation? {
        guard let start = points.first, let end = points.last else { return nil }
        let minimum = 3 * pixelsPerPoint
        let bounds = points.dropFirst().reduce(CGRect(origin: start, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        let style = Annotation.StrokeStyle(color: color, width: thickness.lineWidth * pixelsPerPoint)
        switch self {
        case .arrow:
            return hypot(end.x - start.x, end.y - start.y) >= minimum ? .arrow(from: start, to: end, style: style) : nil
        case .rectangle:
            return min(bounds.width, bounds.height) >= minimum ? .rectangle(bounds, style: style) : nil
        case .redact:
            return min(bounds.width, bounds.height) >= minimum ? .redact(bounds) : nil
        case .highlighter:
            let width = thickness.highlighterWidth * pixelsPerPoint
            // Half transparent, so dark text under the multiply blend stays readable.
            let ink = RGBAColor(r: color.r, g: color.g, b: color.b, a: color.a * 0.5)
            return max(bounds.width, bounds.height) >= minimum ? .highlighter(points: points, color: ink, width: width) : nil
        case .text:
            return nil
        }
    }
}

/// "Độ dày nét", in view points so a stroke looks the same on screen whatever the capture's resolution;
/// it also sets the text size.
nonisolated enum StrokeThickness: CaseIterable, Sendable {
    case thin, medium, thick

    var title: String {
        switch self {
        case .thin: "Mảnh"
        case .medium: "Vừa"
        case .thick: "Dày"
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .thin: 2
        case .medium: 4
        case .thick: 8
        }
    }

    var highlighterWidth: CGFloat { lineWidth * 4 }

    var fontSize: CGFloat {
        switch self {
        case .thin: 16
        case .medium: 24
        case .thick: 36
        }
    }
}
