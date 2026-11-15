import CoreGraphics
import Testing
@testable import MyNotchCore

@Suite struct MenuBarOrderTests {
    /// A display with a notch: its bar is 38 points tall at the top of a 1 117-point-high frame.
    private let main = MenuBarScreen(frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117), barHeight: 38)
    /// A status item's window: 24 points tall, hung from the top edge.
    private func item(x: CGFloat, width: CGFloat = 24, top: CGFloat = 1_117) -> CGRect {
        CGRect(x: x, y: top - 24, width: width, height: 24)
    }

    // MARK: left of the toggle

    @Test func aSeparatorOnTheLeftOfTheToggleIsLeftOfIt() {
        #expect(MenuBarOrder.isLeftOf(separator: item(x: 1_500), toggle: item(x: 1_540, width: 28), screens: [main]))
    }

    @Test func touchingItemsAreStillInOrder() {
        #expect(MenuBarOrder.isLeftOf(separator: item(x: 1_500), toggle: item(x: 1_524, width: 28), screens: [main]))
    }

    @Test func theToggleOnTheLeftIsNot() {
        #expect(!MenuBarOrder.isLeftOf(separator: item(x: 1_540, width: 28), toggle: item(x: 1_500), screens: [main]))
    }

    @Test func theSameCentreIsNotLeftOf() {
        #expect(!MenuBarOrder.isLeftOf(separator: item(x: 1_500), toggle: item(x: 1_500), screens: [main]))
        #expect(!MenuBarOrder.isLeftOf(separator: item(x: 1_490, width: 44), toggle: item(x: 1_500, width: 24), screens: [main]))
    }

    @Test func aSeparatorThatReachesPastTheMiddleOfTheToggleIsNotLeftOfItWhateverItsCentre() {
        // The centres are in order (1 535 < 1 554) but the separator's right edge is past the toggle's centre.
        #expect(!MenuBarOrder.isLeftOf(separator: item(x: 1_500, width: 70), toggle: item(x: 1_540, width: 28), screens: [main]))
        // Overlapping a little is fine: it ends before the toggle's centre.
        #expect(MenuBarOrder.isLeftOf(separator: item(x: 1_500, width: 45), toggle: item(x: 1_540, width: 28), screens: [main]))
    }

    @Test func aFrameWithoutAnAreaIsNotAnItem() {
        let flat = CGRect(x: 1_500, y: 1_093, width: 0, height: 24)
        #expect(!MenuBarOrder.isLeftOf(separator: flat, toggle: item(x: 1_540), screens: [main]))
        #expect(!MenuBarOrder.isLeftOf(separator: item(x: 1_500), toggle: CGRect(x: 1_540, y: 1_093, width: 28, height: 0), screens: [main]))
        #expect(!MenuBarOrder.isLeftOf(separator: .null, toggle: item(x: 1_540), screens: [main]))
    }

    // MARK: on a menu bar at all

    @Test func anItemParkedOffTheScreenDoesNotCount() {
        #expect(!MenuBarOrder.isLeftOf(separator: item(x: -9_000), toggle: item(x: 1_540), screens: [main]))
        #expect(!MenuBarOrder.isLeftOf(separator: item(x: 1_500), toggle: item(x: 1_900), screens: [main]))
    }

    @Test func anItemBelowTheBarDoesNotCount() {
        let low = CGRect(x: 1_500, y: 500, width: 24, height: 24)
        #expect(!MenuBarOrder.isLeftOf(separator: low, toggle: item(x: 1_540), screens: [main]))
        #expect(!MenuBarOrder.isLeftOf(separator: item(x: 1_500), toggle: low.offsetBy(dx: 40, dy: 0), screens: [main]))
    }

    @Test func noDisplayMeansNoOrder() {
        #expect(!MenuBarOrder.isLeftOf(separator: item(x: 1_500), toggle: item(x: 1_540), screens: []))
    }

    // MARK: displays

    @Test func bothItemsMustBeOnTheSameDisplay() {
        let external = MenuBarScreen(frame: CGRect(x: 1_728, y: -300, width: 2_560, height: 1_440), barHeight: 24)
        // The separator on the main display, the toggle on the external one: their positions are in unrelated spaces.
        #expect(!MenuBarOrder.isLeftOf(separator: item(x: 1_500), toggle: item(x: 3_000, top: 1_140), screens: [main, external]))
        // Both on the main display, with another one attached: judged there.
        #expect(MenuBarOrder.isLeftOf(separator: item(x: 1_500), toggle: item(x: 1_660), screens: [main, external]))
    }

    @Test func bothOnASecondDisplayWithANegativeOriginAreJudgedThere() {
        let left = MenuBarScreen(frame: CGRect(x: -1_920, y: -200, width: 1_920, height: 1_080), barHeight: 24)
        #expect(MenuBarOrder.isLeftOf(separator: item(x: -300, top: 880), toggle: item(x: -260, top: 880), screens: [main, left]))
        #expect(!MenuBarOrder.isLeftOf(separator: item(x: -260, top: 880), toggle: item(x: -300, top: 880), screens: [main, left]))
    }

    @Test func aDisplayAboveTheMainOneHasItsBarAtItsOwnTop() {
        let above = MenuBarScreen(frame: CGRect(x: 0, y: 1_117, width: 1_920, height: 1_080), barHeight: 24)
        #expect(MenuBarOrder.isLeftOf(separator: item(x: 1_600, top: 2_197), toggle: item(x: 1_640, top: 2_197), screens: [main, above]))
    }

    // MARK: reachable

    @Test func aToggleOnABarCanBeClicked() {
        #expect(MenuBarOrder.isReachable(toggle: item(x: 1_540), screens: [main]))
    }

    @Test func aToggleThatTheSeparatorPushedOffTheScreenCannot() {
        #expect(MenuBarOrder.isReachable(toggle: item(x: -9_980), screens: [main]) == false)
        #expect(!MenuBarOrder.isReachable(toggle: item(x: 1_728), screens: [main]))
    }

    @Test func aToggleWithoutAnAreaOrBelowTheBarOrWithoutDisplaysCannot() {
        #expect(!MenuBarOrder.isReachable(toggle: .null, screens: [main]))
        #expect(!MenuBarOrder.isReachable(toggle: CGRect(x: 1_540, y: 500, width: 28, height: 24), screens: [main]))
        #expect(!MenuBarOrder.isReachable(toggle: item(x: 1_540), screens: []))
    }
}
