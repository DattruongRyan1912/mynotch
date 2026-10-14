import CoreGraphics

/// The editor's drawing tools, in toolbar order.
nonisolated enum MarkupTool: CaseIterable, Sendable {
    case arrow, rectangle, text, highlighter, step, magnifier, ruler, redact, erase

    var title: String {
        switch self {
        case .arrow: "Mũi tên"
        case .rectangle: "Hình chữ nhật"
        case .text: "Chữ"
        case .highlighter: "Bút dạ quang"
        case .step: "Đánh số bước"
        case .magnifier: "Kính lúp"
        case .ruler: "Thước đo"
        case .redact: "Che vùng"
        case .erase: "Xoá thông minh"
        }
    }

    /// The tooltip: the title, plus what is not obvious about the tool.
    var hint: String {
        switch self {
        case .step: "\(title): bấm để thêm số, ⌥-bấm vào một số để xoá"
        case .magnifier: "\(title): kéo từ tâm ra ngoài để phóng to phần ảnh bên dưới"
        case .ruler: "\(title): kéo giữa hai điểm; giữ ⇧ để giữ ngang hoặc dọc"
        case .erase: "\(title): tô vùng chọn bằng màu viền quanh nó; nếu viền không đồng nhất thì làm nhoè (pixel hoá) vùng đó"
        default: title
        }
    }

    var systemImage: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .text: "textformat"
        case .highlighter: "highlighter"
        case .step: "number.circle"
        case .magnifier: "plus.magnifyingglass"
        case .ruler: "ruler"
        case .redact: "checkerboard.rectangle"
        case .erase: "eraser"
        }
    }

    /// Whether the colour and thickness choices apply; redaction and erasing take their look from the pixels.
    var usesStyle: Bool {
        self != .redact && self != .erase
    }

    /// The shape a drag through `points` (image pixels, first = where it started) draws, or nil for the text tool
    /// and for drags shorter than 3 view points, which are clicks rather than shapes. A step badge is the exception:
    /// a click places it, and dragging moves it until the button is released.
    func annotation(through points: [CGPoint], options: DrawingOptions) -> Annotation? {
        guard let start = points.first, let end = points.last else { return nil }
        let pixelsPerPoint = options.pixelsPerPoint
        let minimum = 3 * pixelsPerPoint
        let bounds = points.dropFirst().reduce(CGRect(origin: start, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        let style = Annotation.StrokeStyle(color: options.color, width: options.thickness.lineWidth * pixelsPerPoint)
        switch self {
        case .arrow:
            return hypot(end.x - start.x, end.y - start.y) >= minimum ? .arrow(from: start, to: end, style: style) : nil
        case .rectangle:
            return min(bounds.width, bounds.height) >= minimum ? .rectangle(bounds, style: style) : nil
        case .redact:
            return min(bounds.width, bounds.height) >= minimum ? .redact(bounds) : nil
        case .erase:
            return min(bounds.width, bounds.height) >= minimum ? .erase(bounds) : nil
        case .highlighter:
            let width = options.thickness.highlighterWidth * pixelsPerPoint
            // Half transparent, so dark text under the multiply blend stays readable.
            let ink = RGBAColor(r: options.color.r, g: options.color.g, b: options.color.b, a: options.color.a * 0.5)
            return max(bounds.width, bounds.height) >= minimum ? .highlighter(points: points, color: ink, width: width) : nil
        case .step:
            return .step(number: options.nextStep, at: end, radius: options.thickness.badgeRadius * pixelsPerPoint, color: options.color)
        case .magnifier:
            let radius = hypot(end.x - start.x, end.y - start.y)
            let zoom = min(max(options.magnification, DrawingOptions.magnificationRange.lowerBound), DrawingOptions.magnificationRange.upperBound)
            return radius >= minimum ? .magnifier(center: start, radius: radius, zoom: zoom, style: style) : nil
        case .ruler:
            let tip = options.snapsToAxis ? Ruler.snapped(end, from: start) : end
            guard Ruler.distance(from: start, to: tip) >= minimum else { return nil }
            return .ruler(from: start, to: tip, style: style, fontSize: options.thickness.fontSize * 0.6 * pixelsPerPoint, scale: options.pointScale)
        case .text:
            return nil
        }
    }
}

/// What a drag needs besides the pointer's path.
nonisolated struct DrawingOptions: Sendable {
    var color: RGBAColor
    var thickness: StrokeThickness
    /// Image pixels per view point, which turns the view-sized thickness into pixels.
    var pixelsPerPoint: CGFloat
    /// The capture's pixels per point (2 on a Retina display), which the ruler's label uses to give points.
    var pointScale: CGFloat = 1
    /// The lens's zoom can be anything in this range; a lens is drawn with the nearest value inside it.
    static let magnificationRange: ClosedRange<CGFloat> = 1.5...4

    var magnification: CGFloat = 2
    /// The number the next step badge gets.
    var nextStep = 1
    /// ⇧ is held: the ruler goes along an axis.
    var snapsToAxis = false
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

    /// The step badge's radius, in view points.
    var badgeRadius: CGFloat {
        switch self {
        case .thin: 10
        case .medium: 14
        case .thick: 20
        }
    }
}
