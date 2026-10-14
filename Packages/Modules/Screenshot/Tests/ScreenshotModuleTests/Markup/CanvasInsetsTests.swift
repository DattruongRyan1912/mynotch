import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct CanvasInsetsTests {
    let image = CGSize(width: 400, height: 300)

    @Test func staysZeroForAnythingInsideTheImage() {
        #expect(CanvasInsets.zero.growing(toContain: CGRect(x: 10, y: 10, width: 100, height: 50), imageSize: image) == .zero)
        #expect(CanvasInsets.zero.growing(toContain: CGRect(x: 0, y: 0, width: 400, height: 300), imageSize: image) == .zero)
        #expect(CanvasInsets.zero.growing(toContain: .null, imageSize: image) == .zero)
        #expect(CanvasInsets.zero.isZero)
    }

    @Test func growsOnEverySideTheRectPassesRoundingUpToWholePixels() {
        let grown = CanvasInsets.zero.growing(toContain: CGRect(x: -4.2, y: 290, width: 420, height: 20.5), imageSize: image)
        #expect(grown == CanvasInsets(left: 5, top: 0, right: 16, bottom: 11))
        let above = CanvasInsets.zero.growing(toContain: CGRect(x: 100, y: -0.5, width: 10, height: 10), imageSize: image)
        #expect(above == CanvasInsets(left: 0, top: 1, right: 0, bottom: 0))
    }

    @Test func keepsWhatItAlreadyGrewWhenTheNextRectNeedsLess() {
        let start = CanvasInsets(left: 8, top: 2, right: 30, bottom: 0)
        let grown = start.growing(toContain: CGRect(x: -3, y: -9, width: 410, height: 20), imageSize: image)
        #expect(grown == CanvasInsets(left: 8, top: 9, right: 30, bottom: 0))
    }

    @Test func limitsEachSideToHalfTheLongerSideButAtLeast256Pixels() {
        #expect(CanvasInsets.limit(for: image) == 256)
        #expect(CanvasInsets.limit(for: CGSize(width: 3000, height: 2000)) == 1500)
        let grown = CanvasInsets.zero.growing(toContain: CGRect(x: -5000, y: -5000, width: 20000, height: 20000), imageSize: image)
        #expect(grown == CanvasInsets(left: 256, top: 256, right: 256, bottom: 256))
    }

    @Test func canvasIsTheImagePlusPaddingStartingAtANegativeOrigin() {
        let insets = CanvasInsets(left: 5, top: 3, right: 16, bottom: 11)
        #expect(insets.size(of: image) == CGSize(width: 421, height: 314))
        #expect(insets.bounds(of: image) == CGRect(x: -5, y: -3, width: 421, height: 314))
        #expect(!insets.isZero)
        #expect(CanvasInsets.zero.bounds(of: image) == CGRect(origin: .zero, size: image))
    }

    @Test func sidesWithNoCanvasGrowthGiveTheCanvasBackItsOriginalSize() {
        let grown = CanvasInsets.zero.growing(toContain: CGRect(x: 380, y: 100, width: 40, height: 10), imageSize: image)
        #expect(grown.size(of: image) == CGSize(width: 420, height: 300))
        #expect(grown.bounds(of: image).origin == .zero)
    }
}
