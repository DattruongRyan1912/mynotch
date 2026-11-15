import CoreGraphics

nonisolated extension MarkupRenderer {
    /// `canvas` (a flattened canvas that covers `canvasBounds` of annotation space) cut to `crop`, as an image of its own
    /// so the whole canvas can go. Works in the canvas's pixels, so a document whose size differs from the picture's is
    /// cut in proportion. nil when the crop misses the canvas.
    static func cut(_ canvas: CGImage, to crop: CGRect, canvasBounds: CGRect) -> CGImage? {
        guard canvasBounds.width > 0, canvasBounds.height > 0 else { return nil }
        let scaleX = CGFloat(canvas.width) / canvasBounds.width, scaleY = CGFloat(canvas.height) / canvasBounds.height
        let pixels = CGRect(
            x: (crop.minX - canvasBounds.minX) * scaleX, y: (crop.minY - canvasBounds.minY) * scaleY,
            width: crop.width * scaleX, height: crop.height * scaleY
        ).integral.intersection(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1 else { return nil }
        return canvas.detachedCrop(to: pixels)
    }
}
