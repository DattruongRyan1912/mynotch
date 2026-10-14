import CoreGraphics
import Testing
@testable import ScreenshotModule

/// The step, lens, ruler and erase tools and the growing canvas, driven the way the view drives the model.
@Suite struct MarkupEditorModelToolsTests {
    let image: CGImage

    init() throws {
        image = try Bitmap.filled(width: 400, height: 300).image()
    }

    func drag(
        _ model: MarkupEditorModel, _ points: [CGPoint], pixelsPerPoint: CGFloat = 2, modifiers: MarkupModifiers = []
    ) {
        for point in points.dropFirst() {
            model.dragChanged(from: points[0], to: point, pixelsPerPoint: pixelsPerPoint, modifiers: modifiers)
        }
        model.dragEnded(from: points[0], to: points[points.count - 1], pixelsPerPoint: pixelsPerPoint, modifiers: modifiers)
    }

    func click(_ model: MarkupEditorModel, _ point: CGPoint, modifiers: MarkupModifiers = []) {
        drag(model, [point], modifiers: modifiers)
    }

    static func numbers(_ model: MarkupEditorModel) -> [Int] {
        model.document.annotations.compactMap { if case .step(let number, _, _, _) = $0 { number } else { nil } }
    }

    static func centres(_ model: MarkupEditorModel) -> [CGPoint] {
        model.document.annotations.compactMap { if case .step(_, let center, _, _) = $0 { center } else { nil } }
    }

    // MARK: Numbered steps

