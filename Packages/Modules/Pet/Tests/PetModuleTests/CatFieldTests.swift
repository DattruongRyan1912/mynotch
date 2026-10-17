import CoreGraphics
import Testing
@testable import PetModule

/// Where the cat plays: the strip, one view across a notch's body, two views one each side of the camera that lie on one line.
@Suite struct CatFieldTests {
    static let picture = CatField.pictureSize.width

    // MARK: The scale

    @Test func thePictureIsAWholeNumberOfPointsToThePixelAndBiggerOnlyWhenTheHeightHoldsTwoOfThem() {
        #expect(CatField.pictureSize == CGSize(width: 32, height: 24))
        for height in [24, 25, 32, 38, 40, 47] as [CGFloat] { #expect(CatField.scale(forHeight: height) == 1, "\(height)") }
        for height in [48, 56, 71] as [CGFloat] { #expect(CatField.scale(forHeight: height) == 2, "\(height)") }
        #expect(CatField.scale(forHeight: 72) == 3)
        #expect(CatField.scale(forHeight: 10) == 1, "never smaller than a pixel to the point")
        #expect(CatField.scale(forHeight: 0) == 1)
    }

    // MARK: The strip

    @Test func theStripIsTheLaneItAlwaysWasAtOnePixelToThePoint() {
        let field = CatField.strip(width: 300)
        #expect(field.scale == 1 && field.origin == 0 && field.crossing == nil)
        #expect(field.lane == WalkLane(width: 300, spriteWidth: 32))
        #expect(field.crossingShares == nil)
        #expect(field.baseY(height: 26, isStrip: true) == CatSpriteView.floor, "a point above the notch's bottom")
        #expect(field.local(share: 0.5) == WalkLane(width: 300, spriteWidth: 32).x(at: 0.5).rounded())
    }

    // MARK: One view across a body

    @Test func aBodyOfAVirtualNotchIsOneLaneAcrossItWithTheCatInTheMiddleOfItsHeight() {
        for (width, height) in [(313, 32), (325, 25), (292, 24), (313, 40)] as [(CGFloat, CGFloat)] {
            let field = CatField.lane(width: width, height: height)
            #expect(field.scale == 1 && field.crossing == nil && field.origin == 0)
            #expect(field.lane == WalkLane(width: width, spriteWidth: 32))
            #expect(field.lane.travel > 220, "room to walk: \(field.lane.travel)")
            let base = field.baseY(height: height, isStrip: false)
            #expect(base >= 0 && base + 24 <= height, "the cat fits the body: \(base) in \(height)")
            #expect(base == max(((height - 24) / 2).rounded(.down), 0))
        }
    }

    @Test func aTallPillDrawsTheCatTwiceAsBigWithEveryPixelABlockOfTwoByTwoPoints() {
        let field = CatField.lane(width: 313, height: 56)
        #expect(field.scale == 2)
        #expect(field.spriteWidth == 64 && field.spriteHeight == 48)
        #expect(field.lane.travel == 313 - 2 * WalkLane.endInset - 64)
        #expect(field.baseY(height: 56, isStrip: false) == 4, "in the middle of the 56 points: 4 over and 4 under its 48")
        #expect(field.portalSize == CGSize(width: 20, height: 48))
    }

    @Test func aBodyTooNarrowForABigCatKeepsTheScaleThatLeavesRoomToWalk() {
        #expect(CatField.lane(width: 313, height: 56).scale == 2)
        #expect(CatField.lane(width: 120, height: 56).scale == 1, "no room to walk at two points to the pixel")
        for width in stride(from: 40.0, through: 400, by: 20) {
            let field = CatField.lane(width: CGFloat(width), height: 56)
            let travel = field.lane.travel
            #expect(field.scale == 1 || travel >= CatField.leastTravel, "\(width): \(field.scale) with \(travel)")
        }
    }

    // MARK: Two views, one line

    /// The two sides of the camera of the Mac this was made for: a notch of 220 by 38 points, and a hundred points of room each side.
    static let left = CGSize(width: 100, height: 38)
    static let right = CGSize(width: 100, height: 38)

    func wings() -> (left: CatField, right: CatField) {
        (.wings(side: .left, own: Self.left, partner: Self.right), .wings(side: .right, own: Self.right, partner: Self.left))
    }

    @Test func theTwoViewsLieOnOneLineAndTheRightOneBeginsWhereTheLeftOneEnds() {
        let (left, right) = wings()
        #expect(left.origin == 0 && right.origin == 100)
        #expect(left.lane == right.lane, "one lane, seen from either view")
        #expect(left.crossing == right.crossing && left.scale == right.scale)
        #expect(left.lane.minX == WalkLane.endInset && left.lane.maxX == 100 + 100 - WalkLane.endInset - 32)
        // The same share of the lane is the same place, wherever the view is.
        for step in 0...20 {
            let share = Double(step) / 20
            #expect(left.local(share: share) + left.origin == right.local(share: share) + right.origin, "\(share)")
        }
    }

    @Test func theCrossingIsWhereThePictureIsPartInOneViewOrInThePortalAndIsMadeOfTheSeamAndThePortal() throws {
        let (left, _) = wings()
        let crossing = try #require(left.crossing)
        let (seam, portal, sprite) = (CGFloat(100), CGFloat(CatField.portalWidth), CGFloat(32))
        #expect(crossing.lowerBound == seam - portal - sprite, "from where the picture touches the portal")
        #expect(crossing.upperBound == seam + portal, "to where it has left it")
        // A cat that stops outside the crossing is whole in one view and clear of the portal.
        #expect(crossing.lowerBound + sprite + portal == seam)
        #expect(left.lane.minX < crossing.lowerBound && crossing.upperBound < left.lane.maxX, "with room to rest at either end")
        #expect(left.lane.restingX > left.lane.minX && left.lane.restingX <= crossing.lowerBound, "it rests in the left view")
    }

    @Test func aCatThatStopsAnywhereButTheCrossingIsWholeInOneViewAndClearOfThePortal() throws {
        let (left, right) = wings()
        let crossing = try #require(left.crossing)
        let sprite = left.spriteWidth
        for step in 0...400 {
            let share = Double(step) / 400
            let x = left.lane.x(at: share)
            if crossing.contains(x) { continue }
            if x < crossing.lowerBound {
                #expect(x >= 0 && x + sprite <= 100 - CGFloat(CatField.portalWidth) + 0.001, "in the left view, clear of its portal: \(x)")
            } else {
                let inRight = right.local(x)
                #expect(inRight >= CGFloat(CatField.portalWidth) - 0.001 && inRight + sprite <= 100, "in the right view, clear of its portal: \(inRight)")
            }
        }
    }

    @Test func whereTheCatIsNotSentToStopIsTheCrossingAndAStepsErrorMoreAtEachEndAndIsWhatTheBrainGoesBy() throws {
        let (left, right) = wings()
        let shares = try #require(left.crossingShares)
        #expect(shares == right.crossingShares)
        #expect(shares.lowerBound > 0 && shares.upperBound < 1 && shares.lowerBound < shares.upperBound)
        let crossing = try #require(left.crossing)
        let free = try #require(left.stopFree)
        #expect(free.lowerBound == crossing.lowerBound - CatField.leastEndError && free.upperBound == crossing.upperBound + CatField.leastEndError)
        #expect(abs(left.lane.x(at: shares.lowerBound) - free.lowerBound) < 1e-6)
        #expect(abs(left.lane.x(at: shares.upperBound) - free.upperBound) < 1e-6)
        // The most a step is of the cat's paces is six points, which ends a leg three points from where it was sent.
        #expect(CatField.leastEndError >= CGFloat(CatMove.frantic.advance) / 2 + 1)
        // A bigger cat takes bigger steps: more room.
        let tall = CGSize(width: 200, height: 56)
        let big = CatField.wings(side: .left, own: tall, partner: tall)
        let (bigFree, bigCrossing) = (try #require(big.stopFree), try #require(big.crossing))
        #expect(bigFree.lowerBound == bigCrossing.lowerBound - 2 * CatField.leastEndError)
    }

    @Test func aViewWithNoPartnerHasALaneOfItsOwnAndNoCrossing() {
        let alone = CatField.wings(side: .left, own: Self.left, partner: nil)
        #expect(alone.crossing == nil && alone.origin == 0)
        #expect(alone.lane == WalkLane(width: 100, spriteWidth: 32))
    }

    @Test func viewsOfAnotherSizeMoveTheSeamAndTheFieldFollowsThem() throws {
        let left = CatField.wings(side: .left, own: CGSize(width: 140, height: 38), partner: CGSize(width: 90, height: 38))
        let right = CatField.wings(side: .right, own: CGSize(width: 90, height: 38), partner: CGSize(width: 140, height: 38))
        #expect(right.origin == 140)
        #expect(left.lane.maxX == 140 + 90 - WalkLane.endInset - 32)
        #expect(left.crossing == right.crossing)
        #expect(try #require(left.crossing).contains(140))
    }

    @Test func wingsTooNarrowForABigCatGetTheOneThatFitsAndATallBodyGetsTheBigCatWhereThereIsRoom() {
        let tall = CGSize(width: 200, height: 56)
        let big = CatField.wings(side: .left, own: tall, partner: tall)
        #expect(big.scale == 2 && big.spriteWidth == 64)
        let narrow = CGSize(width: 100, height: 56)
        #expect(CatField.wings(side: .left, own: narrow, partner: narrow).scale == 1, "two points to the pixel does not fit a hundred")
        let mixed = CatField.wings(side: .right, own: CGSize(width: 200, height: 56), partner: CGSize(width: 200, height: 38))
        #expect(mixed.scale == 1, "one scale for both views: the lower of the two")
    }

    @Test func nothingBreaksForViewsThatAreNotThereYetOrFarTooSmall() {
        for width in [0, 1, 20, 40, 60] as [CGFloat] {
            let size = CGSize(width: width, height: 38)
            for side in [CatField.Side.left, .right] {
                let field = CatField.wings(side: side, own: size, partner: size)
                #expect(field.lane.travel >= 0 && field.scale >= 1)
                if let crossing = field.crossing { #expect(crossing.lowerBound <= crossing.upperBound) }
                _ = field.local(share: 0.5)
            }
        }
    }
}
