import CoreGraphics
import MyNotchCore
import Testing
@testable import NotchUI

/// The pill: where it is, how big, how round, and what the pointer counts as being on it. A display without a notch, 185 x 25 pt as
/// the menu bar there is 25 pt tall (`NotchGeometryTests.external`).
@Suite struct NotchPillGeometryTests {
    let screen = NotchGeometryTests.external
    let pill: NotchGeometry
    let gap = NotchGeometry.pillTopGap

    init() {
        pill = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill))
    }

    var frame: CGRect { screen.frame }
    var centre: CGFloat { frame.midX }

    /// The rect a shape of `size` covers under the top edge of the screen, as the view draws it: the gap below the edge, centred.
    func rect(_ size: CGSize) -> CGRect {
        CGRect(x: centre - size.width / 2, y: frame.maxY - gap - size.height, width: size.width, height: size.height)
    }

    // MARK: the gap

    @Test func theGapIsAFewPointsInsideTheMenuBarBand() {
        // The menu bar is 24 pt at the least on a display without a notch; the gap is well inside it, and small enough that
        // the pill's top stays in the top fifth of the band.
        #expect((4...6).contains(NotchGeometry.pillTopGap))
        #expect(NotchGeometry.pillTopGap < 24 / 4)
        #expect(pill.topGap == NotchGeometry.pillTopGap)
    }

    // MARK: collapsed

    @Test func theCollapsedPillIsAFullCapsuleWithNoEars() {
        #expect(pill.shapeSize(for: .closed) == CGSize(width: 185, height: 25))
        let radii = pill.cornerRadii(for: .closed)
        #expect(radii.top == 0, "no ears: nothing insets the body from the shape's edge")
        #expect(radii.bottom == 12.5, "corner radius = height / 2")
        let shape = pill.shape(for: .closed)
        #expect(shape == NotchShape(topRadius: 0, bottomRadius: 12.5, cornerRadius: 12.5))
        #expect(shape.cornerRadius == pill.shapeSize(for: .closed).height / 2)
    }

    @Test func theStripAndTheListGrowTheCollapsedPillButNotItsRadius() {
        // The radius is the body's half height, so a strip under it makes a rounded rectangle and not a balloon.
        for bottom in [CGFloat(20), 30, 80] {
            let size = pill.shapeSize(for: .compact, bottomHeight: bottom)
            #expect(size == CGSize(width: 185 + 128, height: 25 + bottom))
            #expect(pill.shape(for: .compact).bottomRadius == 12.5)
            #expect(pill.shape(for: .compact).cornerRadius == 12.5)
        }
    }

    @Test func theWidthAndHeightSettingsSizeThePillToo() {
        let sized = NotchGeometry(
            screen: screen, config: NotchLayoutConfig(virtualNotchWidth: 240, virtualNotchHeight: 36, virtualNotchStyle: .pill)
        )
        #expect(sized.shapeSize(for: .closed) == CGSize(width: 240, height: 36))
        #expect(sized.shape(for: .closed).cornerRadius == 18)
        #expect(sized.cornerRadii(for: .closed).bottom == 18)
    }

    @Test func theCollapsedPillFloatsTheGapBelowTheTopEdgeAndStaysCentred() {
        let pillRect = rect(pill.shapeSize(for: .closed))
        #expect(pillRect == CGRect(x: 2472 - 92.5, y: 1080 - 5 - 25, width: 185, height: 25))
        #expect(frame.maxY - pillRect.maxY == gap, "the gap above the pill is empty")
        #expect(pillRect.midX == frame.midX)
        // The hit area is that rect plus the padding, stretched up to the screen's top row.
        #expect(pill.hitRect(for: .closed, in: frame) == CGRect(x: pillRect.minX - 8, y: pillRect.minY - 8, width: 185 + 16, height: gap + 25 + 8 + 1))
        #expect(pill.dragHitRect(for: .closed, in: frame) == CGRect(x: pillRect.minX - 40, y: pillRect.minY - 40, width: 185 + 80, height: gap + 25 + 40 + 1))
    }

    // MARK: open

    @Test func theOpenPillIsARoundedRectangleWithAllFourCornersRoundedAndNoEars() {
        let size = pill.shapeSize(for: .open(nil), contentHeight: 190)
        #expect(size == CGSize(width: 600, height: 14 + 190), "the tab page starts the padding below the top: a pill has no cutout")
        #expect(pill.shapeSize(for: .toast, contentHeight: 190) == size)
        for state in [NotchState.open(nil), .open("a"), .toast] {
            let radii = pill.cornerRadii(for: state)
            #expect(radii.top == 0)
            #expect(radii.bottom == NotchGeometry.pillOpenRadius)
            #expect(pill.shape(for: state) == NotchShape(topRadius: 0, bottomRadius: 24, cornerRadius: 24), "\(state)")
        }
        // As round at the top as at the bottom, and as the notch's own open bottom corners, so the content's tile can be concentric.
        #expect(NotchGeometry.pillOpenRadius == NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig()).cornerRadii(for: .open(nil)).bottom)
    }

    @Test func theOpenPillIsCentredAndKeepsTheGap() {
        let size = pill.shapeSize(for: .open(nil), contentHeight: 190)
        let open = rect(size)
        #expect(open.midX == frame.midX, "it grows from the pill's centre")
        let collapsed = rect(pill.shapeSize(for: .closed))
        #expect(open.maxY == collapsed.maxY, "same top gap as the collapsed pill")
        #expect(frame.maxY - open.maxY == gap)
        #expect(pill.hitRect(for: .open(nil), contentHeight: 190, in: frame)
            == CGRect(x: open.minX - 8, y: open.minY - 8, width: 600 + 16, height: gap + 204 + 8 + 1))
    }

    @Test func theContentFrameIsInsideTheOpenPillAndItsPadding() {
        // No ears, so only the padding insets the content sideways, and the same padding is above it, under the gap.
        let content = pill.contentFrame(height: 100, in: frame)
        let open = rect(pill.shapeSize(for: .open(nil), contentHeight: 190))
        #expect(content == CGRect(x: open.minX + NotchTokens.padding, y: frame.maxY - gap - NotchTokens.padding - 100, width: 600 - 2 * NotchTokens.padding, height: 100))
        #expect(content.midX == frame.midX)
        #expect(open.contains(content))
    }

    // MARK: the panel

    @Test func thePanelHoldsTheGapToo() {
        #expect(pill.panelSize == CGSize(width: 900, height: 25 + gap + 240))
        let panel = pill.panelFrame(in: frame)
        #expect(panel.maxY == frame.maxY, "still anchored to the top edge")
        #expect(panel.midX == frame.midX)
        // The notch style's panel is as it was.
        let notch = NotchGeometry(screen: screen, config: NotchLayoutConfig())
        #expect(notch.panelSize == CGSize(width: 900, height: 25 + 240))
    }

    @Test func theFixedPanelCoversEveryShapeThePillCanTake() {
        for config in [
            NotchLayoutConfig(virtualNotchStyle: .pill),
            NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40, openWidth: 900, virtualNotchStyle: .pill),
            NotchLayoutConfig(virtualNotchWidth: 120, virtualNotchHeight: 24, openWidth: 480, virtualNotchStyle: .pill),
        ] {
            let geometry = NotchGeometry(screen: screen, config: config)
            let panel = geometry.panelFrame(in: frame)
            for height in stride(from: NotchTab.heightRange.lowerBound, through: NotchGeometry.maxContentHeight + 10, by: 10) {
                for state in [NotchState.closed, .compact, .open("a"), .open(nil), .toast] {
                    let size = geometry.shapeSize(for: state, contentHeight: height, bottomHeight: NotchGeometry.maxBottomHeight)
                    let shape = CGRect(
                        x: frame.midX - size.width / 2, y: frame.maxY - geometry.topGap - size.height, width: size.width, height: size.height
                    )
                    #expect(panel.contains(shape), "\(state) \(height) \(config.virtualNotchWidth)")
                }
            }
        }
    }

    // MARK: hover and clicks

    @Test func thePointerAtTheVeryTopEdgeAboveThePillIsOnIt() {
        // The top row of the screen is y == maxY, and the gap is between it and the pill: moving the pointer to the top centre
        // must keep opening the notch.
        for state in [NotchState.closed, .compact] {
            for y in [frame.maxY, frame.maxY - 1, frame.maxY - gap + 0.5, frame.maxY - gap - 1, frame.maxY - gap - 12] {
                #expect(pill.pointerZone(at: CGPoint(x: centre, y: y), state: state, in: frame) == .notch, "\(state) \(y)")
            }
            #expect(pill.pointerZone(at: CGPoint(x: centre + 92.5 + 4, y: frame.maxY), state: state, in: frame) == .notch)
        }
        let hit = pill.hitRect(for: .closed, in: frame)
        #expect(hit.containsMouseLocation(CGPoint(x: centre, y: frame.maxY)))
        #expect(pill.dragHitRect(for: .closed, in: frame).containsMouseLocation(CGPoint(x: centre, y: frame.maxY)))
    }

    @Test func theTopEdgeBesideThePillAndTheDisplayAboveAreNotOnIt() {
        let beyond = 92.5 + NotchGeometry.hitPadding + 1
        for x in [centre - beyond, centre + beyond, centre - 400, centre + 400] {
            #expect(pill.pointerZone(at: CGPoint(x: x, y: frame.maxY), state: .closed, in: frame) == .outside, "\(x)")
        }
        // A display above this one reports its own row at y == maxY + 1.
        #expect(pill.pointerZone(at: CGPoint(x: centre, y: frame.maxY + 1), state: .closed, in: frame) == .outside)
    }

    @Test func aClickInTheGapAboveTheOpenPillIsInside() {
        for state in [NotchState.open(nil), .open("a"), .toast] {
            for dragging in [false, true] {
                for y in [frame.maxY, frame.maxY - gap / 2, frame.maxY - gap + 0.5] {
                    #expect(
                        pill.pointerZone(at: CGPoint(x: centre, y: y), state: state, contentHeight: 190, dragging: dragging, in: frame) == .notch,
                        "\(state) dragging \(dragging) \(y)"
                    )
                }
            }
        }
        // Beside the open pill it is still outside.
        #expect(pill.pointerZone(at: CGPoint(x: centre + 330, y: frame.maxY - 60), state: .open(nil), contentHeight: 190, in: frame) == .outside)
    }

    @Test func theZoneOfTheOpenPillIsItsShapeAndThePaddingNotThePanel() {
        let hit = pill.hitRect(for: .open(nil), contentHeight: 120, in: frame)
        let panel = pill.panelFrame(in: frame)
        var wrong = 0
        for x in stride(from: panel.minX + 1, to: panel.maxX, by: 7) {
            for y in stride(from: panel.minY + 1, to: panel.maxY, by: 7) {
                let point = CGPoint(x: x, y: y)
                let inside = pill.pointerZone(at: point, state: .open(nil), contentHeight: 120, in: frame) != .outside
                if inside != hit.contains(point) { wrong += 1 }
            }
        }
        #expect(wrong == 0)
        // Below the open pill (its bottom is 14 + 120 + gap under the edge, plus the padding) is outside.
        #expect(pill.pointerZone(at: CGPoint(x: centre, y: frame.maxY - gap - 134 - 12), state: .open(nil), contentHeight: 120, in: frame) == .outside)
    }

    // MARK: bubbles and the list

    @Test func theBubblesSitBesideThePillWithTheSameGapAndAreCentredOnIt() {
        let pillRect = rect(pill.shapeSize(for: .compact))
        for index in 0..<NotchGeometry.maxBubbles {
            let bubble = pill.bubbleFrame(at: index)
            let onScreen = pill.bubbleScreenFrame(at: index, in: frame)
            #expect(bubble.size == CGSize(width: 25, height: 25), "as tall as the pill")
            #expect(onScreen.midY == pillRect.midY, "vertically centred on the pill, gap included")
            #expect(frame.maxY - onScreen.maxY == gap)
            let previousRight = index == 0 ? pillRect.maxX : pill.bubbleScreenFrame(at: index - 1, in: frame).maxX
            #expect(onScreen.minX - previousRight == NotchGeometry.bubbleGap, "6 pt from the pill's end and from the bubble before it")
        }
        #expect(pill.bubbleFrame(at: 0).minX == pill.shapeSize(for: .compact).width / 2 + NotchGeometry.bubbleGap)
    }

    @Test func theContainerSpacingKeepsThePillAndItsFirstBubbleApart() {
        // With no ears the nearest the pill's end comes to its first bubble is the bubble gap itself.
        let nearest = pill.bubbleFrame(at: 0).minX - pill.shapeSize(for: .compact).width / 2
        #expect(nearest == NotchGeometry.bubbleGap)
        #expect(NotchGlassPlan.containerSpacing < nearest)
        #expect(NotchGlassPlan.containerSpacing < NotchGeometry.bubbleGap)
    }

    @Test func theBubblesAndTheListAreWhereThePointerSaysTheyAre() {
        let first = pill.bubbleScreenFrame(at: 0, in: frame)
        #expect(pill.pointerZone(at: CGPoint(x: first.midX, y: first.midY), state: .compact, bubbles: 2, in: frame) == .bubbles)
        // The row above a bubble, in the gap and at the top edge, is the bubbles' too.
        #expect(pill.pointerZone(at: CGPoint(x: first.midX, y: frame.maxY), state: .compact, bubbles: 2, in: frame) == .bubbles)
        #expect(pill.pointerZone(at: CGPoint(x: first.midX, y: first.maxY + gap / 2), state: .compact, bubbles: 2, in: frame) == .bubbles)
        // The pill is still the pill.
        #expect(pill.pointerZone(at: CGPoint(x: centre, y: frame.maxY - gap - 12), state: .compact, bubbles: 2, in: frame) == .notch)
        // The list hangs from the pill, under it, with no hole between.
        let listTop = frame.maxY - gap - 25
        let list = pill.listHeight(rows: 3)
        for y in [listTop - 1, listTop - list / 2, listTop - list + 1] {
            #expect(pill.pointerZone(at: CGPoint(x: centre, y: y), state: .compact, listRows: 3, in: frame) == .list, "\(y)")
        }
        #expect(pill.pointerZone(at: CGPoint(x: centre, y: frame.maxY - gap / 2), state: .compact, listRows: 3, in: frame) == .notch)
        #expect(pill.pointerZone(at: CGPoint(x: centre, y: listTop - list - 20), state: .compact, listRows: 3, in: frame) == .outside)
    }

    @Test func theBubbleCapacityIsTheNotchStylesWhenThePillIsAsWide() {
        // Only the width of the compact shape matters (the panel is as wide either way): a wide pill drops the last bubble as before.
        let wide = NotchGeometry(screen: screen, config: NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchStyle: .pill))
        #expect(wide.bubbleCapacity == NotchGeometry.maxBubbles)
        for index in 0..<wide.bubbleCapacity {
            #expect(wide.bubbleFrame(at: index).maxX <= wide.panelSize.width / 2)
        }
    }
}
