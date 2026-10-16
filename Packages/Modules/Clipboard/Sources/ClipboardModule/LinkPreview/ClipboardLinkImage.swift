import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A page's picture made into what MyNotch keeps: a PNG of at most 256 pixels on a side, made by ImageIO's thumbnailing so a big picture is
/// never decoded at full size, and always MyNotch's own bytes, never the page's.
nonisolated enum ClipboardLinkImage {
    /// The longest side of the stored picture.
    static let maxPixelSize = 256
    /// Larger than this many pixels is refused before any decoding: a few kilobytes of PNG can describe a picture that takes gigabytes.
    static let maxPixelCount = 25_000_000
    static let maxSide = 16_384
    /// The most frames of one file looked at, for an icon file that holds several sizes.
    private static let maxFrames = 16

    /// nil for bytes that are not a picture, are not a kind of picture ImageIO reads, or describe too many pixels.
    @concurrent static func thumbnailPNG(from data: Data) async -> Data? {
        thumbnail(from: data)
    }

    static func thumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source), UTType(type as String)?.conforms(to: .image) == true else { return nil }
        let count = min(CGImageSourceGetCount(source), maxFrames)
        // The biggest frame: an icon file's first one is often the smallest.
        var best: (index: Int, pixels: Int)?
        for index in 0..<count {
            guard let size = pixelSize(of: source, at: index), isAcceptable(width: size.width, height: size.height) else { continue }
            if best == nil || size.width * size.height > best!.pixels { best = (index, size.width * size.height) }
        }
        guard let best else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, best.index, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Whether a picture of this size may be decoded at all.
    static func isAcceptable(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && width <= maxSide && height <= maxSide && width * height <= maxPixelCount
    }

    private static func pixelSize(of source: CGImageSource, at index: Int) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}
