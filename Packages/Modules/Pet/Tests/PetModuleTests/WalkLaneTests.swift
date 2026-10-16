import CoreGraphics
import NotchUI
import Testing
@testable import PetModule

@Suite struct WalkLaneTests {
    /// A MacBook's collapsed notch: a wing of 64 by 32 on each side of a camera 185 wide.
    static let wings = Wings(
        leading: CGRect(x: 0, y: 0, width: 64, height: 32), trailing: CGRect(x: 249, y: 0, width: 64, height: 32)
    )
    static let spriteWidth: CGFloat = 30

    @Test func aHardwareNotchHasTheCatKeepToTheRightWingUnlessTheUserAsksForBoth() {
        #expect(LaneMode.resolve(kind: .hardware, bothWings: false) == .rightWing)
        #expect(LaneMode.resolve(kind: .hardware, bothWings: true) == .bothWings)
    }

    @Test func aNotchThatIsOnlyDrawnHasTheCatInsideItWhateverTheChoiceOfWingsIs() {
        #expect(LaneMode.resolve(kind: .virtual, bothWings: false) == .inside)
        #expect(LaneMode.resolve(kind: .virtual, bothWings: true) == .inside)
    }

    @Test func onTheRightWingTheCatWalksOnlyInsideTheWingAndNeverNearTheCamera() throws {
        let lane = try #require(WalkLane.make(mode: .rightWing, wings: Self.wings, spriteWidth: Self.spriteWidth, roundEnd: 8))
        let trailing = try #require(Self.wings.trailing)
        #expect(lane.minX == trailing.minX + WalkLane.innerInset)
        #expect(lane.maxX + Self.spriteWidth == trailing.maxX - WalkLane.hardwareEndInset)
        #expect(lane.clipsToWings)
        for step in 0...20 {
            let x = lane.x(at: Double(step) / 20)
            #expect(x >= trailing.minX && x + Self.spriteWidth <= trailing.maxX, "at \(step)/20: \(x)")
        }
    }

    @Test func overBothWingsTheLaneRunsFromTheLeftEndToTheRightEndAndIsOnlyDrawnWhereAWingIs() throws {
        let lane = try #require(WalkLane.make(mode: .bothWings, wings: Self.wings, spriteWidth: Self.spriteWidth, roundEnd: 8))
        #expect(lane.minX == 0 + WalkLane.hardwareEndInset)
        #expect(lane.maxX + Self.spriteWidth == 313 - WalkLane.hardwareEndInset)
        #expect(lane.clipsToWings, "behind the camera, nothing is drawn")
        #expect(lane.travel > 150)
    }

    @Test func bothWingsWithOnlyOneWingToHandIsTheRightWing() throws {
        let alone = Wings(leading: nil, trailing: Self.wings.trailing)
        let lane = try #require(WalkLane.make(mode: .bothWings, wings: alone, spriteWidth: Self.spriteWidth, roundEnd: 8))
        let right = try #require(WalkLane.make(mode: .rightWing, wings: alone, spriteWidth: Self.spriteWidth, roundEnd: 8))
        #expect(lane == right)
    }

    @Test func insideAPillTheCatHasTheWholeOfItLessItsRoundEndsAndIsNotClipped() throws {
        // A pill of 32 points has ends of 16.
        let lane = try #require(WalkLane.make(mode: .inside, wings: Self.wings, spriteWidth: Self.spriteWidth, roundEnd: 16))
        #expect(lane.minX == 16)
        #expect(lane.maxX + Self.spriteWidth == CGFloat(313 - 16))
        #expect(!lane.clipsToWings)
        // The camera's width is no obstacle where there is no camera.
        #expect(lane.travel > 200)
    }

