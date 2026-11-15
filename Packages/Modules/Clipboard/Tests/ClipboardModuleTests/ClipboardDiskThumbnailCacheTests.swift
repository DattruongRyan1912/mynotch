import AppKit
import CryptoKit
import Foundation
import ImageIO
import MyNotchCore
import MyNotchTestSupport
import Testing
import UniformTypeIdentifiers
@testable import ClipboardModule

@Suite final class ClipboardDiskThumbnailCacheTests {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "ClipboardDiskThumbnailCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    private var imagesDirectory: URL { directory.appending(path: "images", directoryHint: .isDirectory) }
    private var thumbnailsDirectory: URL { directory.appending(path: "thumbnails", directoryHint: .isDirectory) }

    init() throws {
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func hashName(_ seed: String) -> String {
        Data(seed.utf8).sha256Hex + ".png"
    }

    private func writePNG(width: Int, height: Int, named fileName: String) throws -> URL {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let url = imagesDirectory.appending(path: fileName, directoryHint: .notDirectory)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func testDiskThumbnailCacheHitAndAvoidsFullImageDecode() async throws {
        let fileName = hashName("source-480x320")
        let url = try writePNG(width: 480, height: 320, named: fileName)
        let diskStore = ClipboardDiskThumbnailStore(directory: thumbnailsDirectory)

        let sourceDecodeCount = LockedCounter()
        let countingDecoder = ClipboardPreviewImageDecoder(
            file: { sourceURL, maxPixelSize in
                sourceDecodeCount.increment()
                return await ClipboardThumbnailCache.decode(sourceURL, maxPixelSize: maxPixelSize)
            },
            memory: { data, maxPixelSize in
                await ClipboardThumbnailCache.decode(data, maxPixelSize: maxPixelSize)
            }
        )

        let cache = ClipboardThumbnailCache(
            maxPixelSize: ClipboardThumbnailCache.libraryPixelSize,
            decoder: countingDecoder,
            diskStore: diskStore
        )

        let thumbSize = ClipboardThumbnailCache.libraryPixelSize
        let first = try #require(await cache.thumbnail(for: url, maxPixelSize: thumbSize))
        #expect(first.size.width == CGFloat(thumbSize))
        #expect(sourceDecodeCount.value == 1)

        await diskStore.waitForWrites()

        let thumbName = try #require(ClipboardDiskThumbnailStore.thumbnailFileName(forSourceName: fileName, size: thumbSize))
        let thumbURL = thumbnailsDirectory.appending(path: thumbName, directoryHint: .notDirectory)
        #expect(FileManager.default.fileExists(atPath: thumbURL.path(percentEncoded: false)))
        let originalSize = (try url.resourceValues(forKeys: [URLResourceKey.fileSizeKey]).fileSize) ?? 0
        let thumbByteSize = (try thumbURL.resourceValues(forKeys: [URLResourceKey.fileSizeKey]).fileSize) ?? 0
        #expect(thumbByteSize > 0 && thumbByteSize < originalSize)

        cache.removeAll()
        #expect(cache.cachedThumbnail(for: url, maxPixelSize: thumbSize) == nil)

        let cacheAfterReopen = ClipboardThumbnailCache(
            maxPixelSize: ClipboardThumbnailCache.libraryPixelSize,
            decoder: countingDecoder,
            diskStore: diskStore
        )
        let second = try #require(await cacheAfterReopen.thumbnail(for: url, maxPixelSize: thumbSize))
        #expect(second.size == first.size)
        #expect(sourceDecodeCount.value == 1, "disk thumbnail hit must bypass full-source PNG decode")
    }

    @Test func testLockedBoardImageNeverTouchesDiskThumbnailStore() async throws {
        let openImages = ClipboardOpenImages()
        let boardID = UUID()
        let fileName = hashName("locked-secret")
        let sourceURL = try writePNG(width: 400, height: 300, named: fileName)
        let secretData = try Data(contentsOf: sourceURL)
        try FileManager.default.removeItem(at: sourceURL)

        openImages.add(secretData, named: fileName, to: boardID)
        let diskStore = ClipboardDiskThumbnailStore(directory: thumbnailsDirectory)
        let cache = ClipboardThumbnailCache(
            maxPixelSize: ClipboardThumbnailCache.libraryPixelSize,
            diskStore: diskStore
        )
        cache.openImages = openImages

        let thumbSize = ClipboardThumbnailCache.libraryPixelSize
        let secretURL = ClipboardOpenImages.url(forFileName: fileName)
        let image = try #require(await cache.thumbnail(for: secretURL, maxPixelSize: thumbSize))
        #expect(image.size.width == CGFloat(thumbSize))

        await diskStore.waitForWrites()

        let diskFiles = (try? FileManager.default.contentsOfDirectory(at: thumbnailsDirectory, includingPropertiesForKeys: nil)) ?? []
        #expect(diskFiles.isEmpty, "locked board images must never be written to disk thumbnails")

        openImages.remove(board: boardID)
        cache.removeAll()
        #expect(cache.cachedThumbnail(for: secretURL, maxPixelSize: thumbSize) == nil)
        let diskFilesAfterLock = (try? FileManager.default.contentsOfDirectory(at: thumbnailsDirectory, includingPropertiesForKeys: nil)) ?? []
        #expect(diskFilesAfterLock.isEmpty)
    }

    @Test func testCorruptedDiskThumbnailGracefulFallbackToSource() async throws {
        let fileName = hashName("corrupt-thumb-source")
        let url = try writePNG(width: 480, height: 320, named: fileName)
        let diskStore = ClipboardDiskThumbnailStore(directory: thumbnailsDirectory)
        try FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)

        let thumbSize = ClipboardThumbnailCache.libraryPixelSize
        let thumbName = try #require(ClipboardDiskThumbnailStore.thumbnailFileName(forSourceName: fileName, size: thumbSize))
        let thumbURL = thumbnailsDirectory.appending(path: thumbName, directoryHint: .notDirectory)
        try Data("not-a-valid-png-payload".utf8).write(to: thumbURL, options: .atomic)

        let cache = ClipboardThumbnailCache(
            maxPixelSize: thumbSize,
            diskStore: diskStore
        )

        let recovered = try #require(await cache.thumbnail(for: url, maxPixelSize: thumbSize))
        #expect(recovered.size.width == CGFloat(thumbSize))

        await diskStore.waitForWrites()

        let repairedCG = await diskStore.readAsync(name: fileName, size: thumbSize)
        #expect(repairedCG != nil, "corrupted thumbnail must be cleaned up and replaced by valid thumbnail")
    }

    @Test func testStoreDeleteImagesPrunesCorrespondingDiskThumbnails() async throws {
        let scheduler = ManualScheduler()
        let store = ClipboardStore(
            directory: directory,
            scheduler: scheduler,
            logger: Log.logger(category: "ClipboardDiskThumbnailCacheTests")
        )
        _ = store.load()

        let cache = ClipboardThumbnailCache(
            maxPixelSize: ClipboardThumbnailCache.libraryPixelSize,
            diskStore: store.diskThumbnails
        )

        func makeStoredItem(seed: String) throws -> (ClipboardItem, URL) {
            let name = hashName(seed)
            let url = try writePNG(width: 480, height: 320, named: name)
            let content = ClipboardContent.image(ClipboardImage(fileName: name, pixelWidth: 480, pixelHeight: 320, byteCount: 480 * 320 * 4))
            let item = ClipboardItem(
                id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content),
                copiedAt: .now, sourceBundleID: "com.apple.Safari", sourceAppName: "Safari"
            )
            return (item, url)
        }

        let (item1, url1) = try makeStoredItem(seed: "item-1")
        let (item2, url2) = try makeStoredItem(seed: "item-2")
        let (item3, url3) = try makeStoredItem(seed: "item-3")

        let librarySize = ClipboardThumbnailCache.libraryPixelSize
        let defaultSize = ClipboardThumbnailCache.defaultPixelSize
        for url in [url1, url2, url3] {
            #expect(await cache.thumbnail(for: url, maxPixelSize: librarySize) != nil)
            #expect(await cache.thumbnail(for: url, maxPixelSize: defaultSize) != nil)
        }
        await store.diskThumbnails.waitForWrites()

        let name1 = try #require(item1.storedImageFileName)
        let name2 = try #require(item2.storedImageFileName)
        let name3 = try #require(item3.storedImageFileName)

        let thumb1_lib = try #require(store.diskThumbnails.fileURL(forName: name1, size: librarySize))
        let thumb1_def = try #require(store.diskThumbnails.fileURL(forName: name1, size: defaultSize))
        let thumb2_lib = try #require(store.diskThumbnails.fileURL(forName: name2, size: librarySize))
        let thumb3_def = try #require(store.diskThumbnails.fileURL(forName: name3, size: defaultSize))
        #expect(FileManager.default.fileExists(atPath: thumb1_lib.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: thumb1_def.path(percentEncoded: false)))

        store.deleteImages(for: [item1])
        #expect(!FileManager.default.fileExists(atPath: url1.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: thumb1_lib.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: thumb1_def.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: url2.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: thumb2_lib.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: url3.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: thumb3_def.path(percentEncoded: false)))

        let orphanName = hashName("orphan-thumb")
        let orphanThumbURL = try #require(store.diskThumbnails.fileURL(forName: orphanName, size: librarySize))
        try Data("orphan".utf8).write(to: orphanThumbURL, options: .atomic)
        #expect(FileManager.default.fileExists(atPath: orphanThumbURL.path(percentEncoded: false)))

        store.deleteOrphanImages(referencedBy: [item2, item3])

        #expect(!FileManager.default.fileExists(atPath: orphanThumbURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: thumb2_lib.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: thumb3_def.path(percentEncoded: false)))
    }

