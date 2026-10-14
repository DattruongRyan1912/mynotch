import CoreGraphics
import Testing
@testable import ClipboardModule

/// Where the floating panel goes: pure geometry on made-up screens, so no test needs a display.
@Suite struct ClipboardPanelPlacementTests {
    typealias Placement = ClipboardPanelPlacement
    typealias Screen = ClipboardPanelPlacement.Screen

    static let size = CGSize(width: 640, height: 400)
    static let offset = Placement.pointerOffset

    /// A laptop screen with its menu bar (32 pt) and Dock (60 pt) taken off, and a monitor to its right that
    /// extends below it.
    static let main = Screen(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleFrame: CGRect(x: 0, y: 60, width: 1512, height: 890)
    )
    static let external = Screen(
        frame: CGRect(x: 1512, y: -300, width: 1920, height: 1080), visibleFrame: CGRect(x: 1512, y: -300, width: 1920, height: 1050)
    )
    static let screens = [main, external]

    func frame(at pointer: CGPoint, on screens: [Screen] = screens, size: CGSize = size) -> CGRect {
        Placement.frame(size: size, pointer: pointer, screens: screens)
    }

    // MARK: Near the pointer

    @Test func theTopLeftCornerSitsBelowAndRightOfThePointer() {
        let pointer = CGPoint(x: 400, y: 700)
        let frame = frame(at: pointer)

        #expect(frame.size == Self.size)
        #expect(frame.minX == pointer.x + Self.offset)
        #expect(frame.maxY == pointer.y - Self.offset)
    }

    @Test func nearTheRightEdgeThePanelOpensLeftOfThePointer() {
        let pointer = CGPoint(x: 1450, y: 700)
        let frame = frame(at: pointer, on: [Self.main])

        #expect(frame.maxX == pointer.x - Self.offset)
        #expect(Self.main.visibleFrame.contains(frame))
    }

    @Test func nearTheBottomThePanelOpensAboveThePointer() {
        let pointer = CGPoint(x: 400, y: 150)
        let frame = frame(at: pointer)

        #expect(frame.minY == pointer.y + Self.offset)
        #expect(Self.main.visibleFrame.contains(frame))
    }

    @Test func inTheBottomRightCornerThePointerIsOutsideThePanel() {
        let pointer = CGPoint(x: 1500, y: 70)
        let frame = frame(at: pointer, on: [Self.main])

        #expect(!frame.contains(pointer))
        #expect(Self.main.visibleFrame.contains(frame))
    }

    @Test func theMenuBarAndTheDockStayClear() {
        // Under the menu bar: the panel's top would otherwise be above the visible area.
        let high = frame(at: CGPoint(x: 400, y: 975), on: [Self.main])
        #expect(high.maxY <= Self.main.visibleFrame.maxY)
        // Over the Dock.
        let low = frame(at: CGPoint(x: 400, y: 5), on: [Self.main])
        #expect(low.minY >= Self.main.visibleFrame.minY)
    }

    // MARK: Which screen

    @Test func thePanelStaysOnTheScreenThatHasThePointer() {
        let onExternal = frame(at: CGPoint(x: 2000, y: 300))
        #expect(Self.external.visibleFrame.contains(onExternal))

        let onMain = frame(at: CGPoint(x: 300, y: 300))
        #expect(Self.main.visibleFrame.contains(onMain))
    }

    @Test func aPointerOnTheSharedEdgeBelongsToTheScreenOnTheRight() {
        // 1512 is the left edge of the monitor and the (excluded) right edge of the laptop screen.
        let frame = frame(at: CGPoint(x: 1512, y: 300))
        #expect(Self.external.visibleFrame.contains(frame))
    }

    @Test func aPointerOnTheMonitorsLowerPartDoesNotPutThePanelOnTheLaptopScreen() {
        // Below the laptop screen's frame, inside the monitor's: only the monitor has it.
        let frame = frame(at: CGPoint(x: 1600, y: -250))
        #expect(Self.external.visibleFrame.contains(frame))
    }

    @Test func aPointerOutsideEveryScreenUsesTheNearestOne() {
        // A stale position after a monitor was unplugged: 300 pt past the right edge of the only screen.
        let frame = frame(at: CGPoint(x: 1812, y: 400), on: [Self.main])
        #expect(Self.main.visibleFrame.contains(frame))
    }

    @Test func withoutScreensThePanelIsStillPlaced() {
        let frame = frame(at: CGPoint(x: 100, y: 500), on: [])
        #expect(frame.size == Self.size)
        #expect(frame.minX == 100 + Self.offset)
    }

    @Test func aScreenSmallerThanThePanelKeepsItsTopLeftOnScreen() {
        let tiny = Screen(frame: CGRect(x: 0, y: 0, width: 500, height: 300), visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 300))
        let frame = frame(at: CGPoint(x: 250, y: 150), on: [tiny])

        #expect(frame.minX == 0)
        #expect(frame.maxY == 300)
    }

    // MARK: Restoring a pinned position

    @Test func aSavedPositionOnScreenIsKept() {
        let origin = CGPoint(x: 300, y: 200)
        let restored = Placement.restoredFrame(size: Self.size, origin: origin, screens: Self.screens)
        #expect(restored == CGRect(origin: origin, size: Self.size))
    }

    @Test func aSavedPositionPartlyOffScreenIsPulledBack() throws {
        let restored = try #require(Placement.restoredFrame(size: Self.size, origin: CGPoint(x: 1300, y: 800), screens: [Self.main]))
        #expect(Self.main.visibleFrame.contains(restored))
    }

    @Test func aSavedPositionOnAScreenThatIsGoneIsDropped() {
        // The monitor it was on has been unplugged.
        #expect(Placement.restoredFrame(size: Self.size, origin: CGPoint(x: 2500, y: 100), screens: [Self.main]) == nil)
        #expect(Placement.restoredFrame(size: Self.size, origin: CGPoint(x: 100, y: 100), screens: []) == nil)
    }

    @Test func aSavedPositionBetweenTwoScreensGoesToTheOneItOverlapsMore() throws {
        // 100 pt on the laptop screen, 540 pt on the monitor.
        let restored = try #require(Placement.restoredFrame(size: Self.size, origin: CGPoint(x: 1412, y: 200), screens: Self.screens))
        #expect(Self.external.visibleFrame.contains(restored))
    }
}
