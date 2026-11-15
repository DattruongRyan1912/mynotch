import CoreGraphics
import Testing
@testable import TranslationModule

/// Accessibility counts from the top left of the main display, down; AppKit from its bottom left, up. A selection's place
/// has to cross from one to the other, on any display, and a chip has to stay on the display of the selection.
@Suite struct SelectionGeometryTests {
    let main = ScreenArea(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    /// To the right, with its top level with the main display's: in AppKit it hangs 180 pt below zero.
    let right = ScreenArea(frame: CGRect(x: 1440, y: -180, width: 1920, height: 1080), visibleFrame: CGRect(x: 1440, y: -180, width: 1920, height: 1055))
    /// To the left, with its bottom level with the main display's: in AppKit it reaches 180 pt above the main display.
    let left = ScreenArea(frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055))
    let chip = CGSize(width: 200, height: 30)

    var all: [ScreenArea] { [main, right, left] }

    // MARK: Accessibility to AppKit

    @Test func theTopOfTheMainDisplayIsItsHeightInAppKit() {
        let rect = SelectionGeometry.cocoaRect(fromAccessibility: CGRect(x: 100, y: 50, width: 200, height: 20), primaryHeight: 900)
        #expect(rect == CGRect(x: 100, y: 830, width: 200, height: 20))
    }

    @Test func aSelectionOnTheDisplayToTheRightKeepsItsPlace() {
        // 50 pt under the top of the right display, which is the top of the main one too.
        let bounds = CGRect(x: 1540, y: 50, width: 120, height: 20)
        let anchor = SelectionGeometry.anchor(bounds: bounds, pointer: .zero, screens: all)
        #expect(anchor == CGRect(x: 1540, y: 830, width: 120, height: 20))
        #expect(right.frame.contains(anchor))
    }

    @Test func aSelectionOnTheDisplayAboveTheMainOneHasANegativeAccessibilityY() {
        // The left display reaches 180 pt above the main one, so its top is at y = -180 for Accessibility.
        let bounds = CGRect(x: -1820, y: -130, width: 200, height: 20)
        let anchor = SelectionGeometry.anchor(bounds: bounds, pointer: .zero, screens: all)
        #expect(anchor == CGRect(x: -1820, y: 1010, width: 200, height: 20))
        #expect(left.frame.contains(anchor))
    }

    @Test func aSelectionOnTheDisplayBelowTheTopOfTheRightOneIsStillOnIt() {
        // 1000 pt down the right display: past the bottom of the main one, since it is taller.
        let bounds = CGRect(x: 2000, y: 1000, width: 80, height: 18)
        let anchor = SelectionGeometry.anchor(bounds: bounds, pointer: .zero, screens: all)
        #expect(anchor == CGRect(x: 2000, y: -118, width: 80, height: 18))
        #expect(right.frame.contains(anchor))
    }

