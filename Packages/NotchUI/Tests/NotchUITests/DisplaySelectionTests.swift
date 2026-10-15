import CoreGraphics
import Testing
@testable import NotchUI

/// Which displays show a notch, with fake screens: a laptop (the main one, with the menu bar), an external display to
/// its right and another above it. No `NSScreen` is read.
@Suite struct DisplaySelectionTests {
    static let laptop: CGDirectDisplayID = 1
    static let right: CGDirectDisplayID = 2
    static let above: CGDirectDisplayID = 3

    static let frames: [(displayID: CGDirectDisplayID, frame: CGRect)] = [
        (laptop, CGRect(x: 0, y: 0, width: 1512, height: 982)),
        (right, CGRect(x: 1512, y: 0, width: 1920, height: 1080)),
        (above, CGRect(x: -1000, y: 982, width: 1920, height: 1080)),
    ]

    // MARK: modes

    @Test func everyDisplayShowsANotchInTheDefaultMode() {
        #expect(DisplaySelection.shown(mode: .all, displays: [1, 2, 3], active: 2) == [1, 2, 3])
        #expect(DisplaySelection.shown(mode: .all, displays: [1], active: nil) == [1])
    }

    @Test func theMainDisplayAloneShowsItInMainMode() {
        #expect(DisplaySelection.shown(mode: .main, displays: [1, 2, 3], active: 3) == [1])
    }

    @Test func theDisplayThatBecomesMainTakesTheNotchWhenTheArrangementChanges() {
        // The system lists the menu bar's display first; dragging the menu bar to the other display reorders the list.
        #expect(DisplaySelection.shown(mode: .main, displays: [1, 2], active: 1) == [1])
        #expect(DisplaySelection.shown(mode: .main, displays: [2, 1], active: 1) == [2])
    }

    @Test func theActiveDisplayAloneShowsItInTheActiveMode() {
        #expect(DisplaySelection.shown(mode: .cursor, displays: [1, 2, 3], active: 2) == [2])
        #expect(DisplaySelection.shown(mode: .cursor, displays: [1, 2, 3], active: 3) == [3])
    }

    @Test func theActiveModeFallsBackToTheMainDisplayWhenNothingIsActiveOrItWentAway() {
        #expect(DisplaySelection.shown(mode: .cursor, displays: [1, 2], active: nil) == [1])
        // The display the user was on was unplugged.
        #expect(DisplaySelection.shown(mode: .cursor, displays: [1], active: 2) == [1])
        #expect(DisplaySelection.shown(mode: .cursor, displays: [2, 1], active: 3) == [2])
    }

    @Test func noDisplayMeansNoNotchInAnyMode() {
        for mode in DisplayMode.allCases {
            #expect(DisplaySelection.shown(mode: mode, displays: [], active: nil).isEmpty, "\(mode)")
        }
    }

    @Test func pluggingAndUnpluggingADisplayChangesWhereTheNotchesAre() {
        var displays: [CGDirectDisplayID] = [1]
        #expect(DisplaySelection.shown(mode: .all, displays: displays, active: 1) == [1])
        displays.append(2)
        #expect(DisplaySelection.shown(mode: .all, displays: displays, active: 1) == [1, 2])
        #expect(DisplaySelection.shown(mode: .main, displays: displays, active: 1) == [1])
        #expect(DisplaySelection.shown(mode: .cursor, displays: displays, active: 2) == [2])
        displays.removeLast()
        #expect(DisplaySelection.shown(mode: .all, displays: displays, active: 2) == [1])
        #expect(DisplaySelection.shown(mode: .cursor, displays: displays, active: 2) == [1])
    }

    // MARK: the pointer

    @Test func theDisplayUnderThePointerIsTheOneWhoseFrameHoldsIt() {
        #expect(DisplaySelection.display(at: CGPoint(x: 100, y: 100), in: Self.frames) == Self.laptop)
        #expect(DisplaySelection.display(at: CGPoint(x: 1600, y: 500), in: Self.frames) == Self.right)
        #expect(DisplaySelection.display(at: CGPoint(x: -500, y: 1500), in: Self.frames) == Self.above)
    }

    @Test func aScreensTopRowBelongsToItAndNotToTheDisplayAboveIt() {
        // AppKit reports the pointer at y == maxY on the top row (where the notch is): that is the laptop, not the display above.
        #expect(DisplaySelection.display(at: CGPoint(x: 10, y: 982), in: Self.frames) == Self.laptop)
        #expect(DisplaySelection.display(at: CGPoint(x: 10, y: 983), in: Self.frames) == Self.above)
    }

    @Test func aPointerOutsideEveryDisplayIsOnNone() {
        #expect(DisplaySelection.display(at: CGPoint(x: 5000, y: 5000), in: Self.frames) == nil)
        #expect(DisplaySelection.display(at: CGPoint(x: 10, y: 10), in: []) == nil)
    }
}
