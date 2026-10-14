import CoreGraphics
import Testing
@testable import WindowLayoutModule

/// Where each layout puts a window, on the visible area of several displays (what is left once the menu bar and the Dock
/// have taken their share), with and without gaps. AppKit coordinates: y grows up.
@Suite struct SnapLayoutTests {
    /// A 14" MacBook with the Dock hidden: the menu bar (37 pt) is all that is taken.
    static let dockHidden = CGRect(x: 0, y: 0, width: 1512, height: 945)
    /// The same display with the Dock at the bottom (70 pt).
    static let dockBottom = CGRect(x: 0, y: 70, width: 1512, height: 875)
    /// Dock on the left (60 pt).
    static let dockLeft = CGRect(x: 60, y: 0, width: 1452, height: 945)
    /// An external display right of the MacBook and lower than it, whose frame starts at y -98: nothing is at zero.
    static let external = CGRect(x: 1512, y: -98 + 80, width: 2560, height: 1440 - 25 - 80)
    /// A display above and left of the primary one, whose origin is negative on x.
    static let aboveLeft = CGRect(x: -1920, y: 982, width: 1920, height: 1080 - 25)
    /// An odd size, so halves and thirds fall between two points.
    static let odd = CGRect(x: 3, y: 5, width: 1001, height: 701)

    static let areas = [dockHidden, dockBottom, dockLeft, external, aboveLeft, odd]
    static let gaps: [CGFloat] = [0, 8, 16]

    func frames(_ layout: SnapLayout, in area: CGRect, gap: CGFloat = 0) -> [CGRect] {
        layout.zones.indices.map { layout.frame(zone: $0, in: area, gap: gap) }
    }

    // MARK: the six layouts

    @Test func halvesSplitTheVisibleAreaAtItsMiddle() {
        let area = Self.dockBottom
        #expect(frames(.leftHalf, in: area) == [CGRect(x: 0, y: 70, width: 756, height: 875)])
        #expect(frames(.rightHalf, in: area) == [CGRect(x: 756, y: 70, width: 756, height: 875)])
    }

    @Test func fullScreenIsTheVisibleAreaItself() {
        for area in Self.areas {
            #expect(frames(.fullScreen, in: area) == [area], "\(area)")
        }
    }

