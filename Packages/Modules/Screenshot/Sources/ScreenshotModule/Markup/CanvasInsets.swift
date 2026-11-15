import CoreGraphics

/// How many whole pixels the canvas extends past the capture on each side. Annotations keep their coordinates
/// relative to the capture, so growing the canvas never has to move them.
nonisolated struct CanvasInsets: Equatable, Sendable {
    var left = 0
    var top = 0
    var right = 0
    var bottom = 0

    static let zero = CanvasInsets()

    var isZero: Bool { self == .zero }

    /// Half the longer side, but at least 256 pixels: a drag that leaves the window cannot allocate a huge bitmap.
    static func limit(for imageSize: CGSize) -> Int {
        max(256, Int(max(imageSize.width, imageSize.height) / 2))
    }

    /// The canvas in annotation space: the capture's rect plus the padding, so its origin is negative when the left
    /// or top grew.
    func bounds(of imageSize: CGSize) -> CGRect {
        let width = imageSize.width + CGFloat(left) + CGFloat(right)
        let height = imageSize.height + CGFloat(top) + CGFloat(bottom)
        return CGRect(x: CGFloat(-left), y: CGFloat(-top), width: width, height: height)
    }

    func size(of imageSize: CGSize) -> CGSize {
        bounds(of: imageSize).size
    }

    /// These insets, enlarged on each side `rect` reaches past by whole pixels, up to `limit(for:)`; never smaller.
    func growing(toContain rect: CGRect, imageSize: CGSize) -> CanvasInsets {
        guard !rect.isNull, !rect.isInfinite, rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite else { return self }
        let limit = Self.limit(for: imageSize)
        // Clamped before converting: a coordinate from a damaged file can be far beyond what an Int holds.
        func overflow(_ distance: CGFloat) -> Int { distance > 0 ? Int(min(distance.rounded(.up), CGFloat(limit))) : 0 }
        return CanvasInsets(
            left: max(left, overflow(-rect.minX)),
            top: max(top, overflow(-rect.minY)),
            right: max(right, overflow(rect.maxX - imageSize.width)),
            bottom: max(bottom, overflow(rect.maxY - imageSize.height))
        )
    }
}
