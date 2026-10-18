import CoreGraphics
import Testing
@testable import ScreenshotModule

/// The crop tool in the editor's model: dragging a frame, applying it as one undoable step, and what a crop does to
/// the annotations and to the canvas the other tools draw on.
@Suite struct MarkupEditorModelCropTests {
    let image: CGImage
    let canvas = CGRect(x: 0, y: 0, width: 400, height: 300)

    init() throws {
        image = try Bitmap.filled(width: 400, height: 300).image()
    }

    /// A drag from the first point to the last, one point per step, as the view reports it.
    func drag(_ model: MarkupEditorModel, _ points: [CGPoint], pixelsPerPoint: CGFloat = 1) {
        for point in points.dropFirst() {
            model.dragChanged(from: points[0], to: point, pixelsPerPoint: pixelsPerPoint)
        }
        model.dragEnded(from: points[0], to: points[points.count - 1], pixelsPerPoint: pixelsPerPoint)
    }

    /// A model with the crop tool up and a frame at `rect`, made by dragging.
    func cropping(_ rect: CGRect, annotations: [Annotation] = []) -> MarkupEditorModel {
        let model = MarkupEditorModel(image: image, document: MarkupDocument(imageSize: canvas.size, annotations: annotations))
        model.select(.crop)
        drag(model, [rect.origin, CGPoint(x: rect.maxX, y: rect.maxY)])
        return model
    }

    // MARK: The tool

    @Test func theCropToolIsLastInTheToolbarAndTakesNoStyle() {
        #expect(MarkupTool.allCases.last == .crop)
        #expect(MarkupTool.crop.title == "Cắt")
        #expect(!MarkupTool.crop.usesStyle)
        #expect(MarkupTool.crop.annotation(through: [.zero, CGPoint(x: 90, y: 90)], options: DrawingOptions(color: .red, thickness: .medium, pixelsPerPoint: 1)) == nil)
        #expect(MarkupTool.crop.hint.contains("Return") && MarkupTool.crop.hint.contains("Esc"))
    }

    @Test func selectingItStartsWithoutAFrameShowingTheWholeCanvas() {
        let model = MarkupEditorModel(image: image)
        model.select(.crop)
        #expect(model.isCropping)
        #expect(model.cropFrame == nil)
        #expect(model.cropAspect == .free)
        #expect(model.displayedBounds == canvas)
    }

    // MARK: Dragging

    @Test func draggingOnTheImageMakesAFrameLiveAndLeavesTheDocumentAlone() {
        let model = MarkupEditorModel(image: image)
        model.select(.crop)

        model.dragChanged(from: CGPoint(x: 50, y: 40), to: CGPoint(x: 250, y: 190), pixelsPerPoint: 1)
        #expect(model.cropFrame == CGRect(x: 50, y: 40, width: 200, height: 150))
        model.dragEnded(from: CGPoint(x: 50, y: 40), to: CGPoint(x: 250, y: 190), pixelsPerPoint: 1)

        #expect(model.cropFrame == CGRect(x: 50, y: 40, width: 200, height: 150))
        #expect(model.document.crop == nil)
        #expect(!model.canUndo)
        #expect(model.draft == nil)
    }

