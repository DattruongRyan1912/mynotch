import CoreGraphics
import Testing
@testable import ScreenshotModule

/// The step badges, ruler, magnifier and smart erase as flattened pixels, on synthetic bitmaps only.
@Suite struct MarkupRendererToolsTests {
    static func render(
        _ bitmap: Bitmap, _ annotations: [Annotation], fill: CanvasFill = .transparent, imageSize: CGSize? = nil
    ) throws -> Bitmap {
        let size = imageSize ?? CGSize(width: bitmap.width, height: bitmap.height)
        let document = MarkupDocument(imageSize: size, annotations: annotations, canvasFill: fill)
        return try Bitmap(#require(MarkupRenderer.flatten(bitmap.image(), document)))
    }

    static func isRed(_ pixel: Bitmap.Pixel) -> Bool { pixel.r > 200 && pixel.g < 100 && pixel.b < 100 }
    static func isBlue(_ pixel: Bitmap.Pixel) -> Bool { pixel.b > 200 && pixel.r < 60 }
    static func isLight(_ pixel: Bitmap.Pixel) -> Bool { pixel.r > 200 && pixel.g > 200 && pixel.b > 200 }
    static func isDark(_ pixel: Bitmap.Pixel) -> Bool { pixel.r < 90 && pixel.g < 90 && pixel.b < 90 }

    /// Pixels inside the `radius` disc around `center` that satisfy `test`.
    static func pixels(in bitmap: Bitmap, around center: CGPoint, radius: CGFloat, where test: (Bitmap.Pixel) -> Bool) -> [CGPoint] {
        var found: [CGPoint] = []
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where hypot(CGFloat(x) - center.x, CGFloat(y) - center.y) <= radius && test(bitmap.pixel(x, y)) {
                found.append(CGPoint(x: x, y: y))
            }
        }
        return found
    }

    // MARK: Step badges

    @Test func aStepBadgeIsADiscInTheChosenColourAndNothingOutsideIt() throws {
        let output = try Self.render(.filled(width: 100, height: 100), [.step(number: 7, at: CGPoint(x: 50, y: 50), radius: 20, color: .blue)])
        #expect(Self.isBlue(output.pixel(35, 50)))
        #expect(Self.isBlue(output.pixel(50, 66)))
        #expect(output.pixel(50, 24) == .white)
        #expect(output.pixel(76, 50) == .white)
        #expect(output.pixel(33, 33) == .white)
    }

    @Test func theNumberIsDrawnInContrastAndCentredOnTheBadge() throws {
        let output = try Self.render(.filled(width: 100, height: 100), [.step(number: 8, at: CGPoint(x: 50, y: 50), radius: 20, color: .blue)])
        let ink = Self.pixels(in: output, around: CGPoint(x: 50, y: 50), radius: 14, where: Self.isLight)
        #expect(ink.count > 20)
        let xs = ink.map(\.x), ys = ink.map(\.y)
        let middle = CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
        #expect(abs(middle.x - 50) <= 2 && abs(middle.y - 50) <= 2, "number centred at \(middle)")
    }

    @Test func aLightBadgeGetsDarkDigitsAndTwoDigitsStillFit() throws {
        let output = try Self.render(.filled(width: 100, height: 100), [.step(number: 12, at: CGPoint(x: 50, y: 50), radius: 20, color: .yellow)])
        let ink = Self.pixels(in: output, around: CGPoint(x: 50, y: 50), radius: 17, where: Self.isDark)
        #expect(ink.count > 20)
        // Both digits sit well inside the badge: nothing dark between 14 pixels out and the rim's white ring.
        #expect(ink.count == Self.pixels(in: output, around: CGPoint(x: 50, y: 50), radius: 14, where: Self.isDark).count)
    }

    @Test func badgesStackInDrawingOrder() throws {
        let output = try Self.render(.filled(width: 100, height: 60), [
            .step(number: 1, at: CGPoint(x: 40, y: 30), radius: 20, color: .blue),
            .step(number: 2, at: CGPoint(x: 60, y: 30), radius: 20, color: .red),
        ])
        #expect(Self.isRed(output.pixel(50, 40)))
        #expect(Self.isBlue(output.pixel(24, 30)))
    }

    // MARK: Ruler