    @Test func overBothWingsTheCameraIsWhereTheCatCannotBeSeenAndOnTheRightWingThereIsNone() throws {
        let right = try #require(WalkLane.make(mode: .rightWing, wings: Self.wings, spriteWidth: Self.spriteWidth, roundEnd: 8))
        #expect(right.blind == nil)
        let both = try #require(WalkLane.make(mode: .bothWings, wings: Self.wings, spriteWidth: Self.spriteWidth, roundEnd: 8))
        // The cat is hidden from the moment it is no longer wholly in the left wing (its left edge past 64 - 30) until it is wholly in the right.
        #expect(both.blindMinX == CGFloat(64 - 30))
        #expect(both.blindMaxX == CGFloat(249))
        let span = try #require(both.blind)
        #expect(abs(span.low - (34 - both.minX) / both.travel) < 1e-9)
        #expect(abs(span.high - (249 - both.minX) / both.travel) < 1e-9)
        // And the two ends of the lane are not in it.
        #expect(!span.contains(0) && !span.contains(1))
        // Where the sprite is for any share outside the span, it is wholly in a wing.
        for step in 0...200 {
            let share = Double(step) / 200
            guard !span.contains(share) else { continue }
            let x = both.x(at: share)
            #expect(x + Self.spriteWidth <= 64 || x >= 249, "at \(share): \(x)")
        }
    }

    @Test func insideAPillTheMiddleIsBlindToo() throws {
        let pill = try #require(WalkLane.make(mode: .inside, wings: Self.wings, spriteWidth: Self.spriteWidth, roundEnd: 16))
        #expect(pill.blindMinX == CGFloat(34) && pill.blindMaxX == CGFloat(249))
        #expect(pill.blind != nil)
        // With only one wing there is no middle.
        let alone = try #require(WalkLane.make(mode: .inside, wings: Wings(leading: nil, trailing: Self.wings.trailing), spriteWidth: 30, roundEnd: 16))
        #expect(alone.blind == nil)
    }

    @Test func aLaneWithNoRoomToWalkHasNoBlindStretch() throws {
        let narrow = Wings(leading: CGRect(x: 0, y: 0, width: 20, height: 32), trailing: CGRect(x: 22, y: 0, width: 20, height: 32))
        let lane = try #require(WalkLane.make(mode: .bothWings, wings: narrow, spriteWidth: 30, roundEnd: 8))
        #expect(lane.travel == 0)
        #expect(lane.blind == nil)
    }

    @Test func aHardwareNotchKeepsItsRoundEndsAtLeastEightPointsAway() throws {
        let lane = try #require(WalkLane.make(mode: .rightWing, wings: Self.wings, spriteWidth: Self.spriteWidth, roundEnd: 2))
        #expect(lane.maxX + Self.spriteWidth == 313 - WalkLane.hardwareEndInset)
    }

    @Test func theCatRestsInTheMiddleOfTheRightWing() throws {
        let lane = try #require(WalkLane.make(mode: .rightWing, wings: Self.wings, spriteWidth: Self.spriteWidth, roundEnd: 8))
        #expect(lane.restingX == 249 + 32 - Self.spriteWidth / 2)
    }

    @Test func aWingTooNarrowForTheCatLeavesNoRoomToWalk() throws {
        let narrow = Wings(leading: nil, trailing: CGRect(x: 0, y: 0, width: 20, height: 32))
        let lane = try #require(WalkLane.make(mode: .rightWing, wings: narrow, spriteWidth: Self.spriteWidth, roundEnd: 8))
        #expect(lane.travel == 0)
        #expect(lane.x(at: 0.5) == lane.minX)
    }

    @Test func thereIsNoLaneBeforeTheNotchHasLaidOutItsRightWing() {
        #expect(WalkLane.make(mode: .rightWing, wings: Wings(leading: Self.wings.leading, trailing: nil), spriteWidth: 30, roundEnd: 8) == nil)
    }

    @Test func aFractionOutsideTheLaneIsHeldToItsEnds() throws {
        let lane = try #require(WalkLane.make(mode: .rightWing, wings: Self.wings, spriteWidth: Self.spriteWidth, roundEnd: 8))
        #expect(lane.x(at: -1) == lane.minX)
        #expect(lane.x(at: 2) == lane.maxX)
    }

