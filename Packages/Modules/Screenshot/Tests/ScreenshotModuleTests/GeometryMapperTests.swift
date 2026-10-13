import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct GeometryMapperTests {
    /// MacBook display at the origin, 4K monitor centred above it.
    let primary = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
    let external = DisplayInfo(id: 2, frame: CGRect(x: -1164, y: 982, width: 3840, height: 2160), scale: 1)
    var displays: [DisplayInfo] { [primary, external] }

    @Test func flipsBetweenAppKitAndCG() {
        let appKit = CGRect(x: 10, y: 20, width: 30, height: 40)
        let cg = GeometryMapper.cgRect(fromAppKit: appKit, primaryHeight: 982)
        #expect(cg == CGRect(x: 10, y: 922, width: 30, height: 40))
        #expect(GeometryMapper.appKitRect(fromCG: cg, primaryHeight: 982) == appKit)
    }

    @Test func displayAbovePrimaryHasNegativeCGOrigin() {
        let cg = GeometryMapper.cgRect(fromAppKit: external.frame, primaryHeight: 982)
        #expect(cg == CGRect(x: -1164, y: -2160, width: 3840, height: 2160))
        #expect(GeometryMapper.appKitRect(fromCG: cg, primaryHeight: 982) == external.frame)
    }

    @Test func conversionStandardisesNegativeSizes() {
        let reversed = CGRect(x: 40, y: 60, width: -30, height: -40)
        #expect(GeometryMapper.cgRect(fromAppKit: reversed, primaryHeight: 982) == CGRect(x: 10, y: 922, width: 30, height: 40))
    }

    @Test func findsDisplayContainingPoint() {
        #expect(GeometryMapper.display(containing: CGPoint(x: 100, y: 100), in: displays) == primary)
        #expect(GeometryMapper.display(containing: CGPoint(x: -1000, y: 2000), in: displays) == external)
        #expect(GeometryMapper.display(containing: CGPoint(x: -1000, y: 500), in: displays) == nil)
        #expect(GeometryMapper.display(containing: CGPoint(x: 1512, y: 500), in: displays) == nil)
    }

    @Test func sharedEdgeFollowsMouseLocationConvention() {
        // AppKit reports the cursor's y in (minY, maxY]: the top row of the primary display is y = 982.
        #expect(GeometryMapper.display(containing: CGPoint(x: 100, y: 982), in: displays) == primary)
        #expect(GeometryMapper.display(containing: CGPoint(x: 100, y: 982.5), in: displays) == external)
        #expect(GeometryMapper.display(containing: CGPoint(x: 100, y: 3142), in: displays) == external)
        #expect(GeometryMapper.display(containing: CGPoint(x: -1164, y: 1500), in: displays) == external)
    }

    @Test func clampsSelectionCrossingDisplays() {
        let selection = CGRect(x: 0, y: 900, width: 300, height: 200)
        #expect(GeometryMapper.clamp(selection, to: primary) == CGRect(x: 0, y: 900, width: 300, height: 82))
        #expect(GeometryMapper.clamp(selection, to: external) == CGRect(x: 0, y: 982, width: 300, height: 118))
    }

    @Test func clampStandardisesReversedSelection() {
        let reversed = CGRect(x: 1600, y: 500, width: -200, height: -100)
        #expect(GeometryMapper.clamp(reversed, to: primary) == CGRect(x: 1400, y: 400, width: 112, height: 100))
    }

    @Test func clampOutsideDisplayIsEmptyOnItsEdge() {
        let clamped = GeometryMapper.clamp(CGRect(x: 2000, y: 100, width: 50, height: 50), to: primary)
        #expect(clamped == CGRect(x: 1512, y: 100, width: 0, height: 50))
        #expect(clamped.isEmpty)
    }

    @Test func pixelRectOnRetinaDisplayRoundsOutward() {
        let selection = CGRect(x: 100.25, y: 200.5, width: 50.5, height: 30.25)
        // x: 200.5 ... 301.5, y from the top: 1502.5 ... 1563.
        #expect(GeometryMapper.pixelRect(for: selection, on: primary) == CGRect(x: 200, y: 1502, width: 102, height: 61))
    }

    @Test func pixelRectOnExternalDisplayUsesItsOriginAndScale() {
        let selection = CGRect(x: -1000.5, y: 1000, width: 200, height: 100.5)
        // x: 163.5 ... 363.5, y from the top (3142): 2041.5 ... 2142.
        #expect(GeometryMapper.pixelRect(for: selection, on: external) == CGRect(x: 163, y: 2041, width: 201, height: 101))
    }

    @Test func pixelRectOfWholeDisplayIsTheImage() {
        #expect(GeometryMapper.pixelRect(for: primary.frame, on: primary) == CGRect(x: 0, y: 0, width: 3024, height: 1964))
        #expect(GeometryMapper.pixelRect(for: external.frame, on: external) == CGRect(x: 0, y: 0, width: 3840, height: 2160))
    }

    @Test func pixelRectIsClampedToImageBounds() {
        let selection = CGRect(x: 1500, y: -10, width: 50, height: 20)
        #expect(GeometryMapper.pixelRect(for: selection, on: primary) == CGRect(x: 3000, y: 1944, width: 24, height: 20))
        let outside = GeometryMapper.pixelRect(for: CGRect(x: 0, y: 1000, width: 10, height: 10), on: primary)
        #expect(outside.isEmpty)
        #expect(CGRect(x: 0, y: 0, width: 3024, height: 1964).contains(outside.origin))
    }

    @Test func normalizesDragsInAnyDirection() {
        let expected = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(GeometryMapper.normalizedSelection(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 40, y: 60)) == expected)
        #expect(GeometryMapper.normalizedSelection(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 10, y: 20)) == expected)
        #expect(GeometryMapper.normalizedSelection(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 10, y: 60)) == expected)
        #expect(GeometryMapper.normalizedSelection(from: CGPoint(x: 10, y: 60), to: CGPoint(x: 40, y: 20)) == expected)
        #expect(GeometryMapper.normalizedSelection(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5)) == CGRect(x: 5, y: 5, width: 0, height: 0))
    }
}