    @Test func aRulerDrawsItsLineEndTicksAndALabelPill() throws {
        let style = Annotation.StrokeStyle(color: .red, width: 4)
        let from = CGPoint(x: 20, y: 60), to = CGPoint(x: 180, y: 60)
        let output = try Self.render(.filled(width: 200, height: 120), [.ruler(from: from, to: to, style: style, fontSize: 16, scale: 2)])
        #expect(Self.isRed(output.pixel(100, 60)))
        #expect(Self.isRed(output.pixel(20, 54)))
        #expect(Self.isRed(output.pixel(180, 66)))
        #expect(output.pixel(100, 100) == .white)
        let layout = Ruler.layout(from: from, to: to, lineWidth: 4, fontSize: 16, scale: 2)
        #expect(layout.label == "160 px (80 pt)")
        #expect(layout.labelRect.maxY < 60)
        // The pill is the stroke colour, with the text in contrast on top of it.
        #expect(Self.isRed(output.pixel(Int(layout.labelRect.minX) + 2, Int(layout.labelRect.midY))))
        // Between the pill's rounded ends only its fill and the text are left.
        let middle = layout.labelRect.insetBy(dx: layout.labelRect.height / 2, dy: 2)
        var text = 0
        for y in Int(middle.minY)..<Int(middle.maxY) {
            for x in Int(middle.minX)..<Int(middle.maxX) where Self.isLight(output.pixel(x, y)) { text += 1 }
        }
        #expect(text > 30)
    }

    @Test func aVerticalRulerPutsItsLabelBesideTheLine() throws {
        let style = Annotation.StrokeStyle(color: .blue, width: 4)
        let from = CGPoint(x: 30, y: 20), to = CGPoint(x: 30, y: 180)
        let output = try Self.render(.filled(width: 200, height: 200), [.ruler(from: from, to: to, style: style, fontSize: 16, scale: 1)])
        #expect(Self.isBlue(output.pixel(30, 100)))
        let layout = Ruler.layout(from: from, to: to, lineWidth: 4, fontSize: 16, scale: 1)
        #expect(layout.label == "160 px")
        #expect(layout.labelRect.minX > 30)
        #expect(Self.isBlue(output.pixel(Int(layout.labelRect.minX) + 2, Int(layout.labelRect.midY))))
    }

    // MARK: Magnifier

    /// Twenty-pixel bands: red grows with x, green with y, so every region has its own colour.
    static let bands = Bitmap(width: 220, height: 160) { x, y in Bitmap.Pixel(r: UInt8(x / 20 * 20), g: UInt8(y / 20 * 20), b: 0, a: 255) }

    @Test func theLensShowsTheImageUnderItAtTheZoomAroundItsCentre() throws {
        let lens = Annotation.magnifier(center: CGPoint(x: 110, y: 60), radius: 40, zoom: 2, style: .init(color: .red, width: 6))
        let output = try Self.render(Self.bands, [lens])
        // Source (114, 75) lands at 110 + 2 × 4 = 118 across and 60 + 2 × 15 = 90 down.
        #expect(output.pixel(118, 90) == Self.bands.pixel(114, 75))
        #expect(output.pixel(118, 90) != Self.bands.pixel(118, 90))
        // Up and to the left of the centre: source (104, 53) lands at (98, 46).
        #expect(output.pixel(98, 46) == Self.bands.pixel(104, 53))
        #expect(output.pixel(98, 46) != Self.bands.pixel(98, 46))
    }

    @Test func aStrongerZoomPullsInAnEvenSmallerArea() throws {
        let lens = Annotation.magnifier(center: CGPoint(x: 110, y: 60), radius: 40, zoom: 4, style: .init(color: .red, width: 6))
        let output = try Self.render(Self.bands, [lens])
        // Source (105, 64) lands at 110 + 4 × -5 = 90 across and 60 + 4 × 4 = 76 down.
        #expect(output.pixel(90, 76) == Self.bands.pixel(105, 64))
        #expect(output.pixel(90, 76) != Self.bands.pixel(90, 76))
        #expect(output.pixel(110, 62) == Self.bands.pixel(110, 60))
    }

