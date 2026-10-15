import CoreGraphics
import Testing
@testable import MyNotchCore

@Suite struct MenuBarZoneTests {
    private let main = MenuBarScreen(frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117), barHeight: 38)

    @Test func theTopBandOfADisplayCounts() {
        #expect(MenuBarZone.contains(CGPoint(x: 500, y: 1_100), in: [main]))
        #expect(MenuBarZone.contains(CGPoint(x: 0, y: 1_117 - 38), in: [main]))
    }

    @Test func theVeryTopEdgeCountsEvenThoughTheFrameDoesNotContainIt() {
        #expect(MenuBarZone.contains(CGPoint(x: 10, y: 1_117), in: [main]))
    }

    @Test func belowTheBandOrOutsideTheDisplayDoesNot() {
        #expect(!MenuBarZone.contains(CGPoint(x: 500, y: 1_117 - 39), in: [main]))
        #expect(!MenuBarZone.contains(CGPoint(x: 1_728, y: 1_110), in: [main]))
        #expect(!MenuBarZone.contains(CGPoint(x: -1, y: 1_110), in: [main]))
        #expect(!MenuBarZone.contains(CGPoint(x: 500, y: 1_118), in: [main]))
    }

    @Test func noDisplayMeansNoMenuBar() {
        #expect(!MenuBarZone.contains(CGPoint(x: 1, y: 1), in: []))
    }

    @Test func everyDisplayHasItsOwnBandWithItsOwnHeight() {
        // An external display to the right, lower than the main one and without a notch.
        let external = MenuBarScreen(frame: CGRect(x: 1_728, y: -300, width: 2_560, height: 1_440), barHeight: 24)
        let screens = [main, external]
        #expect(MenuBarZone.contains(CGPoint(x: 3_000, y: 1_130), in: screens))
        #expect(!MenuBarZone.contains(CGPoint(x: 3_000, y: 1_100), in: screens))
        #expect(MenuBarZone.contains(CGPoint(x: 500, y: 1_090), in: screens))
        // 30 points below the external display's top is in the notched display's band height but not in its own.
        #expect(!MenuBarZone.contains(CGPoint(x: 3_000, y: 1_140 - 30), in: screens))
    }

    @Test func aDisplayAboveTheMainOneHasItsBandAtItsOwnTop() {
        let above = MenuBarScreen(frame: CGRect(x: 0, y: 1_117, width: 1_920, height: 1_080), barHeight: 24)
        let screens = [main, above]
        #expect(MenuBarZone.contains(CGPoint(x: 100, y: 2_190), in: screens))
        // The main display's band is under the other display's body, so the pointer cannot be there without being in it.
        #expect(!MenuBarZone.contains(CGPoint(x: 100, y: 1_500), in: screens))
    }
}
