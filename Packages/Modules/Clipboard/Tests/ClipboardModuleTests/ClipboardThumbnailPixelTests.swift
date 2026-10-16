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

    // MARK: List rows

    /// Where a picture of `width` x `height` lands when it is drawn aspect-fit into a box, centred on whole pixels.
    func slotArea(width: Int, height: Int, box: CGSize) -> CGRect {
        let fit = min(box.width / CGFloat(width), box.height / CGFloat(height))
        let size = CGSize(width: (CGFloat(width) * fit).rounded(), height: (CGFloat(height) * fit).rounded())
        return CGRect(x: ((box.width - size.width) / 2).rounded(), y: ((box.height - size.height) / 2).rounded(), width: size.width, height: size.height)
    }

    /// `image` drawn into `area` of a box of `box` pixels the way a row's slot shows a picture, with high interpolation, as the pixels of
    /// that area (RGB: the pictures are opaque), leaving out the one-pixel rim, where edges are anti-aliased differently.
    func drawn(_ image: CGImage, box: CGSize, in area: CGRect) throws -> [UInt8] {
        let context = try #require(CGContext(
            data: nil, width: Int(box.width), height: Int(box.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.interpolationQuality = .high
        context.draw(image, in: area)
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var covered: [UInt8] = []
        for y in Int(area.minY) + 1..<Int(area.maxY) - 1 {
            for x in Int(area.minX) + 1..<Int(area.maxX) - 1 {
                let offset = y * context.bytesPerRow + x * 4
                covered.append(contentsOf: [pixels[offset], pixels[offset + 1], pixels[offset + 2]])
            }
        }
        return covered
    }

    /// How far apart two drawings are: the mean and the largest difference of a channel, out of 255.
    func difference(_ first: [UInt8], _ second: [UInt8]) -> (mean: Double, max: Int) {
        precondition(first.count == second.count && !first.isEmpty)
        var total = 0, largest = 0
        for index in first.indices {
            let gap = abs(Int(first[index]) - Int(second[index]))
            total += gap
            largest = max(largest, gap)
        }
        return (Double(total) / Double(first.count), largest)
    }

    @Test func aRowsPictureAtTheSmallSizeLooksLikeTheOldOneScaledIntoTheSameSlot() async throws {
        let cache = ClipboardThumbnailCache()
        let pictures = [
            try write(width: 1200, height: 800, named: "rows-noise.png"),
            try write(width: 1600, height: 900, named: "rows-wide.png"),
            try write(width: 600, height: 900, named: "rows-tall.png"),
        ]
        // The library's rows draw it in 40 x 32 points, the panel's in 34 x 30, on a screen with twice the pixels.
        for box in [CGSize(width: 80, height: 64), CGSize(width: 68, height: 60)] {
            for url in pictures {
                let old = try cgImage(#require(await cache.thumbnail(for: url, maxPixelSize: ClipboardThumbnailCache.libraryPixelSize)))
                let new = try cgImage(#require(await cache.thumbnail(for: url, maxPixelSize: ClipboardThumbnailCache.glyphPixelSize)))
                let area = slotArea(width: new.width, height: new.height, box: box)
                // What the slot would show if the picture were scaled once, straight from the file, to the pixels it covers.
                let ideal = try reference(url, size: Int(max(area.width, area.height)))

                let oldInSlot = try drawn(old, box: box, in: area)
                let newInSlot = try drawn(new, box: box, in: area)
                let idealInSlot = try drawn(ideal, box: box, in: area)
                let sameAsOld = difference(oldInSlot, newInSlot)
                let oldFromIdeal = difference(oldInSlot, idealInSlot)
                let newFromIdeal = difference(newInSlot, idealInSlot)
                print("ROWS \(url.lastPathComponent) \(Int(box.width))x\(Int(box.height)): new vs old mean \(sameAsOld.mean) max \(sameAsOld.max); old vs ideal mean \(oldFromIdeal.mean) max \(oldFromIdeal.max); new vs ideal mean \(newFromIdeal.mean) max \(newFromIdeal.max)")

                // Close to what the 400 px picture gave, and no farther from a single clean scaling than that was.
                #expect(sameAsOld.mean < 8, "\(url.lastPathComponent) \(box)")
                #expect(newFromIdeal.mean <= oldFromIdeal.mean + 0.5, "\(url.lastPathComponent) \(box)")
            }
        }
    }
}
