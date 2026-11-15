import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct MarkupEditorModelTests {
    let image: CGImage

    init() throws {
        image = try Bitmap.filled(width: 400, height: 300).image()
    }

    func drag(_ model: MarkupEditorModel, _ points: [CGPoint], pixelsPerPoint: CGFloat = 2) {
        for point in points.dropFirst() {
            model.dragChanged(from: points[0], to: point, pixelsPerPoint: pixelsPerPoint)
        }
        model.dragEnded(from: points[0], to: points[points.count - 1], pixelsPerPoint: pixelsPerPoint)
    }

    @Test func startsWithAnEmptyDocumentAtThePixelSize() {
        let model = MarkupEditorModel(image: image)
        #expect(model.document == MarkupDocument(imageSize: CGSize(width: 400, height: 300)))
        #expect(model.preview === image)
        #expect(model.tool == .arrow && model.color == .red && model.thickness == .medium)
    }

    @Test func dragDrawsALiveDraftThenCommitsItInImagePixels() {
        let model = MarkupEditorModel(image: image)
        model.select(.rectangle)
        model.dragChanged(from: CGPoint(x: 110, y: 80), to: CGPoint(x: 10, y: 20), pixelsPerPoint: 2)
        let expected = Annotation.rectangle(CGRect(x: 10, y: 20, width: 100, height: 60), style: .init(color: .red, width: 8))
        #expect(model.draft == expected)
        #expect(model.document.annotations.isEmpty)

        model.dragEnded(from: CGPoint(x: 110, y: 80), to: CGPoint(x: 10, y: 20), pixelsPerPoint: 2)
        #expect(model.draft == nil)
        #expect(model.document.annotations == [expected])
        #expect(model.canUndo)
    }

    @Test func arrowAndRedactUseTheSelectedColourAndThickness() {
        let model = MarkupEditorModel(image: image)
        model.color = .blue
        model.thickness = .thick
        drag(model, [CGPoint(x: 5, y: 5), CGPoint(x: 50, y: 60)], pixelsPerPoint: 1.5)
        model.select(.redact)
        drag(model, [CGPoint(x: 100, y: 100), CGPoint(x: 140, y: 120)])
        #expect(model.document.annotations == [
            .arrow(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 50, y: 60), style: .init(color: .blue, width: 12)),
            .redact(CGRect(x: 100, y: 100, width: 40, height: 20)),
        ])
    }

    @Test func clicksAndTinyDragsAddNothing() {
        let model = MarkupEditorModel(image: image)
        for tool in [MarkupTool.arrow, .rectangle, .highlighter, .redact] {
            model.select(tool)
            drag(model, [CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 50)])
            drag(model, [CGPoint(x: 50, y: 50), CGPoint(x: 53, y: 52)])
        }
        model.select(.rectangle)
        drag(model, [CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 53)])
        #expect(model.document.annotations.isEmpty)
        #expect(!model.canUndo)
    }

    @Test func highlighterKeepsPointsAtLeastOneViewPointApart() {
        let model = MarkupEditorModel(image: image)
        model.select(.highlighter)
        model.color = .yellow
        drag(model, [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 6, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 11, y: 0)])
        #expect(model.document.annotations == [
            .highlighter(
                points: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 11, y: 0)],
                color: RGBAColor(r: RGBAColor.yellow.r, g: RGBAColor.yellow.g, b: RGBAColor.yellow.b, a: 0.5), width: 32
            ),
        ])
    }

    @Test func textToolPlacesAnInlineDraftAndCommitsIt() {
        let model = MarkupEditorModel(image: image)
        model.select(.text)
        drag(model, [CGPoint(x: 30, y: 40), CGPoint(x: 31, y: 41)])
        #expect(model.text?.origin == CGPoint(x: 30, y: 40))
        #expect(model.textFontSize == 48)
        #expect(model.document.annotations.isEmpty)

        model.text?.string = "Chào bạn"
        model.color = .green
        model.commitText()
        #expect(model.text == nil)
        #expect(model.document.annotations == [.text("Chào bạn", at: CGPoint(x: 30, y: 40), fontSize: 48, color: .green)])
    }

    @Test func blankTextIsDiscarded() {
        let model = MarkupEditorModel(image: image)
        model.select(.text)
        drag(model, [CGPoint(x: 30, y: 40)])
        model.text?.string = "  \n "
        model.commitText()
        #expect(model.text == nil)
        #expect(model.document.annotations.isEmpty)
    }

    @Test func cancellingTextDropsIt() {
        let model = MarkupEditorModel(image: image)
        model.select(.text)
        drag(model, [CGPoint(x: 30, y: 40)])
        model.text?.string = "Bỏ"
        model.cancelText()
        #expect(model.text == nil)
        #expect(model.document.annotations.isEmpty)
    }

    @Test func pendingTextIsCommittedByAnotherClickAToolChangeOrFinishing() {
        let model = MarkupEditorModel(image: image)
        model.select(.text)
        drag(model, [CGPoint(x: 10, y: 10)])
        model.text?.string = "một"
        drag(model, [CGPoint(x: 20, y: 20)])
        #expect(model.text?.origin == CGPoint(x: 20, y: 20))
        model.text?.string = "hai"
        model.select(.arrow)
        #expect(model.text == nil)
        #expect(model.document.annotations.compactMap(Self.textString) == ["một", "hai"])
        model.select(.text)
        drag(model, [CGPoint(x: 30, y: 30)])
        model.text?.string = "ba"
        let finished = model.finishedDocument()
        #expect(finished.annotations.map(Self.textString) == ["một", "hai", "ba"])
        #expect(model.document == finished)
        #expect(model.text == nil)
    }

    @Test func previewFollowsEditsUndoAndRedo() {
        let model = MarkupEditorModel(image: image)
        model.select(.rectangle)
        drag(model, [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 100)])
        #expect(model.preview !== image)
        #expect((model.preview.width, model.preview.height) == (400, 300))
        model.undo()
        #expect(model.preview === image)
        #expect(model.canRedo)
        model.redo()
        #expect(model.preview !== image)
        #expect(model.document.annotations.count == 1)
    }

    @Test func reopensAnExistingDocument() {
        let document = MarkupDocument(imageSize: CGSize(width: 400, height: 300), annotations: [.redact(CGRect(x: 0, y: 0, width: 50, height: 50))])
        let model = MarkupEditorModel(image: image, document: document)
        #expect(model.document == document)
        #expect(model.preview !== image)
        #expect(!model.canUndo)
    }

    @Test func theRedactToolSaysWhatItDoes() {
        #expect(MarkupTool.redact.title == "Che vùng")
    }

    static func textString(_ annotation: Annotation) -> String? {
        if case .text(let string, _, _, _) = annotation { string } else { nil }
    }
}

