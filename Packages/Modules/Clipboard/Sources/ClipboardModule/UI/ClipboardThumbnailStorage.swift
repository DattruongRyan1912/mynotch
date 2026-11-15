import AppKit
import os
import Synchronization

/// What a thumbnail is kept under: the file's name (a content hash, so a name never changes meaning) and the longest side it was
/// decoded at, since the notch, the panel's rows and the library each need their own size of the same picture.
nonisolated struct ClipboardThumbnailKey: Hashable, Sendable {
    let name: String
    let size: Int
    private let cacheKeyString: String

    init(name: String, size: Int) {
        self.name = name
        self.size = size
        self.cacheKeyString = "\(size)/\(name)"
    }

    var cacheKey: NSString { cacheKeyString as NSString }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.size == rhs.size && lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(size)
        hasher.combine(name)
    }
}

/// One decoded thumbnail and the bytes it costs. The image is never changed after it is made.
nonisolated final class ClipboardThumbnailEntry: @unchecked Sendable {
    let key: ClipboardThumbnailKey
    let image: NSImage
    let cost: Int

    init(key: ClipboardThumbnailKey, image: NSImage, cost: Int) {
        self.key = key
        self.image = image
        self.cost = cost
    }
}

/// What `NSCache` keeps, as far as this knows: `NSCache` does not say how much it holds, and it empties itself whenever the system
/// asks. It hears about those evictions (on whatever thread the system uses), so the lock.
nonisolated final class ClipboardThumbnailLedger: NSObject, NSCacheDelegate, Sendable {
    private let costs = Mutex<[ClipboardThumbnailKey: Int]>([:])

    var total: Int { costs.withLock { $0.values.reduce(0, +) } }
    var count: Int { costs.withLock { $0.count } }

    func add(_ key: ClipboardThumbnailKey, cost: Int) {
        costs.withLock { $0[key] = cost }
    }

    func remove(_ key: ClipboardThumbnailKey) {
        costs.withLock { $0[key] = nil }
    }

    func removeAll() {
        costs.withLock { $0.removeAll() }
    }

    func keys(ofSize size: Int) -> [ClipboardThumbnailKey] {
        costs.withLock { $0.keys.filter { $0.size == size } }
    }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject object: Any) {
        if let entry = object as? ClipboardThumbnailEntry { remove(entry.key) }
    }
}

/// Counts of what the thumbnails did, for the debug log and the tests. Numbers only: never a name.
struct ClipboardThumbnailStats: Equatable {
    var decodesStarted = 0
    /// Requests that were cancelled (their card scrolled away) before a decode began, so none was made.
    var decodesSkipped = 0
    var peakConcurrentDecodes = 0
    /// Requests waiting for their turn to decode.
    var waitingDecodes = 0
    var cachedBytes = 0
    var cachedCount = 0
    /// The latest thumbnails, which are held outside the cache's limit.
    var recentCount = 0
    /// Times the thumbnails were let go because the system was short of memory.
    var memoryReleases = 0
}

/// What the notch's tab, the floating panel and the library share: one `NSCache` with a byte budget, the line of decodes waiting for
/// a turn, and who is using which size. Each of them reaches it through a `ClipboardThumbnailCache` of its own.
final class ClipboardThumbnailStorage {
    /// Decoded bytes kept at most (cost is the thumbnail's bytes). The system may reclaim thumbnails sooner, at any moment, and
    /// `releaseMemory` does when it asks. The `recent` ones are held on top of this.
    nonisolated static let costLimit = 24 * 1024 * 1024
    /// Enough for an 8x6 small-grid screenful of cards so scrolling does not re-decode visible thumbnails.
    static let recentLimit = 48

    let cache = NSCache<NSString, ClipboardThumbnailEntry>()
    let ledger = ClipboardThumbnailLedger()
    let gate: ClipboardDecodeGate
    var decoder: ClipboardPreviewImageDecoder
    /// Persistent disk cache for pre-scaled thumbnails of non-locked items.
    var diskStore: ClipboardDiskThumbnailStore?
    /// Where the bytes of a picture of an open locked board are, which have a URL (`ClipboardOpenImages.url(forFileName:)`) and no file.
    var openImages: ClipboardOpenImages?
    /// Set by the module while it runs, for the debug summaries.
    var logger: Logger?

    /// The latest thumbnails, held strongly so the cards in view are never decoded twice, even right after the system purged the cache.
    private(set) var recent: [ClipboardThumbnailEntry] = []
    /// The sizes each handle has asked for while it is in use; what no handle uses any more is dropped when the last one lets go.
    private var consumers: [ObjectIdentifier: Set<Int>] = [:]
    private(set) var decodesStarted = 0
    private(set) var decodesSkipped = 0
    private(set) var memoryReleases = 0