    @Test func theSpriteIsAsBigAsTheRowAllowsInWholeDevicePixelsToASpritePixel() {
        // A MacBook's notch row: 32 points at 2x makes 64 device pixels; 80 % of it is 51, which is three to a sprite pixel of 16.
        let macbook = SpriteMetrics(rowHeight: 32, backingScale: 2)
        #expect(macbook.pixelScale == 3)
        #expect(macbook.step == 1.5)
        #expect(macbook.size == CGSize(width: 30, height: 24))
        let external = SpriteMetrics(rowHeight: 25, backingScale: 1)
        #expect(external.pixelScale == 1)
        #expect(external.size == CGSize(width: 20, height: 16))
        let tallPill = SpriteMetrics(rowHeight: 56, backingScale: 2)
        #expect(tallPill.pixelScale == 5)
        #expect(SpriteMetrics(rowHeight: 4, backingScale: 1).pixelScale == 1, "never less than a device pixel")
        // Always a whole number of device pixels, whatever the row.
        for height in stride(from: 20.0, through: 60, by: 1.5) {
            for scale in [1.0, 2, 3] {
                let metrics = SpriteMetrics(rowHeight: height, backingScale: scale)
                #expect(abs(metrics.step * scale - Double(metrics.pixelScale)) < 1e-9)
                #expect(metrics.size.height <= max(height * SpriteMetrics.fill, 16 / scale) + 1e-9)
            }
        }
    }
}

@Suite struct PointerProximityTests {
    let wing = CGRect(x: 100, y: 800, width: 64, height: 32)

    @Test func insideTheWingIsNear() {
        #expect(PointerProximity.isNear(CGPoint(x: 130, y: 815), to: [wing]))
    }

    @Test func withinTheMarginOfItIsNearAndBeyondItIsNot() {
        #expect(PointerProximity.isNear(CGPoint(x: 100 - 39, y: 815), to: [wing]))
        #expect(PointerProximity.isNear(CGPoint(x: 164 + 39, y: 800 - 39), to: [wing]))
        #expect(!PointerProximity.isNear(CGPoint(x: 100 - 41, y: 815), to: [wing]))
        #expect(!PointerProximity.isNear(CGPoint(x: 130, y: 800 - 41), to: [wing]))
    }

    @Test func nearEitherOfTwoWingsIsNear() {
        let other = CGRect(x: 400, y: 800, width: 64, height: 32)
        #expect(PointerProximity.isNear(CGPoint(x: 430, y: 810), to: [wing, other]))
        #expect(!PointerProximity.isNear(CGPoint(x: 280, y: 810), to: [wing, other]))
    }

    @Test func noWingMeansNothingIsNear() {
        #expect(!PointerProximity.isNear(CGPoint(x: 130, y: 815), to: []))
    }
}

@Suite struct MeowSynthTests {
    @Test func theMeowIsHalfASecondOfSoundThatIsNeitherSilentNorClipped() {
        let samples = MeowSynth.samples()
        #expect(samples.count == MeowSynth.sampleRate / 2)
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        #expect(peak > 3000, "audible")
        #expect(peak < Int(Int16.max) * 9 / 10, "never clipped")
        // It starts and ends in silence, so it does not click.
        #expect(abs(Int(samples[0])) < 200)
        #expect(abs(Int(samples[samples.count - 1])) < 200)
    }

    @Test func itIsAWaveFileTheSystemCanPlay() {
        let data = MeowSynth.wav()
        let bytes = [UInt8](data)
        #expect(String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: bytes[8..<16], as: UTF8.self) == "WAVEfmt ")
        #expect(String(decoding: bytes[36..<40], as: UTF8.self) == "data")
        func le32(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 }
        func le16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        #expect(le16(20) == 1, "PCM")
        #expect(le16(22) == 1, "mono")
        #expect(le32(24) == MeowSynth.sampleRate)
        #expect(le16(34) == 16)
        #expect(le32(40) == MeowSynth.samples().count * 2)
        #expect(le32(4) == data.count - 8)
        #expect(data.count == 44 + MeowSynth.samples().count * 2)
    }

    @Test func itRisesAndFallsInPitch() {
        // Zero crossings in the first and the middle of the sound: the note goes up from where it begins.
        let samples = MeowSynth.samples()
        func crossings(_ range: Range<Int>) -> Int {
            zip(samples[range], samples[range].dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
        }
        let window = MeowSynth.sampleRate / 20
        let early = crossings(MeowSynth.sampleRate / 50..<MeowSynth.sampleRate / 50 + window)
        let peak = crossings(Int(Double(MeowSynth.sampleRate) * 0.17)..<Int(Double(MeowSynth.sampleRate) * 0.17) + window)
        #expect(peak > early)
    }
}