@Suite struct MarkupEditorModelZoomAndPanTests {
    let image: CGImage

    init() throws {
        image = try Bitmap.filled(width: 500, height: 4000).image()
    }

    @Test func defaultZoomScaleIsOneAndPanIsZero() {
        let model = MarkupEditorModel(image: image)
        #expect(model.zoomScale == 1.0)
        #expect(model.panOffset == .zero)
    }

    @Test func zoomInAndZoomOutStepCorrectly() {
        let model = MarkupEditorModel(image: image)
        let viewport = CGSize(width: 800, height: 600)
        model.zoomIn(viewSize: viewport)
        #expect(model.zoomScale == 1.25)

        model.zoomOut(viewSize: viewport)
        #expect(abs(model.zoomScale - 1.0) < 0.001)

        model.resetZoom()
        #expect(model.zoomScale == 1.0)
        #expect(model.panOffset == .zero)
    }

    @Test func magnifyClampsToAllowedRange() {
        let model = MarkupEditorModel(image: image)
        let viewport = CGSize(width: 800, height: 600)
        model.magnify(by: 100.0, viewSize: viewport)
        #expect(model.zoomScale == 32.0)

        model.magnify(by: -0.99, viewSize: viewport)
        #expect(model.zoomScale >= 0.25)
    }

    @Test func zoomToFitWidthCalculatesScaleForLongScreenshot() {
        let model = MarkupEditorModel(image: image) // 500 x 4000
        let viewport = CGSize(width: 1000, height: 800)
        // With 48pt total margins (24 on each side), available width = 1000 - 48 = 952.
        // baseScale fit is min(952/500, 752/4000) = 752/4000 = 0.188.
        // zoomToFitWidth scale is (952/500) / 0.188 = 1.904 / 0.188 ≈ 10.12.
        model.zoomToFitWidth(viewSize: viewport)
        #expect(model.zoomScale > 1.0)
        #expect(model.panOffset.width == 0)
        #expect(model.panOffset.height > 0) // Automatically aligns to top of long screenshot
    }

    @Test func panAccumulatesAndClamps() {
        let model = MarkupEditorModel(image: image)
        let viewport = CGSize(width: 800, height: 600)
        model.setZoom(2.0, viewSize: viewport)
        model.pan(by: CGSize(width: 50, height: -100), viewSize: viewport)
        #expect(model.panOffset.width == 50)
        #expect(model.panOffset.height == -100)
    }
}
