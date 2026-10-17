import CoreGraphics
import Foundation
import Testing
@testable import PetModule

/// The hamster and what it plays with, as pictures.
@Suite struct HamsterArtTests {
    static let moves = HamsterMove.allCases.map { ($0, HamsterArt.animation(for: $0)) }
    static let props = HamsterProp.allCases.map { ($0, HamsterProps.animation(for: $0)) }

    func frames(_ move: HamsterMove) -> [PixelFrame] { HamsterArt.animation(for: move).frames }

    // MARK: Sizes

    @Test func everyFrameOfEveryMoveAndEveryPropOfTheWheelIsThirtyTwoByTwentyFourLikeTheCatsSoALaneTakesAnyMix() {
        for (move, animation) in Self.moves {
            for (index, frame) in animation.frames.enumerated() { #expect((frame.width, frame.height) == (32, 24), "\(move) frame \(index)") }
        }
        for (prop, animation) in Self.props where prop.isWheel {
            for (index, frame) in animation.frames.enumerated() { #expect((frame.width, frame.height) == (32, 24), "\(prop) frame \(index)") }
        }
        #expect((HamsterArt.width, HamsterArt.height) == (32, 24) && CatField.pictureSize == CGSize(width: 32, height: 24))
        for frame in HamsterArt.restingFrames { #expect((frame.width, frame.height) == (32, 24)) }
    }

    @Test func everyMoveHasTheFramesTheBrainCountsOn() {
        for (move, animation) in Self.moves {
            #expect(animation.frames.count == move.frameCount, "\(move)")
            #expect(animation.fps == move.fps && animation.loops == move.loops && animation.advance == move.advance, "\(move)")
        }
        let asked: [HamsterMove: Int] = [
            .sit: 4, .blink: 1, .groom: 4, .freeze: 2, .happy: 6, .stuffA: 6, .stuffB: 6, .stuffC: 6, .puffed: 4, .unstuff: 5, .curl: 4, .ball: 2,
            .sleep: 4, .uncurl: 4, .scurry: 6, .sitDown: 3, .standUp: 3, .hopIn: 4, .hopOut: 4, .wheelSit: 2, .wheelLazy: 4, .wheelJog: 4,
            .wheelRun: 4, .wheelSprint: 4, .wheelWatch: 2, .wheelHappy: 6,
        ]
        #expect(Set(asked.keys) == Set(HamsterMove.allCases))
        for move in HamsterMove.allCases { #expect(move.frameCount == asked[move], "\(move)") }
    }

    @Test func theMovesThatMoveHaveFramesThatDiffer() {
        let distinct: [HamsterMove: Int] = [
            .scurry: 6, .groom: 2, .happy: 6, .stuffA: 6, .stuffB: 6, .stuffC: 6, .curl: 4, .sleep: 4, .sitDown: 3, .hopIn: 4, .unstuff: 5,
            .wheelLazy: 4, .wheelJog: 4, .wheelRun: 4, .wheelSprint: 4, .wheelHappy: 5, .puffed: 3, .sit: 2,
        ]
        for (move, animation) in Self.moves where animation.frames.count > 1 {
            let count = Set(animation.frames.map(\.cells)).count
            #expect(count >= distinct[move] ?? 2, "\(move) is \(count) pictures")
        }
    }

    @Test func theQuicknessIsInTheWalkAndTheRunningAndNowhereElse() {
        // Quick small steps: more frames to the second than the cat's walk, a step of at most a few points (so a walk ends where it was sent).
        #expect(HamsterMove.scurry.advance <= CatField.leastEndError && HamsterMove.scurry.fps > CatMove.walk.fps)
        for (move, animation) in Self.moves where !move.runs && move != .scurry { #expect(animation.fps <= 12, "\(move) is not in a hurry") }
        for pace in WheelPace.allCases { #expect(HamsterArt.animation(for: pace.move).fps <= Double(CatSpriteView.frameRateCeiling)) }
        for (move, animation) in Self.moves where move.runs || move == .scurry { #expect(animation.fps <= 24) }
        for (prop, animation) in Self.props where prop.turns { #expect(animation.fps <= 24, "\(prop)") }
    }

    @Test func theHopIntoTheWheelIsWholeStepsOfTheFramesItIsPlayedAt() {
        // Four frames in half a second go six pixels each across the hop's span, so the hop ends where the wheel is.
        let move = HamsterMove.hopIn
        #expect(HamsterMove.hopSpan == 24 && move.passDuration == 0.5)
        #expect((HamsterMove.hopSpan / (move.passDuration * move.fps)).rounded() * Double(move.frameCount) == HamsterMove.hopSpan)
        #expect(HamsterMove.hopOut.passDuration == move.passDuration)
    }

    // MARK: Colours

    static let everyLetter: Set<Character> = Set(
        (moves.flatMap(\.1.frames) + props.flatMap(\.1.frames) + HamsterArt.restingFrames).flatMap(\.cells)
    ).subtracting(["."])

    @Test func everyColourTheArtUsesIsInThePaletteAndEveryColourOfThePaletteIsDrawnSomewhere() {
        for letter in Self.everyLetter { #expect(HamsterArt.palette.isKnown(letter), "no \(letter)") }
        for letter in HamsterArt.palette.colors.keys { #expect(Self.everyLetter.contains(letter), "\(letter) is never drawn") }
    }

    @Test func theRimIsLightAndTheLineInsideItIsDarkSoOneOfThemReadsOnAnyGround() {
        let grounds: [(name: String, colour: UInt32)] = [("black", 0x000000), ("dark glass", 0x2A2A30), ("light glass", 0xDCDCE0), ("white", 0xFFFFFF)]
        let (rim, line) = (HamsterArt.palette.colors["R"]!, HamsterArt.palette.colors["K"]!)
        for ground in grounds { #expect(max(contrast(rim, ground.colour), contrast(line, ground.colour)) >= 3, "on \(ground.name)") }
        #expect(contrast(rim, 0x000000) >= 10 && contrast(line, 0xFFFFFF) >= 10)
    }

    @Test func everyFrameOfTheHamsterHasALightRimAllRoundItAndNothingOfItTouchesTheAir() {
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

    @Test func theEdgeOfTheHamsterAndOfTheWheelReadsAgainstEveryGroundInEveryFrame() {
        let palette = HamsterArt.palette.colors
        var pictures: [(name: String, frame: PixelFrame)] = []
        for (move, animation) in Self.moves { pictures += animation.frames.map { (name: "\(move)", frame: $0) } }
        for (prop, animation) in Self.props where prop.isWheel { pictures += animation.frames.map { (name: "\(prop)", frame: $0) } }
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

    // MARK: The hamster

    func box(_ frame: PixelFrame) -> (width: Int, height: Int) {
        let ink = (0..<frame.height).flatMap { y in (0..<frame.width).compactMap { x in frame[x, y] == "." ? nil : (x, y) } }
        return (ink.map(\.0).max()! - ink.map(\.0).min()! + 1, ink.map(\.1).max()! - ink.map(\.1).min()! + 1)
    }

    @Test func itIsSmallRoundAndGoldenWithAWhiteBellyAndPinkEarsAndFacesRightAndMirroredFacesLeft() throws {
        let sitting = box(frames(.sit)[0]), walking = box(frames(.scurry)[0])
        // The smallest of the three, with its rim: well under the cat's, and the capybara's, and still big enough to make out.
        #expect(sitting.width >= 13 && sitting.width <= 19 && sitting.height >= 15 && sitting.height <= 19, "\(sitting)")
        #expect(walking.width >= 15 && walking.width <= 20 && walking.height >= 11 && walking.height <= 16, "\(walking)")
        let cat = box(CatArt.animation(for: .sit).frames[0]), capybara = box(CapybaraArt.animation(for: .walk).frames[0])
        for pose in frames(.sit) + frames(.scurry) + frames(.groom) + frames(.ball) {
            let size = box(pose)
            #expect(size.width * size.height * 10 < cat.width * cat.height * 7, "small: \(size) against the cat's \(cat)")
            #expect(size.width * size.height * 10 < capybara.width * capybara.height * 14, "small: \(size) against the capybara's \(capybara)")
        }
        let cells = frames(.sit)[0].cells
        for letter: Character in ["O", "D", "W", "P", "E", "K", "R"] { #expect(cells.contains(letter), "\(letter)") }
        func columns(_ frame: PixelFrame, _ letter: Character) -> [Int] { (0..<frame.width).filter { x in (0..<frame.height).contains { frame[x, $0] == letter } } }
        let walk = frames(.scurry)[0]
        #expect(try #require(columns(walk, "E").min()) > 16, "the eye is at the right, in the head")
        #expect(try #require(columns(walk.mirrored, "E").max()) < 15)
        let fur = HamsterArt.palette.colors["O"]!
        #expect((fur >> 16) & 0xFF > (fur >> 8) & 0xFF && (fur >> 8) & 0xFF > fur & 0xFF && (fur >> 16) & 0xFF > 0xC0, "golden: a lot of red, less green, little blue")
        let white = HamsterArt.palette.colors["W"]!
        #expect((white >> 16) & 0xFF > 0xEE && (white >> 8) & 0xFF > 0xEE && white & 0xFF > 0xD8, "a white belly")
        #expect(frames(.sit)[0].cells.filter { $0 == "W" }.count >= 8, "a belly you can see")
    }

    @Test func itStandsInTheMiddleOfItsFrameSoTheMirrorImageStandsInTheMiddleToo() {
        for move in [HamsterMove.sit, .scurry, .groom, .ball, .freeze] {
            for frame in frames(move) {
                let ink = (0..<frame.width).filter { x in (0..<frame.height).contains { frame[x, $0] != "." && frame[x, $0] != "R" } }
                let centre = Double(ink.min()! + ink.max()!) / 2
                #expect(abs(centre - 15.5) < 3.5, "\(move): centred at \(centre)")
            }
        }
    }

    @Test func aHamsterThatDoesNotMoveSitsWithItsEyesOpenAndThenShut() {
        #expect(HamsterArt.restingFrames.count == 2)
        #expect(HamsterArt.restingFrames[0] == frames(.sit)[0])
        #expect(HamsterArt.restingFrames[1] == frames(.blink)[0] && HamsterArt.restingFrames[0] != HamsterArt.restingFrames[1])
    }

    @Test func standingAndSittingAndCurlingAndHopsAreTheSamePicturesBothWaysAndMeetWhereTheMovesBegin() {
        #expect(frames(.standUp) == frames(.sitDown).reversed() && frames(.uncurl) == frames(.curl).reversed() && frames(.hopOut) == frames(.hopIn).reversed())
        #expect(frames(.sitDown).last == frames(.sit).first)
        #expect(frames(.hopIn).first == HamsterArt.draw(HamsterArt.sitRig(crouch: 1)))
        // Curling ends in the ball it rests and sleeps in.
        #expect(frames(.curl).last == HamsterArt.draw(HamsterArt.ballRig(1, face: .blink)))
    }

    @Test func theMovesThatSayWhatTheyAreAreDrawnWithWhatTheySayIt() {
        func uses(_ move: HamsterMove, _ letter: Character) -> Bool { frames(move).contains { $0.cells.contains(letter) } }
        #expect(uses(.sleep, "Z") && !uses(.ball, "Z") && !uses(.sit, "Z"))
        #expect(uses(.happy, "H") && !uses(.wheelHappy, "H") && !uses(.scurry, "H"))
        #expect(uses(.stuffA, "S") && uses(.stuffB, "V") && !uses(.sit, "S"), "a seed in its paws")
        #expect(uses(.wheelRun, "X") && uses(.wheelSprint, "X") && !uses(.wheelJog, "X") && !uses(.wheelLazy, "X") && !uses(.scurry, "X"), "lines only when it is fast")
        func lines(_ move: HamsterMove) -> Int { frames(move).reduce(0) { $0 + $1.cells.filter { $0 == "X" }.count } }
        #expect(lines(.wheelSprint) > lines(.wheelRun) * 2, "more of them the faster it goes: \(lines(.wheelRun)), \(lines(.wheelSprint))")
    }

    @Test func theFasterItRunsTheMoreItStretchesAndTheHarderItsLegsGo() {
        func reach(_ move: HamsterMove) -> Int {
            // How far its nose is from the middle of the wheel, on average over the cycle.
            frames(move).reduce(0) { total, frame in total + (0..<frame.width).last { x in (0..<frame.height).contains { frame[x, $0] == "E" } }! } / frames(move).count
        }
        #expect(reach(.wheelLazy) <= reach(.wheelJog) && reach(.wheelJog) <= reach(.wheelRun) && reach(.wheelRun) <= reach(.wheelSprint) && reach(.wheelLazy) < reach(.wheelSprint))
        func lowest(_ move: HamsterMove) -> Int {
            // How low its head is: the row of its eye.
            frames(move).reduce(0) { total, frame in total + (0..<frame.height).first { y in (0..<frame.width).contains { frame[$0, y] == "E" } }! } / frames(move).count
        }
        #expect(lowest(.wheelSprint) >= lowest(.wheelLazy), "it runs lower the faster it goes")
    }

    // MARK: Cheeks

    @Test func theCheeksAreOneSizeFullerAfterEachSeedAndGoDownAgain() {
        func size(_ frame: PixelFrame) -> Int { frame.inkCount }
        let (sit, a, b, c) = (size(frames(.sit)[0]), size(frames(.stuffA).last!), size(frames(.stuffB).last!), size(frames(.stuffC).last!))
        #expect(sit < a && a < b && b < c, "fuller each time: \(sit), \(a), \(b), \(c)")
        #expect(abs(size(frames(.stuffB).first!) - size(frames(.stuffA).last!)) <= 8, "it picks up where it left off")
        #expect(frames(.puffed).allSatisfy { size($0) > b }, "sitting with them full")
        let down = frames(.unstuff).map(size)
        #expect(down[0] > down[1] && down[1] > down[2] && down[2] > down[3], "emptied a size at a time: \(down)")
        #expect(frames(.unstuff).last?.cells.filter { $0 == "L" }.isEmpty == true, "and then empty")
        #expect(frames(.stuffC).last?.cells.contains("L") == true)
        for (move, level) in [(HamsterMove.stuffA, 1), (.stuffB, 2), (.stuffC, 3)] {
            let last = frames(move).last!
            #expect(last == HamsterArt.draw(HamsterArt.sitRig(cheeks: level, face: .happy)), "\(move) ends with the cheeks as full as level \(level)")
        }
    }

    // MARK: In the wheel

    /// A frame of the wheel and the hamster in it, the wheel over the hamster as the view draws them.
    func composite(_ hamster: PixelFrame, _ wheel: PixelFrame) -> PixelFrame { hamster.drawing(wheel, atX: 0, y: 0) }

    @Test func theHamsterInTheWheelIsSeenInsideTheRingAndNeverOutsideIt() {
        let centre = (x: HamsterProps.ringCentre.x + 1, y: HamsterProps.ringCentre.y + 1)
        let wheel = HamsterProps.wheel()
        for move in HamsterMove.allCases where move.stance == .wheel && move != .hopIn {
            for (index, frame) in frames(move).enumerated() {
                var visible = 0, total = 0
                for y in 0..<frame.height {
                    for x in 0..<frame.width where frame[x, y] != "." && frame[x, y] != "R" {
                        total += 1
                        guard wheel[x, y] == "." else { continue }
                        visible += 1
                        let distance = ((Double(x) + 0.5 - centre.x) * (Double(x) + 0.5 - centre.x) + (Double(y) + 0.5 - centre.y) * (Double(y) + 0.5 - centre.y)).squareRoot()
                        #expect(distance <= HamsterProps.ringRadius - 1.5, "\(move) frame \(index): \(frame[x, y]) at \(x), \(y) is out of the ring, \(distance) from the middle")
                    }
                }
                #expect(Double(visible) / Double(total) > 0.82, "\(move) frame \(index): only \(visible) of \(total) is in the clear")
            }
        }
        // The hop in ends in the clear inside it.
        let landing = frames(.hopIn).last!
        #expect(composite(landing, wheel).cells.filter { $0 == "O" }.count > landing.cells.filter { $0 == "O" }.count * 8 / 10)
    }

    @Test func theWheelIsARingWithItsInsideClearAndRungsThatGoRoundAndAreTheOnlyThingThatSaysItIsTurning() {
        let still = HamsterProps.still.frames[0]
        let interior = (0..<32).flatMap { x in (0..<24).map { y in (x, y) } }.filter { x, y in
            let (dx, dy) = (Double(x) + 0.5 - 16, Double(y) + 0.5 - 12)
            return (dx * dx + dy * dy).squareRoot() < HamsterProps.ringRadius - 3
        }
        #expect(interior.count > 150 && interior.allSatisfy { still[$0.0, $0.1] == "." }, "nothing inside it to cover the hamster")
        let size = box(still)
        #expect(size.width == 24 && size.height == 24, "a ring of 22 with its rim: \(size)")
        for prop in [HamsterProp.wheelLazy, .wheelJog, .wheelRun, .wheelSprint] {
            let turning = HamsterProps.animation(for: prop).frames
            #expect(turning.count == 6 && Set(turning.map(\.cells)).count == 6, "six different pictures: \(prop)")
            #expect(turning[0] == still, "it begins where it stands")
            for (before, after) in zip(turning, turning.dropFirst()) {
                let changed = before.cells.indices.filter { before.cells[$0] != after.cells[$0] }.count
                #expect(changed > 8, "the rungs move on")
                // Only the band changes: the line round it and the rim are where they were.
                #expect(before.cells.indices.allSatisfy { before.cells[$0] == after.cells[$0] || "NMB".contains(before.cells[$0]) || "NMB".contains(after.cells[$0]) })
            }
        }
        // A tenth of a turn a picture, six pictures to the sixth of the way round it repeats in: after six it is the first again.
        #expect(HamsterProps.wheel(turn: 6) == still)
    }

    @Test func theWheelPopsUpOutOfADustCloudSitsAndGoesTheWayItCameAndThenThereIsNothing() {
        let (appearing, going) = (HamsterProps.appearing, HamsterProps.going)
        let ink = appearing.frames.map(\.inkCount)
        #expect(ink[1] > 0 && ink[1] < ink[2] && ink[2] < ink[3], "it comes up: \(ink)")
        #expect(!appearing.loops && !going.loops)
        #expect(Array(going.frames.dropLast()) == appearing.frames.reversed(), "the way it came")
        #expect(going.frames.last?.inkCount == 0, "and then there is nothing")
        #expect(going.frames.count == 5 && appearing.frames.count == 4 && HamsterProps.still.frames.count == 1)
        #expect(appearing.frames[0].cells.contains("U") && !appearing.frames[3].cells.contains("U"), "dust first, then the wheel whole")
        #expect(appearing.frames[3].cells.contains("B"), "with sparks")
        // The last picture of it coming up is the wheel at its full size.
        let whole = appearing.frames[3]
        #expect(box(whole).height >= 24 && whole.cells.filter { $0 == "K" }.count == HamsterProps.still.frames[0].cells.filter { $0 == "K" }.count)
    }

    @Test func theSeedsAreSmallRimmedAndFewerAndFewer() {
        let (three, two, one) = (HamsterProps.seeds3.frames[0], HamsterProps.seeds2.frames[0], HamsterProps.seeds1.frames[0])
        #expect(three.inkCount > two.inkCount && two.inkCount > one.inkCount)
        for frame in [three, two, one] {
            #expect(frame.cells.contains("S") && frame.cells.contains("V") && frame.cells.contains("K") && frame.cells.contains("R"))
            #expect(frame.height <= 6 && frame.width <= 18)
        }
        #expect(three.width > two.width && two.width > one.width)
    }

    @Test func theLooksTheBrainHandsTheViewMatchTheArt() {
        for (prop, animation) in Self.props {
            #expect(animation.frames.count == prop.frameCount, "\(prop)")
            #expect(animation.fps == prop.fps && (animation.loops == prop.look.loops || prop.frameCount == 1), "\(prop)")
            #expect(HamsterProp(prop.look) == prop)
            let sizes = Set(animation.frames.map { "\($0.width)x\($0.height)" })
            #expect(sizes.count == 1, "one size to a strip: \(sizes)")
            #expect(prop.look.occupies == prop.isWheel, "a wheel is room that nobody else stops in, seeds are not")
            #expect(prop.look.animatesInPlace == (prop.turns || prop == .wheelAppearing || prop == .wheelGoing))
        }
        for pace in WheelPace.allCases { #expect(WheelPace(pace.move) == pace && pace.prop.look.fps == pace.prop.fps) }
        #expect(HamsterProp.wheelAppearing.passDuration == 4.0 / 6 && HamsterProp.wheelGoing.passDuration == 5.0 / 6)
        #expect(Set(HamsterProp.allCases.map(\.look.key)).count == HamsterProp.allCases.count)
        #expect(HamsterMove.allCases.map { HamsterMove($0.motion) } == HamsterMove.allCases)
    }

    // MARK: Strips and memory

    @Test func stripsAreMadeOnceForEveryMoveAndFacingHoweverOftenTheyAreAsked() {
        let sheets = HamsterSheets()
        for _ in 0..<5 { _ = sheets.strip(for: .scurry, facing: .right) }
        #expect(sheets.builds == 1)
        _ = sheets.strip(for: .scurry, facing: .left)
        #expect(sheets.builds == 2)
        let strip = sheets.strip(for: .scurry, facing: .right)
        #expect(strip.frameCount == 6 && (strip.frameWidth, strip.frameHeight) == (32, 24))
        _ = sheets.restingStrip()
        _ = sheets.restingStrip()
        _ = sheets.propStrip(.wheelSprint)
        _ = sheets.propStrip(.wheelSprint)
        #expect(sheets.builds == 4)
    }

    @Test func theWholeSheetFacingOneWayIsUnderAThirdOfAMegabyteAndBothWaysUnderTwoThirds() {
        let sheets = HamsterSheets()
        for move in HamsterMove.allCases { _ = sheets.strip(for: move, facing: .right) }
        for prop in HamsterProp.allCases { _ = sheets.propStrip(prop) }
        _ = sheets.restingStrip()
        #expect(sheets.bytes < 500_000, "\(sheets.bytes) bytes")
        for move in HamsterMove.allCases { _ = sheets.strip(for: move, facing: .left) }
        #expect(sheets.bytes < 900_000, "\(sheets.bytes) bytes")
    }
}