    @Test func theLensIsACircleWithABorderCentredOnItsEdge() throws {
        let lens = Annotation.magnifier(center: CGPoint(x: 110, y: 60), radius: 40, zoom: 2, style: .init(color: .red, width: 6))
        let output = try Self.render(Self.bands, [lens])
        #expect(Self.isRed(output.pixel(148, 60)))
        #expect(Self.isRed(output.pixel(110, 21)))
        // Outside the border nothing changed, corners of the lens's bounding box included.
        for (x, y) in [(155, 60), (110, 14), (76, 26), (146, 94), (60, 130)] {
            #expect(output.pixel(x, y) == Self.bands.pixel(x, y), "pixel (\(x), \(y)) changed")
        }
        // Inside the border the lens replaced the image.
        #expect(output.pixel(140, 70) != Self.bands.pixel(140, 70))
    }

    @Test func theLensMagnifiesWhatWasDrawnBeforeIt() throws {
        let annotations: [Annotation] = [
            .rectangle(CGRect(x: 100, y: 50, width: 20, height: 20), style: .init(color: .blue, width: 2)),
            .magnifier(center: CGPoint(x: 110, y: 60), radius: 40, zoom: 2, style: .init(color: .red, width: 4)),
        ]
        let output = try Self.render(.filled(width: 220, height: 160), annotations)
        // The rectangle's left edge at x = 100 is 10 left of the centre, so it shows 20 left of it, thickened to 4.
        #expect(Self.isBlue(output.pixel(90, 60)))
        #expect(output.pixel(100, 60) == .white)
    }

    @Test func aLensScalesWithTheDocumentSize() throws {
        let lens = Annotation.magnifier(center: CGPoint(x: 55, y: 30), radius: 20, zoom: 2, style: .init(color: .red, width: 3))
        let output = try Self.render(Self.bands, [lens], imageSize: CGSize(width: 110, height: 80))
        #expect(Self.isRed(output.pixel(148, 60)))
        #expect(output.pixel(118, 90) == Self.bands.pixel(114, 75))
    }

    // MARK: Smart erase

    static let halo = Bitmap.Pixel(r: 200, g: 100, b: 50, a: 255)

    /// A checkerboard everywhere except a flat `colour` ring `width` pixels wide around `rect`.
    static func ringed(_ rect: CGRect, colour: Bitmap.Pixel = halo, width: Int = 2, size: (Int, Int) = (160, 120)) -> Bitmap {
        let outer = rect.insetBy(dx: -CGFloat(width), dy: -CGFloat(width))
        return Bitmap(width: size.0, height: size.1) { x, y in
            let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
            if outer.contains(point), !rect.contains(point) { return colour }
            return (x + y).isMultiple(of: 2) ? .black : .white
        }
    }

