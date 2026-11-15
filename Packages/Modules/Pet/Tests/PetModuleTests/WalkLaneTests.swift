import CoreGraphics
import Testing
@testable import PetModule

@Suite struct WalkLaneTests {
    static let spriteWidth = CatSpriteView.spriteSize.width

    @Test func theLaneIsTheStripLessAFewPointsAtEachEnd() {
        let lane = WalkLane(width: 300, spriteWidth: Self.spriteWidth)
        #expect(lane.minX == WalkLane.endInset)
        #expect(lane.maxX + Self.spriteWidth == 300 - WalkLane.endInset)
        #expect(lane.travel == 300 - 2 * WalkLane.endInset - Self.spriteWidth)
        #expect(lane.travel > 250, "wide enough to walk")
    }

    @Test func theSpriteIsAlwaysWhollyInsideTheStrip() {
        for width in stride(from: 40.0, through: 420, by: 7) {
            let lane = WalkLane(width: width, spriteWidth: Self.spriteWidth)
            for step in 0...20 {
                let x = lane.x(at: Double(step) / 20)
                #expect(x >= 0 && x + Self.spriteWidth <= max(width, Self.spriteWidth), "width \(width), at \(step)/20: \(x)")
            }
        }
    }

    @Test func theCatRestsInTheMiddleOfTheStrip() {
        let lane = WalkLane(width: 300, spriteWidth: Self.spriteWidth)
        #expect(lane.restingX == (300 - Self.spriteWidth) / 2)
        #expect(lane.restingX > lane.minX && lane.restingX < lane.maxX)
    }

    @Test func aStripTooNarrowForTheCatLeavesNoRoomToWalk() {
        let lane = WalkLane(width: 30, spriteWidth: Self.spriteWidth)
        #expect(lane.travel == 0)
        #expect(lane.x(at: 0.5) == lane.minX)
        #expect(lane.restingX == 0)
        let almost = WalkLane(width: 40, spriteWidth: Self.spriteWidth)
        #expect(almost.minX == 4 && almost.travel == 0, "the margin shrinks before the cat is cut off")
    }

    @Test func aFractionOutsideTheLaneIsHeldToItsEndsExceptForWhatMayLeave() {
        let lane = WalkLane(width: 300, spriteWidth: Self.spriteWidth)
        #expect(lane.x(at: -1) == lane.minX)
        #expect(lane.x(at: 2) == lane.maxX)
        #expect(lane.unboundedX(at: 1.2) > lane.maxX, "a moth goes past the end")
        #expect(lane.unboundedX(at: -0.2) < lane.minX)
        #expect(lane.unboundedX(at: 0.5) == lane.x(at: 0.5))
    }

    @Test func theStripTakesTheHeightOfTheStripActivityAndThePictureFitsInIt() {
        #expect(CatActivity.stripHeight == 26)
        #expect(CatSpriteView.spriteSize == CGSize(width: 32, height: 24))
        #expect(CatSpriteView.floor + CatSpriteView.spriteSize.height <= CatActivity.stripHeight)
    }
}

@Suite struct PointerLookTests {
    let strip = CGRect(x: 100, y: 800, width: 300, height: 26)
    let lane = WalkLane(width: 300, spriteWidth: 32)

    func reading(_ x: CGFloat, _ y: CGFloat) -> PointerReading? {
        PointerLook.reading(of: CGPoint(x: x, y: y), strip: strip, lane: lane, spriteWidth: 32)
    }

    @Test func onTheStripIsNearAndInSight() {
        let reading = reading(250, 813)
        #expect(reading?.isNear == true && reading?.isInRange == true)
    }

    @Test func withinFortyPointsOfItIsNearAndBeyondThatOnlyInSightUntilItIsOutOfSight() {
        #expect(reading(100 - 39, 813)?.isNear == true)
        #expect(reading(250, 800 - 39)?.isNear == true)
        #expect(reading(250, 826 + 39)?.isNear == true)
        let seen = reading(100 - 41, 813)
        #expect(seen?.isNear == false && seen?.isInRange == true)
        #expect(reading(100 - 171, 813) == nil)
        #expect(reading(250, 800 - 111) == nil)
        #expect(reading(250, 826 + 111) == nil)
    }

    @Test func theShareIsWhereTheCatWouldHaveToStandToBeUnderThePointer() throws {
        // The cat's centre is under the pointer when its left edge is half a sprite to the left of it.
        let left = try #require(reading(100 + lane.minX + 16, 813))
        #expect(abs(left.share) < 1e-9)
        let right = try #require(reading(100 + lane.maxX + 16, 813))
        #expect(abs(right.share - 1) < 1e-9)
        let middle = try #require(reading(100 + (lane.minX + lane.maxX) / 2 + 16, 813))
        #expect(abs(middle.share - 0.5) < 1e-9)
        // Past the end it goes on.
        let beyond = try #require(reading(100 + lane.maxX + 16 + 20, 813))
        #expect(beyond.share > 1)
        let before = try #require(reading(100 - 20, 813))
        #expect(before.share < 0)
    }

    @Test func aPointerAboveTheStripIsAboveAndOneBelowIsNot() throws {
        #expect(try #require(reading(250, 840)).isAbove)
        #expect(try !#require(reading(250, 790)).isAbove)
    }

    @Test func aStripWithNoRoomToWalkPutsThePointerInTheMiddle() throws {
        let narrow = WalkLane(width: 30, spriteWidth: 32)
        let look = PointerLook.reading(of: CGPoint(x: 110, y: 813), strip: CGRect(x: 100, y: 800, width: 30, height: 26), lane: narrow, spriteWidth: 32)
        #expect(look?.share == 0.5)
    }

    @Test func aPointerInRangeIsAlwaysInRangeWhenItIsNear() {
        #expect(PointerReading(share: 0.5, isNear: true, isInRange: false).isInRange)
    }
}
