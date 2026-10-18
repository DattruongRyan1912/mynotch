import CoreGraphics
import Testing
@testable import ScreenshotModule

/// The crop frame's geometry: what a drag makes of it, and how it stays inside the image.
@Suite struct CropFrameTests {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    func frame(_ rect: CGRect, ratio: CGFloat? = nil, in bounds: CGRect? = nil) -> CropFrame {
        CropFrame(rect: rect, bounds: bounds ?? self.bounds, ratio: ratio)
    }

    func ratio(of rect: CGRect) -> CGFloat { rect.width / rect.height }

    // MARK: Presets

    @Test func theFivePresetsAreNamedAsTheUserReadsThem() {
        #expect(CropAspect.allCases == [.free, .square, .fourThree, .sixteenNine, .original])
        #expect(CropAspect.allCases.map(\.title) == ["Tự do", "1:1", "4:3", "16:9", "Như ảnh gốc"])
    }

    @Test func eachPresetKeepsItsRatioAndTheOriginalFollowsTheCapture() throws {
        let capture = CGSize(width: 1200, height: 800)
        #expect(CropAspect.free.ratio(of: capture) == nil)
        #expect(CropAspect.square.ratio(of: capture) == 1)
        #expect(try abs(#require(CropAspect.fourThree.ratio(of: capture)) - 4.0 / 3.0) < 1e-9)
        #expect(try abs(#require(CropAspect.sixteenNine.ratio(of: capture)) - 16.0 / 9.0) < 1e-9)
        #expect(CropAspect.original.ratio(of: capture) == 1.5)
        #expect(CropAspect.original.ratio(of: CGSize(width: 0, height: 0)) == nil)
    }

    // MARK: Making a frame

    @Test func draggingAnywhereMakesTheFrameBetweenTheTwoPoints() throws {
        let made = try #require(CropFrame.dragging(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 300, y: 200), in: bounds, ratio: nil))
        #expect(made.rect == CGRect(x: 100, y: 50, width: 200, height: 150))
        let backwards = try #require(CropFrame.dragging(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 50), in: bounds, ratio: nil))
        #expect(backwards.rect == made.rect)
    }

    @Test func aFrameNeverLeavesTheImage() throws {
        let made = try #require(CropFrame.dragging(from: CGPoint(x: -50, y: 40), to: CGPoint(x: 900, y: 500), in: bounds, ratio: nil))
        #expect(made.rect == CGRect(x: 0, y: 40, width: 400, height: 260))
        let padded = CGRect(x: -20, y: -10, width: 440, height: 330)
        let inPadding = try #require(CropFrame.dragging(from: CGPoint(x: -100, y: -100), to: CGPoint(x: 50, y: 50), in: padded, ratio: nil))
        #expect(inPadding.rect == CGRect(x: -20, y: -10, width: 70, height: 60))
    }

    @Test func aClickOrASliverMakesNoFrame() {
        #expect(CropFrame.dragging(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50), in: bounds, ratio: nil) == nil)
        #expect(CropFrame.dragging(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 300, y: 55), in: bounds, ratio: nil) == nil)
        #expect(CropFrame.dragging(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 55, y: 200), in: bounds, ratio: nil) == nil)
    }

    @Test func aLockedRatioFollowsTheLongerPull() throws {
        let wide = try #require(CropFrame.dragging(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 60), in: bounds, ratio: 1))
        #expect(wide.rect == CGRect(x: 10, y: 10, width: 100, height: 100))
        let tall = try #require(CropFrame.dragging(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 140), in: bounds, ratio: 1))
        #expect(tall.rect == CGRect(x: 10, y: 10, width: 130, height: 130))
        let sixteenNine = try #require(CropFrame.dragging(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 160, y: 10), in: bounds, ratio: 16.0 / 9.0))
        #expect(sixteenNine.rect.width == 160)
        #expect(abs(sixteenNine.rect.height - 90) < 0.001)
    }

    @Test func aLockedRatioHoldsAtTheEdgeInsteadOfBeingClampedOnOneSide() throws {
        // From (300, 200) towards the far corner there are 100 columns and 100 rows, so a 2:1 frame is 100 × 50 at most.
        let made = try #require(CropFrame.dragging(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 900, y: 900), in: bounds, ratio: 2))
        #expect(made.rect == CGRect(x: 300, y: 200, width: 100, height: 50))
        // Towards the near corner the room is 300 by 200 pixels, so it is 300 × 150 at most.
        let back = try #require(CropFrame.dragging(from: CGPoint(x: 300, y: 200), to: CGPoint(x: -900, y: -900), in: bounds, ratio: 2))
        #expect(back.rect == CGRect(x: 0, y: 50, width: 300, height: 150))
    }

    // MARK: Moving

    @Test func draggingInsideMovesTheFrameAndKeepsItsSize() {
        let moved = frame(CGRect(x: 100, y: 100, width: 80, height: 60)).moved(by: CGSize(width: 30, height: -20))
        #expect(moved.rect == CGRect(x: 130, y: 80, width: 80, height: 60))
    }

