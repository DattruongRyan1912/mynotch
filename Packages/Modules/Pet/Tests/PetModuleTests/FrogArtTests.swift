import CoreGraphics
import Foundation
import Testing
@testable import PetModule

/// The frog, its lily pad and the moth it catches, as pictures.
@Suite struct FrogArtTests {
    static let moves = FrogMove.allCases.map { ($0, FrogArt.animation(for: $0)) }
    static let props: [(FrogProp, PixelAnimation)] = FrogProp.allCases.compactMap { prop in FrogProps.animation(for: prop).map { (prop, $0) } }

    func frames(_ move: FrogMove) -> [PixelFrame] { FrogArt.animation(for: move).frames }

    // MARK: Sizes

    @Test func everyFrameOfEveryMoveAndEveryPicturePropIsThirtyTwoByTwentyFourLikeTheCatsSoALaneTakesAnyMix() {
        for (move, animation) in Self.moves {
            for (index, frame) in animation.frames.enumerated() { #expect((frame.width, frame.height) == (32, 24), "\(move) frame \(index)") }
        }
        for (prop, animation) in Self.props {
            for (index, frame) in animation.frames.enumerated() { #expect((frame.width, frame.height) == (32, 24), "\(prop) frame \(index)") }
        }
        #expect((FrogArt.width, FrogArt.height) == (32, 24) && CatField.pictureSize == CGSize(width: 32, height: 24))
        for frame in FrogArt.restingFrames { #expect((frame.width, frame.height) == (32, 24)) }
    }

    @Test func everyMoveHasTheFramesTheBrainCountsOn() {
        for (move, animation) in Self.moves {
            #expect(animation.frames.count == move.frameCount, "\(move)")
            #expect(animation.fps == move.fps && animation.loops == move.loops && animation.advance == move.advance, "\(move)")
        }
        let asked: [FrogMove: Int] = [
            .sit: 4, .blink: 4, .puff: 6, .hop: 6, .watch: 2, .flick: 5, .jump: 8, .snapOut: 4, .snapIn: 3, .gulp: 6, .sleep: 4, .hopOn: 6, .hopOff: 6,
            .padSit: 4, .padBlink: 4, .padPuff: 6, .padWatch: 2, .padFlick: 5, .padJump: 8, .padSleep: 4,
            .headHopOn: 6, .headSit: 4, .headBlink: 4, .headHopOff: 6,
        ]
        #expect(Set(asked.keys) == Set(FrogMove.allCases))
        for move in FrogMove.allCases { #expect(move.frameCount == asked[move], "\(move)") }
        // A move on the pad or on the head is the same move as on the ground, in the same number of pictures at the same pace.
        for move in FrogMove.allCases where (move.stance == .pad && move != .hopOn) || [.headSit, .headBlink, .headHopOn, .headHopOff].contains(move) {
            let ground = move.onTheGround
            #expect(ground != move && move.frameCount == ground.frameCount && move.fps == ground.fps && move.loops == ground.loops, "\(move)")
        }
    }

    @Test func theMovesThatMoveHaveFramesThatDiffer() {
        let distinct: [FrogMove: Int] = [.hop: 6, .jump: 6, .puff: 3, .flick: 4, .snapOut: 4, .snapIn: 3, .gulp: 5, .hopOn: 6, .hopOff: 6, .sit: 2, .sleep: 4, .blink: 2, .watch: 2]
        for (move, animation) in Self.moves where animation.frames.count > 1 {
            let count = Set(animation.frames.map(\.cells)).count
            #expect(count >= distinct[move.onTheGround] ?? 2, "\(move) is \(count) pictures")
        }
    }

    @Test func aHopIsSlowEnoughToEndOnTheLandingItWasSentToAndNothingIsQuickerThanTheCatsFranticRun() {
        // Half a step is the most a walk ends away from where it was sent, and that has to be less than the room the lane keeps clear.
        #expect(FrogMove.hop.advance / 2 < CatField.leastEndError && FrogMove.hop.speed == 24)
        #expect(FrogMove.hopSpan / Double(FrogMove.hopOn.frameCount) <= Double(CatField.leastEndError), "four a picture, in whole steps")
        #expect(FrogMove.hopSpan / FrogMove.hopOn.passDuration <= CatMove.frantic.speed && FrogMove.hop.speed < CatMove.frantic.speed)
        for (move, animation) in Self.moves {
            #expect(animation.fps <= Double(CatSpriteView.frameRateCeiling), "\(move)")
            #expect(move == .hop || move.advance == 0, "\(move) goes nowhere by itself")
        }
        #expect(FrogMove.hopLength == 18 && Double(FrogMove.hop.frameCount) * FrogMove.hop.advance == 18)
        #expect(FrogProp.moth.look.fps == PropArt.moth.fps, "it flutters as the cat's moth does")
    }

    // MARK: Colours

    static let everyLetter: Set<Character> = Set(
        (moves.flatMap(\.1.frames) + props.flatMap(\.1.frames) + FrogArt.restingFrames).flatMap(\.cells)
    ).subtracting(["."])

    @Test func everyColourTheArtUsesIsInThePaletteAndEveryColourOfThePaletteIsDrawnSomewhere() {
        for letter in Self.everyLetter { #expect(FrogArt.palette.isKnown(letter), "no \(letter)") }
        for letter in FrogArt.palette.colors.keys { #expect(Self.everyLetter.contains(letter), "\(letter) is never drawn") }
    }

    @Test func theRimIsLightAndTheLineInsideItIsDarkSoOneOfThemReadsOnAnyGround() {
        let grounds: [(name: String, colour: UInt32)] = [("black", 0x000000), ("dark glass", 0x2A2A30), ("light glass", 0xDCDCE0), ("white", 0xFFFFFF)]
        let (rim, line) = (FrogArt.palette.colors["R"]!, FrogArt.palette.colors["K"]!)
        for ground in grounds { #expect(max(contrast(rim, ground.colour), contrast(line, ground.colour)) >= 3, "on \(ground.name)") }
        #expect(contrast(rim, 0x000000) >= 10 && contrast(line, 0xFFFFFF) >= 10)
    }

    @Test func theTongueAndTheWaterThatHaveNoLineOfTheirOwnAreColoursThatReadOnLightGlassAndTheRimReadsThemOnDark() {
        let colours = FrogArt.palette.colors
        // The tongue is one pixel wide between its rims; the water's ends are against the rim.
        #expect(contrast(colours["T"]!, 0xDCDCE0) >= 3 && contrast(colours["A"]!, 0xDCDCE0) >= 3 && contrast(colours["V"]!, 0xDCDCE0) >= 3)
        #expect(contrast(colours["R"]!, 0x2A2A30) >= 3)
    }

    @Test func everyFrameOfTheFrogHasALightRimAllRoundItAndNothingOfItTouchesTheAir() {
        for (move, animation) in Self.moves {
            for (index, frame) in animation.frames.enumerated() {
                var rim = 0
                for y in 0..<frame.height {
                    for x in 0..<frame.width where frame[x, y] != "." {
                        if frame[x, y] == "R" { rim += 1 }
                        guard frame[x, y] != "R" else { continue }
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

    @Test func theEdgeOfTheFrogAndOfThePadReadsAgainstEveryGroundInEveryFrame() {
        let palette = FrogArt.palette.colors
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

    // MARK: The frog

    func box(_ frame: PixelFrame, ignoring letters: Set<Character> = ["R"]) -> (left: Int, right: Int, top: Int, bottom: Int) {
        let ink = (0..<frame.height).flatMap { y in (0..<frame.width).compactMap { x in frame[x, y] == "." || letters.contains(frame[x, y]) ? nil : (x, y) } }
        return (ink.map(\.0).min()!, ink.map(\.0).max()!, ink.map(\.1).min()!, ink.map(\.1).max()!)
    }

    func size(_ frame: PixelFrame) -> (width: Int, height: Int) {
        let b = box(frame, ignoring: ["R", "T", "t", "Z", "H"])
        return (b.right - b.left + 1, b.bottom - b.top + 1)
    }

    func columns(_ frame: PixelFrame, _ letters: Set<Character>) -> [Int] {
        (0..<frame.width).filter { x in (0..<frame.height).contains { letters.contains(frame[x, $0]) } }
    }

    func rows(_ frame: PixelFrame, _ letters: Set<Character>) -> [Int] {
        (0..<frame.height).filter { y in (0..<frame.width).contains { letters.contains(frame[$0, y]) } }
    }

    @Test func itIsGreenWithAPaleBellyAndABigEyeOnTopOfItsHeadWideAndLowFacesRightAndMirroredFacesLeft() throws {
        let sit = frames(.sit)[0], sitting = size(sit), cat = size(CatArt.animation(for: .sit).frames[0])
        // Wide and low: wider than it is tall, and of the cat's scale (a good deal lower than it).
        #expect(sitting.width > sitting.height && sitting.width >= 18 && sitting.width <= 26 && sitting.height >= 10 && sitting.height <= 16, "\(sitting)")
        #expect(sitting.height < cat.height && sitting.width >= cat.width - 4, "the cat's scale: \(sitting) against \(cat)")
        for letter: Character in ["G", "g", "W", "w", "Y", "E", "K", "R", "L"] { #expect(sit.cells.contains(letter), "\(letter)") }
        func channels(_ letter: Character) -> (r: UInt32, g: UInt32, b: UInt32) {
            let colour = FrogArt.palette.colors[letter]!
            return ((colour >> 16) & 0xFF, (colour >> 8) & 0xFF, colour & 0xFF)
        }
        let (green, pale, eye) = (channels("G"), channels("W"), channels("Y"))
        #expect(green.g > 0xA0 && green.g > green.r && green.g > green.b + 0x30, "green")
        #expect(pale.r > 0xF0 && pale.g > 0xE8 && pale.b > 0xB0, "a pale belly")
        #expect(eye.r > 0xE0 && eye.g > 0xB0 && eye.b < 0x50, "a golden eye")
        #expect(sit.cells.filter { $0 == "G" || $0 == "g" }.count >= 90, "mostly green")
        #expect(sit.cells.filter { $0 == "W" }.count >= 8, "a belly you can see")
        // The eye is the top of the frog: it stands up over the head, which is lower.
        let eyeRows = rows(sit, ["Y"]), headTop = try #require(rows(sit, ["K"]).first { $0 > (eyeRows.last ?? 0) })
        #expect((eyeRows.first ?? 99) <= box(sit).top + 2, "the eye is on top: \(eyeRows)")
        #expect(headTop > (eyeRows.first ?? 0))
        // Facing right: the eye is towards the right, and so is the snout (the nostril).
        #expect(try #require(columns(sit, ["Y"]).min()) > 12, "the eye is in the head, at the right")
        #expect(try #require(columns(sit.mirrored, ["Y"]).max()) < 20)
        #expect(box(sit).right > box(sit).left + 18)
    }

    @Test func itSitsALittleLeftOfTheMiddleOfItsFrameSoTheMirrorImageDoesNotStandOffTheBoardAndItsTongueHasRoom() {
        let ignoring: Set<Character> = ["R", "T", "t", "Z", "H"]
        for move in FrogMove.allCases {
            for (index, frame) in frames(move).enumerated() {
                let ink = box(frame, ignoring: ignoring)
                let centre = Double(ink.left + ink.right) / 2
                // (A frog on the head of the capybara is where the capybara's head is, which is towards the front of its frame.)
                #expect(abs(centre - 15.5) < (move.isOnTheHead ? 9.5 : 6.5), "\(move) \(index): centred at \(centre)")
                #expect(ink.left >= 1 && ink.right <= 30, "\(move) \(index): on the board, \(ink)")
            }
        }
    }

    @Test func aFrogThatDoesNotMoveSitsWithItsEyesOpenAndThenShut() {
        #expect(FrogArt.restingFrames.count == 2)
        #expect(FrogArt.restingFrames[0] == frames(.sit)[0] || size(FrogArt.restingFrames[0]) == size(frames(.sit)[0]))
        #expect(FrogArt.restingFrames[0] != FrogArt.restingFrames[1])
        #expect(!FrogArt.restingFrames[1].cells.contains("Y") && FrogArt.restingFrames[0].cells.contains("Y"), "eyes shut, then open")
        #expect(frames(.blink)[1].cells.contains("Y") == false, "a slow blink goes all the way shut")
    }

    @Test func aBlinkIsSlowAndGoesHalfShutShutAndHalfShutAgain() {
        let blink = frames(.blink)
        let gold = blink.map { $0.cells.filter { $0 == "Y" }.count }
        #expect(gold[0] < frames(.sit)[0].cells.filter { $0 == "Y" }.count && gold[1] == 0 && gold[2] == 0 && gold[3] == gold[0], "\(gold)")
        #expect(FrogMove.blink.passDuration >= 1 && !FrogMove.blink.loops, "slowly: \(FrogMove.blink.passDuration) s")
    }

    @Test func theThroatPuffsOutAndGoesBackAndTheBodyIsGreenWhereItIsNotPale() {
        let puff = frames(.puff)
        let pale = puff.map { $0.cells.filter { $0 == "W" || $0 == "w" }.count }
        #expect(pale[2] > pale[0] + 6 && pale[3] == pale[2] && pale[5] == pale[0] && pale[1] > pale[0] && pale[4] == pale[1], "swells and goes down: \(pale)")
        // The throat is in front of the chin, to the right of the frog's body, and does not leave the board.
        for frame in puff { #expect(box(frame).right <= 30) }
    }

    @Test func hoppingAndLandingAreTheSameFramesWhicheverWayTheFrogGoesAndTheHopsMeetWhereTheOthersBegin() {
        let (sit, padSit) = (frames(.sit), frames(.padSit))
        func bottom(_ frame: PixelFrame) -> Int { box(frame).bottom }
        // It begins a hop on the ground and ends it on the ground; on to the pad it ends on the pad and off it begins on it.
        #expect(bottom(frames(.hop).first!) == bottom(sit[0]) && bottom(frames(.hopOn).first!) == bottom(sit[0]))
        #expect(bottom(frames(.hopOn).last!) == bottom(padSit[0]) && bottom(frames(.hopOff).first!) == bottom(padSit[0]))
        #expect(bottom(frames(.hopOff).last!) == bottom(sit[0]) && bottom(frames(.hop).last!) == bottom(sit[0]))
        #expect(bottom(padSit[0]) == bottom(sit[0]) - FrogArt.padRise)
        // The same frog, a few rows higher: the pictures on the pad are the pictures on the ground, lifted.
        for (ground, pad) in [(FrogMove.sit, FrogMove.padSit), (.blink, .padBlink), (.puff, .padPuff), (.watch, .padWatch), (.flick, .padFlick), (.jump, .padJump), (.sleep, .padSleep)] {
            for (low, high) in zip(frames(ground), frames(pad)) {
                #expect(box(low, ignoring: ["R"]).left == box(high, ignoring: ["R"]).left && box(low).bottom - FrogArt.padRise == box(high).bottom, "\(pad)")
            }
        }
    }

    @Test func aHopIsMostlyInTheAirAndTheFrogIsNearlyStillOnTheGroundWhileTheLayerMovesUnderIt() {
        let hop = frames(.hop)
        let ground = box(hop[0]).bottom
        let airborne = hop.filter { box($0).bottom < ground }.count
        #expect(airborne >= 3, "\(airborne) of 6 pictures with it off the ground")
        // Where it is drawn on the screen, which is where its picture is (three points a picture) and where it is drawn in it: while it is on the
        // ground it is nearly still, and in the air it goes quickly.
        var screen: [Double] = []
        for (index, frame) in hop.enumerated() {
            let ink = box(frame, ignoring: ["R", "T", "t"])
            screen.append(Double(index) * FrogMove.hop.advance + Double(ink.right))
        }
        for index in 0..<hop.count where box(hop[index]).bottom == ground && box(hop[(index + 1) % hop.count]).bottom == ground {
            let next = index + 1 < hop.count ? screen[index + 1] : screen[0] + FrogMove.hopLength
            #expect(abs(next - screen[index]) <= 2.5, "\(index): slides \(next - screen[index]) on the ground")
        }
        // And the cycle comes round: where it ends is where the next begins, a hop further on.
        #expect(abs(screen[0] + FrogMove.hopLength - (screen[5] + FrogMove.hop.advance)) <= 4)
    }

    @Test func theMovesThatSayWhatTheyAreAreDrawnWithWhatTheySayItAndTheOthersAreNot() {
        func uses(_ move: FrogMove, _ letter: Character) -> Bool { frames(move).contains { $0.cells.contains(letter) } }
        for move in [FrogMove.sleep, .padSleep] { #expect(uses(move, "Z") && !uses(move.onTheGround == .sleep ? .sit : .padSit, "Z")) }
        #expect(uses(.jump, "H") && uses(.padJump, "H") && !uses(.hop, "H") && !uses(.sit, "H") && !uses(.flick, "H"))
        #expect(uses(.flick, "T") && uses(.padFlick, "T") && uses(.snapOut, "T") && uses(.snapIn, "T") && !uses(.sit, "T") && !uses(.hop, "T") && !uses(.gulp, "T"))
        #expect(uses(.flick, "t") && uses(.snapOut, "t") && !uses(.gulp, "t") && !uses(.sleep, "t"), "a sticky end to the tongue")
        // Asleep its eyes are shut, which is a line and no gold; the gulp is done with its eyes shut too.
        for frame in frames(.sleep) + frames(.padSleep) { #expect(!frame.cells.contains("Y"), "no eye shows") }
        #expect(frames(.gulp).prefix(4).allSatisfy { !$0.cells.contains("Y") } && frames(.gulp).last!.cells.contains("K"))
        // Eyes up for the pointer and the moth.
        #expect(frames(.watch)[0] != frames(.sit)[0] && frames(.watch)[0].cells.contains("Y"))
    }

    @Test func theTongueGoesUpAndOutTowardsWhereItIsFlickedAndTheTipOfItIsAtTheMothWhichHoversThereWhicheverWayItFaces() throws {
        // The flick is up and to the front: the tip of it is higher than the mouth and further along than the snout.
        let top = frames(.flick)[2]
        let tongue = (0..<top.height).flatMap { y in (0..<top.width).compactMap { x in "Tt".contains(top[x, y]) ? (x, y) : nil } }
        let snout = box(top, ignoring: ["R", "T", "t", "E"]).right
        #expect(try #require(tongue.map(\.0).max()) > snout, "out past the snout")
        #expect(try #require(tongue.map(\.1).min()) < (rows(top, ["T"]).max() ?? 0) - 3, "and up")
        // The moth hovers at the tip of the tongue: the middle of its picture is where the knob on the end of it is.
        let (width, height) = (Double(PropArt.mothSize.width), Double(PropArt.mothSize.height) + 2)
        for facing in [Facing.right, .left] {
            let last = facing == .right ? frames(.snapOut).last! : frames(.snapOut).last!.mirrored
            let knob = (0..<last.height).flatMap { y in (0..<last.width).compactMap { x in last[x, y] == "t" ? (x, y) : nil } }
            let (x, y) = (Double(knob.map(\.0).reduce(0, +)) / Double(knob.count) + 0.5, Double(knob.map(\.1).reduce(0, +)) / Double(knob.count) + 0.5)
            let left = facing == .right ? FrogMove.mothReach.right : FrogMove.mothReach.left
            let middle = (x: left + width / 2, y: 24 - FrogProp.mothHeld.look.rise - height / 2 + 1)
            #expect(abs(x - middle.x) <= 2 && abs(y - middle.y) <= 2, "\(facing): the tip is at \(x), \(y) and the moth is at \(middle)")
        }
        // The moth is the cat's two pictures, and the one that is held is the same pictures, not bobbing.
        #expect(FrogProp.moth.look.flutters && !FrogProp.mothHeld.look.flutters && FrogProp.mothHeld.look.rise == FrogProp.moth.look.rise + 2)
    }

    @Test func theTongueIsInThePictureAndNeverTouchesTheEdgeOfItWhicheverWayItFaces() {
        for move in [FrogMove.flick, .padFlick, .snapOut, .snapIn] {
            for frame in frames(move) {
                for picture in [frame, frame.mirrored] {
                    for y in 0..<picture.height {
                        for x in 0..<picture.width where "Tt".contains(picture[x, y]) {
                            #expect((1...30).contains(x) && (1...22).contains(y), "\(move): tongue at \(x), \(y)")
                        }
                    }
                }
            }
        }
    }

    // MARK: The lily pad

    @Test func theFrogOnThePadIsDrawnAFewRowsHigherAndNothingOfThePadLandsOnItAndThePadHasNoRimOverItsTop() {
        let pads = FrogProps.rippling.frames + FrogProps.still.frames + FrogProps.appearing.frames + FrogProps.sinking.frames
        for pad in pads {
            for y in 0...19 { for x in 0..<32 { #expect(pad[x, y] != "R", "a rim over the top of the pad, where the frog sits: \(x), \(y)") } }
        }
        for move in [FrogMove.padSit, .padBlink, .padPuff, .padWatch, .padFlick, .padSleep] {
            for frog in frames(move) {
                for pad in FrogProps.rippling.frames + FrogProps.still.frames {
                    // Where the pad is drawn over the frog, they are the same colour (its line under the feet is the line on the top of the pad), or it is
                    // over the frog's rim and nothing of the frog.
                    for y in 0..<24 {
                        for x in 0..<32 where pad[x, y] != "." && frog[x, y] != "." {
                            #expect(pad[x, y] == frog[x, y] || frog[x, y] == "R", "\(move): \(pad[x, y]) over \(frog[x, y]) at \(x), \(y)")
                        }
                    }
                }
                #expect(box(frog).bottom == (rows(FrogProps.still.frames[0], ["K"]).first ?? 0), "its feet are on the top of the pad")
            }
        }
    }

    @Test func thePadComesUpOutOfTheWaterLiesRipplesGoesDownUnderTheFrogAndIsGoneTheWayItCameAndThenThereIsNothing() {
        #expect(FrogProps.appearing.frames.count == 4 && FrogProps.sinking.frames.count == 5 && !FrogProps.appearing.loops && !FrogProps.sinking.loops)
        let ink = FrogProps.appearing.frames.map(\.inkCount)
        #expect(ink == ink.sorted() && Set(ink).count == 4 && FrogProps.appearing.frames.last == FrogProps.still.frames[0], "it comes up and is whole: \(ink)")
        #expect(FrogProps.sinking.frames.dropLast() == FrogProps.appearing.frames.reversed() && FrogProps.sinking.frames.last?.inkCount == 0)
        #expect(FrogProps.rippling.loops && FrogProps.rippling.frames.count == 3 && Set(FrogProps.rippling.frames.map(\.cells)).count == 3)
        #expect(FrogProps.rippling.frames[0] == FrogProps.still.frames[0], "the ripples go round from where it lies")
        // The frog's weight: it is down a row in the picture the frog lands on, and in the one it leaps from.
        let landing = FrogProps.landing.frames
        #expect(landing.dropLast().allSatisfy { $0 == FrogProps.still.frames[0] } && landing.last != FrogProps.still.frames[0])
        #expect(FrogProps.leaping.frames[0] == FrogProps.still.frames[0] && FrogProps.leaping.frames[1] != FrogProps.still.frames[0])
        let top = { (frame: PixelFrame) in self.rows(frame, ["K"]).first ?? 0 }
        #expect(top(landing.last!) == top(landing[0]) + 1 && top(FrogProps.leaping.frames[1]) == top(landing[0]) + 1, "down a row")
        #expect(!FrogProps.landing.loops && !FrogProps.leaping.loops)
    }

    @Test func thePadIsInTheMiddleOfItsPictureWhereTheFrogSitsAndIsAWaterLineOfTwoRowsUnderIt() {
        let (pad, frog) = (FrogProps.still.frames[0], frames(.padSit)[0])
        let (padBox, frogBox) = (box(pad, ignoring: ["R", "A", "a"]), box(frog))
        #expect(abs(Double(padBox.left + padBox.right) / 2 - Double(frogBox.left + frogBox.right) / 2) <= 3, "\(padBox) under \(frogBox)")
        #expect(padBox.right - padBox.left >= 18, "a pad as wide as the frog is")
        let water = columns(pad, ["A", "a"])
        #expect((water.min() ?? 99) < padBox.left - 2 && (water.max() ?? 0) > padBox.right + 2, "the water line goes out past the pad")
        #expect(rows(pad, ["A"]).max() == 22 && rows(pad, ["a", "A"]).min() ?? 0 >= 19, "two rows of it, at the bottom")
    }

    @Test func theLooksTheBrainHandsTheViewMatchTheArt() {
        for (prop, animation) in Self.props {
            #expect(animation.frames.count == prop.frameCount, "\(prop)")
            #expect(animation.fps == prop.fps && animation.loops == prop.look.loops, "\(prop)")
            #expect(FrogProp(prop.look) == prop)
            #expect(prop.look.occupies, "a pad is room that nobody else stops in")
            #expect(prop.look.animatesInPlace == (prop != .padStill) && prop.look.rise == 0 && !prop.look.flutters)
            #expect(animation.duration == prop.passDuration)
        }
        for moth in [FrogProp.moth, .mothHeld] {
            #expect(moth.frameCount == PropArt.moth.frames.count && moth.fps == PropArt.moth.fps && moth.look.loops && moth.look.animatesInPlace && !moth.look.occupies)
            #expect(FrogProp(moth.look) == moth && moth.isMoth)
        }
        #expect(Set(FrogProp.allCases.map(\.look.key)).count == FrogProp.allCases.count)
        #expect(FrogProp.padAppearing.passDuration == 4.0 / 6 && FrogProp.padSinking.passDuration == 5.0 / 6 && FrogProp.padLanding.passDuration == FrogMove.hopOn.passDuration)
        #expect(FrogProp.padLeaping.passDuration == FrogMove.hopOff.passDuration)
        #expect(FrogMove.allCases.map { FrogMove($0.motion) } == FrogMove.allCases)
        #expect(FrogMove.allCases.map(\.motion.key) == Array(0..<FrogMove.allCases.count))
        #expect(FrogMove.mothReach.right - FrogMove.mothReach.left == 29 && FrogMove.hopSpan == 24)
    }

    // MARK: Strips and memory

    @Test func stripsAreMadeOnceForEveryMoveAndFacingHoweverOftenTheyAreAsked() {
        let sheets = FrogSheets()
        for _ in 0..<5 { _ = sheets.strip(for: .hop, facing: .right) }
        #expect(sheets.builds == 1)
        _ = sheets.strip(for: .hop, facing: .left)
        #expect(sheets.builds == 2)
        let strip = sheets.strip(for: .hop, facing: .right)
        #expect(strip.frameCount == 6 && (strip.frameWidth, strip.frameHeight) == (32, 24))
        _ = sheets.restingStrip()
        _ = sheets.restingStrip()
        _ = sheets.propStrip(.padLanding)
        _ = sheets.propStrip(.padLanding)
        #expect(sheets.builds == 4)
    }

    @Test func theMothIsTheCatsOwnStripAndNotOneDrawnInTheFrogsColoursAndTheFrogMakesNoStripOfIt() {
        let sheets = FrogSheets()
        let before = sheets.builds
        let (flying, held) = (sheets.propStrip(.moth), sheets.propStrip(.mothHeld))
        #expect(flying.image === CatSheets.shared.propStrip(.moth).image && held.image === flying.image, "the cat's strip, in the cat's colours")
        #expect(sheets.builds == before, "none made for it")
        #expect(flying.frameCount == 2 && (flying.frameWidth, flying.frameHeight) == (Int(PropArt.mothSize.width), Int(PropArt.mothSize.height)))
        // A moth drawn with the frog's palette would be a moth of nothing: its letters are not the frog's.
        let letters = Set(PropArt.moth.frames.flatMap(\.cells)).subtracting(["."])
        #expect(!letters.isSubset(of: Set(FrogArt.palette.colors.keys)), "\(letters)")
        #expect(FrogSpecies.shared.propStrip(FrogProp.moth.look).image === flying.image && FrogSpecies.shared.propStrip(FrogProp.mothHeld.look).image === flying.image)
    }

    @Test func theWholeSheetFacingOneWayIsUnderAMegabyteAndBothWaysUnderTwo() {
        let sheets = FrogSheets()
        for move in FrogMove.allCases { _ = sheets.strip(for: move, facing: .right) }
        for prop in FrogProp.allCases { _ = sheets.propStrip(prop) }
        _ = sheets.restingStrip()
        #expect(sheets.bytes < 1_000_000, "\(sheets.bytes) bytes")
        for move in FrogMove.allCases { _ = sheets.strip(for: move, facing: .left) }
        #expect(sheets.bytes < 1_800_000, "\(sheets.bytes) bytes")
    }
}
