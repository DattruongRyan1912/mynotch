import CoreGraphics
import Foundation
@testable import ScreenshotModule
import Testing

@Suite("StudioFrame Tests")
struct StudioFrameTests {
    private func makeTestImage(width: Int = 100, height: Int = 60) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var pixelData = [UInt8](repeating: 200, count: width * height * 4)
        for i in stride(from: 3, to: pixelData.count, by: 4) {
            pixelData[i] = 255
        }
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        return context.makeImage()!
    }

    @Test func inactiveConfigReturnsOriginalImage() {
        let img = makeTestImage()
        let config = StudioFrameConfig(backdrop: .none, padding: 48)
        let result = StudioFrameRenderer.render(img, config: config)
        #expect(result === img)
    }

    @Test func renderExpandsDimensionsByDoublePadding() {
        let img = makeTestImage(width: 80, height: 50)
        let config = StudioFrameConfig(backdrop: .tahoe, padding: 24, cornerRadius: 12, shadowRadius: 16)
        let result = StudioFrameRenderer.render(img, config: config)
        #expect(result != nil)
        #expect(result?.width == 80 + 2 * 24)
        #expect(result?.height == 50 + 2 * 24)
    }

    @Test func rendersDifferentBackdropPresets() {
        let img = makeTestImage(width: 60, height: 40)
        for backdrop in [StudioBackdrop.tahoe, .sunset, .ocean, .midnight, .graphite, .zincDark, .snowWhite, .transparent] {
            let config = StudioFrameConfig(backdrop: backdrop, padding: 20, cornerRadius: 10, shadowRadius: 8)
            let result = StudioFrameRenderer.render(img, config: config)
            #expect(result != nil)
            #expect(result?.width == 100)
            #expect(result?.height == 80)
        }
    }

    @Test func markupRendererFlattenAppliesStudioFrame() {
        let img = makeTestImage(width: 120, height: 80)
        var doc = MarkupDocument(imageSize: CGSize(width: 120, height: 80))
        doc.studioFrame = StudioFrameConfig(backdrop: .sunset, padding: 30, cornerRadius: 14, shadowRadius: 20)

        let flattened = MarkupRenderer.flatten(img, doc)
        #expect(flattened != nil)
        #expect(flattened?.width == 120 + 2 * 30)
        #expect(flattened?.height == 80 + 2 * 30)
    }

    @Test func markupEditorModelStudioFrameUndoRedoAndEdits() {
        let img = makeTestImage(width: 100, height: 60)
        let model = MarkupEditorModel(image: img)
        #expect(!model.document.hasEdits)
        #expect(model.outputBounds.width == 100)

        let config = StudioFrameConfig(backdrop: .tahoe, padding: 24, cornerRadius: 12, shadowRadius: 16)
        model.setStudioFrame(config)

        #expect(model.document.hasEdits)
        #expect(model.document.studioFrame == config)
        #expect(model.outputBounds.width == CGFloat(100 + 2 * 24))
        #expect(model.outputBounds.height == CGFloat(60 + 2 * 24))

        // Undo restores plain capture
        model.undo()
        #expect(!model.document.hasEdits)
        #expect(model.outputBounds.width == 100.0)

        // Redo reapplies studio frame
        model.redo()
        #expect(model.document.hasEdits)
        #expect(model.outputBounds.width == CGFloat(100 + 2 * 24))
    }

    @Test func documentJSONRoundTripPreservesStudioFrame() throws {
        var doc = MarkupDocument(imageSize: CGSize(width: 200, height: 150))
        doc.studioFrame = StudioFrameConfig(backdrop: .midnight, padding: 48, cornerRadius: 20, shadowRadius: 32)

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(MarkupDocument.self, from: data)

        #expect(decoded.imageSize == CGSize(width: 200, height: 150))
        #expect(decoded.studioFrame == doc.studioFrame)
        #expect(decoded.hasEdits)
    }
}