    @Test func aMovedFrameStopsAtEveryEdge() {
        let start = frame(CGRect(x: 100, y: 100, width: 80, height: 60))
        #expect(start.moved(by: CGSize(width: -500, height: 0)).rect.minX == 0)
        #expect(start.moved(by: CGSize(width: 500, height: 0)).rect.maxX == 400)
        #expect(start.moved(by: CGSize(width: 0, height: -500)).rect.minY == 0)
        #expect(start.moved(by: CGSize(width: 0, height: 500)).rect.maxY == 300)
        #expect(start.moved(by: CGSize(width: 500, height: 500)).rect.size == CGSize(width: 80, height: 60))
    }

    // MARK: Resizing

    @Test func anEdgeHandleMovesOnlyItsEdge() {
        let start = frame(CGRect(x: 100, y: 100, width: 80, height: 60))
        #expect(start.resized(.right, by: CGSize(width: 40, height: 99)).rect == CGRect(x: 100, y: 100, width: 120, height: 60))
        #expect(start.resized(.left, by: CGSize(width: -40, height: 99)).rect == CGRect(x: 60, y: 100, width: 120, height: 60))
        #expect(start.resized(.bottom, by: CGSize(width: 99, height: 25)).rect == CGRect(x: 100, y: 100, width: 80, height: 85))
        #expect(start.resized(.top, by: CGSize(width: 99, height: -25)).rect == CGRect(x: 100, y: 75, width: 80, height: 85))
    }

    @Test func aCornerHandleMovesTwoEdgesAndLeavesTheOppositeCornerWhereItIs() {
        let start = frame(CGRect(x: 100, y: 100, width: 80, height: 60))
        #expect(start.resized(.bottomRight, by: CGSize(width: 20, height: 10)).rect == CGRect(x: 100, y: 100, width: 100, height: 70))
        #expect(start.resized(.topLeft, by: CGSize(width: -20, height: -10)).rect == CGRect(x: 80, y: 90, width: 100, height: 70))
        #expect(start.resized(.topRight, by: CGSize(width: 20, height: -10)).rect == CGRect(x: 100, y: 90, width: 100, height: 70))
        #expect(start.resized(.bottomLeft, by: CGSize(width: -20, height: 10)).rect == CGRect(x: 80, y: 100, width: 100, height: 70))
    }

    @Test func aHandleStopsAtTheImageEdge() {
        let start = frame(CGRect(x: 100, y: 100, width: 80, height: 60))
        #expect(start.resized(.right, by: CGSize(width: 900, height: 0)).rect.maxX == 400)
        #expect(start.resized(.left, by: CGSize(width: -900, height: 0)).rect.minX == 0)
        #expect(start.resized(.top, by: CGSize(width: 0, height: -900)).rect.minY == 0)
        #expect(start.resized(.bottom, by: CGSize(width: 0, height: 900)).rect.maxY == 300)
        #expect(start.resized(.bottomRight, by: CGSize(width: 900, height: 900)).rect == CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    @Test func aHandleCannotShrinkTheFrameBelowTheMinimumOrFlipIt() {
        let start = frame(CGRect(x: 100, y: 100, width: 80, height: 60))
        let side = CropFrame.minimumSide
        #expect(start.resized(.right, by: CGSize(width: -900, height: 0)).rect == CGRect(x: 100, y: 100, width: side, height: 60))
        #expect(start.resized(.left, by: CGSize(width: 900, height: 0)).rect == CGRect(x: 180 - side, y: 100, width: side, height: 60))
        #expect(start.resized(.top, by: CGSize(width: 0, height: 900)).rect == CGRect(x: 100, y: 160 - side, width: 80, height: side))
        #expect(start.resized(.topLeft, by: CGSize(width: 900, height: 900)).rect == CGRect(x: 180 - side, y: 160 - side, width: side, height: side))
    }

    @Test func aCornerOfALockedFrameKeepsTheRatioAndTheOppositeCorner() {
        let start = frame(CGRect(x: 100, y: 100, width: 160, height: 90), ratio: 16.0 / 9.0)
        let grown = start.resized(.bottomRight, by: CGSize(width: 32, height: 5)).rect
        #expect(grown.origin == CGPoint(x: 100, y: 100))
        #expect(abs(ratio(of: grown) - 16.0 / 9.0) < 0.001)
        #expect(grown.width == 192)
        let shrunk = start.resized(.topLeft, by: CGSize(width: 32, height: 2)).rect
        #expect(abs(shrunk.maxX - 260) < 0.001 && abs(shrunk.maxY - 190) < 0.001)
        #expect(abs(ratio(of: shrunk) - 16.0 / 9.0) < 0.001)
    }

    @Test func aLockedCornerGrowsOnlyAsFarAsTheRatioFitsTheImage() {
        let start = frame(CGRect(x: 200, y: 150, width: 100, height: 100), ratio: 1)
        let grown = start.resized(.bottomRight, by: CGSize(width: 900, height: 900)).rect
        #expect(grown == CGRect(x: 200, y: 150, width: 150, height: 150))
    }

