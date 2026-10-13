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
