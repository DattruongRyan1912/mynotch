import AppKit
import ImageIO
import os

/// Small previews of stored images, decoded off the main thread by ImageIO at the size they are drawn at and kept by file name and
/// size. Owned by the module, so thumbnails survive closing the notch.
///
/// The notch's tab, the floating panel and the library share one budget: each reaches it through a handle of its own
/// (`init(maxPixelSize:sharing:)`) that asks for its own size.
/// - Only a few pictures are decoded at once (`maxConcurrentDecodes`), the rest wait in order; a request whose card has scrolled away
///   by its turn is skipped. Each decode that runs at the same time leaves memory behind in the process, so this is what keeps the
///   library's high-water mark down when it opens on a screenful of screenshots.
/// - The decoded thumbnails fit `ClipboardThumbnailStorage.costLimit` bytes, plus the few latest that are held strongly, and go when
///   the system is short of memory (`releaseMemory`).
/// - A handle that is done, because its window closed, lets go of the sizes nobody else uses (`release`).
final class ClipboardThumbnailCache {
    /// Twice the notch card's width, so previews stay sharp on Retina screens.
    nonisolated static let defaultPixelSize = 240
    /// The library's cards are up to twice as wide.
    nonisolated static let libraryPixelSize = 400
    /// A list row's picture is at most 40 x 32 points: about twice that, which a Retina screen draws one for one.
    nonisolated static let glyphPixelSize = 96
    /// How many pictures are decoded at the same time, over all the handles.
    nonisolated static let maxConcurrentDecodes = 4

    /// The longest side of a thumbnail in pixels, when the caller does not ask for another. Entries are kept by file name and size.
    let maxPixelSize: Int
    private let storage: ClipboardThumbnailStorage
    /// The sizes this handle has asked for since it last let go.
    private var usedSizes: Set<Int> = []

    /// A cache of its own, or, with `sharing`, a handle on the budget, the line of decodes and the pictures of that one. `decoder` and
    /// `decodeLimit` only apply to a cache of its own: tests count the decodes instead of making them.
    init(
        maxPixelSize: Int = ClipboardThumbnailCache.defaultPixelSize, sharing other: ClipboardThumbnailCache? = nil,
        decoder: ClipboardPreviewImageDecoder = .system, decodeLimit: Int = ClipboardThumbnailCache.maxConcurrentDecodes
    ) {
        self.maxPixelSize = maxPixelSize
        storage = other?.storage ?? ClipboardThumbnailStorage(decoder: decoder, decodeLimit: decodeLimit)
        use(size: maxPixelSize)
    }

    /// Where the bytes of a picture of an open locked board are, which have a URL (`ClipboardOpenImages.url(forFileName:)`) and no file.
    var openImages: ClipboardOpenImages? {
        get { storage.openImages }
        set { storage.openImages = newValue }
    }

    /// Where the debug summary of the decodes goes; the module's while it runs.
    var logger: Logger? {
        get { storage.logger }
        set { storage.logger = newValue }
    }

    var stats: ClipboardThumbnailStats { storage.stats }

    /// Lets a card show a thumbnail decoded earlier in its first frame instead of a placeholder.
    func cachedThumbnail(for url: URL, maxPixelSize requested: Int? = nil) -> NSImage? {
        storage.image(for: key(url, size: requested ?? maxPixelSize))
    }

    /// nil when the file is missing or not an image, or when the task asking was cancelled before its turn to decode. Its size in
    /// points equals its pixel size. At most `maxConcurrentDecodes` decodes run at once, over every handle; a request waits its turn.
    func thumbnail(for url: URL, maxPixelSize requested: Int? = nil) async -> NSImage? {
        let size = requested ?? maxPixelSize
        use(size: size)
        let key = key(url, size: size)
        if let cached = storage.image(for: key) { return cached }
        guard await storage.gate.acquire() else {
            storage.noteDecodeSkipped()
            return nil
        }
        let image = await decode(url, key: key)
        storage.gate.release()
        storage.logIfIdle()
        return image
    }

    /// With a turn to decode in hand.
    private func decode(_ url: URL, key: ClipboardThumbnailKey) async -> NSImage? {
        // A card that scrolled away while it waited is not decoded for, and neither is a picture that another card decoded meanwhile.
        guard !Task.isCancelled else {
            storage.noteDecodeSkipped()
            return nil
        }
        if let cached = storage.image(for: key) { return cached }
        let decoded: CGImage?
        let isInMemory = url.scheme == ClipboardOpenImages.scheme
        if isInMemory {
            // Read now, with a turn in hand, not when the card asked: a request that waited holds nothing of a picture whose board
            // locked meanwhile, since the bytes are gone from memory by then.
            guard let data = storage.openImages?.data(forFileName: key.name) else { return nil }
            storage.noteDecodeStarted()
            decoded = await storage.decoder.memory(data, key.size)
            // A board that locked while this was decoding is not kept: the picture must not outlive its lock.
            guard storage.openImages?.contains(key.name) == true else { return nil }
        } else {
            storage.noteDecodeStarted()
            decoded = await storage.decoder.file(url, key.size)
        }
        guard let decoded else { return nil }
        return storage.insert(decoded, for: key)
    }

    /// Forgets every thumbnail of every handle, such as when a board locks. A picture of a locked item must not outlive its lock, so one
    /// held in memory that is being decoded, or waiting to be, is kept only while an open board still holds its bytes.
    func removeAll() {
        storage.removeAll()
    }

    /// Forgets every thumbnail because the system is short of memory. They are decoded again as cards ask.
    func releaseMemory() {
        storage.releaseMemory()
    }

    /// This handle's window is closed: the sizes no other handle uses are forgotten, so the library's pictures go with the library
    /// while the notch's stay for its next opening. A handle that is used again takes its sizes up again.
    func release() {
        storage.release(consumer: ObjectIdentifier(self))
        usedSizes = []
    }

    /// Stands in for the system emptying the cache, for tests.
    func simulateMemoryPressurePurge() {
        storage.simulateSystemPurge()
    }

    private func key(_ url: URL, size: Int) -> ClipboardThumbnailKey {
        ClipboardThumbnailKey(name: url.lastPathComponent, size: size)
    }

    private func use(size: Int) {
        if usedSizes.insert(size).inserted { storage.use(size: size, by: ObjectIdentifier(self)) }
    }

    // MARK: Decoding

    /// Reads only what the thumbnail needs, so a large screenshot is never decoded at full size.
    @concurrent nonisolated static func decode(_ url: URL, maxPixelSize: Int) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return thumbnail(of: source, maxPixelSize: maxPixelSize)
    }

    /// The same, from bytes held in memory.
    @concurrent nonisolated static func decode(_ data: Data, maxPixelSize: Int) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return thumbnail(of: source, maxPixelSize: maxPixelSize)
    }

    /// ImageIO's own thumbnail, which scales while it decodes and returns the pixels once, in the picture's colour space: nothing is
    /// drawn again here or copied.
    private nonisolated static func thumbnail(of source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
