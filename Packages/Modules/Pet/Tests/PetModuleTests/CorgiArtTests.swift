import CoreGraphics
import Foundation
import Testing
@testable import PetModule

/// The corgi and its ball, as pictures.
@Suite struct CorgiArtTests {
    static let moves = CorgiMove.allCases.map { ($0, CorgiArt.animation(for: $0)) }
    static let props = CorgiProp.allCases.map { ($0, CorgiProps.animation(for: $0)) }

    func frames(_ move: CorgiMove) -> [PixelFrame] { CorgiArt.animation(for: move).frames }

    // MARK: Sizes

    @Test func everyFrameOfEveryMoveAndEveryPropIsThirtyTwoByTwentyFourLikeTheCatsSoALaneTakesAnyMix() {
        for (move, animation) in Self.moves {
            for (index, frame) in animation.frames.enumerated() { #expect((frame.width, frame.height) == (32, 24), "\(move) frame \(index)") }
        }
        for (prop, animation) in Self.props {
            for (index, frame) in animation.frames.enumerated() { #expect((frame.width, frame.height) == (32, 24), "\(prop) frame \(index)") }
        }
        #expect((CorgiArt.width, CorgiArt.height) == (32, 24) && CatField.pictureSize == CGSize(width: 32, height: 24))
        for frame in CorgiArt.restingFrames { #expect((frame.width, frame.height) == (32, 24)) }
    }

    @Test func everyMoveHasTheFramesTheBrainCountsOn() {
        for (move, animation) in Self.moves {
            #expect(animation.frames.count == move.frameCount, "\(move)")
            #expect(animation.fps == move.fps && animation.loops == move.loops && animation.advance == move.advance, "\(move)")
        }
        let asked: [CorgiMove: Int] = [
            .stand: 4, .blink: 1, .trot: 6, .run: 6, .wiggle: 6, .watch: 4, .spin: 9, .grab: 4, .carry: 6, .lower: 4, .sitDown: 3, .standUp: 3,
            .sit: 4, .begUp: 3, .beg: 4, .begDown: 3, .lieDown: 4, .getUp: 4, .lie: 2, .settle: 3, .wake: 3, .sleep: 4,
        ]
        #expect(Set(asked.keys) == Set(CorgiMove.allCases))
        for move in CorgiMove.allCases { #expect(move.frameCount == asked[move], "\(move)") }
    }

    @Test func theMovesThatMoveHaveFramesThatDiffer() {
        let distinct: [CorgiMove: Int] = [
            .trot: 6, .run: 6, .carry: 6, .wiggle: 5, .spin: 7, .grab: 4, .lower: 4, .watch: 4, .sitDown: 3, .begUp: 3, .lieDown: 4, .settle: 3,
            .beg: 4, .stand: 3, .sit: 3, .sleep: 4,
        ]
        for (move, animation) in Self.moves where animation.frames.count > 1 {
            let count = Set(animation.frames.map(\.cells)).count
            #expect(count >= distinct[move] ?? 2, "\(move) is \(count) pictures")
        }
    }

    @Test func theRunIsTheQuickestThingItDoesInStepsSmallEnoughForAWalkToEndWhereItWasSentAndTheTrotIsNotInAHurry() {
        // Half a step is the most a walk ends away from where it was sent, and that has to be less than the room the lane keeps clear.
        #expect(CorgiMove.run.advance / 2 < CatField.leastEndError && CorgiMove.trot.advance <= CatField.leastEndError)
        #expect(CorgiMove.run.advance <= CatMove.frantic.advance, "no quicker than the cat's frantic run")
        #expect(CorgiMove.run.speed > CorgiMove.trot.speed * 1.8 && CorgiMove.run.speed == 80 && CorgiMove.trot.speed == 36)
        #expect(CorgiMove.carry.speed == CorgiMove.trot.speed, "it trots home with the ball as it trotted out")
        for (move, animation) in Self.moves {
            #expect(animation.fps <= Double(CatSpriteView.frameRateCeiling), "\(move)")
            #expect([CorgiMove.run, .trot, .carry].contains(move) || move.advance == 0, "\(move) goes nowhere")
            if move != .run { #expect(move.speed <= CorgiMove.trot.speed, "\(move) is not the run") }
        }
    }

    // MARK: Colours

    static let everyLetter: Set<Character> = Set(
        (moves.flatMap(\.1.frames) + props.flatMap(\.1.frames) + CorgiArt.restingFrames).flatMap(\.cells)
    ).subtracting(["."])

    @Test func everyColourTheArtUsesIsInThePaletteAndEveryColourOfThePaletteIsDrawnSomewhere() {
        for letter in Self.everyLetter { #expect(CorgiArt.palette.isKnown(letter), "no \(letter)") }
        for letter in CorgiArt.palette.colors.keys { #expect(Self.everyLetter.contains(letter), "\(letter) is never drawn") }
    }

    @Test func theRimIsLightAndTheLineInsideItIsDarkSoOneOfThemReadsOnAnyGround() {
        let grounds: [(name: String, colour: UInt32)] = [("black", 0x000000), ("dark glass", 0x2A2A30), ("light glass", 0xDCDCE0), ("white", 0xFFFFFF)]
        let (rim, line) = (CorgiArt.palette.colors["R"]!, CorgiArt.palette.colors["K"]!)
        for ground in grounds { #expect(max(contrast(rim, ground.colour), contrast(line, ground.colour)) >= 3, "on \(ground.name)") }
        #expect(contrast(rim, 0x000000) >= 10 && contrast(line, 0xFFFFFF) >= 10)
    }

    @Test func theDustHasNoRimOfItsOwnSoItIsAMiddlingColourThatReadsOnDarkAndLightGlass() {
        let colour = CorgiArt.palette.colors["D"]!
        #expect(contrast(colour, 0x2A2A30) >= 3 && contrast(colour, 0xDCDCE0) >= 3)
    }

    /// The letters that are drawn over the rim, a pixel wide: a rim round them would make them three.
    static let overTheRim: Set<Character> = ["D"]

    @Test func everyFrameOfTheCorgiHasALightRimAllRoundItAndNothingOfItTouchesTheAirButTheDust() {
        for (move, animation) in Self.moves {
            for (index, frame) in animation.frames.enumerated() {
                var rim = 0
                for y in 0..<frame.height {
                    for x in 0..<frame.width where frame[x, y] != "." {
                        if frame[x, y] == "R" { rim += 1 }
                        guard frame[x, y] != "R", !Self.overTheRim.contains(frame[x, y]) else { continue }
                        for dy in -1...1 {
                            for dx in -1...1 where (0..<frame.width).contains(x + dx) && (0..<frame.height).contains(y + dy) {
                                #expect(frame[x + dx, y + dy] != ".", "\(move) frame \(index): \(frame[x, y]) at \(x), \(y) touches the air")
                            }
                        }
                    }
                }
                #expect(rim > 18, "\(move) frame \(index) has a rim")
            }
        }
    }

    @Test func theEdgeOfTheCorgiAndOfTheBallReadsAgainstEveryGroundInEveryFrame() {
        let palette = CorgiArt.palette.colors
        var pictures: [(name: String, frame: PixelFrame)] = []
        for (move, animation) in Self.moves { pictures += animation.frames.enumerated().map { (name: "\(move)#\($0.offset)", frame: $0.element) } }
        for (prop, animation) in Self.props { pictures += animation.frames.enumerated().map { (name: "\(prop)#\($0.offset)", frame: $0.element) } }
        for ground in [0x000000, 0x2A2A30, 0xDCDCE0, 0xFFFFFF] as [UInt32] {
            var weak: [String] = []
            for (name, frame) in pictures {
                var (pairs, readable) = (0, 0)
                for y in 0..<frame.height {
                    for x in 0..<frame.width where frame[x, y] == "R" {
                        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where (0..<frame.width).contains(x + dx) && (0..<frame.height).contains(y + dy) {
                            let inner = frame[x + dx, y + dy]
                            guard inner != ".", inner != "R", let colour = palette[inner] else { continue }
                            pairs += 1
                            if max(contrast(palette["R"]!, ground), contrast(colour, ground)) >= 3 { readable += 1 }
                        }
                    }
                }
                if pairs > 0, Double(readable) / Double(pairs) < 0.9 { weak.append(name) }
            }
            #expect(weak.isEmpty, "on \(String(ground, radix: 16)): \(Set(weak))")
        }
    }

    // MARK: The corgi

    func box(_ frame: PixelFrame, ignoring letters: Set<Character> = ["R"]) -> (left: Int, right: Int, top: Int, bottom: Int) {
        let ink = (0..<frame.height).flatMap { y in (0..<frame.width).compactMap { x in frame[x, y] == "." || letters.contains(frame[x, y]) ? nil : (x, y) } }
        return (ink.map(\.0).min()!, ink.map(\.0).max()!, ink.map(\.1).min()!, ink.map(\.1).max()!)
    }

    func size(_ frame: PixelFrame) -> (width: Int, height: Int) {
        let b = box(frame, ignoring: ["R", "D", "Z", "H"])
        return (b.right - b.left + 1, b.bottom - b.top + 1)
    }

    func columns(_ frame: PixelFrame, _ letters: Set<Character>) -> [Int] {
        (0..<frame.width).filter { x in (0..<frame.height).contains { letters.contains(frame[x, $0]) } }
    }

    @Test func itIsOrangeAndWhiteLongAndLowWithShortLegsBigEarsAndAnEyeAndANoseFacesRightAndMirroredFacesLeft() throws {
        let stand = frames(.stand)[0], standing = size(stand), lying = size(frames(.lie)[0]), cat = size(CatArt.animation(for: .sit).frames[0])
        // Long and low: wider than it is tall, as tall as the cat sits (give or take its ears), flat when it lies.
        #expect(standing.width > standing.height && standing.width >= 22 && standing.width <= 30 && standing.height >= 16 && standing.height <= 22, "\(standing)")
        #expect(abs(standing.height - cat.height) <= 6, "the cat's scale: \(standing) against \(cat)")
        #expect(lying.width > lying.height * 2 && lying.width <= 30 && lying.height <= 14, "\(lying)")
        let cells = stand.cells
        for letter: Character in ["C", "c", "W", "w", "P", "e", "N", "K", "R"] { #expect(cells.contains(letter), "\(letter)") }
        #expect(try #require(columns(stand, ["N"]).max()) > 20, "the nose is out at the right")
        #expect(try #require(columns(stand.mirrored, ["N"]).min()) < 12)
        #expect(try #require(columns(stand, ["e"]).min()) > 14, "the eye is in the head, at the right")
        func channels(_ letter: Character) -> (r: UInt32, g: UInt32, b: UInt32) {
            let colour = CorgiArt.palette.colors[letter]!
            return ((colour >> 16) & 0xFF, (colour >> 8) & 0xFF, colour & 0xFF)
        }
        let (orange, white) = (channels("C"), channels("W"))
        #expect(orange.r > 0xD8 && orange.g > 0x70 && orange.g < 0xA0 && orange.b < 0x50, "orange")
        #expect(white.r > 0xF0 && white.g > 0xEE && white.b > 0xDC, "white")
        #expect(cells.filter { $0 == "C" }.count >= 90, "mostly orange")
        #expect(cells.filter { $0 == "W" }.count >= 14, "a white chest, muzzle and socks you can see")
        // Short legs: the part that is not the body, from the bottom of the belly to the ground, is a few rows.
        let rows = (0..<24).filter { y in (0..<32).filter { !".R".contains(stand[$0, y]) }.count >= 10 }
        let ink = box(stand)
        #expect(ink.bottom - (rows.max() ?? 0) <= 4, "legs of \(ink.bottom - (rows.max() ?? 0)) rows")
        // Big ears: the tip of the ears is well above the eye.
        let eyeRow = try #require((0..<24).first { y in (0..<32).contains { stand[$0, y] == "e" } })
        #expect(eyeRow - ink.top >= 5, "ears stand \(eyeRow - ink.top) rows over the eye")
    }

    @Test func itStandsInTheMiddleOfItsFrameSoTheMirrorImageStandsInTheMiddleToo() {
        let ignoring: Set<Character> = ["R", "D", "Z", "H", "B", "b", "T"]
        for move in CorgiMove.allCases {
            for (index, frame) in frames(move).enumerated() {
                let ink = box(frame, ignoring: ignoring)
                let centre = Double(ink.left + ink.right) / 2
                #expect(abs(centre - 15.5) < 5, "\(move) \(index): centred at \(centre)")
            }
        }
    }

    @Test func aCorgiThatDoesNotMoveStandsWithItsEyesOpenAndThenShut() {
        #expect(CorgiArt.restingFrames.count == 2)
        #expect(CorgiArt.restingFrames[0] == frames(.stand)[0])
        #expect(CorgiArt.restingFrames[1] == frames(.blink)[0] && CorgiArt.restingFrames[0] != CorgiArt.restingFrames[1])
    }

    @Test func gettingUpStandingUpSettingDownAndPuttingTheBallDownAreTheSamePicturesAsTheOtherWayAndTheMovesMeetWhereTheyBegin() {
        #expect(frames(.getUp) == frames(.lieDown).reversed() && frames(.standUp) == frames(.sitDown).reversed())
        #expect(frames(.begDown) == frames(.begUp).reversed() && frames(.wake) == frames(.settle).reversed() && frames(.lower) == frames(.grab).reversed())
        #expect(frames(.sitDown).last == frames(.sit).first && frames(.begUp).last == frames(.beg).first)
        #expect(frames(.lieDown).last == frames(.lie).first && frames(.settle).last == frames(.sleep).first)
        #expect(frames(.getUp).last != frames(.lieDown).last)
        // The spin ends on the picture it began with, which is standing, and getting up ends standing as it stands.
        #expect(frames(.spin).last == frames(.spin).first && frames(.spin).first == frames(.stand).first)
        // Lying down ends flat as it lies, and sitting down ends as it sits: no jump from one move to the next.
        let flat = size(frames(.lie).first!)
        #expect(abs(size(frames(.lieDown).last!).width - flat.width) <= 1 && abs(size(frames(.lieDown).last!).height - flat.height) <= 1)
        // Every move is made in a stance that the others begin and end in.
        for move in CorgiMove.allCases { #expect([CorgiMove.Stance.standing, .sitting, .begging, .lying, .asleep].contains(move.stance)) }
    }

    @Test func theMovesThatSayWhatTheyAreAreDrawnWithWhatTheySayItAndTheOthersAreNot() {
        func uses(_ move: CorgiMove, _ letter: Character) -> Bool { frames(move).contains { $0.cells.contains(letter) } }
        #expect(uses(.sleep, "Z") && !uses(.lie, "Z") && !uses(.stand, "Z") && frames(.settle).dropLast().allSatisfy { !$0.cells.contains("Z") })
        #expect(uses(.spin, "H") && !uses(.run, "H") && !uses(.stand, "H") && !uses(.wiggle, "H"))
        #expect(uses(.run, "D") && !uses(.trot, "D") && !uses(.stand, "D") && !uses(.carry, "D"), "dust where it runs")
        #expect(uses(.run, "T") && uses(.wiggle, "T") && uses(.beg, "T") && !uses(.sleep, "T"), "tongue out when it is glad")
        for move in [CorgiMove.grab, .carry, .lower] { #expect(uses(move, "B") && uses(move, "b"), "the ball in \(move)") }
        for move in [CorgiMove.stand, .trot, .run, .wiggle, .watch, .spin, .sit, .beg, .lie, .sleep] { #expect(!uses(move, "B"), "no ball in \(move)") }
        // The ball is in its mouth in every picture of the carry, and on the board.
        for frame in frames(.carry) {
            let ball = columns(frame, ["B", "b"])
            #expect(ball.count >= 5 && (ball.max() ?? 0) <= 28, "the ball is on the board: \(ball)")
            #expect(ball.min()! >= 21 && ball.min()! <= 24, "and at its nose: \(ball)")
        }
    }

    @Test func theBallItTakesUpIsWhereTheBallsOwnPictureHasItWhicheverWayTheCorgiFaces() {
        let ballLies = CorgiProps.rest.frames[0]
        func cells(_ frame: PixelFrame) -> [(x: Int, y: Int)] {
            (0..<frame.height).flatMap { y in (0..<frame.width).compactMap { x in "Bb".contains(frame[x, y]) ? (x, y) : nil } }
        }
        let reach = Int(CorgiMove.ballReach)
        let (lying, grabbing) = (cells(ballLies), cells(frames(.grab)[0]))
        #expect(!lying.isEmpty && lying.count == grabbing.count, "\(lying.count) pixels of ball against \(grabbing.count)")
        // Facing right, the corgi's picture begins `ballReach` pixels before the ball's.
        #expect(Set(lying.map { "\($0.x + reach),\($0.y)" }) == Set(grabbing.map { "\($0.x),\($0.y)" }))
        // Facing left, it is the mirror image, and its picture begins `ballReach` pixels after the ball's.
        let mirrored = cells(frames(.grab)[0].mirrored)
        #expect(Set(lying.map { "\($0.x - reach),\($0.y)" }) == Set(mirrored.map { "\($0.x),\($0.y)" }))
        // And the ball lies on the floor, where its feet are.
        #expect(lying.map(\.y).max() == 21 && grabbing.map(\.y).max() == 21)
    }

    // MARK: The ball

    @Test func theBallFallsInFromAboveBouncesLowerEachTimeAndLiesAndIsSetDownAndTakenUpAndThenThereIsNothing() {
        func bottom(_ frame: PixelFrame) -> Int? { (0..<24).last { y in (0..<32).contains { "Bb".contains(frame[$0, y]) } } }
        func top(_ frame: PixelFrame) -> Int? { (0..<24).first { y in (0..<32).contains { "Bb".contains(frame[$0, y]) } } }
        let toss = CorgiProps.toss.frames
        #expect(top(toss[0]) == 1 && bottom(toss[0])! <= 6, "it comes in at the top of the picture")
        #expect(toss.last == CorgiProps.rest.frames[0], "and lies as it lies")
        let bottoms = toss.compactMap(bottom)
        #expect(bottoms.count == toss.count)
        // The bounces: it hits the floor, goes up and comes down again three times, each time not so high.
        let floors = bottoms.indices.filter { bottoms[$0] == 21 }
        #expect(floors.count >= 4, "\(bottoms)")
        var heights: [Int] = []
        for (a, b) in zip(floors, floors.dropFirst()) where b > a + 1 { heights.append(21 - (bottoms[a...b].min() ?? 21)) }
        #expect(heights.count == 3 && heights == heights.sorted(by: >) && Set(heights).count == 3, "bounces of \(heights)")
        // Whole picture, one ball: it is the same size and the same column in all of them, and rims everywhere but where it is cut off.
        for animation in [CorgiProps.toss, CorgiProps.rest, CorgiProps.drop, CorgiProps.up] {
            for frame in animation.frames where frame.inkCount > 0 {
                let across = (0..<32).filter { x in (0..<24).contains { "Bb".contains(frame[x, $0]) } }
                #expect(across.isEmpty || (across.min()! >= 13 && across.max()! <= 18), "\(across)")
            }
        }
        #expect(CorgiProps.drop.frames[0] == CorgiProps.rest.frames[0] && CorgiProps.drop.frames.last == CorgiProps.rest.frames[0], "it is set down where it lies")
        #expect(bottom(CorgiProps.drop.frames[2])! <= 17, "and bounces")
        #expect(CorgiProps.up.frames[0] == CorgiProps.rest.frames[0] && CorgiProps.up.frames.last?.inkCount == 0)
        let rising = CorgiProps.up.frames.dropLast().compactMap(bottom)
        #expect(rising == rising.sorted(by: >) && Set(rising).count == rising.count, "it goes up: \(rising)")
        #expect(!CorgiProps.toss.loops && !CorgiProps.drop.loops && !CorgiProps.up.loops && CorgiProps.rest.frames.count == 1)
        #expect(CorgiProps.held.frames.count == 1 && CorgiProps.held.frames[0].inkCount == 0, "the ball in its mouth is a picture with nothing in it")
    }

    @Test func theLooksTheBrainHandsTheViewMatchTheArt() {
        for (prop, animation) in Self.props {
            #expect(animation.frames.count == prop.frameCount, "\(prop)")
            #expect(animation.fps == prop.fps && animation.loops == prop.look.loops, "\(prop)")
            #expect(CorgiProp(prop.look) == prop)
            #expect(prop.look.occupies, "a ball that lies is room that nobody else stops in")
            #expect(prop.look.animatesInPlace == (prop != .ballRest && prop != .ballHeld) && prop.look.rise == 0 && !prop.look.flutters)
        }
        #expect(CorgiProp.ballToss.passDuration == 14.0 / 12 && CorgiProp.ballDrop.passDuration == 0.5 && CorgiProp.ballUp.passDuration == 0.5)
        #expect(Set(CorgiProp.allCases.map(\.look.key)).count == CorgiProp.allCases.count)
        #expect(CorgiMove.allCases.map { CorgiMove($0.motion) } == CorgiMove.allCases)
        #expect(CorgiMove.allCases.map(\.motion.key) == Array(0..<CorgiMove.allCases.count))
        // The pose that shows a ball falling lasts as long as the ball takes to fall, and so on.
        #expect(Self.props.allSatisfy { $0.1.duration == $0.0.passDuration })
    }

    // MARK: Strips and memory

    @Test func stripsAreMadeOnceForEveryMoveAndFacingHoweverOftenTheyAreAsked() {
        let sheets = CorgiSheets()
        for _ in 0..<5 { _ = sheets.strip(for: .trot, facing: .right) }
        #expect(sheets.builds == 1)
        _ = sheets.strip(for: .trot, facing: .left)
        #expect(sheets.builds == 2)
        let strip = sheets.strip(for: .trot, facing: .right)
        #expect(strip.frameCount == 6 && (strip.frameWidth, strip.frameHeight) == (32, 24))
        _ = sheets.restingStrip()
        _ = sheets.restingStrip()
        _ = sheets.propStrip(.ballToss)
        _ = sheets.propStrip(.ballToss)
        #expect(sheets.builds == 4)
    }

    @Test func theWholeSheetFacingOneWayIsUnderAMegabyteAndBothWaysUnderTwo() {
        let sheets = CorgiSheets()
        for move in CorgiMove.allCases { _ = sheets.strip(for: move, facing: .right) }
        for prop in CorgiProp.allCases { _ = sheets.propStrip(prop) }
        _ = sheets.restingStrip()
        #expect(sheets.bytes < 1_000_000, "\(sheets.bytes) bytes")
        for move in CorgiMove.allCases { _ = sheets.strip(for: move, facing: .left) }
        #expect(sheets.bytes < 1_800_000, "\(sheets.bytes) bytes")
    }
}
