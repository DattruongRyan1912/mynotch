import CoreGraphics
import Testing
@testable import WindowLayoutModule

/// What is left of a zone once the windows beside it are out of the way, in Accessibility coordinates (y grows down), on
/// a 1512 x 945 visible area below a 37 pt menu bar.
@Suite struct SnapRoomTests {
    static let area = CGRect(x: 0, y: 37, width: 1512, height: 945)

    func placement(_ layout: SnapLayout, zone: Int = 0, gap: CGFloat = 0) -> SnapPlacement {
        let frame = layout.frame(zone: zone, in: CGRect(x: 0, y: 0, width: 1512, height: 945), gap: gap)
        return SnapPlacement(
            frame: SnapSpace.accessibilityFrame(of: frame, primaryHeight: 982), area: Self.area, anchor: layout.zones[zone].anchor
        )
    }

    /// The zone's frame (the same placement with its own layout) in Accessibility coordinates.
    func frame(_ layout: SnapLayout, zone: Int = 0, gap: CGFloat = 0) -> CGRect { placement(layout, zone: zone, gap: gap).frame }

    func part(_ room: SnapRoom) -> CGRect? {
        if case .part(let placement) = room { placement.frame } else { nil }
    }

    // MARK: nothing in the way

    @Test func withNoNeighbourTheWholeZoneIsFree() {
        #expect(placement(.rightHalf).room(beside: [], gap: 0) == .whole)
    }

    @Test func aNeighbourInItsOwnZoneIsNeverInTheWayForEveryGap() {
        for gap: CGFloat in [0, 8, 16] {
            let left = frame(.leftHalf, gap: gap)
            #expect(placement(.rightHalf, gap: gap).room(beside: [left], gap: gap) == .whole, "gap \(gap)")
            #expect(placement(.leftHalf, gap: gap).room(beside: [frame(.rightHalf, gap: gap)], gap: gap) == .whole, "gap \(gap)")
            for index in 1...2 {
                let before = frame(.thirds, zone: index - 1, gap: gap)
                #expect(placement(.thirds, zone: index, gap: gap).room(beside: [before], gap: gap) == .whole, "thirds \(index) gap \(gap)")
            }
            // Diagonal and vertical quarters.
            for (zone, other) in [(1, 0), (3, 0), (2, 0), (3, 1), (0, 2), (3, 2)] {
                let neighbour = frame(.quarters, zone: other, gap: gap)
                #expect(placement(.quarters, zone: zone, gap: gap).room(beside: [neighbour], gap: gap) == .whole, "quarter \(zone) beside \(other) gap \(gap)")
            }
        }
    }

    @Test func aSliverOfOverlapThatAppsRoundAwayIsLeftAlone() {
        let zone = placement(.rightHalf)
        #expect(zone.room(beside: [CGRect(x: 0, y: 37, width: 756.4, height: 945)], gap: 0) == .whole)
        #expect(zone.room(beside: [CGRect(x: 0, y: 37, width: 757, height: 945)], gap: 0) != .whole)
    }

    // MARK: a neighbour in the way

    @Test func aNeighbourThatKeptAWiderSizeLeavesTheRestOfTheRightHalf() {
        let room = placement(.rightHalf).room(beside: [CGRect(x: 0, y: 37, width: 1040, height: 945)], gap: 0)
        #expect(part(room) == CGRect(x: 1040, y: 37, width: 472, height: 945))
    }

    @Test func theFreePartKeepsTheAreaAndTheAnchorOfTheZone() throws {
        let zone = placement(.rightHalf)
        guard case .part(let free) = zone.room(beside: [CGRect(x: 0, y: 37, width: 1040, height: 945)], gap: 0) else {
            Issue.record("expected a free part")
            return
        }
        #expect(free.area == zone.area)
        #expect(free.anchor == zone.anchor)
    }

    @Test func aNeighbourOnTheRightLeavesTheLeftPartOfTheLeftHalf() {
        let room = placement(.leftHalf).room(beside: [CGRect(x: 472, y: 37, width: 1040, height: 945)], gap: 0)
        #expect(part(room) == CGRect(x: 0, y: 37, width: 472, height: 945))
    }

    @Test func theGapIsKeptBetweenTheNeighbourAndTheFreePart() {
        for gap: CGFloat in [8, 16] {
            // The left window kept 1040 pt from the gap at the edge of the area, so it ends at 1040 + gap.
            let neighbour = CGRect(x: gap, y: 37 + gap, width: 1040, height: 945 - 2 * gap)
            let zone = placement(.rightHalf, gap: gap)
            let free = part(zone.room(beside: [neighbour], gap: gap))
            #expect(free?.minX == neighbour.maxX + gap, "gap \(gap)")
            // The edge facing the screen keeps its own gap.
            #expect(free?.maxX == zone.frame.maxX, "gap \(gap)")
            #expect(free?.minY == zone.frame.minY && free?.height == zone.frame.height, "gap \(gap)")
        }
    }

