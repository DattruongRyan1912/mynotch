import CoreGraphics
import Testing
@testable import WindowLayoutModule

/// What happens to a window that does not take the size a layout asks for (a smallest size, a fixed size, a size the
/// display it was on clamped), on displays with the Dock on each side and the menu bar at the top: it has to stay inside
/// the visible area, on the edge of its zone that the layout anchors it to. Fake attributes only: no real window is moved.
@Suite struct WindowPlacerTests {
    static let primaryHeight: CGFloat = 982
    /// The visible area (AppKit coordinates) of a 1512 x 982 display whose menu bar is 37 pt and whose Dock sits on one side.
    static let docks: [(name: String, area: CGRect)] = [
        ("no Dock", CGRect(x: 0, y: 0, width: 1512, height: 945)),
        ("Dock left", CGRect(x: 60, y: 0, width: 1452, height: 945)),
        ("Dock bottom", CGRect(x: 0, y: 70, width: 1512, height: 875)),
        ("Dock right", CGRect(x: 0, y: 0, width: 1452, height: 945)),
    ]
    /// The zones that are anchored to something other than the top left, and the ones next to them.
    static let zones: [(layout: SnapLayout, zone: Int)] = [
        (.thirds, 0), (.thirds, 1), (.thirds, 2), (.rightHalf, 0), (.leftHalf, 0),
        (.quarters, 0), (.quarters, 1), (.quarters, 2), (.quarters, 3), (.focus, 0),
    ]

    func placement(_ layout: SnapLayout, zone: Int, area: CGRect, gap: CGFloat = 0) -> SnapPlacement {
        SnapPlacement(
            frame: SnapSpace.accessibilityFrame(of: layout.frame(zone: zone, in: area, gap: gap), primaryHeight: Self.primaryHeight),
            area: SnapSpace.accessibilityFrame(of: area, primaryHeight: Self.primaryHeight),
            anchor: layout.zones[zone].anchor
        )
    }

    // MARK: a window that takes the size

    @Test func aWindowThatTakesTheSizeCostsTwoCallsAndIsNotMovedAgain() {
        let placement = placement(.rightHalf, zone: 0, area: Self.docks[0].area)
        let window = FakeWindowAttributes()
        #expect(WindowPlacer.place(placement, on: window))
        #expect(window.calls == ["size", "position"])
        #expect(window.frame == placement.frame)
    }

