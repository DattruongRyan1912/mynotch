import CoreGraphics

/// "Tỉ lệ" of the crop frame: a fixed ratio the frame keeps while it is dragged, or none.
nonisolated enum CropAspect: CaseIterable, Sendable {
    case free, square, fourThree, sixteenNine
    /// The ratio of the capture the editor opened on, before any crop.
    case original

    var title: String {
        switch self {
        case .free: "Tự do"
        case .square: "1:1"
        case .fourThree: "4:3"
        case .sixteenNine: "16:9"
        case .original: "Như ảnh gốc"
        }
    }

    /// Width over height the frame keeps, or nil for any shape. The original's ratio is that of `imageSize`, the capture
    /// without padding or crop.
    func ratio(of imageSize: CGSize) -> CGFloat? {
        switch self {
        case .free: nil
        case .square: 1
        case .fourThree: 4.0 / 3.0
        case .sixteenNine: 16.0 / 9.0
        case .original: imageSize.width > 0 && imageSize.height > 0 ? imageSize.width / imageSize.height : nil
        }
    }
}

/// The eight places a crop frame is resized from.
nonisolated enum CropHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    /// Where this handle sits on `rect`: a corner, or the middle of an edge.
    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}

/// What a point on the canvas takes hold of.
nonisolated enum CropGrab: Equatable, Sendable {
    case handle(CropHandle)
    /// The frame's middle: moves it.
    case inside
    /// Nothing of the frame: a drag from here makes a new one.
    case outside
}

