import CoreGraphics

extension CGImage {
    /// The pixels of `rect` (image pixels, origin top-left) as an image of its own. `cropping(to:)` keeps the whole
    /// parent alive, and a frozen 6K screen is some 80 MB that must go once the overlay is done, however long
    /// storing or reading the region takes. nil when `rect` misses the image.
    nonisolated func detachedCrop(to rect: CGRect) -> CGImage? {
        guard let cropped = cropping(to: rect) else { return nil }
        guard cropped.width != width || cropped.height != height,
              let space = cropped.colorSpace,
              let context = CGContext(
                  data: nil, width: cropped.width, height: cropped.height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return cropped }
        // The same colour space and a straight copy: no conversion, no blending, no resampling.
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        return context.makeImage() ?? cropped
    }
}
