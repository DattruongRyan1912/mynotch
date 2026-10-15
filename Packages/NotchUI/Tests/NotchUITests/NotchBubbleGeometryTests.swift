import CoreGraphics
import MyNotchCore
import Testing
@testable import NotchUI

/// The bubbles beside the collapsed notch and the list under it: frames, gaps, what fits in the fixed panel, and which
/// part of the notch a pointer is over.
@Suite struct NotchBubbleGeometryTests {
    let macBook = NotchGeometryTests.macBook14
    let external = NotchGeometryTests.external

    func geometry(_ screen: ScreenDescriptor, _ config: NotchLayoutConfig = NotchLayoutConfig()) -> NotchGeometry {
        NotchGeometry(screen: screen, config: config)
    }

    /// A pill so wide (the widest notch with 230 pt on each side, 772 pt) and a notch so tall that the second bubble no
    /// longer fits the 900 pt panel.
    static let crowded = NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40, compactSideWidth: 230, openWidth: 720)

    // MARK: Frames

    @Test func aBubbleIsAsTallAsTheCollapsedNotchBody() {
        #expect(geometry(macBook).bubbleDiameter == 32)
        #expect(geometry(external).bubbleDiameter == 25)
        #expect(geometry(external, Self.crowded).bubbleDiameter == 40)
    }

    @Test func theBubblesSitToTheRightOfTheCollapsedNotchWithASixPointGapFromItsBody() {
        let geometry = geometry(macBook)
        // The pill is 325 wide with 6 pt ears, so its body ends 156.5 pt right of the centre line.
        #expect(geometry.bubbleFrame(at: 0) == CGRect(x: 162.5, y: 0, width: 32, height: 32))
        #expect(geometry.bubbleFrame(at: 1) == CGRect(x: 200.5, y: 0, width: 32, height: 32))
        #expect(geometry.bubbleFrame(at: 0).minX - (162.5 - geometry.cornerRadii(for: .compact).top) == NotchGeometry.bubbleGap)
        #expect(geometry.bubbleFrame(at: 1).minX - geometry.bubbleFrame(at: 0).maxX == NotchGeometry.bubbleGap)
    }

    @Test func aNotchlessDisplayGetsTheSameBubblesBesideThePill() {
        let geometry = geometry(external)
        #expect(geometry.bubbleFrame(at: 0) == CGRect(x: 162.5, y: 0, width: 25, height: 25))
        #expect(geometry.bubbleFrame(at: 1) == CGRect(x: 193.5, y: 0, width: 25, height: 25))
    }

    @Test func theBubblesFollowAWiderPill() {
        let wide = geometry(macBook, NotchLayoutConfig(compactSideWidth: 90))
        // 26 pt more of side width each side of the notch: the right edge of the pill moves by that much.
        #expect(wide.bubbleFrame(at: 0).minX == geometry(macBook).bubbleFrame(at: 0).minX + 26)
    }

    @Test func screenFramesAreTheSameFramesAtTheTopOfTheScreen() {
        let geometry = geometry(macBook)
        let frame = macBook.frame
        // The notch centre is at x 754.5 on this display; AppKit's y grows upward from the bottom.
        #expect(geometry.bubbleScreenFrame(at: 0, in: frame) == CGRect(x: 754.5 + 162.5, y: 982 - 32, width: 32, height: 32))
        #expect(geometry.bubbleScreenFrame(at: 1, in: frame) == CGRect(x: 754.5 + 200.5, y: 982 - 32, width: 32, height: 32))
        let above = NotchGeometryTests.externalAboveLeft
        let offset = self.geometry(above).bubbleScreenFrame(at: 0, in: above.frame)
        #expect(offset == CGRect(x: -40 + 162.5, y: 982 + 1080 - 25, width: 25, height: 25))
    }

    // MARK: Capacity and the fixed panel

    @Test func twoBubblesFitBesideAnOrdinaryPill() {
        #expect(geometry(macBook).bubbleCapacity == NotchGeometry.maxBubbles)
        #expect(geometry(external).bubbleCapacity == NotchGeometry.maxBubbles)
        #expect(geometry(external, NotchLayoutConfig(virtualNotchWidth: 120, virtualNotchHeight: 24, openWidth: 480)).bubbleCapacity == 2)
    }

    @Test func theWidestPillTheSettingsCanMakeStillHasRoomForTwoBubbles() {
        // The side width is not a setting (it is 64 pt), so a pill is at most the widest virtual notch (300 pt) with it.
        let widest = NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40)
        #expect(widest.compactSideWidth == 64)
        for screen in [macBook, external, NotchGeometryTests.externalAboveLeft] {
            let geometry = geometry(screen, widest)
            #expect(geometry.bubbleCapacity == NotchGeometry.maxBubbles)
            #expect(geometry.panelFrame(in: screen.frame).contains(geometry.bubbleScreenFrame(at: NotchGeometry.maxBubbles - 1, in: screen.frame)))
        }
    }

    @Test func aWidestPillLeavesRoomForOneBubbleOnly() {
        #expect(geometry(external, Self.crowded).bubbleCapacity == 1)
    }

    @Test func everyBubbleThatFitsIsInsideThePanelAndNoneOverlap() {
        let screens = [macBook, external, NotchGeometryTests.externalAboveLeft]
        let configs = [
            NotchLayoutConfig(), Self.crowded,
            NotchLayoutConfig(virtualNotchWidth: 120, virtualNotchHeight: 24, openWidth: 480),
            NotchLayoutConfig(virtualNotchWidth: 300, compactSideWidth: 64),
            NotchLayoutConfig(virtualNotchWidth: 200, virtualNotchHeight: 40, compactSideWidth: 100),
        ]
        for screen in screens {
            for config in configs {
                let geometry = geometry(screen, config)
                let panel = geometry.panelFrame(in: screen.frame)
                let pill = geometry.shapeSize(for: .compact)
                let pillRect = CGRect(
                    x: screen.frame.midX + geometry.centerOffset - pill.width / 2, y: screen.frame.maxY - pill.height,
                    width: pill.width, height: pill.height
                )
                var previous: CGRect?
                for index in 0..<geometry.bubbleCapacity {
                    let rect = geometry.bubbleScreenFrame(at: index, in: screen.frame)
                    #expect(panel.contains(rect), "bubble \(index) fits the panel on \(screen.frame) with \(config)")
                    #expect(rect.width > 0 && rect.height == geometry.notchSize.height)
                    #expect(!rect.intersects(pillRect.insetBy(dx: 0.5, dy: 0.5)), "a bubble never covers the pill")
                    if let previous { #expect(rect.minX - previous.maxX == NotchGeometry.bubbleGap) }
                    previous = rect
                }
                // One more bubble than the capacity would not fit, so capacity is the most that does.
                if geometry.bubbleCapacity < NotchGeometry.maxBubbles {
                    #expect(!panel.contains(geometry.bubbleScreenFrame(at: geometry.bubbleCapacity, in: screen.frame)))
                }
            }
        }
    }

    @Test func thePillsShapeDoesNotTakeTheBubblesAsAnInput() {
        // The panel is fixed, and the pill's shape is a function of the state and of what hangs below it only: bubbles
        // come and go beside it without a size change of either (`shapeSize` has no parameter for them).
        let geometry = geometry(macBook)
        #expect(geometry.shapeSize(for: .compact) == CGSize(width: 325, height: 32))
        #expect(geometry.shapeSize(for: .compact, bottomHeight: 0) == geometry.shapeSize(for: .compact))
        #expect(geometry.panelSize == CGSize(width: 900, height: 432))
    }

    /// A bubble appears from a fraction of its size on the notch's spring (which overshoots a little) and leaves the
    /// same way: no step of that is empty, taller than the notch, or outside the panel.
    @Test func aBubbleComingOrGoingNeverPassesThroughAHiddenOrOutOfPanelFrame() {
        for screen in [macBook, external] {
            let geometry = geometry(screen)
            let panel = geometry.panelFrame(in: screen.frame)
            #expect(NotchTokens.bubbleAppearScale > 0 && NotchTokens.bubbleAppearScale < 1)
            for index in 0..<geometry.bubbleCapacity {
                let full = geometry.bubbleScreenFrame(at: index, in: screen.frame)
                let scales = (0 ... 20).map { NotchTokens.bubbleAppearScale + (1.03 - NotchTokens.bubbleAppearScale) * Double($0) / 20 }
                for scale in scales + scales.reversed() {
                    // Scaled about its leading edge, centred on the notch's height; the overshoot above the screen's top
                    // edge is under a point and off screen.
                    let size = CGSize(width: full.width * scale, height: full.height * scale)
                    let rect = CGRect(x: full.minX, y: full.midY - size.height / 2, width: size.width, height: size.height)
                    #expect(rect.width > 0 && rect.height > 0)
                    #expect(rect.minX >= panel.minX && rect.maxX <= panel.maxX && rect.minY >= panel.minY, "scale \(scale) of bubble \(index)")
                    #expect(rect.maxY <= panel.maxY + 1, "scale \(scale) of bubble \(index)")
                    #expect(rect.height <= full.height * 1.03 + 0.001)
                }
            }
        }
    }

    // MARK: The list

    @Test func theListIsTallEnoughForItsRowsAndFitsTheFixedPanelWhateverTheRowCount() {
        let geometry = geometry(macBook)
        #expect(geometry.listHeight(rows: 0) == 0)
        #expect(geometry.listHeight(rows: -3) == 0)
        #expect(geometry.listHeight(rows: 1) == NotchGeometry.listRowHeight + 2 * NotchGeometry.listInset)
        #expect(geometry.listHeight(rows: 3) == CGFloat(3 * 28 + 12))
        #expect(geometry.listHeight(rows: 100) == geometry.listHeight(rows: NotchGeometry.maxListRows))
        for rows in 0...20 {
            let size = geometry.shapeSize(for: .compact, bottomHeight: geometry.listHeight(rows: rows))
            #expect(size.height <= geometry.panelSize.height, "\(rows) rows fit the panel")
            #expect(size.height == 32 + geometry.listHeight(rows: rows))
        }
    }

    @Test func theListTakesTheStripsPlaceAndKeepsTheCompactWidth() {
        let geometry = geometry(macBook)
        let strip = geometry.bottomHeight(for: .compact, strip: 36, listRows: 0)
        let list = geometry.bottomHeight(for: .compact, strip: 36, listRows: 3)
        #expect(strip == 36)
        #expect(list == geometry.listHeight(rows: 3))
        #expect(geometry.shapeSize(for: .compact, bottomHeight: list).width == 325)
        #expect(geometry.bottomHeight(for: .compact, strip: 500, listRows: 0) == NotchGeometry.maxBottomHeight)
        #expect(geometry.bottomHeight(for: .compact, strip: .nan, listRows: 0) == 0)
        // Only the collapsed notch has either.
        for state in [NotchState.closed, .open("a"), .open(nil), .toast] {
            #expect(geometry.bottomHeight(for: state, strip: 36, listRows: 3) == 0, "\(state)")
        }
    }

    // MARK: Pointer zones

    func zone(
        _ point: CGPoint, _ state: NotchState = .compact, strip: CGFloat = 0, bubbles: Int = 0, listRows: Int = 0,
        dragging: Bool = false, screen: ScreenDescriptor? = nil, config: NotchLayoutConfig = NotchLayoutConfig()
    ) -> PointerZone {
        let screen = screen ?? macBook
        return geometry(screen, config).pointerZone(
            at: point, state: state, strip: strip, bubbles: bubbles, listRows: listRows, dragging: dragging, in: screen.frame
        )
    }

    /// Notch centre line and top of the MacBook test display, AppKit coordinates.
    let centre: CGFloat = 754.5
    let top: CGFloat = 982

    @Test func withoutBubblesOnlyThePillCountsAsInside() {
        #expect(zone(CGPoint(x: centre, y: top - 10)) == .notch)
        #expect(zone(CGPoint(x: centre + 170, y: top - 10)) == .notch)
        #expect(zone(CGPoint(x: centre + 178.5, y: top - 16)) == .outside)
        #expect(zone(CGPoint(x: centre, y: top - 60)) == .outside)
    }

    @Test func aBubbleIsItsOwnZoneAndTheGapAtTheNotchStaysThePills() {
        // The gap between the body and the first bubble is part of the pill's hit padding: moving onto a bubble never
        // leaves the notch's area on the way.
        #expect(zone(CGPoint(x: centre + 160, y: top - 16), bubbles: 1) == .notch)
        #expect(zone(CGPoint(x: centre + 178.5, y: top - 16), bubbles: 1) == .bubbles)
        #expect(zone(CGPoint(x: centre + 178.5, y: top), bubbles: 1) == .bubbles)
        #expect(zone(CGPoint(x: centre + 178.5, y: top - 36), bubbles: 1) == .bubbles)
        #expect(zone(CGPoint(x: centre + 178.5, y: top - 50), bubbles: 1) == .outside)
        // Beyond the last bubble only the padding counts.
        #expect(zone(CGPoint(x: centre + 196, y: top - 16), bubbles: 1) == .bubbles)
        #expect(zone(CGPoint(x: centre + 204, y: top - 16), bubbles: 1) == .outside)
    }

    @Test func theGapBetweenTwoBubblesBelongsToThemSoMovingAcrossNeverLeaves() {
        let between = CGPoint(x: centre + 197.5, y: top - 16)
        #expect(zone(between, bubbles: 2) == .bubbles)
        #expect(zone(CGPoint(x: centre + 216.5, y: top - 16), bubbles: 2) == .bubbles)
        #expect(zone(CGPoint(x: centre + 216.5, y: top - 16), bubbles: 1) == .outside)
        #expect(zone(CGPoint(x: centre + 240, y: top - 16), bubbles: 2) == .bubbles)
        #expect(zone(CGPoint(x: centre + 245, y: top - 16), bubbles: 2) == .outside)
    }

    @Test func theStripStaysPartOfThePill() {
        #expect(zone(CGPoint(x: centre, y: top - 50), strip: 36, bubbles: 1) == .notch)
        #expect(zone(CGPoint(x: centre, y: top - 50), strip: 0, bubbles: 1) == .outside)
    }

    @Test func theListIsItsOwnZoneUnderThePillAndTakesTheStripsPlace() {
        // 3 rows: the pill grows by 96 pt, so the list reaches 128 pt below the top edge.
        #expect(zone(CGPoint(x: centre, y: top - 60), strip: 36, bubbles: 1, listRows: 3) == .list)
        #expect(zone(CGPoint(x: centre, y: top - 120), bubbles: 1, listRows: 3) == .list)
        // Its padding at the sides and the bottom counts, so the pointer can wander off a row's edge without closing it.
        #expect(zone(CGPoint(x: centre + 168, y: top - 100), bubbles: 1, listRows: 3) == .list)
        #expect(zone(CGPoint(x: centre, y: top - 134), bubbles: 1, listRows: 3) == .list)
        #expect(zone(CGPoint(x: centre, y: top - 140), bubbles: 1, listRows: 3) == .outside)
        #expect(zone(CGPoint(x: centre + 175, y: top - 100), bubbles: 1, listRows: 3) == .outside)
        // The pill's own row stays the pill; from its bottom edge on it is the list, padding included.
        #expect(zone(CGPoint(x: centre, y: top - 10), bubbles: 1, listRows: 3) == .notch)
        #expect(zone(CGPoint(x: centre, y: top - 36), bubbles: 1, listRows: 3) == .list)
    }

    @Test func movingFromABubbleToTheListNeverGoesThroughOutside() {
        // A straight path from the middle of the first bubble to the middle of the second row.
        let from = CGPoint(x: centre + 178.5, y: top - 16)
        let to = CGPoint(x: centre, y: top - 32 - 6 - 28 - 14)
        for step in 0...40 {
            let t = CGFloat(step) / 40
            let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            #expect(zone(point, bubbles: 1, listRows: 3) != .outside, "step \(step) at \(point)")
        }
    }

    /// A path that cuts the list's top-right corner leaves the area for a few points; the close delay absorbs that, so
    /// this one goes the way the pointer usually does, up along the pill's side.
    @Test func movingFromTheListToABubbleNeverGoesThroughOutside() {
        let from = CGPoint(x: centre + 150, y: top - 50)
        let to = CGPoint(x: centre + 216.5, y: top - 16)
        for step in 0...40 {
            let t = CGFloat(step) / 40
            let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            #expect(zone(point, bubbles: 2, listRows: 3) != .outside, "step \(step) at \(point)")
        }
    }

    @Test func nothingBesideOrUnderTheNotchCountsWhileItIsExpanded() {
        // An open or toast notch is far wider than the pill: its own rect is all that counts and bubbles and list do not exist.
        for state in [NotchState.open("a"), .open(nil), .toast] {
            #expect(zone(CGPoint(x: centre + 250, y: top - 16), state, bubbles: 2, listRows: 3) == .notch, "\(state)")
            #expect(zone(CGPoint(x: centre + 330, y: top - 16), state, bubbles: 2, listRows: 3) == .outside, "\(state)")
        }
        #expect(zone(CGPoint(x: centre + 178.5, y: top - 16), .closed, bubbles: 2) == .outside)
    }

    @Test func aDragUsesTheNotchsDragAreaAlone() {
        #expect(zone(CGPoint(x: centre + 178.5, y: top - 16), bubbles: 1, dragging: true) == .notch)
        #expect(zone(CGPoint(x: centre, y: top - 60), bubbles: 1, listRows: 3, dragging: true) == .notch)
        #expect(zone(CGPoint(x: centre + 300, y: top - 16), bubbles: 1, dragging: true) == .outside)
    }

    @Test func aNotchlessDisplayHasTheSameZones() {
        let centre: CGFloat = 1512 + 960
        let top: CGFloat = 1080
        #expect(zone(CGPoint(x: centre + 175, y: top - 12), bubbles: 1, screen: external) == .bubbles)
        #expect(zone(CGPoint(x: centre, y: top - 12), bubbles: 1, screen: external) == .notch)
        #expect(zone(CGPoint(x: centre, y: top - 45), bubbles: 1, listRows: 2, screen: external) == .list)
    }
}
