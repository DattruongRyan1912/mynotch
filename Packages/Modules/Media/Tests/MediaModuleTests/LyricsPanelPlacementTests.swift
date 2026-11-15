import CoreGraphics
import Foundation
import Testing
@testable import MediaModule

/// Where the floating lyrics panel goes and how it is remembered for each display, as pure geometry: no display is needed.
/// AppKit coordinates: origin at the bottom left of the main display, y up.
@Suite struct LyricsPanelPlacementTests {
    /// A 1440 x 900 main display with a 25 pt menu bar and a 70 pt Dock.
    let main = PanelDisplay(
        key: "MAIN", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805)
    )
    /// A 1920 x 1080 display to the right of it, with no Dock.
    let side = PanelDisplay(
        key: "SIDE", frame: CGRect(x: 1440, y: -100, width: 1920, height: 1080), visibleFrame: CGRect(x: 1440, y: -100, width: 1920, height: 1055)
    )

    func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect { CGRect(x: x, y: y, width: width, height: height) }

    // MARK: the first time

    @Test func theFirstTimeThePanelIsCentredAboveTheBottomOfTheVisibleArea() {
        let frame = LyricsPanelPlacement.defaultFrame(on: main)
        #expect(frame.size == LyricsPanelPlacement.defaultSize)
        #expect(frame.midX == main.visibleFrame.midX)
        #expect(frame.minY == main.visibleFrame.minY + LyricsPanelPlacement.bottomGap)
        #expect(main.visibleFrame.contains(frame))
    }

    @Test func aPlacementThatRemembersNothingOpensThereOnTheMainDisplay() {
        #expect(LyricsPanelPlacement().restoredFrame(among: [main, side]) == LyricsPanelPlacement.defaultFrame(on: main))
    }

    @Test func withNoDisplayAtAllTheDefaultSizeIsAnswered() {
        #expect(LyricsPanelPlacement().restoredFrame(among: []).size == LyricsPanelPlacement.defaultSize)
    }

    // MARK: remembering

    @Test func whereTheUserLeftThePanelIsWhereItComesBack() {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(200, 300, 500, 150), among: [main, side])
        #expect(placement.restoredFrame(among: [main, side]) == rect(200, 300, 500, 150))
    }

    @Test func eachDisplayKeepsItsOwnFrameAndTheLastOneUsedIsWhereItOpens() {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(200, 300, 500, 150), among: [main, side])
        placement.remember(rect(2000, 400, 600, 180), among: [main, side])
        #expect(placement.lastDisplay == "SIDE")
        #expect(placement.restoredFrame(among: [main, side]) == rect(2000, 400, 600, 180))
        // Moved back: the main display's frame is the one it had left there.
        placement.remember(rect(200, 300, 500, 150), among: [main, side])
        #expect(placement.lastDisplay == "MAIN")
        #expect(placement.restoredFrame(among: [main, side]) == rect(200, 300, 500, 150))
    }

    @Test func aFrameStraddlingTwoDisplaysBelongsToTheOneItCoversMore() {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(1300, 300, 500, 150), among: [main, side])
        #expect(placement.lastDisplay == "SIDE")
        placement.remember(rect(1100, 300, 500, 150), among: [main, side])
        #expect(placement.lastDisplay == "MAIN")
    }

    @Test func aFrameOnNoDisplayIsNotRemembered() {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(9000, 9000, 500, 150), among: [main, side])
        #expect(placement == LyricsPanelPlacement())
    }

    // MARK: displays that come and go

    @Test func theFrameIsKeptRelativeToItsDisplayWhichMayMoveInTheArrangement() {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(2000, 400, 600, 180), among: [main, side])
        var moved = side
        moved.frame.origin = CGPoint(x: 1440, y: 200)
        moved.visibleFrame.origin = CGPoint(x: 1440, y: 200)
        // The display is 300 points higher in the arrangement, so is the panel.
        #expect(placement.restoredFrame(among: [main, moved]) == rect(2000, 700, 600, 180))
    }

    @Test func aDisplayThatIsGoneSendsThePanelToTheMainOneAndComingBackBringsItHome() {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(200, 300, 500, 150), among: [main, side])
        placement.remember(rect(2000, 400, 600, 180), among: [main, side])
        #expect(placement.restoredFrame(among: [main]) == rect(200, 300, 500, 150))
        // Nothing was remembered while it was on the main display, so it still belongs on the other one.
        #expect(placement.lastDisplay == "SIDE")
        #expect(placement.restoredFrame(among: [main, side]) == rect(2000, 400, 600, 180))
    }

    @Test func aDisplayWithNothingRememberedGetsTheDefaultFrame() {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(2000, 400, 600, 180), among: [main, side])
        #expect(placement.restoredFrame(among: [main]) == LyricsPanelPlacement.defaultFrame(on: main))
    }

    // MARK: staying usable

    @Test func aFrameThatNoLongerFitsTheDisplayIsPulledInside() {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(1300, 700, 500, 150), among: [main, side])
        placement.remember(rect(1000, 700, 400, 150), among: [main, side])
        var smaller = main
        smaller.frame.size = CGSize(width: 1024, height: 768)
        smaller.visibleFrame = rect(0, 70, 1024, 673)
        let restored = placement.restoredFrame(among: [smaller])
        #expect(smaller.visibleFrame.contains(restored))
        #expect(restored.size == CGSize(width: 400, height: 150))
    }

    @Test func aFrameBiggerThanTheDisplayIsShrunkToIt() {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(0, 100, 1400, 700), among: [main])
        var small = main
        small.frame.size = CGSize(width: 500, height: 400)
        small.visibleFrame = rect(0, 30, 500, 350)
        let restored = placement.restoredFrame(among: [small])
        #expect(small.visibleFrame.contains(restored))
        #expect(restored.width == 500 && restored.height == 350)
    }

    @Test func aSizeBelowTheMinimumIsRaisedToIt() {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(300, 300, 50, 20), among: [main])
        let restored = placement.restoredFrame(among: [main])
        #expect(restored.size == LyricsPanelPlacement.minimumSize)
        #expect(restored.origin == CGPoint(x: 300, y: 300))
    }

    // MARK: stored form

    @Test func itSurvivesBeingStoredAsJSON() throws {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(200, 300, 500, 150), among: [main, side])
        placement.remember(rect(2000, 400, 600, 180), among: [main, side])
        let decoded = try JSONDecoder().decode(LyricsPanelPlacement.self, from: JSONEncoder().encode(placement))
        #expect(decoded == placement)
        #expect(decoded.restoredFrame(among: [main, side]) == rect(2000, 400, 600, 180))
    }

    @Test func aStoredValueFromSomethingElseIsAnErrorForTheSettingsToAnswerWithTheDefault() {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(LyricsPanelPlacement.self, from: Data("[1,2]".utf8)) }
    }

    @Test func notANumberOrInfiniteNumbersAreNeverRemembered() {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(.nan, 300, 500, 150), among: [main])
        placement.remember(rect(200, .infinity, 500, 150), among: [main])
        #expect(placement == LyricsPanelPlacement())
    }
}
