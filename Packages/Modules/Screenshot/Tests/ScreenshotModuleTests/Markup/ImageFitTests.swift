import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct ImageFitTests {
    @Test func wideImageIsLetterboxedTopAndBottom() {
        let fit = ImageFit(imageSize: CGSize(width: 400, height: 200), viewSize: CGSize(width: 300, height: 300))
        #expect(fit.scale == 0.75)
        #expect(fit.frame == CGRect(x: 0, y: 75, width: 300, height: 150))
    }

    @Test func tallImageIsLetterboxedLeftAndRight() {
        let fit = ImageFit(imageSize: CGSize(width: 200, height: 400), viewSize: CGSize(width: 300, height: 300))
        #expect(fit.scale == 0.75)
        #expect(fit.frame == CGRect(x: 75, y: 0, width: 150, height: 300))
    }

    @Test func convertsPointsBothWays() {
        let fit = ImageFit(imageSize: CGSize(width: 400, height: 200), viewSize: CGSize(width: 300, height: 300))
        #expect(fit.imagePoint(fromView: CGPoint(x: 150, y: 150)) == CGPoint(x: 200, y: 100))
        #expect(fit.imagePoint(fromView: CGPoint(x: 0, y: 75)) == .zero)
        #expect(fit.imagePoint(fromView: CGPoint(x: 300, y: 225)) == CGPoint(x: 400, y: 200))
        #expect(fit.viewPoint(fromImage: CGPoint(x: 200, y: 100)) == CGPoint(x: 150, y: 150))
        #expect(fit.viewPoint(fromImage: CGPoint(x: 40, y: 20)) == CGPoint(x: 30, y: 90))
        #expect(fit.viewRect(fromImage: CGRect(x: 40, y: 20, width: 80, height: 40)) == CGRect(x: 30, y: 90, width: 60, height: 30))
    }

    @Test func pointsInTheLetterboxClampToTheImageEdge() {
        let fit = ImageFit(imageSize: CGSize(width: 400, height: 200), viewSize: CGSize(width: 300, height: 300))
        #expect(fit.imagePoint(fromView: CGPoint(x: 150, y: 10)) == CGPoint(x: 200, y: 0))
        #expect(fit.imagePoint(fromView: CGPoint(x: -20, y: 290)) == CGPoint(x: 0, y: 200))
        #expect(fit.imagePoint(fromView: CGPoint(x: 400, y: 150)) == CGPoint(x: 400, y: 100))
    }

    @Test func maximumScaleKeepsSmallImagesCentredAtThatScale() {
        let fit = ImageFit(imageSize: CGSize(width: 100, height: 50), viewSize: CGSize(width: 400, height: 400), maximumScale: 1)
        #expect(fit.scale == 1)
        #expect(fit.frame == CGRect(x: 150, y: 175, width: 100, height: 50))
        #expect(fit.imagePoint(fromView: CGPoint(x: 160, y: 185)) == CGPoint(x: 10, y: 10))
        let unlimited = ImageFit(imageSize: CGSize(width: 100, height: 50), viewSize: CGSize(width: 400, height: 400))
        #expect(unlimited.scale == 4)
    }

    @Test func emptyViewOrImageYieldsFiniteValues() {
        let noView = ImageFit(imageSize: CGSize(width: 100, height: 50), viewSize: .zero)
        #expect(noView.scale == 0)
        #expect(noView.imagePoint(fromView: CGPoint(x: 5, y: 5)) == .zero)
        let noImage = ImageFit(imageSize: .zero, viewSize: CGSize(width: 100, height: 100))
        #expect(noImage.scale == 0)
        #expect(noImage.imagePoint(fromView: CGPoint(x: 5, y: 5)) == .zero)
    }
}

@Suite struct ImageFitCanvasTests {
    @Test func aMarginLeavesRoomAroundTheCanvasToDrawBeyondItsEdge() {
        let fit = ImageFit(imageSize: CGSize(width: 400, height: 200), viewSize: CGSize(width: 300, height: 300), margin: 20)
        #expect(fit.scale == 0.65)
        #expect(fit.frame == CGRect(x: 20, y: 85, width: 260, height: 130))
        let plain = ImageFit(imageSize: CGSize(width: 400, height: 200), viewSize: CGSize(width: 300, height: 300))
        #expect(plain.scale == 0.75)
    }

    @Test func aNegativeOriginPutsTheCanvasCornerAtTheFramesCorner() {
        // A 421 × 314 canvas that grew 5 pixels left and 3 up: annotation space starts at (-5, -3).
        let fit = ImageFit(imageSize: CGSize(width: 421, height: 314), viewSize: CGSize(width: 842, height: 628), origin: CGPoint(x: -5, y: -3))
        #expect(fit.scale == 2)
        #expect(fit.viewPoint(fromImage: CGPoint(x: -5, y: -3)) == fit.frame.origin)
        #expect(fit.viewPoint(fromImage: .zero) == CGPoint(x: fit.frame.minX + 10, y: fit.frame.minY + 6))
        #expect(fit.imagePoint(fromView: fit.frame.origin) == CGPoint(x: -5, y: -3))
        #expect(fit.imagePoint(fromView: CGPoint(x: fit.frame.minX + 10, y: fit.frame.minY + 6)) == .zero)
        let rect = fit.viewRect(fromImage: CGRect(x: 0, y: 0, width: 10, height: 5))
        #expect(rect == CGRect(x: fit.frame.minX + 10, y: fit.frame.minY + 6, width: 20, height: 10))
    }

    @Test func clampingKeepsAPointOnTheCanvasUnlessAskedNotTo() {
        let fit = ImageFit(imageSize: CGSize(width: 400, height: 200), viewSize: CGSize(width: 400, height: 200), origin: CGPoint(x: -10, y: -10))
        let outside = CGPoint(x: -50, y: 500)
        #expect(fit.imagePoint(fromView: outside) == CGPoint(x: -10, y: 190))
        #expect(fit.imagePoint(fromView: outside, clamped: false) == CGPoint(x: -60, y: 490))
    }
}