    @Test func testRecentCacheUsesLRUPromotionInsteadOfFIFO() async throws {
        let cache = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize)
        var urls: [URL] = []
        for index in 0..<48 {
            let fileName = hashName("lru-\(index)")
            urls.append(try writePNG(width: 120, height: 120, named: fileName))
        }
        for url in urls {
            #expect(await cache.thumbnail(for: url) != nil)
        }

        // Purge NSCache so only `recent` (48 entries) remains, then touch item 0 to promote it.
        cache.simulateMemoryPressurePurge()
        #expect(cache.cachedThumbnail(for: urls[0]) != nil)

        // Adding a 49th item must evict item 1 (least recently used), keeping promoted item 0.
        let extraURL = try writePNG(width: 120, height: 120, named: hashName("lru-48"))
        #expect(await cache.thumbnail(for: extraURL) != nil)
        cache.simulateMemoryPressurePurge()

        #expect(cache.cachedThumbnail(for: urls[0]) != nil, "promoted entry must survive FIFO eviction")
        #expect(cache.cachedThumbnail(for: urls[1]) == nil, "least-recently-used entry must be evicted first")
    }

    @Test func testMediaBytesIncludesDiskThumbnailsForReleasableItems() async throws {
        let fileName = hashName("media-bytes-thumb")
        let url = try writePNG(width: 480, height: 320, named: fileName)
        let imageBytes = Int64((try url.resourceValues(forKeys: [URLResourceKey.fileSizeKey]).fileSize) ?? 0)
        let content = ClipboardContent.image(ClipboardImage(fileName: fileName, pixelWidth: 480, pixelHeight: 320, byteCount: 480 * 320 * 4))
        let item = ClipboardItem(
            id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content),
            copiedAt: .now, sourceBundleID: "com.apple.Safari", sourceAppName: "Safari"
        )
        let history = ClipboardHistory(items: [item], boards: [])
        let baselineBytes = await ClipboardStorageScan.mediaBytes(directory: directory, history: history)
        #expect(baselineBytes == imageBytes)

        let diskStore = ClipboardDiskThumbnailStore(directory: thumbnailsDirectory)
        let cache = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, diskStore: diskStore)
        #expect(await cache.thumbnail(for: url) != nil)
        await diskStore.waitForWrites()

        let withThumbBytes = await ClipboardStorageScan.mediaBytes(directory: directory, history: history)
        #expect(withThumbBytes > baselineBytes)
    }

    @Test func scrollingDownUpDownAcross165LibraryThumbnailsKeepsAllInMemoryWithoutReload() async throws {
        #expect(ClipboardThumbnailCache.libraryPixelSize == 200)
        let decodeCount = LockedCounter()
        let decoder = ClipboardPreviewImageDecoder(
            file: { _, maxPixelSize in
                decodeCount.increment()
                let height = max(1, Int((Double(maxPixelSize) * 0.7).rounded()))
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                guard let ctx = CGContext(
                    data: nil, width: maxPixelSize, height: height, bitsPerComponent: 8,
                    bytesPerRow: maxPixelSize * 4, space: colorSpace, bitmapInfo: bitmapInfo
                ) else { return nil }
                return ctx.makeImage()
            },
            memory: { _, _ in nil }
        )
        let library = ClipboardThumbnailCache(
            maxPixelSize: ClipboardThumbnailCache.libraryPixelSize,
            decoder: decoder
        )
        let urls = (0..<165).map { imagesDirectory.appending(path: hashName("scroll-\($0)"), directoryHint: .notDirectory) }

        // Pass 1: Scroll down 0 -> 164
        for url in urls {
            #expect(await library.thumbnail(for: url) != nil)
        }
        #expect(decodeCount.value == 165)

        // Pass 2: Scroll back up 164 -> 0 — zero eviction and zero placeholder nil
        for url in urls.reversed() {
            #expect(library.cachedThumbnail(for: url) != nil)
        }

        // Pass 3: Scroll back down 0 -> 164 — zero re-decode and zero placeholder nil
        for url in urls {
            #expect(library.cachedThumbnail(for: url) != nil)
            #expect(await library.thumbnail(for: url) != nil)
        }
        #expect(decodeCount.value == 165)
    }

    @Test func deleteOrphanThumbnailsPrunesStaleUnsupportedSizesLike400() async throws {
        let aliveHash = String(repeating: "a", count: 64) + ".png"
        let sourceURL = try writePNG(width: 480, height: 320, named: aliveHash)
        let cgImage = try #require(await ClipboardThumbnailCache.decode(sourceURL, maxPixelSize: 240))
        let diskStore = ClipboardDiskThumbnailStore(directory: thumbnailsDirectory)

        diskStore.scheduleWrite(cgImage, name: aliveHash, size: 400)
        diskStore.scheduleWrite(cgImage, name: aliveHash, size: ClipboardThumbnailCache.libraryPixelSize)
        diskStore.scheduleWrite(cgImage, name: aliveHash, size: ClipboardThumbnailCache.defaultPixelSize)
        await diskStore.waitForWrites()

        #expect(ClipboardDiskThumbnailStore.thumbnailSize(fromThumbnailFileName: "\(String(repeating: "a", count: 64))_400.png") == 400)
        #expect(diskStore.read(name: aliveHash, size: 400) != nil)

        diskStore.deleteOrphanThumbnails(keeping: [aliveHash])

        #expect(diskStore.read(name: aliveHash, size: 400) == nil)
        #expect(diskStore.read(name: aliveHash, size: ClipboardThumbnailCache.libraryPixelSize) != nil)
        #expect(diskStore.read(name: aliveHash, size: ClipboardThumbnailCache.defaultPixelSize) != nil)
    }

    @Test func previewImageResolutionRemainsHighResWhileLibraryGridUses200px() {
        #expect(ClipboardThumbnailCache.libraryPixelSize == 200)
        #expect(
            ClipboardPreviewImage.maxPixelSize(
                display: CGSize(width: 800, height: 600), scale: 2.0, pixelWidth: 3840, pixelHeight: 2160
            ) == 1600
        )
        #expect(
            ClipboardPreviewImage.maxPixelSize(
                display: CGSize(width: 2560, height: 1440), scale: 2.0, pixelWidth: 3840, pixelHeight: 2160
            ) == 3840
        )
    }
}

private nonisolated final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}