    init(decoder: ClipboardPreviewImageDecoder, decodeLimit: Int, diskStore: ClipboardDiskThumbnailStore? = nil) {
        self.decoder = decoder
        self.diskStore = diskStore
        gate = ClipboardDecodeGate(limit: decodeLimit)
        cache.totalCostLimit = Self.costLimit
        cache.delegate = ledger
    }

    var stats: ClipboardThumbnailStats {
        ClipboardThumbnailStats(
            decodesStarted: decodesStarted, decodesSkipped: decodesSkipped, peakConcurrentDecodes: gate.peak,
            waitingDecodes: gate.queued, cachedBytes: ledger.total, cachedCount: ledger.count, recentCount: recent.count, memoryReleases: memoryReleases
        )
    }

    // MARK: Reading and writing

    func image(for key: ClipboardThumbnailKey) -> NSImage? {
        if let entry = cache.object(forKey: key.cacheKey) {
            touchRecent(entry)
            return entry.image
        }
        if let idx = recent.firstIndex(where: { $0.key == key }) {
            let entry = recent[idx]
            if idx != recent.count - 1 {
                recent.remove(at: idx)
                recent.append(entry)
            }
            return entry.image
        }
        return nil
    }

    private func touchRecent(_ entry: ClipboardThumbnailEntry) {
        if recent.last?.key == entry.key { return }
        if let idx = recent.firstIndex(where: { $0.key == entry.key }) {
            recent.remove(at: idx)
            recent.append(entry)
        } else {
            recent.append(entry)
            if recent.count > Self.recentLimit { recent.removeFirst() }
        }
    }

    /// Keeps a decoded picture and returns the image to show. Another card may have decoded the same file meanwhile; both get the first.
    func insert(_ cgImage: CGImage, for key: ClipboardThumbnailKey) -> NSImage {
        if let existing = image(for: key) { return existing }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let entry = ClipboardThumbnailEntry(key: key, image: image, cost: cgImage.bytesPerRow * cgImage.height)
        // The ledger first: a cache too small for this entry evicts it at once, and that is heard.
        ledger.add(key, cost: entry.cost)
        cache.setObject(entry, forKey: key.cacheKey, cost: entry.cost)
        recent.append(entry)
        if recent.count > Self.recentLimit { recent.removeFirst() }
        return image
    }

    func noteDecodeStarted() {
        decodesStarted += 1
    }

    func noteDecodeSkipped() {
        decodesSkipped += 1
    }

    /// One line, once the line of decodes has run dry: what a screenful of pictures took. Counts only.
    func logIfIdle() {
        guard let logger, gate.running == 0, gate.queued == 0 else { return }
        let stats = stats
        logger.debug("Thumbnails: \(stats.decodesStarted) decoded, \(stats.decodesSkipped) skipped, at most \(stats.peakConcurrentDecodes) at once, \(stats.cachedBytes / 1024) KB kept")
    }

    // MARK: Forgetting

    /// Forgets every thumbnail, such as when the board they came from locks.
    func removeAll() {
        dropEverything()
    }

    /// Forgets every thumbnail because the system is short of memory. Decodes that are running or waiting go on, and are kept: they
    /// are what the cards on screen are waiting for.
    func releaseMemory() {
        let freed = ledger.total
        dropEverything()
        memoryReleases += 1
        logger?.debug("Thumbnails let go for memory: \(freed / 1024) KB")
    }

    /// Stands in for the system emptying the cache, for tests.
    func simulateSystemPurge() {
        cache.removeAllObjects()
        ledger.removeAll()
    }

    private func dropEverything() {
        cache.removeAllObjects()
        ledger.removeAll()
        recent = []
    }

    // MARK: Who uses which size

    func use(size: Int, by consumer: ObjectIdentifier) {
        consumers[consumer, default: []].insert(size)
    }

    /// `consumer` is done (its window closed): the sizes only it used are dropped, in the cache and among the latest.
    func release(consumer: ObjectIdentifier) {
        let mine = consumers.removeValue(forKey: consumer) ?? []
        let stillUsed = consumers.values.reduce(into: Set<Int>()) { $0.formUnion($1) }
        let dropped = mine.subtracting(stillUsed)
        guard !dropped.isEmpty else { return }
        for size in dropped {
            for key in ledger.keys(ofSize: size) {
                cache.removeObject(forKey: key.cacheKey)
                ledger.remove(key)
            }
        }
        recent.removeAll { dropped.contains($0.key.size) }
    }
}
