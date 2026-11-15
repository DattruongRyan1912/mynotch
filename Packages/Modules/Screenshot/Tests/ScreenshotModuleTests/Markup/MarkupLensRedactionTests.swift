import CoreGraphics
import Testing
@testable import ScreenshotModule

/// A redaction or smart erase must hide its area inside every magnifier lens too, wherever the two sit in the order
/// the annotations were drawn: otherwise a lens drawn first keeps an enlarged copy of what was hidden afterwards.
@Suite struct MarkupLensRedactionTests {
    /// Every pixel differs from its neighbours, so a block average never equals an original pixel by accident.
    static let detail = Bitmap(width: 400, height: 300) { x, y in
        Bitmap.Pixel(r: UInt8(x * 7 % 256), g: UInt8(y * 13 % 256), b: UInt8(x * y % 256), a: 255)
    }

    /// A lens at the centre whose source disc (radius 20 at 4×) lies inside the rectangle hidden below.
    static let lens = Annotation.magnifier(center: CGPoint(x: 200, y: 150), radius: 80, zoom: 4, style: .init(color: .red, width: 4))
    static let redaction = Annotation.redact(CGRect(x: 180, y: 130, width: 40, height: 40))
    static let erasing = Annotation.erase(CGRect(x: 185, y: 135, width: 30, height: 30))

    static func render(_ bitmap: Bitmap, _ annotations: [Annotation]) throws -> Bitmap {
        try MarkupRendererToolsTests.render(bitmap, annotations)
    }

    /// The pixels where `a` and `b` differ outside `hole`, which is where the later operation rewrites the picture
    /// itself instead of what the lens shows.
    static func differences(_ a: Bitmap, _ b: Bitmap, outside hole: CGRect) -> [CGPoint] {
        var found: [CGPoint] = []
        let hole = hole.integral
        for y in 0..<a.height {
            for x in 0..<a.width where !hole.contains(CGPoint(x: x, y: y)) && a.pixel(x, y) != b.pixel(x, y) {
                found.append(CGPoint(x: x, y: y))
            }
        }
        return found
    }

    // MARK: Renderer

    @Test func aRedactionDrawnAfterALensHidesItsAreaInsideTheLens() throws {
        let redactOnly = try Self.render(Self.detail, [Self.redaction])
        let leaky = try Self.render(Self.detail, [Self.lens])
        let output = try Self.render(Self.detail, [Self.lens, Self.redaction])

        // (260, 150) shows source (215.1, 150.1): inside the redacted block, so it is the block's flat colour.
        #expect(output.pixel(260, 150) == redactOnly.pixel(215, 150))
        #expect(output.pixel(260, 150) != leaky.pixel(260, 150))
        #expect(output.pixel(240, 180) == redactOnly.pixel(210, 157))
        // Everywhere but the rectangle itself the picture is what a redaction drawn first gives.
        let redactedFirst = try Self.render(Self.detail, [Self.redaction, Self.lens])
        #expect(Self.differences(output, redactedFirst, outside: CGRect(x: 180, y: 130, width: 40, height: 40)).isEmpty)
        // The check means something: without the fix the enlarged pixels differ from it over the lens's middle.
        #expect(Self.differences(leaky, redactedFirst, outside: CGRect(x: 180, y: 130, width: 40, height: 40)).count > 5000)
    }

    @Test func aSmartEraseDrawnAfterALensHidesItsAreaInsideTheLens() throws {
        let capture = MarkupRendererToolsTests.ringed(CGRect(x: 185, y: 135, width: 30, height: 30), size: (400, 300))
        let leaky = try Self.render(capture, [Self.lens])
        let output = try Self.render(capture, [Self.lens, Self.erasing])

        // (250, 150) shows source (212.6, 150.1), inside the erased rectangle: the ring's flat colour.
        #expect(output.pixel(250, 150) == MarkupRendererToolsTests.halo)
        #expect(leaky.pixel(250, 150) != MarkupRendererToolsTests.halo)
        let erasedFirst = try Self.render(capture, [Self.erasing, Self.lens])
        #expect(Self.differences(output, erasedFirst, outside: CGRect(x: 185, y: 135, width: 30, height: 30)).isEmpty)
        #expect(Self.differences(leaky, erasedFirst, outside: CGRect(x: 185, y: 135, width: 30, height: 30)).count > 3000)
    }

