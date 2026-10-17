import CoreGraphics
import Foundation
import Testing
@testable import PetModule

/// The capybara and what it plays with, as pictures.
@Suite struct CapybaraArtTests {
    static let moves = CapybaraMove.allCases.map { ($0, CapybaraArt.animation(for: $0)) }
    static let props = CapybaraProp.allCases.map { ($0, CapybaraProps.animation(for: $0)) }

    // MARK: Sizes

    @Test func everyFrameOfEveryMoveIsThirtyTwoByTwentyFourLikeTheCatsSoALaneTakesAnyMix() {
        for (move, animation) in Self.moves {
            for (index, frame) in animation.frames.enumerated() { #expect((frame.width, frame.height) == (32, 24), "\(move) frame \(index)") }
        }
        #expect((CapybaraArt.width, CapybaraArt.height) == (32, 24) && CatField.pictureSize == CGSize(width: 32, height: 24))
        for frame in CapybaraArt.restingFrames { #expect((frame.width, frame.height) == (32, 24)) }
    }

    @Test func everyMoveHasTheFramesTheBrainCountsOn() {
        for (move, animation) in Self.moves {
            #expect(animation.frames.count == move.frameCount, "\(move)")
            #expect(animation.fps == move.fps && animation.loops == move.loops && animation.advance == move.advance, "\(move)")
        }
        let asked: [CapybaraMove: Int] = [
            .walk: 6, .sit: 4, .blink: 1, .doze: 8, .hold: 2, .peel: 4, .chew: 4, .happy: 4, .sweat: 4, .turn: 3, .watch: 1, .turnBack: 3,
            .lie: 2, .sleep: 4, .lieDown: 4, .sitUp: 4, .sitDown: 4, .standUp: 4, .climbIn: 6, .climbOut: 6, .soak: 4, .soakOrange: 4,
            .soakHappy: 4,
        ]
        #expect(Set(asked.keys) == Set(CapybaraMove.allCases))
        for move in CapybaraMove.allCases { #expect(move.frameCount == asked[move], "\(move)") }
    }

    @Test func theMovesThatMoveHaveFramesThatDiffer() {
        let distinct: [CapybaraMove: Int] = [
            .walk: 6, .doze: 6, .happy: 4, .sweat: 4, .sleep: 3, .lieDown: 4, .sitDown: 4, .climbIn: 6, .peel: 4, .chew: 2, .turn: 3, .hold: 2,
            .soakHappy: 4, .soakOrange: 2,
        ]
        for (move, animation) in Self.moves where animation.frames.count > 1 {
            let count = Set(animation.frames.map(\.cells)).count
            #expect(count >= distinct[move] ?? 2, "\(move) is \(count) pictures")
        }
    }

    @Test func aCapybaraTakesItsTimeEverySlowMoveIsSlowAndItWalksSlowerThanTheCatTrots() {
        for (move, animation) in Self.moves { #expect(animation.fps <= 8, "\(move)") }
        for move in [CapybaraMove.sit, .lie, .sleep, .soak] { #expect(move.fps == 2, "a breath takes its time") }
        #expect(CapybaraMove.walk.speed == 8 && CapybaraMove.walk.speed < CatMove.walk.speed / 2)
        #expect(CapybaraMove.walk.advance == 1)
    }

    @Test func theHopIntoTheTubIsWholeStepsOfTheFramesItIsPlayedAt() {
        // Six frames in a second go four pixels each across the hop's span, so the hop ends where the tub is.
        let move = CapybaraMove.climbIn
        #expect(CapybaraMove.hopSpan == 24 && move.passDuration == 1)
        #expect((CapybaraMove.hopSpan / (move.passDuration * move.fps)).rounded() * 6 == CapybaraMove.hopSpan)
        #expect(CapybaraMove.climbOut.passDuration == move.passDuration)
    }

    // MARK: Colours

    static let everyLetter: Set<Character> = Set(
        (moves.flatMap(\.1.frames) + props.flatMap(\.1.frames) + CapybaraArt.restingFrames).flatMap(\.cells)
    ).subtracting(["."])

    @Test func everyColourTheArtUsesIsInThePaletteAndEveryColourOfThePaletteIsDrawnSomewhere() {
        for letter in Self.everyLetter { #expect(CapybaraArt.palette.isKnown(letter), "no \(letter)") }
        for letter in CapybaraArt.palette.colors.keys { #expect(Self.everyLetter.contains(letter), "\(letter) is never drawn") }
    }

    @Test func theRimIsLightAndTheLineInsideItIsDarkSoOneOfThemReadsOnAnyGround() {
        let grounds: [(name: String, colour: UInt32)] = [("black", 0x000000), ("dark glass", 0x2A2A30), ("light glass", 0xDCDCE0), ("white", 0xFFFFFF)]
        let (rim, line) = (CapybaraArt.palette.colors["R"]!, CapybaraArt.palette.colors["K"]!)
        for ground in grounds { #expect(max(contrast(rim, ground.colour), contrast(line, ground.colour)) >= 3, "on \(ground.name)") }
        #expect(contrast(rim, 0x000000) >= 10 && contrast(line, 0xFFFFFF) >= 10)
    }

    @Test func everyFrameHasALightRimAllRoundTheCapybaraAndNothingOfItTouchesTheAir() {
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
                #expect(rim > 25, "\(move) frame \(index) has a rim")
            }
        }
    }

    @Test func theEdgeOfTheCapybaraReadsAgainstEveryGroundInEveryFrame() {
        let palette = CapybaraArt.palette.colors
        for ground in [0x000000, 0x2A2A30, 0xDCDCE0, 0xFFFFFF] as [UInt32] {
            var weak: [String] = []
            for (move, animation) in Self.moves {
                for frame in animation.frames {
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
                    if pairs > 0, Double(readable) / Double(pairs) < 0.9 { weak.append("\(move)") }
                }
            }
            #expect(weak.isEmpty, "on \(String(ground, radix: 16)): \(Set(weak))")
        }
    }

    // MARK: The capybara

    func box(_ frame: PixelFrame) -> (width: Int, height: Int) {
        let ink = (0..<frame.height).flatMap { y in (0..<frame.width).compactMap { x in frame[x, y] == "." ? nil : (x, y) } }
        return (ink.map(\.0).max()! - ink.map(\.0).min()! + 1, ink.map(\.1).max()! - ink.map(\.1).min()! + 1)
    }

    @Test func itIsBigEnoughToMakeOutAndLongAndLowLikeACapybara() {
        for frame in CapybaraArt.animation(for: .walk).frames {
            let size = box(frame)
            #expect(size.width >= 26 && size.height >= 14 && size.height <= 20, "\(size)")
        }
        let sitting = box(CapybaraArt.animation(for: .sit).frames[0])
        #expect(sitting.width >= 26)
    }

    @Test func itIsBrownWithABluntSnoutAndAsmallEarAndFacesRightAndMirroredFacesLeft() throws {
        let head = CapybaraArt.head(.open)
        #expect(head.count == 10 && head.allSatisfy { $0.count == 11 })
        #expect(head.joined().contains("N") && head.joined().contains("P") && head.joined().filter { $0 == "E" }.count == 1)
        for face in [CapybaraArt.Face.open, .blink, .happy, .half, .sleep, .chewA, .chewB, .squint, .front] {
            let rows = CapybaraArt.head(face)
            #expect(rows.count == 10 && rows.allSatisfy { $0.count == 11 }, "\(face)")
        }
        let faces = [CapybaraArt.Face.open, .blink, .happy, .half, .chewB, .squint].map { CapybaraArt.head($0) }
        #expect(Set(faces).count == faces.count)
        let frame = CapybaraArt.animation(for: .walk).frames[0]
        func columns(_ frame: PixelFrame, _ letter: Character) -> [Int] { (0..<frame.width).filter { x in (0..<frame.height).contains { frame[x, $0] == letter } } }
        #expect(try #require(columns(frame, "N").min()) > 20, "the nostril is at the right")
        #expect(try #require(columns(frame.mirrored, "N").max()) < 11)
        let fur = CapybaraArt.palette.colors["O"]!
        #expect((fur >> 16) & 0xFF > (fur >> 8) & 0xFF && (fur >> 8) & 0xFF > fur & 0xFF, "brown: red over green over blue")
    }

    @Test func aCapybaraThatDoesNotMoveSitsWithItsEyesOpenAndThenShut() {
        #expect(CapybaraArt.restingFrames.count == 2)
        #expect(CapybaraArt.restingFrames[0] == CapybaraArt.animation(for: .sit).frames[0])
        #expect(CapybaraArt.restingFrames[1] == CapybaraArt.animation(for: .blink).frames[0] && CapybaraArt.restingFrames[0] != CapybaraArt.restingFrames[1])
    }

    @Test func goingDownAndGettingUpAreTheSamePicturesBothWaysAndMeetWhereTheMovesBegin() {
        func frames(_ move: CapybaraMove) -> [PixelFrame] { CapybaraArt.animation(for: move).frames }
        #expect(frames(.standUp) == frames(.sitDown).reversed() && frames(.sitUp) == frames(.lieDown).reversed())
        #expect(frames(.turnBack) == frames(.turn).reversed() && frames(.climbOut) == frames(.climbIn).reversed())
        #expect(frames(.sitDown).last == frames(.sit).first && frames(.sitDown).first == frames(.walk).first.map { _ in CapybaraArt.capybara() })
        #expect(frames(.lieDown).first == frames(.sit).first && frames(.lieDown).last == frames(.lie).first)
        #expect(frames(.turn).first == frames(.sit).first && frames(.watch) == [frames(.turn).last!])
        #expect(frames(.climbIn).last == CapybaraArt.sit(breath: 1))
    }

    @Test func theMovesThatSayWhatTheyAreAreDrawnWithWhatTheySayIt() {
        func uses(_ move: CapybaraMove, _ letter: Character) -> Bool { CapybaraArt.animation(for: move).frames.contains { $0.cells.contains(letter) } }
        #expect(uses(.sleep, "Z") && !uses(.sit, "Z"))
        #expect(uses(.happy, "H") && uses(.soakHappy, "H") && !uses(.walk, "H"))
        #expect(uses(.sweat, "S") && !uses(.doze, "S"))
        #expect(uses(.doze, "Q") && uses(.doze, "I"), "a bubble")
        #expect(uses(.hold, "G") && uses(.peel, "G") && uses(.soakOrange, "G") && !uses(.soak, "G"), "an orange")
    }

    // MARK: Dozing

    @Test func theBubbleGrowsAndBurstsAndTheHeadNodsDownAndComesUpWithAStart() {
        let frames = CapybaraArt.animation(for: .doze).frames
        func bubble(_ frame: PixelFrame) -> Int { frame.cells.filter { $0 == "Q" || $0 == "I" }.count }
        let sizes = frames.map(bubble)
        #expect(sizes[0] == 0 && sizes[1] > 0 && sizes[1] < sizes[2] && sizes[2] < sizes[3], "it grows: \(sizes)")
        #expect(sizes[4] > 0 && sizes[4] < sizes[3], "and bursts: \(sizes)")
        #expect(sizes[5...].allSatisfy { $0 == 0 }, "and is gone")
        func headTop(_ frame: PixelFrame) -> Int { (0..<frame.height).first { y in (14..<30).contains { ["K", "D"].contains(frame[$0, y]) } } ?? 0 }
        let tops = frames.map(headTop)
        #expect(tops[3] > tops[0], "the head nods down: \(tops)")
        #expect(tops[4] < tops[3], "and comes up with a start: \(tops)")
        #expect(frames.count == 8 && CapybaraMove.doze.fps == 3, "slowly")
    }

    // MARK: The back

    func topOfBack(_ frame: PixelFrame, columns: ClosedRange<Int>) -> Int? {
        (0..<frame.height).first { y in columns.contains { !["R", "."].contains(frame[$0, y]) } }
    }

    @Test func theTopOfTheBackIsAtTheSameRowSittingOrInTheTubWhateverItIsDoing() {
        // Frame rows are the board's plus one for the rim.
        let expected = CapybaraArt.backTop + 1
        for move in [CapybaraMove.sit, .blink, .soak, .soakOrange] {
            for frame in CapybaraArt.animation(for: move).frames {
                #expect(topOfBack(frame, columns: 6...15) == expected, "\(move)")
            }
        }
        #expect(CapybaraMove.sit.givesPerch && CapybaraMove.soak.givesPerch && !CapybaraMove.walk.givesPerch && !CapybaraMove.doze.givesPerch)
        #expect(CapybaraArt.perchShift == CapybaraMove.perchShift)
    }

    @Test func theCatOnItsBackStandsOnTheRimAboveItAndOverItsRump() {
        let cat = CatCoat.tabby.palette
        for frame in CatArt.perchFrames + CatArt.perchLoafFrames {
            let bottom = (0..<frame.height).last { y in (0..<frame.width).contains { frame[$0, y] != "." } }!
            #expect(bottom == CapybaraArt.backTop, "the rim of the cat is the rim of the capybara: row \(bottom)")
            let feet = (0..<frame.height).last { y in (0..<frame.width).contains { !["R", "."].contains(frame[$0, y]) } }!
            #expect(feet == CapybaraArt.backTop - 1, "the cat's own line is the row above it")
            for letter in Set(frame.cells).subtracting(["."]) { #expect(cat.isKnown(letter)) }
            // Every pixel of its feet has the capybara's back under it.
            let seat = Set((0..<frame.width).filter { !["R", "."].contains(frame[$0, feet]) })
            let back = CapybaraArt.animation(for: .sit).frames[0]
            for x in seat { #expect(back[x, CapybaraArt.backTop + 1] != ".", "nothing under the cat at \(x)") }
        }
    }

    @Test func theCatIsSmallerOnTheCapybarasBackThanOnTheGroundBecauseThereIsRoomForNoMore() {
        let sitting = CatArt.animation(for: .sit).frames[0]
        let (small, big) = (box(CatArt.perchFrames[0]), box(sitting))
        #expect(small.height == CapybaraArt.backTop + 1 && big.height >= 22, "\(small) against \(big)")
        // The strip is 26 points and the picture is drawn a point above its floor: nothing of the cat on the back goes over the top.
        #expect(CatActivity.stripHeight >= 24 + 1)
        for frame in CatArt.perchFrames + CatArt.perchLoafFrames + CatArt.hopOnFrames.suffix(3) {
            let top = (0..<frame.height).first { y in (0..<frame.width).contains { frame[$0, y] != "." } }!
            #expect(top >= 0, "\(top)")
        }
    }

    // MARK: The tub

    @Test func theTubComesUpOutOfTheFloorSitsRipplingAndGoesBackAndTheWayItGoesIsTheWayItCame() {
        let (appearing, going, rippling, empty) = (CapybaraProps.appearing, CapybaraProps.going, CapybaraProps.rippling, CapybaraProps.empty)
        let ink = appearing.frames.map(\.inkCount)
        #expect(ink[1] < ink[2] && ink[2] < ink[3] && ink[0] < ink[3], "it comes up: \(ink)")
        #expect(!appearing.loops && !going.loops && rippling.loops)
        #expect(Array(going.frames.dropLast()) == appearing.frames.reversed(), "the way it came")
        #expect(going.frames.last?.inkCount == 0, "and then there is nothing")
        #expect(going.frames.count == 5 && appearing.frames.count == 4 && rippling.frames.count == 4 && empty.frames.count == 1)
        #expect(Set(rippling.frames.map(\.cells)).count == 4, "the water moves")
        #expect(empty.frames[0] == CapybaraProps.tub(), "standing empty is the tub at its full size")
    }

    @Test func theWaterIsAtTheWaterLineAndTheCapybarasBackComesUpThroughItWithNoRimOverIt() {
        let water = CapybaraProps.waterLine
        for frame in CapybaraProps.rippling.frames {
            for x in 4...27 { #expect(frame[x, water] != "R", "a rim over the back at \(x)") }
            let band = (4...27).map { frame[$0, water + 1] }
            #expect(band.allSatisfy { $0 == "A" || $0 == "B" }, "water at the line: \(String(band))")
            #expect(frame.cells.contains("T") && frame.cells.contains("J"), "boards and hoops under it")
        }
        // Empty, the tub has its rim over the water like any picture.
        #expect((4...27).contains { CapybaraProps.empty.frames[0][$0, water] == "R" })
        // The back (sitting) is above the water line, and the body under it is behind the tub.
        #expect(CapybaraArt.backTop + 1 < water + 1)
        #expect(CapybaraArt.animation(for: .soak).frames[0].cells == CapybaraArt.sit().cells)
    }

    @Test func theTubIsAsWideAsTheCapybaraAndItsHeadAndBackAreAboveTheWater() {
        let rows = CapybaraProps.rippling.frames[0]
        let columns = (0..<rows.width).filter { x in (0..<rows.height).contains { rows[x, $0] != "." } }
        #expect(columns.count >= 26)
        let composite = CapybaraArt.animation(for: .soak).frames[0].drawing(rows, atX: 0, y: 0)
        // Above the water: fur and the head; at the line and below, none of the capybara's colours that are not the tub's.
        let aboveWater = (0...CapybaraProps.waterLine).flatMap { y in (0..<32).map { composite[$0, y] } }
        #expect(aboveWater.contains("O") && aboveWater.contains("E"))
        let below = (CapybaraProps.waterLine + 1..<23).flatMap { y in (3..<29).map { composite[$0, y] } }
        #expect(!below.contains("O") && !below.contains("W"), "the belly is behind the boards")
    }

    @Test func theOrangeAndThePeelAreSmallRimmedAndTheOneIsRoundWithALeaf() {
        let orange = CapybaraProps.orange.frames[0]
        #expect(orange.cells.contains("G") && orange.cells.contains("Y") && orange.cells.contains("K") && orange.cells.contains("R"))
        #expect((orange.width, orange.height) == (10, 10))
        for frame in CapybaraProps.peelGoing.frames { #expect((frame.width, frame.height) == (12, 8)) }
        #expect(CapybaraProps.peel.frames[0].cells.contains("F") && CapybaraProps.peelGoing.frames.last?.inkCount == 0)
        #expect(!CapybaraProps.peelGoing.loops)
    }

    @Test func theLooksTheBrainHandsTheViewMatchTheArt() {
        for (prop, animation) in Self.props {
            #expect(animation.frames.count == prop.frameCount, "\(prop)")
            #expect(animation.fps == prop.fps && animation.loops == prop.look.loops, "\(prop)")
            #expect(CapybaraProp(prop.look) == prop)
            let sizes = Set(animation.frames.map { "\($0.width)x\($0.height)" })
            #expect(sizes.count == 1, "one size to a strip: \(sizes)")
        }
        #expect(CapybaraProp.tubAppearing.passDuration == 4.0 / 6 && CapybaraProp.tubGoing.passDuration == 5.0 / 6)
        #expect(Set(CapybaraProp.allCases.map(\.look.key)).count == CapybaraProp.allCases.count)
    }

    // MARK: Strips and memory

    @Test func stripsAreMadeOnceForEveryMoveAndFacingHoweverOftenTheyAreAsked() {
        let sheets = CapybaraSheets()
        for _ in 0..<5 { _ = sheets.strip(for: .walk, facing: .right) }
        #expect(sheets.builds == 1)
        _ = sheets.strip(for: .walk, facing: .left)
        #expect(sheets.builds == 2)
        let strip = sheets.strip(for: .walk, facing: .right)
        #expect(strip.frameCount == 6 && (strip.frameWidth, strip.frameHeight) == (32, 24))
        _ = sheets.restingStrip()
        _ = sheets.restingStrip()
        _ = sheets.propStrip(.tubRippling)
        _ = sheets.propStrip(.tubRippling)
        #expect(sheets.builds == 4)
    }

    @Test func theWholeSheetFacingOneWayIsUnderHalfAMegabyteAndBothWaysUnderOne() {
        let sheets = CapybaraSheets()
        for move in CapybaraMove.allCases { _ = sheets.strip(for: move, facing: .right) }
        for prop in CapybaraProp.allCases { _ = sheets.propStrip(prop) }
        _ = sheets.restingStrip()
        #expect(sheets.bytes < 450_000, "\(sheets.bytes) bytes")
        for move in CapybaraMove.allCases { _ = sheets.strip(for: move, facing: .left) }
        #expect(sheets.bytes < 900_000, "\(sheets.bytes) bytes")
    }
}
