import AppKit
import ImageIO

/// Small previews of stored images, decoded off the main thread and kept by file name (a content hash, so a name
/// never changes meaning). Owned by the module so thumbnails survive closing the notch.
final class ClipboardThumbnailCache {
    /// Twice the notch card's width, so previews stay sharp on Retina screens.
    nonisolated static let defaultPixelSize = 240
    /// The library's cards are up to twice as wide.
    nonisolated static let libraryPixelSize = 400
    /// About two rows of cards.
    private static let recentLimit = 12

    /// Decoded bytes kept at most; the system may reclaim thumbnails sooner, at any moment, under memory pressure.
    private static let costLimit = 32 * 1024 * 1024

    /// The longest side of a thumbnail in pixels. One cache serves one size, since entries are keyed by file name.
    let maxPixelSize: Int
    private let cache = NSCache<NSString, NSImage>()
    /// The latest thumbnails, held strongly so the cards in view are never decoded twice, even right after a purge.
    private var recent: [(key: NSString, image: NSImage)] = []

    init(maxPixelSize: Int = ClipboardThumbnailCache.defaultPixelSize) {
        self.maxPixelSize = maxPixelSize
        cache.totalCostLimit = Self.costLimit
    }

    /// Lets a card show a thumbnail decoded earlier in its first frame instead of a placeholder.
    func cachedThumbnail(for url: URL) -> NSImage? {
        let key = Self.key(url)
        return cache.object(forKey: key) ?? recent.first { $0.key == key }?.image
    }

    /// nil when the file is missing or not an image. Its size in points equals its pixel size.
    func thumbnail(for url: URL) async -> NSImage? {
        if let cached = cachedThumbnail(for: url) { return cached }
        guard let cgImage = await Self.decode(url, maxPixelSize: maxPixelSize) else { return nil }
        // Another card may have decoded the same file meanwhile; both get the first image.
        if let cached = cachedThumbnail(for: url) { return cached }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let key = Self.key(url)
        cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        recent.append((key, image))
        if recent.count > Self.recentLimit { recent.removeFirst() }
        return image
    }

    /// Stands in for the system emptying the cache, for tests.
    func simulateMemoryPressurePurge() {
        cache.removeAllObjects()
    }

    private static func key(_ url: URL) -> NSString {
        url.lastPathComponent as NSString
    }

    /// Reads only what the thumbnail needs, so a large screenshot is never decoded at full size.
    @concurrent private nonisolated static func decode(_ url: URL, maxPixelSize: Int) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
