import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ClipboardModule

/// What a thumbnail looks like has not changed: it is the picture ImageIO makes at that size, in the colour space of the file, upright,
/// never enlarged. The reference is built here from the options the cache used before it was shared and queued, so these tests catch
/// any later change to how a thumbnail is made.
@Suite final class ClipboardThumbnailPixelTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "ClipboardThumbnailPixelTests-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A picture with detail in it, so a different way of scaling would give different pixels: a gradient with noise from a fixed seed.
    func write(
        width: Int, height: Int, named name: String, type: UTType = .png, space: CFString = CGColorSpace.sRGB,
        orientation: Int? = nil
    ) throws -> URL {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: space)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var seed: UInt32 = 2_463_534_242
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let offset = y * context.bytesPerRow + x * 4
                let noise = Int(seed >> 28)
                pixels[offset] = UInt8(truncatingIfNeeded: x * 255 / width + noise)
                pixels[offset + 1] = UInt8(truncatingIfNeeded: y * 255 / height + noise)
                pixels[offset + 2] = UInt8(truncatingIfNeeded: (x + y) % 256)
                pixels[offset + 3] = 255
            }
        }
        let image = try #require(context.makeImage())
        let url = directory.appending(path: name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        let properties = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// The thumbnail as it was made before: ImageIO's own, with these options.
    func reference(_ url: URL, size: Int) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
        ]
        return try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary))
    }

    func cgImage(_ image: NSImage) throws -> CGImage {
        var rect = CGRect(origin: .zero, size: image.size)
        return try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
    }

    func bytes(_ image: CGImage) throws -> Data {
        try #require(image.dataProvider?.data as Data?)
    }

    @Test func aThumbnailIsTheSamePixelsAsImageIOMakesAtThatSizeForEverySizeTheCardsAskFor() async throws {
        let url = try write(width: 1200, height: 800, named: "detail.png")
        let cache = ClipboardThumbnailCache()
        for size in [ClipboardThumbnailCache.defaultPixelSize, ClipboardThumbnailCache.libraryPixelSize, ClipboardThumbnailCache.glyphPixelSize] {
            let thumbnail = try cgImage(#require(await cache.thumbnail(for: url, maxPixelSize: size)))
            let expected = try reference(url, size: size)

            #expect(max(thumbnail.width, thumbnail.height) == size)
            #expect(thumbnail.width == expected.width && thumbnail.height == expected.height)
            #expect(thumbnail.bitsPerPixel == expected.bitsPerPixel && thumbnail.bytesPerRow == expected.bytesPerRow)
            #expect(thumbnail.alphaInfo == expected.alphaInfo)
            #expect(try bytes(thumbnail) == bytes(expected), "size \(size)")
        }
    }

    @Test func aThumbnailKeepsTheAspectRatioAndIsNeverEnlarged() async throws {
        let cache = ClipboardThumbnailCache()
        let wide = try #require(await cache.thumbnail(for: write(width: 600, height: 300, named: "wide.png")))
        #expect(wide.size == NSSize(width: 240, height: 120))
        let glyph = try #require(await cache.thumbnail(for: write(width: 600, height: 300, named: "wide.png"), maxPixelSize: ClipboardThumbnailCache.glyphPixelSize))
        #expect(glyph.size == NSSize(width: 96, height: 48))
        let small = try #require(await cache.thumbnail(for: write(width: 40, height: 80, named: "small.png"), maxPixelSize: ClipboardThumbnailCache.libraryPixelSize))
        #expect(small.size == NSSize(width: 40, height: 80))
    }

    @Test func aWideGamutPictureKeepsItsColourSpace() async throws {
        let url = try write(width: 500, height: 300, named: "p3.png", space: CGColorSpace.displayP3)
        let cache = ClipboardThumbnailCache()

        let thumbnail = try cgImage(#require(await cache.thumbnail(for: url)))

        #expect(thumbnail.colorSpace?.name as String? == CGColorSpace.displayP3 as String)
        let expected = try reference(url, size: ClipboardThumbnailCache.defaultPixelSize)
        #expect(thumbnail.colorSpace?.name == expected.colorSpace?.name)
        #expect(try bytes(thumbnail) == bytes(expected))
    }

    @Test func anSRGBPictureStaysSRGB() async throws {
        let url = try write(width: 500, height: 300, named: "srgb.png")
        let thumbnail = try cgImage(#require(await ClipboardThumbnailCache().thumbnail(for: url)))
        #expect(thumbnail.colorSpace?.name as String? == CGColorSpace.sRGB as String)
    }

    @Test func aPhotoTakenSidewaysComesOutUpright() async throws {
        // Stored 600 wide and 400 high, with the tag that says to turn it a quarter: shown it is 400 wide and 600 high.
        let url = try write(width: 600, height: 400, named: "sideways.jpg", type: .jpeg, orientation: 6)
        let cache = ClipboardThumbnailCache()

        let thumbnail = try #require(await cache.thumbnail(for: url, maxPixelSize: ClipboardThumbnailCache.libraryPixelSize))
        let expected = try reference(url, size: ClipboardThumbnailCache.libraryPixelSize)

        #expect(thumbnail.size.height > thumbnail.size.width)
        #expect(Int(thumbnail.size.width) == expected.width && Int(thumbnail.size.height) == expected.height)
        #expect(try bytes(cgImage(thumbnail)) == bytes(expected))
    }

    @Test func aPictureHeldInMemoryGivesTheSamePixelsAsItsFile() async throws {
        let url = try write(width: 800, height: 500, named: "memory.png")
        let data = try Data(contentsOf: url)
        let openImages = ClipboardOpenImages()
        openImages.add(data, named: "memory.png", to: UUID())
        let cache = ClipboardThumbnailCache()
        cache.openImages = openImages

        let fromMemory = try cgImage(#require(await cache.thumbnail(for: ClipboardOpenImages.url(forFileName: "memory.png"))))
        let expected = try reference(url, size: ClipboardThumbnailCache.defaultPixelSize)

        #expect(try bytes(fromMemory) == bytes(expected))
    }

    /// The same drawn at the size the card shows it at: a card's thumbnail scaled down to its slot looks like the reference scaled the same.
    @Test func drawnAtTheDisplaySizeItMatchesTheReference() async throws {
        let url = try write(width: 1000, height: 600, named: "drawn.png")
        let cache = ClipboardThumbnailCache()
        let thumbnail = try cgImage(#require(await cache.thumbnail(for: url)))
        let expected = try reference(url, size: ClipboardThumbnailCache.defaultPixelSize)

        // The notch's card draws it about 96 points wide, at twice the pixels.
        func drawn(_ image: CGImage) throws -> Data {
            let context = try #require(CGContext(
                data: nil, width: 192, height: 116, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 192, height: 116))
            return try #require(context.makeImage()?.dataProvider?.data as Data?)
        }

        #expect(try drawn(thumbnail) == drawn(expected))
    }
}
