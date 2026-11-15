import CoreGraphics
import Testing
@testable import MyNotchCore

@Suite struct MenuBarItemsBarPlacementTests {
    private let notched = MenuBarScreen(frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117), barHeight: 38, notchGap: 764...964)
    private let plain = MenuBarScreen(frame: CGRect(x: 0, y: 0, width: 1_440, height: 900), barHeight: 24)
    private let content = CGSize(width: 300, height: 44)
    private let margin = MenuBarItemsBarPlacement.margin
    private let gap = MenuBarItemsBarPlacement.gap

    /// The MyNotch icon's window, hung from the top of a display whose top edge is at `top`.
    private func icon(x: CGFloat, top: CGFloat) -> CGRect {
        CGRect(x: x, y: top - 24, width: 28, height: 24)
    }

    // MARK: placed to the left of the icon

    @Test func theBarIsPlacedToTheLeftOfTheIconOnANotchedDisplay() {
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: 1_540, top: 1_117), screens: [notched])
        #expect(frame.maxX == 1_540)
        #expect(frame.size.width == content.width)
        #expect(frame.maxY == 1_117)
        #expect(frame.height == 24)
    }

    @Test func theBarIsPlacedOnTheBarOnADisplayWithoutANotch() {
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: 1_300, top: 900), screens: [plain])
        #expect(frame.maxX == 1_300)
        #expect(frame.maxY == 900)
        #expect(frame.height == 24)
    }

    @Test func anIconAtTheEdgeOfTheDisplayKeepsTheBarInsideItsMargin() {
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: 1_435, top: 900), screens: [plain])
        #expect(frame.maxX == 1_440 - margin)
        #expect(frame.minX == 1_440 - margin - 300)
    }

    @Test func theBarIsBoundedByTheNotchOnANotchedDisplay() {
        // Icon at x: 1200. Notch gap is 764...964, so minX is 964 + 8 = 972.
        // Available width to the left of icon is 1200 - 972 = 228 < 300.
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: 1_200, top: 1_117), screens: [notched])
        #expect(frame.minX == 972)
        #expect(frame.maxX == 1_200)
        #expect(frame.width == 228)
        #expect(frame.maxY == 1_117)
    }

    @Test func aBarBarelyFittingIsStillRightAligned() {
        // The icon's left edge is 308, so a 300-point bar starts exactly at margin (8).
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: 308, top: 900), screens: [plain])
        #expect(frame.minX == margin)
        #expect(frame.maxX == 308)
    }

    @Test func aBarWiderThanTheDisplayTakesItAllAndScrolls() {
        let frame = MenuBarItemsBarPlacement.frame(content: CGSize(width: 3_000, height: 44), anchor: icon(x: 1_300, top: 900), screens: [plain])
        #expect(frame.width == 1_300 - margin)
        #expect(frame.minX == margin)
        #expect(frame.maxX == 1_300)
    }

    @Test func withoutAnIconTheBarIsPlacedAtTheRightEdge() {
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: nil, screens: [notched, plain])
        #expect(frame.maxX == 1_728 - margin)
        #expect(frame.maxY == 1_117)
        #expect(frame.height == 38)
    }

    @Test func anIconNotOnAnyBarIsAsGoodAsNone() {
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: -9_900, top: 1_117), screens: [notched])
        #expect(frame.maxX == 1_728 - margin)
        #expect(frame.maxY == 1_117)
        #expect(frame.height == 38)
    }

    // MARK: displays

    @Test func theBarFollowsTheIconToAnotherDisplay() {
        let external = MenuBarScreen(frame: CGRect(x: 1_728, y: -300, width: 2_560, height: 1_440), barHeight: 24)
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: 4_100, top: 1_140), screens: [notched, external])
        #expect(frame.maxX == 4_100)
        #expect(frame.maxY == 1_140)
        #expect(frame.height == 24)
    }

    @Test func aDisplayWithANegativeOrigin() {
        let left = MenuBarScreen(frame: CGRect(x: -1_920, y: -200, width: 1_920, height: 1_080), barHeight: 24)
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: -100, top: 880), screens: [notched, left])
        #expect(frame.maxX == -100)
        #expect(frame.maxY == 880)
        #expect(frame.height == 24)
    }

    @Test func noDisplaysLeavesTheBarAtTheOrigin() {
        #expect(MenuBarItemsBarPlacement.frame(content: content, anchor: nil, screens: []) == CGRect(origin: .zero, size: content))
    }

    // MARK: how big the content is

    @Test func theContentIsAsWideAsItsCellsPlusSpacingAndPadding() {
        let size = MenuBarItemsBarMetrics.contentSize(cellWidths: [28, 28, 40])
        let padding = MenuBarItemsBarMetrics.padding
        #expect(size.width == 96 + 2 * MenuBarItemsBarMetrics.spacing + 2 * padding)
        #expect(size.height == MenuBarItemsBarMetrics.cellHeight + 2 * padding)
    }

    @Test func noCellsIsThePlaceForAMessage() {
        #expect(MenuBarItemsBarMetrics.contentSize(cellWidths: []) == MenuBarItemsBarMetrics.messageSize)
        #expect(MenuBarItemsBarMetrics.messageSize.height == MenuBarItemsBarMetrics.cellHeight + 2 * MenuBarItemsBarMetrics.padding)
    }

    @Test func aSingleCellHasNoSpacing() {
        #expect(MenuBarItemsBarMetrics.contentSize(cellWidths: [28]).width == 28 + 2 * MenuBarItemsBarMetrics.padding)
    }
}