    @Test func aUniformBorderIsFilledWithItsColour() throws {
        let rect = CGRect(x: 30, y: 20, width: 60, height: 40)
        let original = Self.ringed(rect)
        let output = try Self.render(original, [.erase(rect)])
        for y in 20..<60 {
            for x in 30..<90 { #expect(output.pixel(x, y) == Self.halo, "pixel (\(x), \(y))") }
        }
        // Nothing outside the rectangle changed, the ring included.
        for (x, y) in [(29, 40), (90, 40), (60, 19), (60, 60), (10, 10), (150, 110)] {
            #expect(output.pixel(x, y) == original.pixel(x, y))
        }
    }

    @Test func onlyTheRingTwoPixelsWideIsSampled() throws {
        // Noise three pixels out, right next to the ring, is ignored.
        let rect = CGRect(x: 30, y: 20, width: 60, height: 40)
        let output = try Self.render(Self.ringed(rect), [.erase(rect)])
        #expect(output.pixel(60, 40) == Self.halo)
        let wider = Self.ringed(rect, width: 1)
        let narrowOutput = try Self.render(wider, [.erase(rect)])
        // One flat pixel and one noisy one: no longer a uniform border.
        #expect(narrowOutput.pixel(60, 40) != Self.halo)
    }

    @Test func slightNoiseInTheBorderStillCountsAsUniform() throws {
        let rect = CGRect(x: 30, y: 20, width: 60, height: 40)
        let quiet = Bitmap(width: 160, height: 120) { x, y in
            rect.insetBy(dx: -2, dy: -2).contains(CGPoint(x: x, y: y)) && !rect.contains(CGPoint(x: x, y: y))
                ? Bitmap.Pixel(r: (x + y).isMultiple(of: 2) ? 100 : 106, g: 100, b: 100, a: 255)
                : ((x + y).isMultiple(of: 2) ? .black : .white)
        }
        let output = try Self.render(quiet, [.erase(rect)])
        let filled = output.pixel(60, 40)
        #expect(abs(Int(filled.r) - 103) <= 3 && filled.g == 100 && filled.b == 100)
        #expect(output.pixel(31, 21) == filled)
        #expect(output.pixel(88, 58) == filled)
    }

    @Test func aNoisyBorderFallsBackToPixelatingTheArea() throws {
        let rect = CGRect(x: 30, y: 20, width: 60, height: 40)
        let original = Bitmap.checkerboard(width: 160, height: 120)
        let output = try Self.render(original, [.erase(rect)])
        let block = MarkupRenderer.redactBlockSize(for: CGSize(width: 160, height: 120))
        for y in 20..<60 {
            for x in 30..<90 {
                #expect(output.pixel(x, y) != original.pixel(x, y), "pixel (\(x), \(y)) kept its original value")
                #expect(output.pixel(x, y) == output.pixel(30 + (x - 30) / block * block, 20 + (y - 20) / block * block))
            }
        }
        #expect(output.pixel(29, 40) == original.pixel(29, 40))
    }

    @Test func aBorderSplitBetweenTwoColoursIsNotUniform() throws {
        let rect = CGRect(x: 30, y: 20, width: 60, height: 40)
        let split = Bitmap(width: 160, height: 120) { x, _ in x < 60 ? Bitmap.Pixel(r: 200, g: 0, b: 0, a: 255) : Bitmap.Pixel(r: 0, g: 0, b: 200, a: 255) }
        let output = try Self.render(split, [.erase(rect)])
        // Filling would leave one flat colour; pixelating keeps both sides and averages the block across the seam.
        #expect(output.pixel(40, 40) != output.pixel(80, 40))
        #expect(output.pixel(58, 40) == Bitmap.Pixel(r: 100, g: 0, b: 100, a: 255))
    }

    @Test func aRectangleAgainstTheImageEdgeSamplesTheSidesThatExist() throws {
        let rect = CGRect(x: 0, y: 0, width: 50, height: 30)
        let original = Bitmap(width: 160, height: 120) { x, y in
            let inRing = x < 52 && y < 32 && !(x < 50 && y < 30)
            return inRing ? Self.halo : ((x + y).isMultiple(of: 2) ? .black : .white)
        }
        // The ring is the 2 pixels right of and below the rectangle; above and left of it is outside the image.
        let output = try Self.render(original, [.erase(rect)])
        #expect(output.pixel(0, 0) == Self.halo)
        #expect(output.pixel(49, 29) == Self.halo)
    }

    @Test func eraseCoveringTheWholeImageHasNoBorderSoItPixelates() throws {
        let original = Bitmap(width: 60, height: 60) { x, y in Bitmap.Pixel(r: UInt8(x * 4), g: UInt8(y * 4), b: 0, a: 255) }
        let output = try Self.render(original, [.erase(CGRect(x: 0, y: 0, width: 60, height: 60))])
        #expect(output.pixel(0, 0) != original.pixel(0, 0))
        #expect(output.pixel(59, 59) != original.pixel(59, 59))
    }

    @Test func eraseSeesEarlierAnnotationsAndHidesThem() throws {
        let rect = CGRect(x: 30, y: 30, width: 40, height: 40)
        let output = try Self.render(.filled(width: 120, height: 120), [
            .rectangle(CGRect(x: 40, y: 40, width: 20, height: 20), style: .init(color: .red, width: 4)),
            .erase(rect),
        ])
        #expect(output.pixel(40, 50) == .white)
        #expect(output.pixel(50, 50) == .white)
    }

    // MARK: Canvas growth

    static let plain = Bitmap(width: 200, height: 100) { x, y in Bitmap.Pixel(r: UInt8(x), g: UInt8(y), b: 90, a: 255) }

    @Test func theExportGrowsToHoldAnAnnotationPastTheEdge() throws {
        let badge = Annotation.step(number: 1, at: CGPoint(x: 190, y: 50), radius: 20, color: .red)
        let output = try Self.render(Self.plain, [badge])
        #expect((output.width, output.height) == (210, 100))
        // The capture keeps its place and the badge is whole, including the part beyond the old edge.
        #expect(output.pixel(10, 10) == Self.plain.pixel(10, 10))
        #expect(Self.isRed(output.pixel(205, 50)))
    }

    @Test func growingLeftAndUpShiftsTheCaptureAndKeepsAnnotationsAttachedToIt() throws {
        let rectangle = Annotation.rectangle(CGRect(x: -10, y: -6, width: 50, height: 30), style: .init(color: .red, width: 6))
        let output = try Self.render(Self.plain, [rectangle], fill: .white)
        // Stroke reach 3: left 13, top 9.
        #expect((output.width, output.height) == (213, 109))
        #expect(output.pixel(13 + 100, 9 + 50) == Self.plain.pixel(100, 50))
        #expect(output.pixel(13 + 0, 9 + 0) == Self.plain.pixel(0, 0))
        #expect(Self.isRed(output.pixel(13 - 10, 9 + 10)))
        #expect(Self.isRed(output.pixel(13 + 20, 9 - 6)))
        #expect(output.pixel(2, 100) == .white)
    }

    @Test func transparentPaddingHasNoAlphaAndLeavesTheCaptureAlone() throws {
        let output = try Self.render(Self.plain, [.step(number: 1, at: CGPoint(x: 190, y: 50), radius: 20, color: .red)], fill: .transparent)
        #expect(output.pixel(209, 5).a == 0)
        #expect(output.pixel(209, 95).a == 0)
        #expect(output.pixel(100, 50) == Self.plain.pixel(100, 50))
    }

    @Test func whiteAndBlackPaddingAreOpaque() throws {
        let badge = Annotation.step(number: 1, at: CGPoint(x: 190, y: 50), radius: 20, color: .red)
        #expect(try Self.render(Self.plain, [badge], fill: .white).pixel(209, 5) == .white)
        #expect(try Self.render(Self.plain, [badge], fill: .black).pixel(209, 95) == .black)
        #expect(try Self.render(Self.plain, [badge], fill: .black).pixel(5, 5) == Self.plain.pixel(5, 5))
    }

    @Test func edgeColourPaddingTakesTheMostCommonColourAlongTheEdge() throws {
        let background = Bitmap.Pixel(r: 30, g: 120, b: 200, a: 255)
        let stripe = Bitmap.Pixel(r: 250, g: 10, b: 10, a: 255)
        // Mostly background; a coloured band along the bottom and a few noisy pixels inside.
        let capture = Bitmap(width: 200, height: 100) { x, y in
            if y >= 85 { return stripe }
            return x == 100 && y == 50 ? .black : background
        }
        let output = try Self.render(capture, [.step(number: 1, at: CGPoint(x: 190, y: 20), radius: 20, color: .green)], fill: .edgeColor)
        #expect((output.width, output.height) == (210, 100))
        #expect(output.pixel(209, 2) == background)
        #expect(output.pixel(209, 95) == background)
    }

    @Test func edgeColourPaddingCoversEverySideTheCanvasGrew() throws {
        let background = Bitmap.Pixel(r: 30, g: 120, b: 200, a: 255)
        let capture = Bitmap.filled(width: 100, height: 80, with: background)
        let rectangle = Annotation.rectangle(CGRect(x: -20, y: -20, width: 150, height: 120), style: .init(color: .red, width: 2))
        let output = try Self.render(capture, [rectangle], fill: .edgeColor)
        #expect((output.width, output.height) == (100 + 21 + 31, 80 + 21 + 21))
        #expect(output.pixel(10, 30) == background)
        #expect(output.pixel(output.width - 10, output.height - 10) == background)
        #expect(output.pixel(60, 10) == background)
    }

    @Test func aDamagedImageSizeCannotMakeThePaddingEnormous() throws {
        // An imageSize a thousand times too small would scale a 10-pixel inset to 10 000 pixels.
        let badge = Annotation.step(number: 1, at: CGPoint(x: 0.19, y: 0.05), radius: 0.02, color: .red)
        let document = MarkupDocument(imageSize: CGSize(width: 0.2, height: 0.1), annotations: [badge, .step(number: 2, at: CGPoint(x: 0.25, y: 0.05), radius: 0.02, color: .red)])
        let output = try #require(MarkupRenderer.flatten(Self.plain.image(), document))
        #expect(output.width <= 200 + 2 * 256 && output.height <= 100 + 2 * 256)
    }

    @Test func aDocumentWithNothingBeyondTheEdgeKeepsTheCapturesSize() throws {
        let output = try Self.render(Self.plain, [.rectangle(CGRect(x: 0, y: 0, width: 200, height: 100), style: .init(color: .red, width: 4))], fill: .white)
        #expect((output.width, output.height) == (200, 100))
    }
}
