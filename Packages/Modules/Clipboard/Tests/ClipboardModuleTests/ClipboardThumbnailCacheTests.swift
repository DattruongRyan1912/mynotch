import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ClipboardModule

@Suite final class ClipboardThumbnailCacheTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "ClipboardThumbnailCacheTests-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A solid PNG of the given pixel size.
    func writePNG(width: Int, height: Int, named name: String = "image.png") throws -> URL {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let url = directory.appending(path: name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func theSameFileGivesTheSameImageObject() async throws {
        let url = try writePNG(width: 64, height: 64)
        let cache = ClipboardThumbnailCache()
        #expect(cache.cachedThumbnail(for: url) == nil)
        let first = try #require(await cache.thumbnail(for: url))
        let second = try #require(await cache.thumbnail(for: url))
        #expect(first === second)
        #expect(cache.cachedThumbnail(for: url) === first)
    }

    /// NSCache may empty itself under memory pressure at any moment, even right after an insert.
    @Test func recentThumbnailsSurviveTheSystemPurgingTheCache() async throws {
        let url = try writePNG(width: 64, height: 64)
        let cache = ClipboardThumbnailCache()
        let first = try #require(await cache.thumbnail(for: url))

        cache.simulateMemoryPressurePurge()

        #expect(cache.cachedThumbnail(for: url) === first)
        #expect(await cache.thumbnail(for: url) === first)
    }

    @Test func thumbnailsAreAtMost240PixelsAndKeepTheAspectRatio() async throws {
        let cache = ClipboardThumbnailCache()
        let wide = try #require(await cache.thumbnail(for: writePNG(width: 600, height: 300, named: "wide.png")))
        #expect(wide.size == NSSize(width: 240, height: 120))
        let small = try #require(await cache.thumbnail(for: writePNG(width: 40, height: 80, named: "small.png")))
        #expect(small.size == NSSize(width: 40, height: 80))
    }

    @Test func aMissingOrUnreadableFileHasNoThumbnail() async throws {
        let cache = ClipboardThumbnailCache()
        #expect(await cache.thumbnail(for: directory.appending(path: "missing.png")) == nil)
        let garbage = directory.appending(path: "garbage.png")
        try Data("not a png".utf8).write(to: garbage)
        #expect(await cache.thumbnail(for: garbage) == nil)
    }
}