    @Test func aSizeTheDisplayClampedIsSetAgainOnceTheWindowIsThere() {
        let placement = placement(.fullScreen, zone: 0, area: Self.docks[0].area)
        let window = FakeWindowAttributes(frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        window.sizeLimitUntilMoved = CGSize(width: 800, height: 600)
        #expect(WindowPlacer.place(placement, on: window))
        #expect(window.calls == ["size", "position", "size"])
        #expect(window.frame == placement.frame)
    }

    // MARK: a window that does not

    @Test func aFixedWindowTooWideForARightThirdEndsAtTheRightEdgeNotOffTheScreen() {
        // The example of the review: 715 pt wide, dropped on the right third of a 1512 pt display, would end at x 1723.
        let placement = placement(.thirds, zone: 2, area: Self.docks[0].area)
        #expect(placement.frame == CGRect(x: 1008, y: 37, width: 504, height: 945))
        let window = FakeWindowAttributes(frame: CGRect(x: 100, y: 100, width: 715, height: 945))
        window.isResizable = false
        #expect(WindowPlacer.place(placement, on: window))
        #expect(window.frame == CGRect(x: 797, y: 37, width: 715, height: 945))
    }

    @Test func aWindowWithASmallestSizeIsOnlyAskedForTheSizeTwice() {
        let placement = placement(.thirds, zone: 2, area: Self.docks[0].area)
        let window = FakeWindowAttributes()
        window.minimum = CGSize(width: 715, height: 300)
        #expect(WindowPlacer.place(placement, on: window))
        #expect(window.calls == ["size", "position", "size"], "one retry for a size the display might have clamped, no more")
        #expect(window.frame.maxX == 1512)
    }

    @Test func everyZoneKeepsAWindowThatIsBiggerThanItInsideTheVisibleAreaOnItsAnchoredEdges() {
        for dock in Self.docks {
            for gap: CGFloat in [0, 8] {
                for (layout, zone) in Self.zones {
                    let placement = placement(layout, zone: zone, area: dock.area, gap: gap)
                    let target = placement.frame
                    // Wider than the zone by 150 pt, and taller by 120 pt where the zone is a part of the height (the quarters).
                    let tall = target.height < placement.area.height * 0.75
                    let window = FakeWindowAttributes()
                    window.minimum = CGSize(width: target.width + 150, height: target.height + (tall ? 120 : 0))
                    WindowPlacer.place(placement, on: window)
                    let name = "\(layout) \(zone), \(dock.name), gap \(gap): \(window.frame) for \(target) in \(placement.area)"
                    let frame = window.frame
                    #expect(placement.area.contains(frame), "inside the visible area: \(name)")
                    switch placement.anchor.horizontal {
                    case .leading: #expect(frame.minX == target.minX, "\(name)")
                    case .trailing: #expect(frame.maxX == target.maxX, "\(name)")
                    case .centre: #expect(abs(frame.midX - target.midX) <= 0.5, "\(name)")
                    }
                    switch placement.anchor.vertical {
                    case .top: #expect(frame.minY == target.minY, "\(name)")
                    case .bottom: #expect(frame.maxY == target.maxY, "\(name)")
                    case .centre: #expect(abs(frame.midY - target.midY) <= 0.5, "\(name)")
                    }
                }
            }
        }
    }

    @Test func aWindowTooTallForABottomQuarterGrowsUpwardFromTheBottomEdge() {
        // Bottom right quarter above a 70 pt Dock: the window keeps its bottom edge on the Dock's top edge.
        let placement = placement(.quarters, zone: 3, area: Self.docks[2].area)
        let window = FakeWindowAttributes()
        window.minimum = CGSize(width: 300, height: 700)
        WindowPlacer.place(placement, on: window)
        #expect(window.frame.maxY == placement.area.maxY)
        #expect(window.frame.maxX == placement.area.maxX)
        #expect(window.frame.height == 700)
    }

    @Test func aWindowTooWideForFocusStaysCentredOnADisplayWithTheDockOnTheLeft() {
        let placement = placement(.focus, zone: 0, area: Self.docks[1].area)
        let window = FakeWindowAttributes()
        window.minimum = CGSize(width: 1200, height: 100)
        WindowPlacer.place(placement, on: window)
        #expect(window.frame.width == 1200)
        // Centred in the visible area, which starts after the Dock.
        #expect(window.frame.midX == placement.area.midX)
        #expect(window.frame.minX >= 60)
    }

    @Test func aWindowSmallerThanItsZoneKeepsTheEdgeItIsAnchoredTo() {
        // A window that cannot grow past 400 pt: on the right half it stays against the right edge.
        let placement = placement(.rightHalf, zone: 0, area: Self.docks[3].area)
        let window = FakeWindowAttributes()
        window.maximum = CGSize(width: 400, height: 500)
        WindowPlacer.place(placement, on: window)
        #expect(window.frame.maxX == placement.frame.maxX)
        #expect(window.frame.minY == placement.frame.minY)
        #expect(window.frame.size == CGSize(width: 400, height: 500))
    }

    @Test func aWindowLargerThanTheWholeAreaStartsAtItsTopLeftWhereTheTitleBarIs() {
        for (layout, zone) in Self.zones {
            let placement = placement(layout, zone: zone, area: Self.docks[2].area)
            let window = FakeWindowAttributes()
            window.minimum = CGSize(width: placement.area.width + 100, height: placement.area.height + 100)
            WindowPlacer.place(placement, on: window)
            #expect(window.frame.origin == placement.area.origin, "\(layout) \(zone)")
        }
    }

    @Test func theGapIsKeptOnTheAnchoredSideOfAWindowThatIsTooBig() {
        let placement = placement(.thirds, zone: 2, area: Self.docks[0].area, gap: 16)
        let window = FakeWindowAttributes()
        window.minimum = CGSize(width: 700, height: 100)
        WindowPlacer.place(placement, on: window)
        let edge: CGFloat = 1512 - 16
        #expect(window.frame.maxX == edge)
    }

    // MARK: apps that refuse

    @Test func anAppThatRefusesToMoveIsNotCalledAgain() {
        let window = FakeWindowAttributes()
        window.isMovable = false
        #expect(!WindowPlacer.place(placement(.rightHalf, zone: 0, area: Self.docks[0].area), on: window))
        // Neither a second size nor a correction: it would only wait for the same refusal.
        #expect(window.calls == ["size", "position"])
    }

    @Test func aFixedSizeWindowIsStillMovedAndNotAskedForItsSizeAgain() {
        let window = FakeWindowAttributes()
        window.isResizable = false
        #expect(WindowPlacer.place(placement(.leftHalf, zone: 0, area: Self.docks[0].area), on: window))
        #expect(window.calls == ["size", "position"])
        #expect(window.frame.origin == CGPoint(x: 0, y: 37))
    }

    @Test func aSizeThatCannotBeReadLeavesTheWindowWhereItWasPlaced() {
        let placement = placement(.rightHalf, zone: 0, area: Self.docks[0].area)
        let window = FakeWindowAttributes()
        window.canReadSize = false
        #expect(WindowPlacer.place(placement, on: window))
        #expect(window.origin == placement.frame.origin)
        // Without a size there is nothing to correct and nothing to ask again.
        #expect(window.calls == ["size", "position"])
    }
}