/// The crop frame and what dragging does to it, in annotation space (y down). Every operation keeps the frame inside
/// `bounds` (the canvas), at least `minimumSide` on each side, and, when `ratio` is set, in that ratio: a frame is
/// shrunk to fit the image rather than clamped on one side only, which would change its shape.
nonisolated struct CropFrame: Equatable, Sendable {
    /// The least a side of the frame can be, in pixels (less when the canvas itself is smaller).
    static let minimumSide: CGFloat = 16

    private(set) var rect: CGRect
    let bounds: CGRect
    /// Width over height, or nil when the frame is free.
    let ratio: CGFloat?

    init(rect: CGRect, bounds: CGRect, ratio: CGFloat?) {
        self.rect = rect.standardized
        self.bounds = bounds
        self.ratio = ratio.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
    }

    // MARK: Making a frame

    /// The frame a drag from `start` to `end` makes, anchored at `start`; nil when it would be smaller than the minimum,
    /// which is what a click is.
    static func dragging(from start: CGPoint, to end: CGPoint, in bounds: CGRect, ratio: CGFloat?) -> CropFrame? {
        let anchor = clamped(start, to: bounds)
        let signs = (x: end.x >= anchor.x ? CGFloat(1) : -1, y: end.y >= anchor.y ? CGFloat(1) : -1)
        let rect = sized(
            from: anchor, signs: signs, pulled: CGSize(width: abs(end.x - anchor.x), height: abs(end.y - anchor.y)),
            bounds: bounds, ratio: ratio, minimum: nil
        )
        let minimum = minimumSize(ratio: ratio, in: bounds)
        guard rect.width >= minimum.width, rect.height >= minimum.height else { return nil }
        return CropFrame(rect: rect, bounds: bounds, ratio: ratio)
    }

    /// The biggest frame of `ratio` the canvas holds, in its middle.
    static func largest(ratio: CGFloat, in bounds: CGRect) -> CropFrame {
        let size = largestSize(ratio: ratio, in: bounds.size)
        let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        return CropFrame(rect: rect, bounds: bounds, ratio: ratio)
    }

    /// This frame reshaped to `ratio`: the biggest frame of that ratio inside it, around its middle.
    func fitting(ratio: CGFloat) -> CropFrame {
        let size = Self.largestSize(ratio: ratio, in: rect.size)
        let fitted = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        return CropFrame(rect: fitted, bounds: bounds, ratio: ratio)
    }

    // MARK: Dragging

    /// What `point` takes hold of, with handles reaching `tolerance` from the corners and edges. A small frame keeps its
    /// middle for moving: handles never reach further than a third of a side.
    func grab(at point: CGPoint, tolerance: CGFloat) -> CropGrab {
        let reachX = min(tolerance, rect.width / 3), reachY = min(tolerance, rect.height / 3)
        guard point.x >= rect.minX - reachX, point.x <= rect.maxX + reachX,
              point.y >= rect.minY - reachY, point.y <= rect.maxY + reachY else { return .outside }
        let left = abs(point.x - rect.minX) <= reachX, right = abs(point.x - rect.maxX) <= reachX
        let top = abs(point.y - rect.minY) <= reachY, bottom = abs(point.y - rect.maxY) <= reachY
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .handle(.topLeft)
        case (_, true, true, _): return .handle(.topRight)
        case (true, _, _, true): return .handle(.bottomLeft)
        case (_, true, _, true): return .handle(.bottomRight)
        case (true, _, _, _): return .handle(.left)
        case (_, true, _, _): return .handle(.right)
        case (_, _, true, _): return .handle(.top)
        case (_, _, _, true): return .handle(.bottom)
        default: return rect.contains(point) ? .inside : .outside
        }
    }

    /// The frame moved by `delta`, stopping at the canvas's edges, with its size unchanged.
    func moved(by delta: CGSize) -> CropFrame {
        var moved = rect.offsetBy(dx: delta.width, dy: delta.height)
        moved.origin.x = max(bounds.minX, min(moved.minX, bounds.maxX - moved.width))
        moved.origin.y = max(bounds.minY, min(moved.minY, bounds.maxY - moved.height))
        return CropFrame(rect: moved, bounds: bounds, ratio: ratio)
    }

    /// The frame with `handle` pulled by `delta` from where this frame has it. A corner keeps the opposite corner and an
    /// edge keeps the opposite edge, and in a locked ratio the other axis follows around the frame's middle. The frame
    /// stops at the canvas and at its minimum size; it never flips.
    func resized(_ handle: CropHandle, by delta: CGSize) -> CropFrame {
        let minimum = Self.minimumSize(ratio: ratio, in: bounds)
        switch handle {
        case .topLeft: return corner(anchor: CGPoint(x: rect.maxX, y: rect.maxY), signs: (-1, -1), delta: delta, minimum: minimum)
        case .topRight: return corner(anchor: CGPoint(x: rect.minX, y: rect.maxY), signs: (1, -1), delta: delta, minimum: minimum)
        case .bottomLeft: return corner(anchor: CGPoint(x: rect.maxX, y: rect.minY), signs: (-1, 1), delta: delta, minimum: minimum)
        case .bottomRight: return corner(anchor: CGPoint(x: rect.minX, y: rect.minY), signs: (1, 1), delta: delta, minimum: minimum)
        case .left: return horizontalEdge(anchorX: rect.maxX, sign: -1, pull: delta.width, minimum: minimum)
        case .right: return horizontalEdge(anchorX: rect.minX, sign: 1, pull: delta.width, minimum: minimum)
        case .top: return verticalEdge(anchorY: rect.maxY, sign: -1, pull: delta.height, minimum: minimum)
        case .bottom: return verticalEdge(anchorY: rect.minY, sign: 1, pull: delta.height, minimum: minimum)
        }
    }

    /// The frame on whole pixels, rounding each edge to the nearest one, inside the canvas. This is what a crop is saved as.
    var pixelRect: CGRect {
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        let rounded = CGRect(x: minX, y: minY, width: max(rect.maxX.rounded() - minX, 0), height: max(rect.maxY.rounded() - minY, 0))
        let inside = rounded.intersection(bounds)
        return inside.isNull ? .zero : inside
    }

    // MARK: Geometry

    private func corner(anchor: CGPoint, signs: (x: CGFloat, y: CGFloat), delta: CGSize, minimum: CGSize) -> CropFrame {
        let pulled = CGSize(
            width: max(0, rect.width + signs.x * delta.width),
            height: max(0, rect.height + signs.y * delta.height)
        )
        let resized = Self.sized(from: anchor, signs: signs, pulled: pulled, bounds: bounds, ratio: ratio, minimum: minimum)
        return CropFrame(rect: resized, bounds: bounds, ratio: ratio)
    }

    private func horizontalEdge(anchorX: CGFloat, sign: CGFloat, pull: CGFloat, minimum: CGSize) -> CropFrame {
        let room = sign > 0 ? bounds.maxX - anchorX : anchorX - bounds.minX
        var width = rect.width + sign * pull
        var height = rect.height
        if let ratio {
            // The height follows around the middle, so it can be no more than twice the room on the nearer side.
            let vertical = 2 * min(rect.midY - bounds.minY, bounds.maxY - rect.midY)
            width = min(max(width, minimum.width), room, vertical * ratio)
            height = width / ratio
        } else {
            width = min(max(width, minimum.width), room)
        }
        let resized = CGRect(
            x: sign > 0 ? anchorX : anchorX - width, y: ratio == nil ? rect.minY : rect.midY - height / 2, width: width, height: height
        )
        return CropFrame(rect: resized, bounds: bounds, ratio: ratio)
    }

    private func verticalEdge(anchorY: CGFloat, sign: CGFloat, pull: CGFloat, minimum: CGSize) -> CropFrame {
        let room = sign > 0 ? bounds.maxY - anchorY : anchorY - bounds.minY
        var height = rect.height + sign * pull
        var width = rect.width
        if let ratio {
            let horizontal = 2 * min(rect.midX - bounds.minX, bounds.maxX - rect.midX)
            height = min(max(height, minimum.height), room, horizontal / ratio)
            width = height * ratio
        } else {
            height = min(max(height, minimum.height), room)
        }
        let resized = CGRect(
            x: ratio == nil ? rect.minX : rect.midX - width / 2, y: sign > 0 ? anchorY : anchorY - height, width: width, height: height
        )
        return CropFrame(rect: resized, bounds: bounds, ratio: ratio)
    }

    /// The rectangle that grows from `anchor` towards `signs`, `pulled` far, held to the canvas and, when `minimum` is
    /// given, lifted to it first. With a ratio the longer pull wins and the shorter side follows.
    private static func sized(
        from anchor: CGPoint, signs: (x: CGFloat, y: CGFloat), pulled: CGSize, bounds: CGRect, ratio: CGFloat?, minimum: CGSize?
    ) -> CGRect {
        let roomX = signs.x > 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let roomY = signs.y > 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        var width = pulled.width, height = pulled.height
        if let ratio {
            width = max(width, height * ratio)
            if let minimum { width = max(width, minimum.width) }
            width = min(width, roomX, roomY * ratio)
            height = width / ratio
        } else {
            if let minimum { (width, height) = (max(width, minimum.width), max(height, minimum.height)) }
            (width, height) = (min(width, roomX), min(height, roomY))
        }
        return CGRect(x: signs.x > 0 ? anchor.x : anchor.x - width, y: signs.y > 0 ? anchor.y : anchor.y - height, width: width, height: height)
    }

    private static func minimumSize(ratio: CGFloat?, in bounds: CGRect) -> CGSize {
        let side = max(0, min(minimumSide, bounds.width, bounds.height))
        guard let ratio else { return CGSize(width: side, height: side) }
        return ratio >= 1 ? CGSize(width: side * ratio, height: side) : CGSize(width: side, height: side / ratio)
    }

    private static func largestSize(ratio: CGFloat, in container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0, ratio > 0 else { return .zero }
        return container.width / container.height > ratio
            ? CGSize(width: container.height * ratio, height: container.height)
            : CGSize(width: container.width, height: container.width / ratio)
    }

    private static func clamped(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}
