import CoreGraphics
import Testing
@testable import ScreenshotModule

/// Cropping cuts the finished canvas: the picture, what is drawn on it and any padding, all in one place.
@Suite struct MarkupRendererCropTests {
    /// Pixel (x, y) is red x, green y, so where a crop started can be read back from its first pixel.
    static func gradient(width: Int = 200, height: Int = 160) throws -> CGImage {
        try Bitmap(width: width, height: height) { x, y in Bitmap.Pixel(r: UInt8(x), g: UInt8(y), b: 0, a: 255) }.image()
    }

    static func flatten(_ image: CGImage, _ document: MarkupDocument) throws -> Bitmap {
        try Bitmap(#require(MarkupRenderer.flatten(image, document)))
    }

    func document(crop: CGRect?, annotations: [Annotation] = [], size: CGSize = CGSize(width: 200, height: 160)) -> MarkupDocument {
        var document = MarkupDocument(imageSize: size, annotations: annotations)
        document.crop = crop
        return document
    }

    @Test func theOutputIsTheCropsSizeWithTheCapturesPixels() throws {
        let output = try Self.flatten(Self.gradient(), document(crop: CGRect(x: 20, y: 30, width: 40, height: 50)))

        #expect((output.width, output.height) == (40, 50))
        #expect(output.pixel(0, 0) == Bitmap.Pixel(r: 20, g: 30, b: 0, a: 255))
        #expect(output.pixel(39, 49) == Bitmap.Pixel(r: 59, g: 79, b: 0, a: 255))
    }

    @Test func annotationsInsideTheCropKeepTheirPlaceOnThePicture() throws {
        // A box around (100, 80) of the capture: inside the crop it sits 80 and 50 pixels from the crop's corner.
        let box = Annotation.rectangle(CGRect(x: 100, y: 80, width: 30, height: 20), style: .init(color: .red, width: 4))
        let plain = try Self.flatten(Self.gradient(), document(crop: nil, annotations: [box]))
        let cropped = try Self.flatten(Self.gradient(), document(crop: CGRect(x: 20, y: 30, width: 150, height: 100), annotations: [box]))

        #expect((cropped.width, cropped.height) == (150, 100))
        for (x, y) in [(100, 80), (115, 80), (129, 90), (110, 99)] {
            #expect(cropped.pixel(x - 20, y - 30) == plain.pixel(x, y), "pixel (\(x), \(y)) of the capture")
        }
    }

    @Test func anAnnotationThatStraddlesTheEdgeIsCutThereAndAddsNoPadding() throws {
        let box = Annotation.rectangle(CGRect(x: 10, y: 10, width: 100, height: 100), style: .init(color: .red, width: 6))
        let output = try Self.flatten(Self.gradient(), document(crop: CGRect(x: 50, y: 50, width: 80, height: 80), annotations: [box]))

        #expect((output.width, output.height) == (80, 80))
        // The right and bottom edges of the box are inside the crop; the left and top ones were cut away with the rest.
        #expect(MarkupRendererTests.isRed(output.pixel(60, 40)))
        #expect(MarkupRendererTests.isRed(output.pixel(40, 60)))
        #expect(!MarkupRendererTests.isRed(output.pixel(0, 0)))
        #expect(output.pixel(0, 0) == Bitmap.Pixel(r: 50, g: 50, b: 0, a: 255))
    }

    @Test func redactionKeepsHidingWhatItCoveredInsideTheCrop() throws {
        let checkerboard = Bitmap.checkerboard(width: 200, height: 160)
        let redact = Annotation.redact(CGRect(x: 60, y: 60, width: 40, height: 40))
        let output = try Self.flatten(checkerboard.image(), document(crop: CGRect(x: 50, y: 50, width: 80, height: 80), annotations: [redact]))

        // The 40×40 square sits at (10, 10) of the crop, and no pixel in it is the capture's own.
        for y in 10..<50 {
            for x in 10..<50 { #expect(output.pixel(x, y) != checkerboard.pixel(x + 50, y + 50), "pixel (\(x), \(y)) kept its value") }
        }
        #expect(output.pixel(9, 9) == checkerboard.pixel(59, 59))
    }

    @Test func aCropPastTheCapturesEdgeIsClippedToIt() throws {
        let output = try Self.flatten(Self.gradient(), document(crop: CGRect(x: 150, y: 100, width: 300, height: 300)))
        #expect((output.width, output.height) == (50, 60))
        #expect(output.pixel(0, 0) == Bitmap.Pixel(r: 150, g: 100, b: 0, a: 255))
    }

    @Test func aCropCanTakeInThePaddingAnAnnotationGrew() throws {
        // A badge sticking 15 pixels out of the right edge adds padding there; the crop takes the last 20 columns of the
        // capture and all of that padding.
        let badge = Annotation.step(number: 1, at: CGPoint(x: 205, y: 80), radius: 10, color: .red)
        var padded = document(crop: CGRect(x: 180, y: 0, width: 35, height: 160), annotations: [badge])
        padded.canvasFill = .white

        let output = try Self.flatten(Self.gradient(), padded)

        #expect((output.width, output.height) == (35, 160))
        #expect(output.pixel(0, 0) == Bitmap.Pixel(r: 180, g: 0, b: 0, a: 255))
        #expect(output.pixel(34, 0) == .white)
    }

    @Test func aCropThatMissesTheCanvasLeavesTheWholePicture() throws {
        let output = try Self.flatten(Self.gradient(), document(crop: CGRect(x: 900, y: 900, width: 50, height: 50)))
        #expect((output.width, output.height) == (200, 160))
    }

    @Test func aLensAtTheCropsEdgeIsDrawnAsItIsWithoutTheCrop() throws {
        // The lens straddles the crop's left edge, so it samples pixels the crop does not keep; what the crop shows of it
        // is what the uncropped picture shows there.
        let lens = Annotation.magnifier(center: CGPoint(x: 60, y: 80), radius: 20, zoom: 2, style: .init(color: .blue, width: 2))
        let plain = try Self.flatten(Self.gradient(), document(crop: nil, annotations: [lens]))
        let output = try Self.flatten(Self.gradient(), document(crop: CGRect(x: 50, y: 50, width: 100, height: 60), annotations: [lens]))

        #expect((output.width, output.height) == (100, 60))
        for (x, y) in [(55, 80), (65, 70), (70, 90), (75, 80)] {
            #expect(output.pixel(x - 50, y - 50) == plain.pixel(x, y), "pixel (\(x), \(y)) of the capture")
        }
    }

    @Test func theCropFollowsTheDocumentsScaleWhenItsSizeDiffersFromThePixels() throws {
        // The document was drawn on a 100×80 capture and is applied to a 200×160 one: everything doubles, the crop too.
        let output = try Self.flatten(Self.gradient(), document(crop: CGRect(x: 10, y: 15, width: 20, height: 25), size: CGSize(width: 100, height: 80)))
        #expect((output.width, output.height) == (40, 50))
        #expect(output.pixel(0, 0) == Bitmap.Pixel(r: 20, g: 30, b: 0, a: 255))
    }
}