    @Test func theMainDisplayIsTheFirstOfTheList() {
        // The same rectangle read against a taller "main" display lands elsewhere: the first one sets the height.
        let tall = ScreenArea(frame: CGRect(x: 0, y: 0, width: 1000, height: 1200), visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 1175))
        let anchor = SelectionGeometry.anchor(bounds: CGRect(x: 100, y: 100, width: 50, height: 20), pointer: .zero, screens: [tall, main])
        #expect(anchor.origin.y == 1080)
    }

    // MARK: the end of the selection, for the small button

    @Test func aMouseSelectionEndsWhereThePointerIsWithinItsRectangle() {
        let rect = CGRect(x: 100, y: 300, width: 200, height: 20)
        let end = SelectionGeometry.endAnchor(of: rect, pointer: CGPoint(x: 260, y: 310), byPointer: true)
        #expect(end == CGRect(x: 260, y: 300, width: 0, height: 20))
        #expect(SelectionGeometry.endAnchor(of: rect, pointer: CGPoint(x: 330, y: 310), byPointer: true).origin.x == 300)
        #expect(SelectionGeometry.endAnchor(of: rect, pointer: CGPoint(x: 70, y: 310), byPointer: true).origin.x == 100)
    }

    @Test func aKeyboardSelectionEndsAtTheRightEdgeOfItsRectangle() {
        let rect = CGRect(x: 100, y: 300, width: 200, height: 20)
        let end = SelectionGeometry.endAnchor(of: rect, pointer: CGPoint(x: 5, y: 5), byPointer: false)
        #expect(end == CGRect(x: 300, y: 300, width: 0, height: 20))
    }

    @Test func aSelectionWithNoRectangleIsWhereThePointerIs() {
        let point = CGRect(x: 120, y: 340, width: 0, height: 0)
        #expect(SelectionGeometry.endAnchor(of: point, pointer: CGPoint(x: 120, y: 340), byPointer: true) == point)
        #expect(SelectionGeometry.endAnchor(of: point, pointer: CGPoint(x: 900, y: 900), byPointer: false) == point)
    }

    @Test func theButtonGoesThroughTheChipsOwnPlacement() {
        // Below the end of the selection, centred on it; above when there is no room; and kept on the display.
        let button = CGSize(width: 22, height: 22)
        let low = SelectionGeometry.endAnchor(of: CGRect(x: 100, y: 500, width: 200, height: 20), pointer: CGPoint(x: 250, y: 510), byPointer: true)
        let below = SelectionGeometry.chipFrame(size: button, anchor: low, screens: all)
        #expect(below == CGRect(x: 239, y: 472, width: 22, height: 22))
        let near = SelectionGeometry.endAnchor(of: CGRect(x: 100, y: 5, width: 200, height: 20), pointer: CGPoint(x: 250, y: 10), byPointer: true)
        let above = SelectionGeometry.chipFrame(size: button, anchor: near, screens: all)
        #expect(above.minY >= 25)
        let edge = SelectionGeometry.endAnchor(of: CGRect(x: 1400, y: 500, width: 100, height: 20), pointer: CGPoint(x: 1500, y: 510), byPointer: false)
        #expect(main.visibleFrame.union(right.visibleFrame).contains(SelectionGeometry.chipFrame(size: button, anchor: edge, screens: all)))
    }

    // MARK: where there is nothing to go by

    @Test(arguments: [
        nil,
        CGRect(x: 100, y: 100, width: 0, height: 20),
        CGRect(x: 100, y: 100, width: 50, height: 0),
        CGRect(x: 100, y: 100, width: -50, height: 20),
        CGRect(x: 100, y: 99_000, width: 50, height: 20),
        CGRect(x: CGFloat.nan, y: 100, width: 50, height: 20),
        CGRect(x: 100, y: 100, width: CGFloat.infinity, height: 20),
        CGRect.zero,
    ])
    func boundsThatCannotBeTrustedFallBackToThePointer(bounds: CGRect?) {
        let anchor = SelectionGeometry.anchor(bounds: bounds, pointer: CGPoint(x: 600, y: 300), screens: all)
        #expect(anchor == CGRect(x: 600, y: 300, width: 0, height: 0))
    }

    @Test func withNoDisplaysThePointerIsAllThereIs() {
        let anchor = SelectionGeometry.anchor(bounds: CGRect(x: 1, y: 2, width: 3, height: 4), pointer: CGPoint(x: 7, y: 8), screens: [])
        #expect(anchor == CGRect(x: 7, y: 8, width: 0, height: 0))
    }

    // MARK: when the pointer is the better guide

    @Test func aRectangleBesideThePointerIsBelievedForAMouseGesture() {
        let bounds = CGRect(x: 100, y: 100, width: 200, height: 20)
        let anchor = SelectionGeometry.anchor(bounds: bounds, pointer: CGPoint(x: 250, y: 790), screens: all, pointerMatters: true)
        #expect(anchor == CGRect(x: 100, y: 780, width: 200, height: 20))
    }

    @Test func aRectangleFarFromThePointerIsNotBelievedForAMouseGesture() {
        // Some apps answer with a rectangle at the corner of the display whatever is selected.
        let bounds = CGRect(x: 0, y: 0, width: 40, height: 20)
        let pointer = CGPoint(x: 800, y: 400)
        #expect(SelectionGeometry.anchor(bounds: bounds, pointer: pointer, screens: all, pointerMatters: true) == CGRect(origin: pointer, size: .zero))
        // A keyboard selection has no pointer to check against, so the rectangle is all there is.
        #expect(SelectionGeometry.anchor(bounds: bounds, pointer: pointer, screens: all, pointerMatters: false) == CGRect(x: 0, y: 880, width: 40, height: 20))
    }

    @Test func aTallSelectionOfAMouseGestureGoesByThePointerNotTheBlock() {
        // A paragraph 300 pt tall: the end of the drag is where the user is looking, not under the whole block.
        let bounds = CGRect(x: 100, y: 100, width: 400, height: 300)
        let pointer = CGPoint(x: 480, y: 520)
        #expect(SelectionGeometry.anchor(bounds: bounds, pointer: pointer, screens: all, pointerMatters: true) == CGRect(origin: pointer, size: .zero))
        let threeLines = CGRect(x: 100, y: 100, width: 400, height: 60)
        #expect(SelectionGeometry.anchor(bounds: threeLines, pointer: CGPoint(x: 480, y: 760), screens: all, pointerMatters: true).height == 60)
    }

    @Test func aTallSelectionOfTheKeyboardKeepsItsRectangle() {
        let bounds = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(SelectionGeometry.anchor(bounds: bounds, pointer: CGPoint(x: 480, y: 520), screens: all, pointerMatters: false).height == 300)
    }

    // MARK: the chip's place

    @Test func theChipSitsJustBelowTheSelectionCentredOnIt() {
        let frame = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: 500, y: 400, width: 100, height: 20), screens: [main])
        #expect(frame == CGRect(x: 450, y: 364, width: 200, height: 30))
    }

    @Test func belowThePointerWhenThereIsNoSelectionRectangle() {
        let frame = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: 600, y: 300, width: 0, height: 0), screens: [main])
        #expect(frame == CGRect(x: 500, y: 264, width: 200, height: 30))
    }

    @Test func aboveTheSelectionWhenThereIsNoRoomBelow() {
        let frame = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: 500, y: 20, width: 100, height: 20), screens: [main])
        #expect(frame == CGRect(x: 450, y: 46, width: 200, height: 30))
    }

    @Test func aSelectionTallerThanTheDisplayLeavesTheChipInsideIt() {
        let frame = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: 500, y: 0, width: 100, height: 875), screens: [main])
        #expect(frame == CGRect(x: 450, y: 845, width: 200, height: 30))
    }

    @Test func theChipStaysUnderTheMenuBar() {
        let frame = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: 500, y: 860, width: 100, height: 15), screens: [main])
        #expect(frame.maxY <= main.visibleFrame.maxY)
        // Below fits here, so it is below.
        #expect(frame.maxY < 860)
    }

    @Test func theChipIsPushedBackFromTheEdges() {
        let atRight = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: 1400, y: 400, width: 30, height: 20), screens: [main])
        #expect(atRight.maxX == main.visibleFrame.maxX)
        let atLeft = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: 0, y: 400, width: 10, height: 20), screens: [main])
        #expect(atLeft.minX == main.visibleFrame.minX)
    }

    @Test func aChipLargerThanTheDisplayIsPinnedToItsCorner() {
        let frame = SelectionGeometry.chipFrame(size: CGSize(width: 2000, height: 30), anchor: CGRect(x: 500, y: 400, width: 100, height: 20), screens: [main])
        #expect(frame.origin.x == 0)
    }

    // MARK: how much room there is

    @Test func theRoomIsTheBiggerSideOfTheSelection() {
        // 394 pt below and 449 above (the menu bar is not room).
        #expect(SelectionGeometry.room(besides: CGRect(x: 500, y: 400, width: 100, height: 20), screens: [main]) == 449)
        // Near the bottom there is more above; near the top, more below.
        #expect(SelectionGeometry.room(besides: CGRect(x: 500, y: 20, width: 100, height: 20), screens: [main]) == 829)
        #expect(SelectionGeometry.room(besides: CGRect(x: 500, y: 840, width: 100, height: 20), screens: [main]) == 834)
    }

    @Test func theRoomIsOfTheDisplayOfTheSelection() {
        #expect(SelectionGeometry.room(besides: CGRect(x: 2000, y: 100, width: 100, height: 20), screens: all) == 749)
    }

    @Test func aSelectionTallerThanTheDisplayLeavesNoRoom() {
        #expect(SelectionGeometry.room(besides: CGRect(x: 500, y: 0, width: 100, height: 875), screens: [main]) == 0)
    }

    @Test func withNoDisplaysThereIsAsMuchRoomAsAChipEverTakes() {
        #expect(SelectionGeometry.room(besides: CGRect(x: 500, y: 400, width: 100, height: 20), screens: []) == SelectionChipLayout.maxHeight)
    }

    // MARK: several displays

    @Test func theChipIsOnTheDisplayOfTheSelection() {
        let onRight = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: 2000, y: 100, width: 100, height: 20), screens: all)
        #expect(onRight == CGRect(x: 1950, y: 64, width: 200, height: 30))
        let onLeft = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: -1000, y: 500, width: 100, height: 20), screens: all)
        #expect(onLeft == CGRect(x: -1050, y: 464, width: 200, height: 30))
    }

    @Test func aSelectionAtTheEdgeOfTheMainDisplayDoesNotPushTheChipOntoTheNextOne() {
        let frame = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: 1380, y: 300, width: 100, height: 20), screens: all)
        #expect(frame.maxX == main.visibleFrame.maxX)
        #expect(main.frame.contains(frame))
    }

    @Test func belowTheBottomOfTheRightDisplayTheChipGoesAboveTheSelection() {
        let frame = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: 2000, y: -170, width: 100, height: 20), screens: all)
        #expect(frame == CGRect(x: 1950, y: -144, width: 200, height: 30))
    }

    @Test func aSelectionAcrossTwoDisplaysIsOnTheOneWithItsCentre() {
        // 1300...1700 wide: the centre, 1500, is on the right display, whose left edge is 1440.
        let frame = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: 1300, y: 400, width: 400, height: 20), screens: all)
        #expect(frame.minX >= right.visibleFrame.minX)
        #expect(right.frame.contains(frame))
    }

    @Test func aPointOutsideEveryDisplayGoesToTheNearest() {
        let frame = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: 3500, y: 100, width: 10, height: 10), screens: all)
        #expect(right.visibleFrame.contains(frame))
    }

    @Test func withNoDisplaysTheChipIsJustBelow() {
        let frame = SelectionGeometry.chipFrame(size: chip, anchor: CGRect(x: 500, y: 400, width: 100, height: 20), screens: [])
        #expect(frame == CGRect(x: 450, y: 364, width: 200, height: 30))
    }
}
