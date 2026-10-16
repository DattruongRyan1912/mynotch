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

    // MARK: right-aligned under the icon

    @Test func theBarIsRightAlignedUnderTheIconOnANotchedDisplay() {
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: 1_540, top: 1_117), screens: [notched])
        #expect(frame.maxX == 1_568)
        #expect(frame.size == content)
        // Directly under the 38-point bar, with a small gap.
        #expect(frame.maxY == 1_117 - 38 - gap)
    }

    @Test func theBarHangsUnderAShorterBarOnADisplayWithoutANotch() {
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: 1_300, top: 900), screens: [plain])
        #expect(frame.maxX == 1_328)
        #expect(frame.maxY == 900 - 24 - gap)
        #expect(frame.height == 44)
    }

    @Test func anIconAtTheEdgeOfTheDisplayKeepsTheBarInsideItsMargin() {
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: 1_410, top: 900), screens: [plain])
        #expect(frame.maxX == 1_440 - margin)
        #expect(frame.minX == 1_440 - margin - 300)
    }

    // MARK: centred when it does not fit

    @Test func theBarIsCentredWhenRightAligningWouldRunOffTheLeftEdge() {
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: 100, top: 900), screens: [plain])
        #expect(frame.midX == 720)
        #expect(frame.width == 300)
    }

    @Test func aBarBarelyFittingIsStillRightAligned() {
        // The icon's right edge is 308, so a 300-point bar starts exactly at the margin.
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: 280, top: 900), screens: [plain])
        #expect(frame.minX == margin)
        #expect(frame.maxX == 308)
    }

    @Test func aBarWiderThanTheDisplayTakesItAllAndScrolls() {
        let frame = MenuBarItemsBarPlacement.frame(content: CGSize(width: 3_000, height: 44), anchor: icon(x: 1_300, top: 900), screens: [plain])
        #expect(frame.width == 1_440 - 2 * margin)
        #expect(frame.minX == margin)
    }

    @Test func withoutAnIconTheBarIsCentredOnTheMainDisplay() {
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: nil, screens: [notched, plain])
        #expect(frame.midX == 864)
        #expect(frame.maxY == 1_117 - 38 - gap)
    }

    @Test func anIconNotOnAnyBarIsAsGoodAsNone() {
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: -9_900, top: 1_117), screens: [notched])
        #expect(frame.midX == 864)
    }

    // MARK: displays

    @Test func theBarFollowsTheIconToAnotherDisplay() {
        let external = MenuBarScreen(frame: CGRect(x: 1_728, y: -300, width: 2_560, height: 1_440), barHeight: 24)
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: 4_100, top: 1_140), screens: [notched, external])
        #expect(frame.maxX == 4_128)
        #expect(frame.maxY == 1_140 - 24 - gap)
    }

    @Test func aDisplayWithANegativeOriginIsCentredWithinItself() {
        let left = MenuBarScreen(frame: CGRect(x: -1_920, y: -200, width: 1_920, height: 1_080), barHeight: 24)
        let frame = MenuBarItemsBarPlacement.frame(content: content, anchor: icon(x: -1_900, top: 880), screens: [notched, left])
        #expect(frame.midX == -960)
        #expect(frame.maxY == 880 - 24 - gap)
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