    @Test func quartersAreTopLeftTopRightBottomLeftBottomRight() {
        // Below the menu bar the "top" half is the upper one: larger y in AppKit coordinates.
        let area = Self.dockHidden
        #expect(frames(.quarters, in: area) == [
            CGRect(x: 0, y: 473, width: 756, height: 472),
            CGRect(x: 756, y: 473, width: 756, height: 472),
            CGRect(x: 0, y: 0, width: 756, height: 473),
            CGRect(x: 756, y: 0, width: 756, height: 473),
        ])
    }

    @Test func thirdsAreThreeColumnsFromLeftToRight() {
        #expect(frames(.thirds, in: Self.dockHidden) == [
            CGRect(x: 0, y: 0, width: 504, height: 945),
            CGRect(x: 504, y: 0, width: 504, height: 945),
            CGRect(x: 1008, y: 0, width: 504, height: 945),
        ])
    }

    @Test func focusIsTheMiddleTwoThirdsOfTheWidthAtFullHeight() {
        #expect(frames(.focus, in: Self.dockHidden) == [CGRect(x: 252, y: 0, width: 1008, height: 945)])
    }

    @Test func zonesFollowTheDocumentedOrderAndCount() {
        #expect(SnapLayout.allCases == [.leftHalf, .rightHalf, .fullScreen, .quarters, .thirds, .focus])
        #expect(SnapLayout.allCases.map(\.zones.count) == [1, 1, 1, 4, 3, 1])
        #expect(SnapLayout.allCases.map(\.title) == ["Nửa trái", "Nửa phải", "Toàn màn hình", "Chia bốn", "Chia ba", "Giữa"])
    }

    // MARK: every display

    @Test func aDisplayWithADockOrAnOffsetOriginKeepsEveryWindowInsideTheVisibleArea() {
        for area in Self.areas {
            for layout in SnapLayout.allCases {
                for frame in frames(layout, in: area) {
                    #expect(area.contains(frame), "\(layout) in \(area): \(frame)")
                }
            }
        }
    }

    @Test func withoutGapsHalvesQuartersAndThirdsTileTheAreaExactlyEvenWhenItIsOdd() {
        for area in Self.areas {
            let groups = [
                frames(.leftHalf, in: area) + frames(.rightHalf, in: area),
                frames(.quarters, in: area),
                frames(.thirds, in: area),
            ]
            for covered in groups {
                // Each edge is rounded once, so neighbours share it: no sliver between them and no overlap.
                let sum = covered.reduce(CGFloat.zero) { $0 + $1.width * $1.height }
                #expect(sum == area.width * area.height, "\(covered) in \(area)")
                for (index, frame) in covered.enumerated() {
                    for other in covered[(index + 1)...] {
                        #expect(frame.intersection(other).isEmpty, "\(frame) overlaps \(other)")
                    }
                }
            }
        }
    }

    @Test func framesAreWholePoints() {
        for area in Self.areas {
            for layout in SnapLayout.allCases {
                for gap in Self.gaps {
                    for frame in frames(layout, in: area, gap: gap) {
                        for value in [frame.minX, frame.minY, frame.width, frame.height] {
                            #expect(value == value.rounded(), "\(layout) \(gap): \(frame)")
                        }
                    }
                }
            }
        }
    }

    // MARK: gaps

    @Test func aGapIsTheSpaceBetweenWindowsAndAlsoBetweenAWindowAndTheEdgeOfTheArea() {
        let area = Self.dockHidden
        // Full screen: the gap on every side.
        #expect(frames(.fullScreen, in: area, gap: 8) == [CGRect(x: 8, y: 8, width: 1496, height: 929)])
        // Halves: 8 from the edges and 8 between them.
        let left = frames(.leftHalf, in: area, gap: 8)[0]
        let right = frames(.rightHalf, in: area, gap: 8)[0]
        #expect(left == CGRect(x: 8, y: 8, width: 744, height: 929))
        #expect(right == CGRect(x: 760, y: 8, width: 744, height: 929))
        #expect(right.minX - left.maxX == 8)
    }

    @Test func theSpaceBetweenNeighboursIsTheGapInEveryLayoutAndOnEveryDisplay() {
        for area in Self.areas {
            for gap in Self.gaps {
                let thirds = frames(.thirds, in: area, gap: gap)
                #expect(thirds[1].minX - thirds[0].maxX == gap && thirds[2].minX - thirds[1].maxX == gap, "thirds \(area) \(gap)")
                let quarters = frames(.quarters, in: area, gap: gap)
                #expect(quarters[1].minX - quarters[0].maxX == gap && quarters[3].minX - quarters[2].maxX == gap, "quarters \(area) \(gap)")
                // Top row above bottom row.
                #expect(quarters[0].minY - quarters[2].maxY == gap && quarters[1].minY - quarters[3].maxY == gap, "quarters rows \(area) \(gap)")
                // The first and last window keep the gap to the edges.
                #expect(thirds[0].minX == area.minX + gap && thirds[2].maxX == area.maxX - gap)
                #expect(quarters[0].maxY == area.maxY - gap && quarters[2].minY == area.minY + gap)
            }
        }
    }

    @Test func focusHasNoNeighbourSoOnlyTheTopAndBottomKeepTheGap() {
        let area = Self.dockHidden
        let focus = frames(.focus, in: area, gap: 16)[0]
        #expect(focus.minY == 16 && focus.maxY == 945 - 16)
        // The middle two thirds of the area inside the gap (1480 wide, starting at 16), not shifted by it.
        #expect(focus == CGRect(x: 263, y: 16, width: 986, height: 913))
    }

    @Test func noGapEverMakesAWindowEmptyOnATinyArea() {
        let tiny = CGRect(x: 0, y: 0, width: 20, height: 20)
        for layout in SnapLayout.allCases {
            for frame in frames(layout, in: tiny, gap: 16) {
                #expect(frame.width >= 1 && frame.height >= 1, "\(layout): \(frame)")
            }
        }
    }

    // MARK: Accessibility coordinates

    @Test func accessibilityCoordinatesStartAtTheTopLeftOfThePrimaryDisplayAndGrowDown() {
        // The left half below the menu bar and above a 70 pt Dock on a 982 pt tall primary display.
        let appKit = CGRect(x: 0, y: 70, width: 756, height: 875)
        #expect(SnapSpace.accessibilityFrame(of: appKit, primaryHeight: 982) == CGRect(x: 0, y: 37, width: 756, height: 875))
    }

    @Test func aDisplayAboveThePrimaryOneHasNegativeAccessibilityY() {
        let appKit = CGRect(x: -1920, y: 982, width: 1920, height: 1055)
        #expect(SnapSpace.accessibilityFrame(of: appKit, primaryHeight: 982) == CGRect(x: -1920, y: -1055, width: 1920, height: 1055))
    }

    @Test func aDisplayBelowThePrimaryOneHasAccessibilityYPastItsHeight() {
        let appKit = CGRect(x: 0, y: -1000, width: 1440, height: 900)
        #expect(SnapSpace.accessibilityFrame(of: appKit, primaryHeight: 982) == CGRect(x: 0, y: 1082, width: 1440, height: 900))
    }

    // MARK: anchors

    @Test func eachZoneIsAnchoredToTheEdgesItTouchesAndCentredBetweenThem() {
        func anchors(_ layout: SnapLayout) -> [SnapAnchor] { layout.zones.map(\.anchor) }
        #expect(anchors(.leftHalf) == [SnapAnchor(horizontal: .leading, vertical: .top)])
        #expect(anchors(.rightHalf) == [SnapAnchor(horizontal: .trailing, vertical: .top)])
        #expect(anchors(.fullScreen) == [SnapAnchor(horizontal: .leading, vertical: .top)])
        #expect(anchors(.quarters) == [
            SnapAnchor(horizontal: .leading, vertical: .top), SnapAnchor(horizontal: .trailing, vertical: .top),
            SnapAnchor(horizontal: .leading, vertical: .bottom), SnapAnchor(horizontal: .trailing, vertical: .bottom),
        ])
        #expect(anchors(.thirds) == [
            SnapAnchor(horizontal: .leading, vertical: .top), SnapAnchor(horizontal: .centre, vertical: .top),
            SnapAnchor(horizontal: .trailing, vertical: .top),
        ])
        #expect(anchors(.focus) == [SnapAnchor(horizontal: .centre, vertical: .top)])
    }

    @Test func aPlacementKeepsAnyWindowInsideTheAreaAlignedToItsAnchor() {
        let area = CGRect(x: 0, y: 37, width: 1512, height: 945)
        let frame = CGRect(x: 1008, y: 37, width: 504, height: 945)
        let right = SnapPlacement(frame: frame, area: area, anchor: SnapAnchor(horizontal: .trailing, vertical: .top))
        #expect(right.origin(for: CGSize(width: 715, height: 945)) == CGPoint(x: 797, y: 37))
        #expect(right.origin(for: frame.size) == frame.origin)
        let centre = SnapPlacement(frame: frame, area: area, anchor: SnapAnchor(horizontal: .centre, vertical: .bottom))
        // Centred on x 1260 would reach past the right edge, so it stops against it.
        #expect(centre.origin(for: CGSize(width: 600, height: 400)) == CGPoint(x: 912, y: 582))
        #expect(centre.origin(for: CGSize(width: 300, height: 400)) == CGPoint(x: 1110, y: 582))
        // Too big for the area: the top left, never a negative share of it.
        #expect(right.origin(for: CGSize(width: 2000, height: 2000)) == area.origin)
    }

    // MARK: settings

    @Test func theLayoutsTheUserKeptAreInTheOrderOfTheTiles() {
        #expect(SnapOptions(storedLayouts: ["focus", "leftHalf", "thirds"], gap: .none).layouts == [.leftHalf, .thirds, .focus])
    }

    @Test func nothingKnownInTheStoredLayoutsMeansAllOfThem() {
        #expect(SnapOptions(storedLayouts: [], gap: .none).layouts == SnapLayout.allCases)
        #expect(SnapOptions(storedLayouts: ["bogus"], gap: .none).layouts == SnapLayout.allCases)
        #expect(SnapOptions(storedLayouts: ["bogus", "quarters"], gap: .none).layouts == [.quarters])
    }

    @Test func gapsAreZeroEightAndSixteen() {
        #expect(SnapGap.allCases.map(\.points) == [0, 8, 16])
    }
}
