import CoreGraphics
import Foundation
import Testing
@testable import PetModule

/// The penguin and what it fishes in, as pictures.
@Suite struct PenguinArtTests {
    static let moves = PenguinMove.allCases.map { ($0, PenguinArt.animation(for: $0)) }
    static let props = PenguinProp.allCases.map { ($0, PenguinProps.animation(for: $0)) }

    func frames(_ move: PenguinMove) -> [PixelFrame] { PenguinArt.animation(for: move).frames }

    // MARK: Sizes

    @Test func everyFrameOfEveryMoveAndEveryPropIsThirtyTwoByTwentyFourLikeTheCatsSoALaneTakesAnyMix() {
        for (move, animation) in Self.moves {
            for (index, frame) in animation.frames.enumerated() { #expect((frame.width, frame.height) == (32, 24), "\(move) frame \(index)") }
        }
        for (prop, animation) in Self.props {
            for (index, frame) in animation.frames.enumerated() { #expect((frame.width, frame.height) == (32, 24), "\(prop) frame \(index)") }
        }
        #expect((PenguinArt.width, PenguinArt.height) == (32, 24) && CatField.pictureSize == CGSize(width: 32, height: 24))
        for frame in PenguinArt.restingFrames { #expect((frame.width, frame.height) == (32, 24)) }
    }

    @Test func everyMoveHasTheFramesTheBrainCountsOn() {
        for (move, animation) in Self.moves {
            #expect(animation.frames.count == move.frameCount, "\(move)")
            #expect(animation.fps == move.fps && animation.loops == move.loops && animation.advance == move.advance, "\(move)")
        }
        let asked: [PenguinMove: Int] = [
            .stand: 4, .blink: 1, .flap: 6, .waddle: 6, .lookTurn: 3, .lookFlap: 6, .lookBack: 3, .happy: 6, .getUp: 4, .untuck: 3, .reel: 4,
            .bellyDown: 3, .slide: 4, .lie: 2, .slip: 5, .dazed: 4, .tuck: 3, .tucked: 2, .sleep: 4, .cast: 4, .fish: 4, .bite: 2, .pull: 5,
            .gulp: 5, .fishHappy: 6,
        ]
        #expect(Set(asked.keys) == Set(PenguinMove.allCases))
        for move in PenguinMove.allCases { #expect(move.frameCount == asked[move], "\(move)") }
    }

    @Test func theMovesThatMoveHaveFramesThatDiffer() {
        let distinct: [PenguinMove: Int] = [
            .waddle: 6, .flap: 6, .lookFlap: 4, .happy: 6, .getUp: 4, .bellyDown: 3, .slide: 4, .slip: 5, .dazed: 4, .tuck: 3, .sleep: 4, .cast: 4,
            .fish: 3, .pull: 5, .gulp: 5, .fishHappy: 6, .stand: 2, .lookTurn: 3,
        ]
        for (move, animation) in Self.moves where animation.frames.count > 1 {
            let count = Set(animation.frames.map(\.cells)).count
            #expect(count >= distinct[move] ?? 2, "\(move) is \(count) pictures")
        }
    }

    @Test func theSlideIsTheQuickestThingItDoesInStepsSmallEnoughForAWalkToEndWhereItWasSentAndNothingElseIsInAHurry() {
        #expect(PenguinMove.slide.advance <= CatField.leastEndError && PenguinMove.waddle.advance <= CatField.leastEndError)
        #expect(PenguinMove.slide.speed > PenguinMove.waddle.speed * 2 && PenguinMove.slide.speed == 48)
        // The busiest waddle is still no more than half the slide.
        #expect(PenguinMove.waddle.speed * (1 + PenguinMove.busyBoost) <= PenguinMove.slide.speed / 2)
        for (move, animation) in Self.moves {
            #expect(animation.fps <= Double(CatSpriteView.frameRateCeiling), "\(move)")
            if move != .slide { #expect(animation.fps <= 10, "\(move) is not in a hurry") }
            #expect(move == .slide || move == .waddle || move.advance == 0, "\(move) goes nowhere")
        }
        #expect(PenguinMove.waddle.fps * (1 + PenguinMove.busyBoost) <= 12, "its quickest waddle is a clumsy one")
    }

    // MARK: Colours

    static let everyLetter: Set<Character> = Set(
        (moves.flatMap(\.1.frames) + props.flatMap(\.1.frames) + PenguinArt.restingFrames).flatMap(\.cells)
    ).subtracting(["."])

    @Test func everyColourTheArtUsesIsInThePaletteAndEveryColourOfThePaletteIsDrawnSomewhere() {
        for letter in Self.everyLetter { #expect(PenguinArt.palette.isKnown(letter), "no \(letter)") }
        for letter in PenguinArt.palette.colors.keys { #expect(Self.everyLetter.contains(letter), "\(letter) is never drawn") }
    }

    @Test func theRimIsLightAndTheLineInsideItIsDarkSoOneOfThemReadsOnAnyGround() {
        let grounds: [(name: String, colour: UInt32)] = [("black", 0x000000), ("dark glass", 0x2A2A30), ("light glass", 0xDCDCE0), ("white", 0xFFFFFF)]
        let (rim, line) = (PenguinArt.palette.colors["R"]!, PenguinArt.palette.colors["K"]!)
        for ground in grounds { #expect(max(contrast(rim, ground.colour), contrast(line, ground.colour)) >= 3, "on \(ground.name)") }
        #expect(contrast(rim, 0x000000) >= 10 && contrast(line, 0xFFFFFF) >= 10)
    }

    @Test func theRodAndItsLineAreAMiddlingColourThatReadsOnDarkAndLightGlassForTheyHaveNoRimOfTheirOwn() {
        for letter: Character in ["J", "L"] {
            let colour = PenguinArt.palette.colors[letter]!
            #expect(contrast(colour, 0x2A2A30) >= 3 && contrast(colour, 0xDCDCE0) >= 3, "\(letter)")
        }
    }

    /// The letters that are drawn over the rim, a pixel wide: a rim round them would make them three.
    static let overTheRim: Set<Character> = ["J", "L", "T"]

    @Test func everyFrameOfThePenguinHasALightRimAllRoundItAndNothingOfItTouchesTheAirButWhatIsDrawnOverTheRim() {
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

    @Test func theEdgeOfThePenguinAndOfTheHoleReadsAgainstEveryGroundInEveryFrame() {
        let palette = PenguinArt.palette.colors
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

    // MARK: The penguin

    func box(_ frame: PixelFrame, ignoring letters: Set<Character> = ["R"]) -> (left: Int, right: Int, top: Int, bottom: Int) {
        let ink = (0..<frame.height).flatMap { y in (0..<frame.width).compactMap { x in frame[x, y] == "." || letters.contains(frame[x, y]) ? nil : (x, y) } }
        return (ink.map(\.0).min()!, ink.map(\.0).max()!, ink.map(\.1).min()!, ink.map(\.1).max()!)
    }

    func size(_ frame: PixelFrame) -> (width: Int, height: Int) {
        let b = box(frame, ignoring: ["T"])
        return (b.right - b.left + 1, b.bottom - b.top + 1)
    }

    @Test func itIsTallBlackAndWhiteWithAnOrangeBeakAndFeetFacesRightAndMirroredFacesLeft() throws {
        let standing = size(frames(.stand)[0]), lying = size(frames(.lie)[0]), cat = size(CatArt.animation(for: .sit).frames[0])
        // As tall as the cat sits and taller than it is wide; lying on its belly, long and low like the capybara.
        #expect(standing.height + 2 >= standing.width && standing.height >= 17 && standing.height <= 22, "\(standing)")
        #expect(lying.width > lying.height * 2 && lying.width <= 30 && lying.height <= 12, "\(lying)")
        #expect(abs(standing.height - cat.height) <= 6, "the cat's scale: \(standing) against \(cat)")
        let cells = frames(.stand)[0].cells
        for letter: Character in ["N", "W", "O", "o", "E", "K", "R"] { #expect(cells.contains(letter), "\(letter)") }
        func columns(_ frame: PixelFrame, _ letter: Character) -> [Int] { (0..<frame.width).filter { x in (0..<frame.height).contains { frame[x, $0] == letter } } }
        let stand = frames(.stand)[0]
        #expect(try #require(columns(stand, "O").max()) > 20, "the beak is out at the right")
        #expect(try #require(columns(stand.mirrored, "O").min()) < 12)
        #expect(try #require(columns(stand, "E").min()) > 14, "the eye is in the head, at the right")
        func channels(_ letter: Character) -> (r: UInt32, g: UInt32, b: UInt32) {
            let colour = PenguinArt.palette.colors[letter]!
            return ((colour >> 16) & 0xFF, (colour >> 8) & 0xFF, colour & 0xFF)
        }
        let (black, white, orange) = (channels("N"), channels("W"), channels("O"))
        #expect(black.r < 0x60 && black.g < 0x60 && black.b < 0x70, "black, or as near it as a slate that the line round it shows against")
        #expect(white.r > 0xEE && white.g > 0xEE && white.b > 0xEE, "white")
        #expect(orange.r > 0xE0 && orange.g > 0x70 && orange.g < 0xB0 && orange.b < 0x40, "orange")
        #expect(cells.filter { $0 == "W" }.count >= 14, "a belly you can see")
        #expect(cells.filter { $0 == "O" }.count + cells.filter { $0 == "o" }.count >= 10, "a beak and feet you can see")
    }

    @Test func itStandsInTheMiddleOfItsFrameSoTheMirrorImageStandsInTheMiddleToo() {
        for move in [PenguinMove.stand, .waddle, .flap, .tucked, .lookFlap, .happy, .lie, .slide] {
            for frame in frames(move) {
                let ink = box(frame, ignoring: ["R", "J", "L", "T", "S"])
                let centre = Double(ink.left + ink.right) / 2
                #expect(abs(centre - 15.5) < 4.5, "\(move): centred at \(centre)")
            }
        }
    }

    @Test func aPenguinThatDoesNotMoveStandsWithItsEyesOpenAndThenShut() {
        #expect(PenguinArt.restingFrames.count == 2)
        #expect(PenguinArt.restingFrames[0] == frames(.stand)[0])
        #expect(PenguinArt.restingFrames[1] == frames(.blink)[0] && PenguinArt.restingFrames[0] != PenguinArt.restingFrames[1])
    }

    @Test func gettingUpTurningTuckingAndTakingTheLineInAreTheSamePicturesAsTheOtherWayAndMeetWhereTheMovesBegin() {
        #expect(frames(.lookBack) == frames(.lookTurn).reversed() && frames(.untuck) == frames(.tuck).reversed() && frames(.reel) == frames(.cast).reversed())
        // Getting up ends standing as it stands; lying down ends flat as it lies; it turns to face the viewer and is flapping facing it.
        #expect(frames(.getUp).last == frames(.stand).first)
        #expect(frames(.lookTurn).last == frames(.lookFlap).first)
        #expect(frames(.cast).last == frames(.fish).first)
        let flat = size(frames(.lie).first!)
        for (name, frame) in [("lying down ends", frames(.bellyDown).last!), ("getting up begins", frames(.getUp).first!)] {
            #expect(abs(size(frame).width - flat.width) <= 1 && abs(size(frame).height - flat.height) <= 3, "\(name) flat: \(size(frame)) against \(flat)")
        }
        #expect(box(frames(.slip).last!).bottom >= 20)
        #expect(frames(.tuck).last!.cells.filter { $0 == "E" }.isEmpty && frames(.sleep).allSatisfy { !$0.cells.contains("E") }, "no eye shows when it is tucked in")
        // The stance it ends the move in is the one the next move begins in: from standing, lying, tucked, fishing.
        for move in PenguinMove.allCases { #expect([PenguinMove.Stance.standing, .lying, .tucked, .fishing].contains(move.stance)) }
    }

    @Test func theMovesThatSayWhatTheyAreAreDrawnWithWhatTheySayItAndTheOthersAreNot() {
        func uses(_ move: PenguinMove, _ letter: Character) -> Bool { frames(move).contains { $0.cells.contains(letter) } }
        #expect(uses(.sleep, "Z") && !uses(.tucked, "Z") && !uses(.stand, "Z"))
        #expect(uses(.happy, "H") && !uses(.lookFlap, "H") && !uses(.fishHappy, "H") && !uses(.flap, "H"))
        #expect(uses(.dazed, "S") && !uses(.lie, "S") && !uses(.slip, "S"))
        #expect(uses(.slide, "T") && uses(.bellyDown, "T") && !uses(.waddle, "T") && !uses(.lie, "T"), "snow where it kicks it up")
        for move in [PenguinMove.cast, .fish, .bite, .pull, .gulp, .fishHappy, .reel] { #expect(uses(move, "J"), "a rod in \(move)") }
        for move in [PenguinMove.stand, .waddle, .slide, .lookFlap, .tucked, .sleep, .flap, .happy] { #expect(!uses(move, "J") && !uses(move, "L"), "no rod in \(move)") }
        for move in [PenguinMove.fish, .bite, .fishHappy, .pull] { #expect(uses(move, "L"), "a line in \(move)") }
        #expect(uses(.pull, "F") && uses(.pull, "f") && uses(.gulp, "F") && !uses(.fish, "F") && !uses(.stand, "F"), "a fish only when it has caught one")
    }

    @Test func theRodsLineComesDownInTheMiddleOfTheHoleThatIsHoleReachAlongAndTheHoleHasNothingWhereThePenguinIs() throws {
        let hole = PenguinProps.still.frames[0]
        let across = (0..<32).filter { x in (0..<24).contains { hole[x, $0] != "." } }
        let middle = Double(try #require(across.min()) + (try #require(across.max()))) / 2
        let reach = Int(PenguinMove.holeReach)
        for move in [PenguinMove.fish, .bite, .fishHappy] {
            for frame in frames(move) {
                let lineColumns = (0..<32).filter { x in (0..<24).contains { frame[x, $0] == "L" } }
                #expect(lineColumns.count == 1, "one line: \(lineColumns)")
                // The hole's middle on the penguin's frame is the hole picture's, a hole's reach along.
                #expect(Double(try #require(lineColumns.first)) == middle + Double(reach), "\(move): line at \(lineColumns), hole at \(middle) + \(reach)")
                let low = (0..<24).filter { frame[lineColumns[0], $0] == "L" }.max()!
                #expect(low >= 16, "it goes down to the hole")
            }
        }
        // The hole is drawn over the penguin, and is not on top of it: nothing of the hole is where the penguin's own body is, in any picture it
        // is fished in (a fish that comes up out of it is, which is the idea).
        var overlaps: Set<String> = []
        for move in [PenguinMove.cast, .fish, .bite, .pull, .gulp, .fishHappy, .reel, .stand, .blink] {
            for (index, frame) in frames(move).enumerated() {
                for (prop, animation) in Self.props {
                    for holeFrame in animation.frames {
                        for y in 16..<24 {
                            for x in 0..<32 where holeFrame[x, y] != "." && holeFrame[x, y] != "R" && x + reach < 32 {
                                let there = frame[x + reach, y]
                                if "NnWwOoE".contains(there) { overlaps.insert("\(move) frame \(index) \(there) at \(x + reach), \(y) under \(prop)") }
                            }
                        }
                    }
                }
            }
        }
        #expect(overlaps.isEmpty, "\(overlaps.sorted().prefix(12))")
    }

    // MARK: The hole

    @Test func theHoleCracksOpenStaysAndRipplesIsStirredAndSplashesAndClosesTheWayItOpenedAndThenThereIsNothing() {
        let (opening, closing) = (PenguinProps.opening, PenguinProps.closing)
        let ink = opening.frames.map(\.inkCount)
        #expect(ink[0] > 0 && ink[0] < ink[1] && ink[1] < ink[2] && ink[2] <= ink[3] + 8, "it opens: \(ink)")
        #expect(!opening.loops && !closing.loops && !PenguinProps.splashing.loops && PenguinProps.rippling.loops && PenguinProps.churning.loops)
        #expect(Array(closing.frames.dropLast()) == opening.frames.reversed(), "the way it opened")
        #expect(closing.frames.last?.inkCount == 0, "and then there is nothing")
        #expect(closing.frames.count == 5 && opening.frames.count == 4 && PenguinProps.still.frames.count == 1)
        #expect(PenguinProps.still.frames[0].cells.contains("A") && PenguinProps.still.frames[0].cells.contains("I"), "ice and water")
        #expect(PenguinProps.rippling.frames[0].cells.contains("a"), "light on the water")
        #expect(Set(PenguinProps.rippling.frames.map(\.cells)).count == 3 && Set(PenguinProps.churning.frames.map(\.cells)).count == 2)
        #expect(Set(PenguinProps.splashing.frames.map(\.cells)).count == 4)
        // Stirred up and splashing are more than the ripples are: drops over the hole.
        func top(_ frame: PixelFrame) -> Int { (0..<24).first { y in (0..<32).contains { frame[$0, y] != "." } }! }
        #expect(PenguinProps.splashing.frames.map(top).min()! < top(PenguinProps.rippling.frames[0]) - 3, "drops go up")
        #expect(PenguinProps.churning.frames.map(top).min()! < top(PenguinProps.rippling.frames[0]))
    }

    @Test func theHoleIsFlatOnTheFloorAndTheLowestThingInThePicture() {
        for frame in PenguinProps.still.frames + PenguinProps.rippling.frames {
            let b = box(frame)
            #expect(b.bottom >= 21 && b.top >= 15, "a flat oval on the floor: rows \(b.top) to \(b.bottom)")
            #expect(b.right - b.left >= 12 && b.right - b.left <= 18)
        }
    }

    @Test func theLooksTheBrainHandsTheViewMatchTheArt() {
        for (prop, animation) in Self.props {
            #expect(animation.frames.count == prop.frameCount, "\(prop)")
            #expect(animation.fps == prop.fps && animation.loops == prop.look.loops, "\(prop)")
            #expect(PenguinProp(prop.look) == prop)
            #expect(Set(animation.frames.map { "\($0.width)x\($0.height)" }).count == 1)
            #expect(prop.look.occupies, "a hole in the ice is room that nobody else stops in")
            #expect(prop.look.animatesInPlace == (prop != .holeStill) && prop.look.rise == 0 && !prop.look.flutters)
        }
        #expect(PenguinProp.holeOpening.passDuration == 4.0 / 6 && PenguinProp.holeClosing.passDuration == 5.0 / 6)
        #expect(Set(PenguinProp.allCases.map(\.look.key)).count == PenguinProp.allCases.count)
        #expect(PenguinMove.allCases.map { PenguinMove($0.motion) } == PenguinMove.allCases)
        #expect(PenguinMove.allCases.map(\.motion.key) == Array(0..<PenguinMove.allCases.count))
    }

    // MARK: Strips and memory

    @Test func stripsAreMadeOnceForEveryMoveAndFacingHoweverOftenTheyAreAsked() {
        let sheets = PenguinSheets()
        for _ in 0..<5 { _ = sheets.strip(for: .waddle, facing: .right) }
        #expect(sheets.builds == 1)
        _ = sheets.strip(for: .waddle, facing: .left)
        #expect(sheets.builds == 2)
        let strip = sheets.strip(for: .waddle, facing: .right)
        #expect(strip.frameCount == 6 && (strip.frameWidth, strip.frameHeight) == (32, 24))
        _ = sheets.restingStrip()
        _ = sheets.restingStrip()
        _ = sheets.propStrip(.holeSplashing)
        _ = sheets.propStrip(.holeSplashing)
        #expect(sheets.builds == 4)
    }

    @Test func theWholeSheetFacingOneWayIsUnderAMegabyteAndBothWaysUnderTwo() {
        let sheets = PenguinSheets()
        for move in PenguinMove.allCases { _ = sheets.strip(for: move, facing: .right) }
        for prop in PenguinProp.allCases { _ = sheets.propStrip(prop) }
        _ = sheets.restingStrip()
        #expect(sheets.bytes < 1_000_000, "\(sheets.bytes) bytes")
        for move in PenguinMove.allCases { _ = sheets.strip(for: move, facing: .left) }
        #expect(sheets.bytes < 1_800_000, "\(sheets.bytes) bytes")
    }
}
