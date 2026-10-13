import CoreGraphics

/// Where an image sits in the editor's canvas when aspect-fitted and centred, and the conversions between
/// view points (origin top-left) and image pixels (origin top-left) that drawing gestures need.
nonisolated struct ImageFit: Equatable, Sendable {
    let imageSize: CGSize
    /// View points per image pixel; 0 when either size is empty.
    let scale: CGFloat
    /// The image's frame in the view; the rest is letterbox.
    let frame: CGRect

    /// `maximumScale` stops small captures from being blown up past that many points per pixel.
    init(imageSize: CGSize, viewSize: CGSize, maximumScale: CGFloat = .infinity) {
        self.imageSize = imageSize
        let fitted = imageSize.width > 0 && imageSize.height > 0
            ? min(viewSize.width / imageSize.width, viewSize.height / imageSize.height, maximumScale)
            : 0
        scale = max(fitted, 0)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        frame = CGRect(
            x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2,
            width: size.width, height: size.height
        )
    }

    /// The image pixel under a view point, clamped to the image so drags that leave it stay on its edge.
    func imagePoint(fromView point: CGPoint) -> CGPoint {
        guard scale > 0 else { return .zero }
        return CGPoint(
            x: min(max((point.x - frame.minX) / scale, 0), imageSize.width),
            y: min(max((point.y - frame.minY) / scale, 0), imageSize.height)
        )
    }

    func viewPoint(fromImage point: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + point.x * scale, y: frame.minY + point.y * scale)
    }

    func viewRect(fromImage rect: CGRect) -> CGRect {
        CGRect(origin: viewPoint(fromImage: rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale))
    }
}
