import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct MarkupRendererTests {
    static func flatten(_ bitmap: Bitmap, _ annotations: [Annotation], imageSize: CGSize? = nil) throws -> Bitmap {
        let size = imageSize ?? CGSize(width: bitmap.width, height: bitmap.height)
        let image = try bitmap.image()
        let output = try #require(MarkupRenderer.flatten(image, MarkupDocument(imageSize: size, annotations: annotations)))
        #expect((output.width, output.height) == (image.width, image.height))
        return try Bitmap(output)
    }

    static func isRed(_ pixel: Bitmap.Pixel) -> Bool { pixel.r > 200 && pixel.g < 100 && pixel.b < 100 }
    static func isDark(_ pixel: Bitmap.Pixel) -> Bool { pixel.r < 100 && pixel.g < 100 && pixel.b < 100 }

    @Test func outputKeepsThePixelSize() throws {
        let image = try Bitmap.filled(width: 317, height: 211).image()
        let output = try #require(MarkupRenderer.flatten(image, MarkupDocument(imageSize: CGSize(width: 317, height: 211))))
        #expect((output.width, output.height) == (317, 211))
        let wide = try Bitmap.filled(width: 64, height: 9).image()
        let annotated = MarkupDocument(imageSize: CGSize(width: 64, height: 9), annotations: [.redact(CGRect(x: 0, y: 0, width: 64, height: 9))])
        let wideOutput = try #require(MarkupRenderer.flatten(wide, annotated))
        #expect((wideOutput.width, wideOutput.height) == (64, 9))
    }

    @Test func rectangleStrokesItsBorderOnly() throws {
        let rect = CGRect(x: 40, y: 20, width: 120, height: 60)
        let output = try Self.flatten(.filled(width: 200, height: 150), [.rectangle(rect, style: .init(color: .red, width: 6))])
        #expect(Self.isRed(output.pixel(40, 50)))
        #expect(Self.isRed(output.pixel(159, 50)))
        #expect(Self.isRed(output.pixel(100, 20)))
        #expect(Self.isRed(output.pixel(100, 79)))
        #expect(output.pixel(100, 50) == .white)
        #expect(output.pixel(30, 50) == .white)
        // Top-left origin: a y-up renderer would put the edges at y = 70 and y = 130.
        #expect(output.pixel(100, 70) == .white)
        #expect(output.pixel(100, 130) == .white)
    }

    @Test func arrowHasAFilledHeadAtItsTip() throws {
        let arrow = Annotation.arrow(from: CGPoint(x: 20, y: 100), to: CGPoint(x: 180, y: 100), style: .init(color: .red, width: 4))
        let output = try Self.flatten(.filled(width: 200, height: 200), [arrow])
        #expect(Self.isRed(output.pixel(60, 100)))
        #expect(Self.isRed(output.pixel(177, 100)))
        // The head is wider than the shaft…
        #expect(Self.isRed(output.pixel(165, 105)))
        #expect(Self.isRed(output.pixel(165, 94)))
        #expect(output.pixel(60, 105) == .white)
        // …and nothing sticks out past the tip.
        #expect(output.pixel(184, 100) == .white)
    }

    @Test func textIsDrawnBelowAndRightOfItsAnchor() throws {
        let output = try Self.flatten(.filled(width: 300, height: 120), [
            .text("Hello", at: CGPoint(x: 20, y: 30), fontSize: 40, color: .black),
        ])
        var inked = 0
        for y in 0..<output.height {
            for x in 0..<output.width where Self.isDark(output.pixel(x, y)) {
                inked += 1
                #expect((18..<280).contains(x) && (28..<86).contains(y), "ink outside the text box at (\(x), \(y))")
            }
        }
        #expect(inked > 100)
    }

    @Test func textLinesStackDownwards() throws {
        let output = try Self.flatten(.filled(width: 300, height: 160), [
            .text("Hello\nWorld", at: CGPoint(x: 20, y: 20), fontSize: 30, color: .black),
        ])
        let rows = (0..<output.height).filter { y in (0..<output.width).contains { Self.isDark(output.pixel($0, y)) } }
        #expect(rows.contains { (20..<56).contains($0) })
        #expect(rows.contains { (60..<100).contains($0) })
        #expect(rows.allSatisfy { (18..<100).contains($0) })
    }

    @Test func highlighterMultipliesWithRoundCaps() throws {
        let grey = Bitmap.Pixel(r: 128, g: 128, b: 128, a: 255)
        let background = Bitmap(width: 200, height: 100) { x, _ in x < 100 ? .white : grey }
        let output = try Self.flatten(background, [
            .highlighter(points: [CGPoint(x: 20, y: 50), CGPoint(x: 180, y: 50)], color: .yellow, width: 20),
        ])
        let onWhite = output.pixel(50, 50)
        #expect(onWhite.r > 240 && onWhite.b < 20)
        // Multiply keeps the grey's red channel; a normal blend would paint it fully yellow.
        let onGrey = output.pixel(150, 50)
        #expect((110...145).contains(onGrey.r) && onGrey.b < 20)
        #expect(output.pixel(13, 50).b < 50)
        #expect(output.pixel(20, 64) == .white)
        #expect(output.pixel(50, 30) == .white)
    }

    @Test func redactPixelatesEveryPixelInUniformBlocks() throws {
        let original = Bitmap.checkerboard(width: 240, height: 180)
        let region = (x: 30, y: 40, width: 100, height: 50)
        let output = try Self.flatten(original, [.redact(CGRect(x: region.x, y: region.y, width: region.width, height: region.height))])
        let block = MarkupRenderer.redactBlockSize(for: CGSize(width: 240, height: 180))
        #expect(block == 12)
        for y in region.y..<(region.y + region.height) {
            for x in region.x..<(region.x + region.width) {
                #expect(output.pixel(x, y) != original.pixel(x, y), "pixel (\(x), \(y)) kept its original value")
                let blockOrigin = (x: region.x + (x - region.x) / block * block, y: region.y + (y - region.y) / block * block)
                #expect(output.pixel(x, y) == output.pixel(blockOrigin.x, blockOrigin.y), "block at \(blockOrigin) is not uniform")
            }
        }
        for x in region.x..<(region.x + region.width) {
            #expect(output.pixel(x, region.y - 1) == original.pixel(x, region.y - 1))
            #expect(output.pixel(x, region.y + region.height) == original.pixel(x, region.y + region.height))
        }
        for y in region.y..<(region.y + region.height) {
            #expect(output.pixel(region.x - 1, y) == original.pixel(region.x - 1, y))
            #expect(output.pixel(region.x + region.width, y) == original.pixel(region.x + region.width, y))
        }
    }

    @Test func redactCoversPartiallySelectedPixelsAndStaysInsideTheImage() throws {
        let original = Bitmap.checkerboard(width: 240, height: 180)
        let output = try Self.flatten(original, [
            .redact(CGRect(x: 10.5, y: 10.5, width: 20, height: 20)),
            .redact(CGRect(x: 230, y: 170, width: 50, height: 50)),
        ])
        #expect(output.pixel(10, 10) != original.pixel(10, 10))
        #expect(output.pixel(30, 30) != original.pixel(30, 30))
        #expect(output.pixel(9, 10) == original.pixel(9, 10))
        #expect(output.pixel(31, 31) == original.pixel(31, 31))
        #expect(output.pixel(239, 179) != original.pixel(239, 179))
        #expect(output.pixel(229, 179) == original.pixel(229, 179))
    }

    @Test func redactAlsoHidesEarlierAnnotations() throws {
        let output = try Self.flatten(.filled(width: 200, height: 150), [
            .rectangle(CGRect(x: 40, y: 20, width: 120, height: 60), style: .init(color: .red, width: 6)),
            .redact(CGRect(x: 36, y: 36, width: 24, height: 24)),
        ])
        #expect(!Self.isRed(output.pixel(40, 50)))
        #expect(Self.isRed(output.pixel(159, 50)))
    }

    @Test func blockSizeGrowsWithTheImage() {
        #expect(MarkupRenderer.redactBlockSize(for: CGSize(width: 240, height: 180)) == 12)
        #expect(MarkupRenderer.redactBlockSize(for: CGSize(width: 3024, height: 1964)) == 65)
        #expect(MarkupRenderer.redactBlockSize(for: CGSize(width: 5000, height: 300)) == 12)
    }

    @Test func annotationsScaleWhenTheDocumentSizeDiffers() throws {
        let original = Bitmap(width: 200, height: 150) { x, y in Bitmap.Pixel(r: UInt8(x), g: UInt8(y), b: 255, a: 255) }
        let output = try Self.flatten(original, [
            .rectangle(CGRect(x: 20, y: 10, width: 60, height: 30), style: .init(color: .red, width: 3)),
            .redact(CGRect(x: 60, y: 50, width: 20, height: 20)),
        ], imageSize: CGSize(width: 100, height: 75))
        // The redaction covers (120, 100) to (160, 140) in pixels.
        #expect(output.pixel(120, 100) != original.pixel(120, 100))
        #expect(output.pixel(159, 139) != original.pixel(159, 139))
        #expect(output.pixel(119, 100) == original.pixel(119, 100))
        #expect(output.pixel(160, 139) == original.pixel(160, 139))
        #expect(Self.isRed(output.pixel(40, 50)))
        #expect(Self.isRed(output.pixel(100, 20)))
        #expect(output.pixel(100, 50) == original.pixel(100, 50))
        #expect(output.pixel(25, 15) == original.pixel(25, 15))
    }

    @Test func redactMergesALeftoverStripNarrowerThanHalfABlockIntoThePreviousBlock() throws {
        let original = Bitmap(width: 240, height: 180) { x, y in Bitmap.Pixel(r: UInt8(x), g: UInt8(y), b: 0, a: 255) }
        // 12 px blocks: 25 = 2 × 12 + 1, so the last row and column are one pixel wide.
        let output = try Self.flatten(original, [.redact(CGRect(x: 0, y: 0, width: 25, height: 25))])
        for (x, y) in [(24, 24), (24, 0), (0, 24), (24, 11)] {
            #expect(output.pixel(x, y) != original.pixel(x, y), "pixel (\(x), \(y)) kept its original value")
        }
        #expect(output.pixel(24, 24) == output.pixel(12, 12))
        #expect(output.pixel(24, 5) == output.pixel(12, 5))
        #expect(output.pixel(5, 24) == output.pixel(5, 12))
        // The first block is still a block of its own.
        #expect(output.pixel(5, 5) != output.pixel(12, 12))
    }

    @Test func redactKeepsALeftoverStripOfAtLeastHalfABlockAsItsOwnBlock() throws {
        let original = Bitmap(width: 240, height: 180) { x, y in Bitmap.Pixel(r: UInt8(x), g: UInt8(y), b: 0, a: 255) }
        // 30 = 2 × 12 + 6.
        let output = try Self.flatten(original, [.redact(CGRect(x: 0, y: 0, width: 30, height: 12))])
        #expect(output.pixel(24, 5) == output.pixel(29, 5))
        #expect(output.pixel(24, 5) != output.pixel(23, 5))
    }

    @Test func aRedactionSmallerThanHalfABlockIsStillOneBlock() throws {
        let original = Bitmap(width: 240, height: 180) { x, y in Bitmap.Pixel(r: UInt8(x), g: UInt8(y), b: 0, a: 255) }
        let output = try Self.flatten(original, [.redact(CGRect(x: 50, y: 50, width: 4, height: 3))])
        #expect(output.pixel(50, 50) == output.pixel(53, 52))
    }
}