    @Test func aClickMakesNoFrame() {
        let model = MarkupEditorModel(image: image)
        model.select(.crop)
        drag(model, [CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 100)])
        drag(model, [CGPoint(x: 100, y: 100), CGPoint(x: 103, y: 102)])
        #expect(model.cropFrame == nil)
    }

    @Test func theFrameStaysInsideTheImageWhateverTheDragDoes() {
        let model = MarkupEditorModel(image: image)
        model.select(.crop)
        drag(model, [CGPoint(x: -40, y: 20), CGPoint(x: 700, y: 900)])
        #expect(model.cropFrame == CGRect(x: 0, y: 20, width: 400, height: 280))
    }

    @Test func draggingAHandleResizesAndInsideMoves() {
        let model = cropping(CGRect(x: 100, y: 100, width: 200, height: 100))
        // The bottom-right corner, grabbed 3 pixels off the corner, pulled 40 right and 20 down.
        drag(model, [CGPoint(x: 303, y: 198), CGPoint(x: 343, y: 218)])
        #expect(model.cropFrame == CGRect(x: 100, y: 100, width: 240, height: 120))
        // The middle moves the frame without resizing it.
        drag(model, [CGPoint(x: 200, y: 160), CGPoint(x: 190, y: 170)])
        #expect(model.cropFrame == CGRect(x: 90, y: 110, width: 240, height: 120))
        // The left edge.
        drag(model, [CGPoint(x: 90, y: 170), CGPoint(x: 60, y: 170)])
        #expect(model.cropFrame == CGRect(x: 60, y: 110, width: 270, height: 120))
    }

    @Test func handlesReachTenViewPointsWhateverTheZoom() {
        let start = CGRect(x: 100, y: 100, width: 200, height: 100)
        // 16 pixels left of the left edge is 16 points at 1 pixel per point: out of reach, so the drag makes a new frame.
        let outside = cropping(start)
        drag(outside, [CGPoint(x: 84, y: 150), CGPoint(x: 30, y: 200)], pixelsPerPoint: 1)
        #expect(outside.cropFrame == CGRect(x: 30, y: 150, width: 54, height: 50))
        // The same 16 pixels are 8 points at 2 pixels per point: the left handle, which moves that edge by the drag.
        let handle = cropping(start)
        drag(handle, [CGPoint(x: 84, y: 150), CGPoint(x: 30, y: 200)], pixelsPerPoint: 2)
        #expect(handle.cropFrame == CGRect(x: 46, y: 100, width: 254, height: 100))
    }

    @Test func draggingOutsideTheFrameMakesANewOne() {
        let model = cropping(CGRect(x: 100, y: 100, width: 100, height: 100))
        drag(model, [CGPoint(x: 300, y: 50), CGPoint(x: 380, y: 130)])
        #expect(model.cropFrame == CGRect(x: 300, y: 50, width: 80, height: 80))
    }

    // MARK: Ratio

    @Test func aPresetBeforeAnyFrameMakesTheBiggestCentredOne() throws {
        let model = MarkupEditorModel(image: image)
        model.select(.crop)
        model.setCropAspect(.square)
        #expect(model.cropAspect == .square)
        #expect(model.cropFrame == CGRect(x: 50, y: 0, width: 300, height: 300))

        let original = MarkupEditorModel(image: image)
        original.select(.crop)
        original.setCropAspect(.original)
        let frame = try #require(original.cropFrame)
        #expect(abs(frame.width - 400) < 0.01 && abs(frame.height - 300) < 0.01)
    }

    @Test func aPresetReshapesTheFrameThereIsAroundItsMiddle() {
        let model = cropping(CGRect(x: 100, y: 100, width: 200, height: 100))
        model.setCropAspect(.square)
        #expect(model.cropFrame == CGRect(x: 150, y: 100, width: 100, height: 100))
        model.setCropAspect(.free)
        #expect(model.cropFrame == CGRect(x: 150, y: 100, width: 100, height: 100))
    }

    @Test func aLockedRatioHoldsWhileDraggingAndResizing() throws {
        let model = MarkupEditorModel(image: image)
        model.select(.crop)
        model.setCropAspect(.sixteenNine)
        let start = try #require(model.cropFrame)
        // The bottom-right corner pulled in by exactly the ratio.
        drag(model, [CGPoint(x: start.maxX, y: start.maxY), CGPoint(x: start.maxX - 160, y: start.maxY - 90)])
        let resized = try #require(model.cropFrame)
        #expect(resized.origin == start.origin)
        #expect(abs(resized.width - 240) < 0.01)
        #expect(abs(resized.width / resized.height - 16.0 / 9.0) < 0.001)

        // A new frame made outside it keeps the ratio too.
        drag(model, [CGPoint(x: 300, y: 250), CGPoint(x: 380, y: 290)])
        let made = try #require(model.cropFrame)
        #expect(made.origin == CGPoint(x: 300, y: 250))
        #expect(abs(made.width / made.height - 16.0 / 9.0) < 0.001)
    }

    @Test func theOriginalRatioIsTheCapturesNotTheCanvas() throws {
        let badge = Annotation.step(number: 1, at: CGPoint(x: 395, y: 100), radius: 20, color: .red)
        let model = MarkupEditorModel(image: image, document: MarkupDocument(imageSize: canvas.size, annotations: [badge]))
        model.select(.crop)
        model.setCropAspect(.original)
        let frame = try #require(model.cropFrame)
        #expect(abs(frame.width / frame.height - 400.0 / 300.0) < 0.01)
    }

    // MARK: Applying

    @Test func applyingCutsThePictureAsOneUndoableStep() throws {
        let model = cropping(CGRect(x: 50, y: 40, width: 200, height: 150))

        model.applyCrop()

        #expect(model.document.crop == CGRect(x: 50, y: 40, width: 200, height: 150))
        #expect((model.preview.width, model.preview.height) == (200, 150))
        #expect(model.canvasSize == CGSize(width: 200, height: 150))
        #expect(model.canvasOrigin == CGPoint(x: 50, y: 40))
        #expect(!model.isCropping)
        #expect(model.cropFrame == nil)
        #expect(model.tool == .arrow)

        model.undo()
        #expect(model.document.crop == nil)
        #expect(model.preview === image)
        #expect(model.canvasSize == CGSize(width: 400, height: 300))
        #expect(!model.canUndo)

        model.redo()
        #expect((model.preview.width, model.preview.height) == (200, 150))
    }

    @Test func applyingGoesBackToTheToolThatWasInUse() {
        let model = MarkupEditorModel(image: image)
        model.select(.rectangle)
        model.select(.crop)
        drag(model, [CGPoint(x: 10, y: 10), CGPoint(x: 210, y: 160)])
        model.applyCrop()
        #expect(model.tool == .rectangle)
    }

    @Test func theCroppedPreviewHoldsThePicturesPixels() throws {
        let gradient = try Bitmap(width: 400, height: 300) { x, y in Bitmap.Pixel(r: UInt8(x / 2), g: UInt8(y / 2), b: 9, a: 255) }.image()
        let model = MarkupEditorModel(image: gradient)
        model.select(.crop)
        drag(model, [CGPoint(x: 100, y: 60), CGPoint(x: 300, y: 200)])
        model.applyCrop()

        let preview = try Bitmap(model.preview)
        #expect((preview.width, preview.height) == (200, 140))
        #expect(preview.pixel(0, 0) == Bitmap.Pixel(r: 50, g: 30, b: 9, a: 255))
    }

    @Test func aFrameThatIsTheWholeCanvasIsNoCropAndNoStep() {
        let model = cropping(canvas)
        model.applyCrop()
        #expect(model.document.crop == nil)
        #expect(!model.canUndo)
    }

    @Test func applyingWithoutAFrameChangesNothing() {
        let model = MarkupEditorModel(image: image)
        model.select(.crop)
        model.applyCrop()
        #expect(model.document.crop == nil)
        #expect(!model.canUndo)
        #expect(!model.isCropping)
    }

    @Test func applyingTheSameCropAgainAddsNoStep() {
        let model = cropping(CGRect(x: 50, y: 40, width: 200, height: 150))
        model.applyCrop()
        model.select(.crop)
        // Entering the tool again starts from the crop that is there, so applying at once changes nothing.
        #expect(model.cropFrame == CGRect(x: 50, y: 40, width: 200, height: 150))
        model.applyCrop()
        model.undo()
        #expect(model.document.crop == nil)
        #expect(!model.canUndo)
    }

    // MARK: Annotations

    @Test func annotationsOutsideTheCropAreCutWithItAndTheOthersKeepTheirPlace() {
        let inside = Annotation.rectangle(CGRect(x: 120, y: 80, width: 60, height: 40), style: .init(color: .red, width: 4))
        let outside = Annotation.rectangle(CGRect(x: 300, y: 220, width: 60, height: 40), style: .init(color: .red, width: 4))
        let hidden = Annotation.redact(CGRect(x: 10, y: 10, width: 30, height: 30))
        let model = cropping(CGRect(x: 100, y: 60, width: 200, height: 150), annotations: [inside, outside, hidden])

        model.applyCrop()

        #expect(model.document.annotations == [inside])
        model.undo()
        #expect(model.document.annotations == [inside, outside, hidden])
        #expect(model.document.crop == nil)
    }

    @Test func anAnnotationThatReachesIntoTheCropIsKept() {
        let straddling = Annotation.rectangle(CGRect(x: 50, y: 50, width: 100, height: 100), style: .init(color: .red, width: 4))
        let redaction = Annotation.redact(CGRect(x: 280, y: 190, width: 60, height: 60))
        let model = cropping(CGRect(x: 100, y: 60, width: 200, height: 150), annotations: [straddling, redaction])

        model.applyCrop()

        #expect(model.document.annotations == [straddling, redaction])
    }

    @Test func stepBadgesAreRenumberedWhenOneIsCutAway() {
        let steps: [Annotation] = [
            .step(number: 1, at: CGPoint(x: 150, y: 100), radius: 10, color: .red),
            .step(number: 2, at: CGPoint(x: 350, y: 280), radius: 10, color: .red),
            .step(number: 3, at: CGPoint(x: 200, y: 120), radius: 10, color: .red),
        ]
        let model = cropping(CGRect(x: 100, y: 60, width: 200, height: 150), annotations: steps)

        model.applyCrop()

        #expect(model.document.annotations == [
            .step(number: 1, at: CGPoint(x: 150, y: 100), radius: 10, color: .red),
            .step(number: 2, at: CGPoint(x: 200, y: 120), radius: 10, color: .red),
        ])
    }

    @Test func theSavedPictureShowsOnlyWhatSurvivedTheCut() throws {
        let inside = Annotation.rectangle(CGRect(x: 120, y: 80, width: 60, height: 40), style: .init(color: .red, width: 4))
        let outside = Annotation.rectangle(CGRect(x: 300, y: 220, width: 60, height: 40), style: .init(color: .red, width: 4))
        let model = cropping(CGRect(x: 100, y: 60, width: 200, height: 150), annotations: [inside, outside])
        model.applyCrop()

        let preview = try Bitmap(model.preview)

        #expect((preview.width, preview.height) == (200, 150))
        // The surviving box's top edge is 20 pixels in; nothing of the cut one is left in the corner it would have been in.
        #expect(MarkupRendererTests.isRed(preview.pixel(50, 20)))
        for y in 100..<150 {
            for x in 150..<200 { #expect(preview.pixel(x, y) == .white) }
        }
    }

    // MARK: Cancelling and leaving

    @Test func cancellingDropsTheFrameAndLeavesTheHistoryAlone() {
        let model = MarkupEditorModel(image: image)
        model.select(.step)
        model.select(.crop)
        drag(model, [CGPoint(x: 10, y: 10), CGPoint(x: 210, y: 160)])

        model.cancelCrop()

        #expect(model.cropFrame == nil)
        #expect(!model.isCropping)
        #expect(model.tool == .step)
        #expect(model.document.crop == nil)
        #expect(!model.canUndo)
    }

    @Test func cancellingAfterACropKeepsTheCropThatWasApplied() {
        let model = cropping(CGRect(x: 50, y: 40, width: 200, height: 150))
        model.applyCrop()
        model.select(.crop)
        drag(model, [CGPoint(x: 60, y: 50), CGPoint(x: 120, y: 100)])

        model.cancelCrop()

        #expect(model.document.crop == CGRect(x: 50, y: 40, width: 200, height: 150))
    }

    @Test func switchingToolsDiscardsAFrameThatWasNotApplied() {
        let model = cropping(CGRect(x: 50, y: 40, width: 200, height: 150))
        model.select(.rectangle)
        #expect(model.cropFrame == nil)
        #expect(model.document.crop == nil)
        model.select(.crop)
        #expect(model.cropFrame == nil)
    }

    @Test func theDocumentToSaveLeavesOutAFrameThatWasNotApplied() {
        let model = cropping(CGRect(x: 50, y: 40, width: 200, height: 150))
        #expect(model.finishedDocument().crop == nil)
    }

    @Test func enteringTheToolCommitsTextBeingTyped() {
        let model = MarkupEditorModel(image: image)
        model.select(.text)
        model.dragEnded(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 20, y: 20), pixelsPerPoint: 1)
        model.text?.string = "Xin chào"
        model.select(.crop)
        #expect(model.text == nil)
        #expect(model.document.annotations.count == 1)
    }

    // MARK: After a crop

    @Test func aCroppedEditorShowsTheCropAndLetsTheToolShowTheWholeCanvasAgain() {
        let model = cropping(CGRect(x: 50, y: 40, width: 200, height: 150))
        model.applyCrop()
        #expect(model.displayedBounds == CGRect(x: 50, y: 40, width: 200, height: 150))
        #expect(model.displayedPreview === model.preview)

        model.select(.crop)
        #expect(model.displayedBounds == canvas)
        #expect(model.displayedPreview === image)
        #expect(model.cropFrame == CGRect(x: 50, y: 40, width: 200, height: 150))
    }

    @Test func theFrameOfACroppedPictureCanBeDraggedOutToBringBackEveryPixel() {
        let model = cropping(CGRect(x: 50, y: 40, width: 200, height: 150))
        model.applyCrop()
        model.select(.crop)
        drag(model, [CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 300)])
        model.applyCrop()
        #expect(model.document.crop == nil)
        #expect(model.preview === image)
    }

    @Test func aSecondCropCutsTheCanvasAgainInTheSameSpace() {
        let model = cropping(CGRect(x: 50, y: 40, width: 200, height: 150))
        model.applyCrop()
        model.select(.crop)
        // The top-left corner pulled in, then the bottom-right one.
        drag(model, [CGPoint(x: 50, y: 40), CGPoint(x: 100, y: 80)])
        drag(model, [CGPoint(x: 250, y: 190), CGPoint(x: 200, y: 160)])
        model.applyCrop()
        #expect(model.document.crop == CGRect(x: 100, y: 80, width: 100, height: 80))
        model.undo()
        #expect(model.document.crop == CGRect(x: 50, y: 40, width: 200, height: 150))
    }

    @Test func drawingOnACroppedPictureStaysOnIt() {
        let model = cropping(CGRect(x: 50, y: 40, width: 200, height: 150))
        model.applyCrop()
        model.select(.rectangle)
        drag(model, [CGPoint(x: 100, y: 60), CGPoint(x: 900, y: 700)])
        #expect(model.document.annotations == [
            .rectangle(CGRect(x: 100, y: 60, width: 150, height: 130), style: .init(color: .red, width: 4))
        ])
        #expect(model.canvas.isZero)
        #expect((model.preview.width, model.preview.height) == (200, 150))
    }
}