    @Test func aSmartEraseThatPixelatesAfterALensHidesItInsideTheLensToo() throws {
        // A noisy ring makes the erase fall back to pixelating; the lens must still show the pixelated area.
        let rect = CGRect(x: 180, y: 130, width: 40, height: 40)
        let capture = Bitmap.checkerboard(width: 400, height: 300)
        let output = try Self.render(capture, [Self.lens, .erase(rect)])
        let erasedFirst = try Self.render(capture, [.erase(rect), Self.lens])
        #expect(Self.differences(output, erasedFirst, outside: rect).isEmpty)
        let leaky = try Self.render(capture, [Self.lens])
        #expect(Self.differences(leaky, erasedFirst, outside: rect).count > 3000)
    }

    @Test func aRedactionDrawnBeforeALensIsMagnifiedAsAFlatBlock() throws {
        let redactOnly = try Self.render(Self.detail, [Self.redaction])
        let output = try Self.render(Self.detail, [Self.redaction, Self.lens])
        // (180, 150) shows source (195.1, 150.1): inside the rectangle too.
        #expect(output.pixel(180, 150) == redactOnly.pixel(195, 150))
        #expect(output.pixel(260, 150) == redactOnly.pixel(215, 150))
        #expect(output.pixel(260, 150) != Self.detail.pixel(215, 150))
        // The lens itself is unchanged: outside it, and on its border, the picture is the redacted capture.
        #expect(output.pixel(100, 150) == redactOnly.pixel(100, 150))
        #expect(MarkupRendererToolsTests.isRed(output.pixel(278, 150)))
    }

    @Test func aLensStillMagnifiesAnnotationsDrawnBeforeItWithARedactionAfterIt() throws {
        // Hiding things must not cost the lens the arrows and boxes it already showed.
        let box = Annotation.rectangle(CGRect(x: 300, y: 100, width: 20, height: 20), style: .init(color: .blue, width: 2))
        let lens = Annotation.magnifier(center: CGPoint(x: 310, y: 110), radius: 40, zoom: 2, style: .init(color: .red, width: 4))
        let hidden = Annotation.redact(CGRect(x: 40, y: 40, width: 30, height: 30))
        let output = try Self.render(.filled(width: 400, height: 300), [box, lens, hidden])
        #expect(MarkupRendererToolsTests.isBlue(output.pixel(290, 110)))
    }

    @Test func aRedactionBelowTheLensThatDoesNotTouchItsSourceChangesNothingInsideIt() throws {
        let away = Annotation.redact(CGRect(x: 20, y: 20, width: 40, height: 40))
        let output = try Self.render(Self.detail, [Self.lens, away])
        let without = try Self.render(Self.detail, [Self.lens])
        #expect(Self.differences(output, without, outside: CGRect(x: 20, y: 20, width: 40, height: 40)).isEmpty)
    }

    // MARK: Editor

    @Test func undoAndRedoOfARedactionUpdateTheLensOnScreen() throws {
        let image = try Self.detail.image()
        let model = MarkupEditorModel(image: image)
        model.select(.magnifier)
        model.magnification = 4
        model.dragEnded(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 280, y: 150), pixelsPerPoint: 1)
        model.select(.redact)
        model.dragEnded(from: CGPoint(x: 180, y: 130), to: CGPoint(x: 220, y: 170), pixelsPerPoint: 1)
        #expect(model.document.annotations.count == 2)

        let redactOnly = try Self.render(Self.detail, [Self.redaction])
        let lensOnly = try Self.render(Self.detail, [.magnifier(center: CGPoint(x: 200, y: 150), radius: 80, zoom: 4, style: .init(color: .red, width: 4))])
        let hidden = try Bitmap(model.preview)
        #expect(hidden.pixel(260, 150) == redactOnly.pixel(215, 150))

        model.undo()
        let shown = try Bitmap(model.preview)
        #expect(shown.pixel(260, 150) == lensOnly.pixel(260, 150))
        #expect(shown.pixel(260, 150) != hidden.pixel(260, 150))

        model.redo()
        let hiddenAgain = try Bitmap(model.preview)
        #expect(hiddenAgain.pixel(260, 150) == hidden.pixel(260, 150))
        #expect(Self.differences(hiddenAgain, hidden, outside: .zero).isEmpty)
    }

    @Test func theLensDrawnAfterTheRedactionShowsItHiddenOnScreenToo() throws {
        let image = try Self.detail.image()
        let model = MarkupEditorModel(image: image)
        model.select(.redact)
        model.dragEnded(from: CGPoint(x: 180, y: 130), to: CGPoint(x: 220, y: 170), pixelsPerPoint: 1)
        model.select(.magnifier)
        model.magnification = 4
        model.dragEnded(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 280, y: 150), pixelsPerPoint: 1)
        let redactOnly = try Self.render(Self.detail, [Self.redaction])
        #expect(try Bitmap(model.preview).pixel(260, 150) == redactOnly.pixel(215, 150))
    }
}