    @Test func clickingWithTheStepToolDropsBadgesNumberedFromOneInTheCurrentColour() {
        let model = MarkupEditorModel(image: image)
        model.select(.step)
        model.color = .blue
        click(model, CGPoint(x: 50, y: 50))
        model.color = .green
        click(model, CGPoint(x: 120, y: 60))
        click(model, CGPoint(x: 200, y: 70))
        let radius = StrokeThickness.medium.badgeRadius * 2
        #expect(model.document.annotations == [
            .step(number: 1, at: CGPoint(x: 50, y: 50), radius: radius, color: .blue),
            .step(number: 2, at: CGPoint(x: 120, y: 60), radius: radius, color: .green),
            .step(number: 3, at: CGPoint(x: 200, y: 70), radius: radius, color: .green),
        ])
        #expect(model.canUndo)
    }

    @Test func theBadgeSizeFollowsTheThickness() {
        let model = MarkupEditorModel(image: image)
        model.select(.step)
        model.thickness = .thick
        click(model, CGPoint(x: 50, y: 50))
        #expect(model.document.annotations == [.step(number: 1, at: CGPoint(x: 50, y: 50), radius: 40, color: .red)])
    }

    @Test func aStepDraftFollowsThePointerAndShowsTheNumberItWillGet() {
        let model = MarkupEditorModel(image: image)
        model.select(.step)
        click(model, CGPoint(x: 50, y: 50))
        model.dragChanged(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 110, y: 104), pixelsPerPoint: 2)
        #expect(model.draft == .step(number: 2, at: CGPoint(x: 110, y: 104), radius: 28, color: .red))
        #expect(Self.numbers(model) == [1])
        model.dragEnded(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 110, y: 104), pixelsPerPoint: 2)
        #expect(model.draft == nil)
        #expect(Self.centres(model) == [CGPoint(x: 50, y: 50), CGPoint(x: 110, y: 104)])
    }

    @Test func optionClickOnABadgeRemovesItAndRenumbersTheRest() {
        let model = MarkupEditorModel(image: image)
        model.select(.step)
        for x in [50.0, 150, 250] { click(model, CGPoint(x: x, y: 100)) }
        click(model, CGPoint(x: 152, y: 98), modifiers: .option)
        #expect(Self.numbers(model) == [1, 2])
        #expect(Self.centres(model) == [CGPoint(x: 50, y: 100), CGPoint(x: 250, y: 100)])
        click(model, CGPoint(x: 150, y: 100))
        #expect(Self.numbers(model) == [1, 2, 3])
        #expect(Self.centres(model) == [CGPoint(x: 50, y: 100), CGPoint(x: 250, y: 100), CGPoint(x: 150, y: 100)])
    }

    @Test func undoAndRedoBringTheNumbersBackAsTheyWere() {
        let model = MarkupEditorModel(image: image)
        model.select(.step)
        for x in [50.0, 150, 250] { click(model, CGPoint(x: x, y: 100)) }
        click(model, CGPoint(x: 50, y: 100), modifiers: .option)
        #expect(Self.numbers(model) == [1, 2])
        model.undo()
        #expect(Self.numbers(model) == [1, 2, 3])
        #expect(Self.centres(model).first == CGPoint(x: 50, y: 100))
        model.redo()
        #expect(Self.numbers(model) == [1, 2])
        #expect(Self.centres(model) == [CGPoint(x: 150, y: 100), CGPoint(x: 250, y: 100)])
        model.undo()
        model.undo()
        #expect(Self.numbers(model) == [1, 2])
        click(model, CGPoint(x: 300, y: 100))
        #expect(Self.numbers(model) == [1, 2, 3])
    }

    @Test func optionClickOnEmptySpaceOrAnotherToolDeletesNothing() {
        let model = MarkupEditorModel(image: image)
        model.select(.step)
        click(model, CGPoint(x: 50, y: 50))
        click(model, CGPoint(x: 300, y: 250), modifiers: .option)
        #expect(Self.numbers(model) == [1])
        #expect(model.draft == nil)
        model.select(.rectangle)
        drag(model, [CGPoint(x: 40, y: 40), CGPoint(x: 80, y: 80)], modifiers: .option)
        #expect(model.document.annotations.count == 2)
    }

    @Test func removingABadgeIsOneUndoStep() {
        let model = MarkupEditorModel(image: image)
        model.select(.step)
        click(model, CGPoint(x: 50, y: 50))
        click(model, CGPoint(x: 150, y: 50))
        click(model, CGPoint(x: 50, y: 50), modifiers: .option)
        model.undo()
        #expect(Self.numbers(model) == [1, 2])
        model.undo()
        #expect(Self.numbers(model) == [1])
    }

    // MARK: Magnifier

    @Test func theLensToolDrawsFromTheCentreOutAtTheChosenMagnification() {
        let model = MarkupEditorModel(image: image)
        model.select(.magnifier)
        #expect(model.magnification == 2)
        model.magnification = 3
        model.color = .yellow
        drag(model, [CGPoint(x: 200, y: 150), CGPoint(x: 240, y: 180)])
        #expect(model.document.annotations == [
            .magnifier(center: CGPoint(x: 200, y: 150), radius: 50, zoom: 3, style: .init(color: .yellow, width: 8)),
        ])
    }

    @Test func aLensDraftAppearsWhileDragging() {
        let model = MarkupEditorModel(image: image)
        model.select(.magnifier)
        model.dragChanged(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 230, y: 150), pixelsPerPoint: 1)
        #expect(model.draft == .magnifier(center: CGPoint(x: 200, y: 150), radius: 30, zoom: 2, style: .init(color: .red, width: 4)))
    }

    @Test func theLensShowsInThePreviewOnceDrawn() throws {
        let bands = try Bitmap(width: 220, height: 160) { x, y in Bitmap.Pixel(r: UInt8(x / 20 * 20), g: UInt8(y / 20 * 20), b: 0, a: 255) }.image()
        let model = MarkupEditorModel(image: bands)
        model.select(.magnifier)
        drag(model, [CGPoint(x: 110, y: 60), CGPoint(x: 150, y: 60)], pixelsPerPoint: 1)
        let preview = try Bitmap(model.preview)
        #expect(preview.pixel(118, 90) == (try Bitmap(bands)).pixel(114, 75))
    }

    // MARK: Ruler

    @Test func theRulerCarriesTheCapturesScaleAndSnapsWithShift() {
        let model = MarkupEditorModel(image: image, pointScale: 2)
        model.select(.ruler)
        drag(model, [CGPoint(x: 20, y: 20), CGPoint(x: 140, y: 30)], modifiers: .shift)
        drag(model, [CGPoint(x: 20, y: 60), CGPoint(x: 80, y: 120)])
        let style = Annotation.StrokeStyle(color: .red, width: 8)
        let fontSize = StrokeThickness.medium.fontSize * 0.6 * 2
        #expect(model.document.annotations == [
            .ruler(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 140, y: 20), style: style, fontSize: fontSize, scale: 2),
            .ruler(from: CGPoint(x: 20, y: 60), to: CGPoint(x: 80, y: 120), style: style, fontSize: fontSize, scale: 2),
        ])
    }

    @Test func theRulerDraftSnapsLiveWhileShiftIsHeld() {
        let model = MarkupEditorModel(image: image)
        model.select(.ruler)
        model.dragChanged(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 90, y: 40), pixelsPerPoint: 1, modifiers: .shift)
        guard case .ruler(_, let end, _, _, _) = model.draft else { Issue.record("no draft"); return }
        #expect(end == CGPoint(x: 90, y: 20))
        model.dragChanged(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 90, y: 40), pixelsPerPoint: 1)
        guard case .ruler(_, let free, _, _, _) = model.draft else { Issue.record("no draft"); return }
        #expect(free == CGPoint(x: 90, y: 40))
    }

    // MARK: Smart erase

    @Test func theEraseToolCommitsARectangleAndIsUndoable() {
        let model = MarkupEditorModel(image: image)
        model.select(.erase)
        drag(model, [CGPoint(x: 100, y: 100), CGPoint(x: 160, y: 130)])
        #expect(model.document.annotations == [.erase(CGRect(x: 100, y: 100, width: 60, height: 30))])
        model.undo()
        #expect(model.document.annotations.isEmpty)
        #expect(model.preview === image)
    }

    @Test func eraseAndRedactStayOnTheCanvasInsteadOfGrowingIt() {
        let model = MarkupEditorModel(image: image)
        model.select(.erase)
        drag(model, [CGPoint(x: 300, y: 200), CGPoint(x: 900, y: 700)])
        model.select(.redact)
        drag(model, [CGPoint(x: -300, y: -200), CGPoint(x: 50, y: 40)])
        #expect(model.document.annotations == [
            .erase(CGRect(x: 300, y: 200, width: 100, height: 100)),
            .redact(CGRect(x: 0, y: 0, width: 50, height: 40)),
        ])
        #expect(model.canvasSize == CGSize(width: 400, height: 300))
    }

    @Test func clicksAndTinyDragsOfTheNewToolsAddNothing() {
        let model = MarkupEditorModel(image: image)
        for tool in [MarkupTool.magnifier, .ruler, .erase] {
            model.select(tool)
            drag(model, [CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 50)])
            drag(model, [CGPoint(x: 50, y: 50), CGPoint(x: 53, y: 52)])
        }
        #expect(model.document.annotations.isEmpty)
        #expect(!model.canUndo)
    }

    // MARK: Canvas

    @Test func startsWithTheCaptureAsTheCanvas() {
        let model = MarkupEditorModel(image: image)
        #expect(model.canvas.isZero)
        #expect(model.canvasSize == CGSize(width: 400, height: 300))
        #expect(model.canvasOrigin == .zero)
    }

    @Test func drawingPastTheEdgeGrowsTheCanvasAndUndoShrinksItBack() {
        let model = MarkupEditorModel(image: image)
        model.select(.rectangle)
        drag(model, [CGPoint(x: 350, y: 250), CGPoint(x: 450, y: 330)])
        // The stroke is 8 pixels wide, so it reaches 4 past the corner at (450, 330).
        #expect(model.canvas == CanvasInsets(left: 0, top: 0, right: 54, bottom: 34))
        #expect(model.canvasSize == CGSize(width: 454, height: 334))
        #expect((model.preview.width, model.preview.height) == (454, 334))
        #expect(model.document.annotations == [.rectangle(CGRect(x: 350, y: 250, width: 100, height: 80), style: .init(color: .red, width: 8))])

        model.undo()
        #expect(model.canvas.isZero)
        #expect(model.canvasSize == CGSize(width: 400, height: 300))
        #expect(model.preview === image)

        model.redo()
        #expect(model.canvasSize == CGSize(width: 454, height: 334))
        #expect((model.preview.width, model.preview.height) == (454, 334))
    }

    @Test func growingLeftOrUpMovesTheCanvasOriginIntoNegativeCoordinates() {
        let model = MarkupEditorModel(image: image)
        model.select(.arrow)
        drag(model, [CGPoint(x: -30, y: -20), CGPoint(x: 100, y: 100)])
        #expect(model.canvas.left > 30 && model.canvas.top > 20)
        #expect(model.canvasOrigin == CGPoint(x: -model.canvas.left, y: -model.canvas.top))
        #expect(model.canvasSize.width == 400 + CGFloat(model.canvas.left) + CGFloat(model.canvas.right))
        // Coordinates stay relative to the capture, so the annotation did not move.
        guard case .arrow(let start, _, _) = model.document.annotations.first else { Issue.record("no arrow"); return }
        #expect(start == CGPoint(x: -30, y: -20))
    }

    @Test func aDragInsideTheCaptureNeverGrowsTheCanvas() {
        let model = MarkupEditorModel(image: image)
        model.select(.rectangle)
        drag(model, [CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 300)])
        #expect(model.canvas.isZero)
        #expect(model.preview !== image)
        #expect((model.preview.width, model.preview.height) == (400, 300))
    }

    @Test func aDragFarOutsideIsCappedSoTheBitmapStaysReasonable() {
        let model = MarkupEditorModel(image: image)
        model.select(.rectangle)
        drag(model, [CGPoint(x: 100, y: 100), CGPoint(x: 100_000, y: 100_000)])
        let limit = CanvasInsets.limit(for: CGSize(width: 400, height: 300))
        #expect(limit == 256)
        #expect(model.canvas == CanvasInsets(left: 0, top: 0, right: limit, bottom: limit))
        #expect((model.preview.width, model.preview.height) == (400 + limit, 300 + limit))
    }

    @Test func textPlacedPastTheEdgeGrowsTheCanvasToHoldIt() {
        let model = MarkupEditorModel(image: image)
        model.select(.text)
        drag(model, [CGPoint(x: 380, y: 100)])
        model.text?.string = "Ghi chú dài"
        model.commitText()
        #expect(model.canvas.right > 40)
        #expect(model.canvas.bottom == 0)
        model.undo()
        #expect(model.canvas.isZero)
    }

    @Test func removingTheBadgeThatGrewTheCanvasShrinksItBack() {
        let model = MarkupEditorModel(image: image)
        model.select(.step)
        click(model, CGPoint(x: 395, y: 100))
        #expect(model.canvas.right == 28 - 5)
        click(model, CGPoint(x: 395, y: 100), modifiers: .option)
        #expect(model.canvas.isZero)
        #expect(model.document.annotations.isEmpty)
        #expect(model.preview === image)
    }

    @Test func theFillComesFromTheSettingAndReachesThePreviewAndTheDocument() throws {
        let capture = try Bitmap.filled(width: 100, height: 80, with: Bitmap.Pixel(r: 10, g: 20, b: 30, a: 255)).image()
        let model = MarkupEditorModel(image: capture, canvasFill: .white)
        model.select(.step)
        click(model, CGPoint(x: 100, y: 10))
        #expect(model.document.canvasFill == .white)
        #expect(model.finishedDocument().canvasFill == .white)
        let preview = try Bitmap(model.preview)
        #expect(preview.width > 100)
        #expect(preview.pixel(preview.width - 1, 79) == .white)
        #expect(MarkupEditorModel(image: capture).document.canvasFill == .standard)
    }

    @Test func reopeningKeepsTheAnnotationsButTakesTheCurrentFill() {
        let document = MarkupDocument(
            imageSize: CGSize(width: 400, height: 300),
            annotations: [.step(number: 1, at: CGPoint(x: 395, y: 100), radius: 20, color: .red)]
        )
        let model = MarkupEditorModel(image: image, document: document, canvasFill: .black)
        #expect(model.document.annotations == document.annotations)
        #expect(model.document.canvasFill == .black)
        #expect(model.canvas == CanvasInsets(left: 0, top: 0, right: 15, bottom: 0))
        #expect((model.preview.width, model.preview.height) == (415, 300))
    }

    // MARK: Failed renders

    /// A renderer that can be told to fail, as when no bitmap of the canvas's size could be allocated.
    final class FlakyRenderer {
        var fails = false
        func render(_ image: CGImage, _ document: MarkupDocument) -> CGImage? {
            fails ? nil : MarkupRenderer.flatten(image, document)
        }
    }

    @Test func aFailedRenderKeepsThePreviousPreviewAndCanvasSoTheyStillMatch() {
        let renderer = FlakyRenderer()
        let model = MarkupEditorModel(image: image, render: renderer.render)
        model.select(.step)
        click(model, CGPoint(x: 395, y: 100))
        let grown = model.preview
        #expect(model.canvasSize == CGSize(width: 423, height: 300))

        renderer.fails = true
        click(model, CGPoint(x: 450, y: 250))
        // The annotation is in the document, but the picture on screen is still the last one that could be made.
        #expect(model.document.annotations.count == 2)
        #expect(model.preview === grown)
        #expect(model.canvasSize == CGSize(width: 423, height: 300))
        #expect((model.preview.width, model.preview.height) == (Int(model.canvasSize.width), Int(model.canvasSize.height)))

        renderer.fails = false
        click(model, CGPoint(x: 100, y: 100))
        #expect(model.document.annotations.count == 3)
        #expect(model.canvasSize == CGSize(width: 478, height: 300))
        #expect((model.preview.width, model.preview.height) == (478, 300))
    }

    @Test func openingADocumentThatCannotBeRenderedShowsTheCaptureAtItsOwnSize() {
        let document = MarkupDocument(
            imageSize: CGSize(width: 400, height: 300),
            annotations: [.step(number: 1, at: CGPoint(x: 395, y: 100), radius: 20, color: .red)]
        )
        let model = MarkupEditorModel(image: image, document: document, render: { _, _ in nil })
        #expect(model.preview === image)
        #expect(model.canvasSize == CGSize(width: 400, height: 300))
    }
}