    @Test func anEdgeOfALockedFrameKeepsTheRatioAndTheMiddleOfTheOtherAxis() {
        let start = frame(CGRect(x: 100, y: 100, width: 160, height: 90), ratio: 16.0 / 9.0)
        let wider = start.resized(.right, by: CGSize(width: 32, height: 0)).rect
        #expect(wider.minX == 100 && wider.width == 192)
        #expect(abs(ratio(of: wider) - 16.0 / 9.0) < 0.001)
        #expect(abs(wider.midY - 145) < 0.001)
        let taller = start.resized(.top, by: CGSize(width: 0, height: -45)).rect
        #expect(taller.maxY == 190 && taller.height == 135)
        #expect(abs(ratio(of: taller) - 16.0 / 9.0) < 0.001)
        #expect(abs(taller.midX - 180) < 0.001)
    }

    @Test func anEdgeOfALockedFrameNeverPushesTheOtherAxisOutOfTheImage() {
        let nearTop = frame(CGRect(x: 100, y: 10, width: 160, height: 20), ratio: 8)
        let grown = nearTop.resized(.right, by: CGSize(width: 200, height: 0)).rect
        #expect(grown.minY >= 0 && grown.maxY <= 300 && grown.maxX <= 400)
        #expect(abs(ratio(of: grown) - 8) < 0.001)
    }

    // MARK: Grabbing

    @Test func aPointOnACornerOrEdgeGrabsItsHandle() {
        let start = frame(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(start.grab(at: CGPoint(x: 100, y: 100), tolerance: 10) == .handle(.topLeft))
        #expect(start.grab(at: CGPoint(x: 305, y: 195), tolerance: 10) == .handle(.bottomRight))
        #expect(start.grab(at: CGPoint(x: 300, y: 100), tolerance: 10) == .handle(.topRight))
        #expect(start.grab(at: CGPoint(x: 96, y: 200), tolerance: 10) == .handle(.bottomLeft))
        #expect(start.grab(at: CGPoint(x: 200, y: 95), tolerance: 10) == .handle(.top))
        #expect(start.grab(at: CGPoint(x: 200, y: 203), tolerance: 10) == .handle(.bottom))
        #expect(start.grab(at: CGPoint(x: 104, y: 150), tolerance: 10) == .handle(.left))
        #expect(start.grab(at: CGPoint(x: 296, y: 150), tolerance: 10) == .handle(.right))
    }

    @Test func aPointInsideGrabsTheFrameAndOneOutsideGrabsNothing() {
        let start = frame(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(start.grab(at: CGPoint(x: 200, y: 150), tolerance: 10) == .inside)
        #expect(start.grab(at: CGPoint(x: 50, y: 50), tolerance: 10) == .outside)
        #expect(start.grab(at: CGPoint(x: 200, y: 215), tolerance: 10) == .outside)
        #expect(start.grab(at: CGPoint(x: 150, y: 80), tolerance: 10) == .outside)
    }

    @Test func aSmallFrameKeepsItsMiddleForMoving() {
        let small = frame(CGRect(x: 100, y: 100, width: 24, height: 24))
        #expect(small.grab(at: CGPoint(x: 112, y: 112), tolerance: 10) == .inside)
        #expect(small.grab(at: CGPoint(x: 100, y: 100), tolerance: 10) == .handle(.topLeft))
    }

    // MARK: Changing the ratio

    @Test func aPresetFitsTheLargestFrameOfThatRatioInsideTheOneThereIsAroundItsMiddle() {
        let start = frame(CGRect(x: 100, y: 100, width: 200, height: 100))
        let square = start.fitting(ratio: 1).rect
        #expect(square == CGRect(x: 150, y: 100, width: 100, height: 100))
        let wide = start.fitting(ratio: 4).rect
        #expect(wide.width == 200 && wide.height == 50 && wide.midY == 150)
        let same = start.fitting(ratio: 2).rect
        #expect(same == start.rect)
    }

    @Test func withoutAFrameAPresetStartsWithTheLargestCentredOne() {
        let square = CropFrame.largest(ratio: 1, in: bounds)
        #expect(square.rect == CGRect(x: 50, y: 0, width: 300, height: 300))
        let wide = CropFrame.largest(ratio: 16.0 / 9.0, in: bounds)
        #expect(wide.rect.width == 400)
        #expect(abs(wide.rect.height - 225) < 0.001)
        #expect(abs(wide.rect.midY - 150) < 0.001)
    }

    // MARK: Pixels

    @Test func theFrameIsAppliedOnWholePixelsInsideTheImage() {
        let rough = frame(CGRect(x: 10.4, y: 20.6, width: 100, height: 50))
        #expect(rough.pixelRect == CGRect(x: 10, y: 21, width: 100, height: 50))
        let edge = frame(CGRect(x: 390.4, y: 0.2, width: 9.8, height: 299.9))
        #expect(edge.pixelRect == CGRect(x: 390, y: 0, width: 10, height: 300))
    }
}