    @Test func aFractionalEdgeIsRoundedAwayFromTheNeighbourSoNothingOverlaps() {
        let neighbour = CGRect(x: 0, y: 37, width: 1040.4, height: 945)
        let free = part(placement(.rightHalf).room(beside: [neighbour], gap: 0))
        #expect(free?.minX == 1041)
        let other = CGRect(x: 471.6, y: 37, width: 1040.4, height: 945)
        #expect(part(placement(.leftHalf).room(beside: [other], gap: 0))?.maxX == 471)
    }

    @Test func aNeighbourReachingOverTwoZonesCutsOnlyTheOnePartlyCovered() {
        // Left third window of 1100 pt: it covers the middle third (504 to 1008) completely and 92 pt of the right one.
        let neighbour = CGRect(x: 0, y: 37, width: 1100, height: 945)
        #expect(placement(.thirds, zone: 1).room(beside: [neighbour], gap: 0) == .crowded)
        #expect(part(placement(.thirds, zone: 2).room(beside: [neighbour], gap: 0)) == CGRect(x: 1100, y: 37, width: 412, height: 945))
    }

    @Test func theMiddleThirdBetweenTwoWideNeighboursKeepsWhatIsBetweenThem() {
        let left = CGRect(x: 0, y: 37, width: 600, height: 945)
        let right = CGRect(x: 900, y: 37, width: 612, height: 945)
        let room = placement(.thirds, zone: 1).room(beside: [left, right], gap: 0)
        #expect(part(room) == CGRect(x: 600, y: 37, width: 300, height: 945))
        // Whatever order they come in.
        #expect(part(placement(.thirds, zone: 1).room(beside: [right, left], gap: 0)) == CGRect(x: 600, y: 37, width: 300, height: 945))
    }

    @Test func aTallNeighbourBelowATopQuarterCutsItsHeightNotItsWidth() {
        // The bottom left window kept 700 pt of height: it starts at 982 - 700 = 282, 227 pt into the top left quarter.
        let neighbour = CGRect(x: 0, y: 282, width: 756, height: 700)
        let room = placement(.quarters, zone: 0).room(beside: [neighbour], gap: 0)
        #expect(part(room) == CGRect(x: 0, y: 37, width: 756, height: 245))
    }

    @Test func aWideNeighbourBesideATopQuarterCutsItsWidth() {
        let neighbour = CGRect(x: 0, y: 37, width: 1000, height: 472)
        let room = placement(.quarters, zone: 1).room(beside: [neighbour], gap: 0)
        #expect(part(room) == CGRect(x: 1000, y: 37, width: 512, height: 472))
    }

    @Test func aNeighbourInsideTheZoneLeavesTheLargerSide() {
        let neighbour = CGRect(x: 300, y: 37, width: 100, height: 945)
        #expect(part(placement(.leftHalf).room(beside: [neighbour], gap: 0)) == CGRect(x: 400, y: 37, width: 356, height: 945))
    }

    // MARK: not enough room

    @Test func aZoneCoveredCompletelyIsCrowded() {
        #expect(placement(.rightHalf).room(beside: [CGRect(x: 0, y: 37, width: 1512, height: 945)], gap: 0) == .crowded)
    }

    @Test func aSliverIsNotARoomEither() {
        // A quarter of the zone's width is the least worth a window: 189 pt of 756.
        let zone = placement(.rightHalf)
        #expect(zone.room(beside: [CGRect(x: 0, y: 37, width: 1330, height: 945)], gap: 0) == .crowded)
        #expect(part(zone.room(beside: [CGRect(x: 0, y: 37, width: 1320, height: 945)], gap: 0)) == CGRect(x: 1320, y: 37, width: 192, height: 945))
    }

    @Test func theHeightCountsAsMuchAsTheWidth() {
        let zone = placement(.quarters, zone: 0)
        // 472 pt high, so at least 118 pt must stay.
        #expect(zone.room(beside: [CGRect(x: 0, y: 37, width: 756, height: 400)], gap: 0) == .crowded)
        #expect(part(zone.room(beside: [CGRect(x: 0, y: 37 + 354, width: 756, height: 400)], gap: 0))?.height == 354)
    }
}
