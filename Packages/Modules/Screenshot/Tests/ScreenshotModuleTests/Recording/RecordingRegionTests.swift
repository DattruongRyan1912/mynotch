import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct RecordingRegionTests {
    /// A 2× display 1000×600 pt, to the right of and lower than the primary one, so its origin is not (0, 0).
    static let display = DisplayInfo(id: 7, frame: CGRect(x: 1440, y: -200, width: 1000, height: 600), scale: 2)

    @Test func aSelectionBecomesWholePixelsOfTheDisplayFromItsTopLeft() throws {
        // AppKit: 100 pt from the display's left; its top edge is y = 50, and the display's top is y = 400: 350 pt down.
        let region = try #require(RecordingRegion(display: Self.display, selection: CGRect(x: 1540, y: -150, width: 300, height: 200)))

        #expect(region.pixelRect == CGRect(x: 200, y: 700, width: 600, height: 400))
        #expect(region.pixelWidth == 600 && region.pixelHeight == 400)
        #expect(region.sourceRect == CGRect(x: 100, y: 350, width: 300, height: 200))
    }

    @Test func theWholeDisplayIsItsPixelsFromTheOrigin() throws {
        let region = try #require(RecordingRegion(fullScreen: Self.display))

        #expect(region.pixelRect == CGRect(x: 0, y: 0, width: 2000, height: 1200))
        #expect(region.sourceRect == CGRect(x: 0, y: 0, width: 1000, height: 600))
    }

    @Test func anOddSizeLosesOnePixelSoTheVideoIsEven() throws {
        // Half-point edges at 2× cover pixels 1 to 202 across (201 wide) and 1000 to 1101 down (101 high).
        let region = try #require(RecordingRegion(display: Self.display, selection: CGRect(x: 1440.5, y: -150.5, width: 100.5, height: 50.5)))

        #expect(region.pixelWidth == 200 && region.pixelHeight == 100)
        let odd = try #require(RecordingRegion(display: DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 80), scale: 1), selection: CGRect(x: 0, y: 0, width: 33, height: 21)))
        #expect(odd.pixelWidth == 32 && odd.pixelHeight == 20)
    }

    @Test func aSelectionPastTheDisplayIsKeptOnIt() throws {
        let region = try #require(RecordingRegion(display: Self.display, selection: CGRect(x: 2340, y: 300, width: 400, height: 400)))

        #expect(region.pixelRect == CGRect(x: 1800, y: 0, width: 200, height: 200))
    }

    @Test func nothingLeftOfTheSelectionIsNoRegion() {
        #expect(RecordingRegion(display: Self.display, selection: CGRect(x: 0, y: 0, width: 50, height: 50)) == nil)
        #expect(RecordingRegion(display: Self.display, selection: CGRect(x: 1500, y: 0, width: 0, height: 80)) == nil)
    }

    @Test func thePointerIsMappedToPixelsOfTheVideoWithYDown() throws {
        let region = try #require(RecordingRegion(display: Self.display, selection: CGRect(x: 1540, y: -150, width: 300, height: 200)))

        // The region's top-left corner in AppKit: (1540, 50).
        #expect(region.pixelPoint(forAppKit: CGPoint(x: 1540, y: 50)) == CGPoint(x: 0, y: 0))
        // Its bottom-right corner: (1840, -150), 300 × 200 pt, 600 × 400 px.
        #expect(region.pixelPoint(forAppKit: CGPoint(x: 1840, y: -150)) == CGPoint(x: 600, y: 400))
        #expect(region.pixelPoint(forAppKit: CGPoint(x: 1690, y: -50)) == CGPoint(x: 300, y: 200))
    }

    @Test func aPointerOutsideTheRegionIsMappedNotClamped() throws {
        let region = try #require(RecordingRegion(display: Self.display, selection: CGRect(x: 1540, y: -150, width: 300, height: 200)))

        #expect(region.pixelPoint(forAppKit: CGPoint(x: 1500, y: 100)) == CGPoint(x: -80, y: -100))
        // Another display to the left of this one.
        let farLeft = region.pixelPoint(forAppKit: CGPoint(x: 100, y: 50)).x
        #expect(farLeft == -2880)
    }

    @Test func theCaptureAreaAndThePointerAgreeOnTheSameCorner() throws {
        let region = try #require(RecordingRegion(display: Self.display, selection: CGRect(x: 1555.25, y: -120.5, width: 301, height: 199)))
        // The first captured pixel is the top-left of the video, and the pointer there maps to (0, 0), however the selection rounded.
        let topLeft = CGPoint(x: Self.display.frame.minX + region.pixelRect.minX / 2, y: Self.display.frame.maxY - region.pixelRect.minY / 2)

        #expect(region.pixelPoint(forAppKit: topLeft) == .zero)
        #expect(region.sourceRect.minX * 2 == region.pixelRect.minX)
    }

    @Test func aRegionSurvivesTheRoundTripThroughJSON() throws {
        let region = try #require(RecordingRegion(display: Self.display, selection: CGRect(x: 1540, y: -150, width: 300, height: 200)))

        let decoded = try JSONDecoder().decode(RecordingRegion.self, from: JSONEncoder().encode(region))

        #expect(decoded == region)
    }
}
