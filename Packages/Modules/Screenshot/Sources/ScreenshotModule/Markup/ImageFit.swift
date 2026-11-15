import CoreGraphics

/// Where the canvas (the capture plus any padding) sits in the editor's view when aspect-fitted and centred, and
/// the conversions between view points (origin top-left) and annotation pixels (origin top-left) that drawing
/// gestures need.
nonisolated struct ImageFit: Equatable, Sendable {
    /// The canvas's size in pixels.
    let imageSize: CGSize
    /// The viewport size the canvas is laid out in.
    let viewSize: CGSize
    /// The annotation-space point of the canvas's top-left corner: negative once the canvas grew left or up.
    let origin: CGPoint
    /// The baseline view points per image pixel before any user zoom is applied.
    let baseScale: CGFloat
    /// Effective view points per image pixel (`baseScale * zoomScale`); 0 when either size is empty.
    let scale: CGFloat
    /// The image's frame in the view; the rest is letterbox or canvas background.
    let frame: CGRect

    /// `maximumScale` stops small captures from being blown up past that many points per pixel. `margin` keeps that
    /// many points free around the canvas, so a drag can leave the picture and grow the canvas.
    /// `zoomScale` and `panOffset` support zooming into long screenshots or high-res captures.
    init(
        imageSize: CGSize,
        viewSize: CGSize,
        maximumScale: CGFloat = .infinity,
        margin: CGFloat = 0,
        origin: CGPoint = .zero,
        zoomScale: CGFloat = 1,
        panOffset: CGSize = .zero
    ) {
        self.imageSize = imageSize
        self.viewSize = viewSize
        self.origin = origin
        let fitted = imageSize.width > 0 && imageSize.height > 0
            ? min((viewSize.width - 2 * margin) / imageSize.width, (viewSize.height - 2 * margin) / imageSize.height, maximumScale)
            : 0
        let base = max(fitted, 0)
        self.baseScale = base
        let effective = base * max(zoomScale, 0)
        self.scale = effective
        let size = CGSize(width: imageSize.width * effective, height: imageSize.height * effective)
        self.frame = CGRect(
            x: (viewSize.width - size.width) / 2 + panOffset.width,
            y: (viewSize.height - size.height) / 2 + panOffset.height,
            width: size.width,
            height: size.height
        )
    }

    /// The annotation pixel under a view point. Clamped to the canvas by default, so drags that leave it stay on its
    /// edge; drawing tools pass `clamped: false` to reach beyond it.
    func imagePoint(fromView point: CGPoint, clamped: Bool = true) -> CGPoint {
        guard scale > 0 else { return .zero }
        let x = (point.x - frame.minX) / scale, y = (point.y - frame.minY) / scale
        guard clamped else { return CGPoint(x: x + origin.x, y: y + origin.y) }
        return CGPoint(x: min(max(x, 0), imageSize.width) + origin.x, y: min(max(y, 0), imageSize.height) + origin.y)
    }

    func viewPoint(fromImage point: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + (point.x - origin.x) * scale, y: frame.minY + (point.y - origin.y) * scale)
    }

    func viewRect(fromImage rect: CGRect) -> CGRect {
        CGRect(origin: viewPoint(fromImage: rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale))
    }
}
