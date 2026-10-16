import CoreGraphics
import Foundation
import Testing
@testable import PetModule

/// How a colour reads against another, as the web's accessibility guidelines count it (1 for the same, 21 for black on white).
func contrast(_ first: UInt32, _ second: UInt32) -> Double {
    func luminance(_ rgb: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((rgb >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
    let (high, low) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
    return (high + 0.05) / (low + 0.05)
}

@Suite struct CatArtTests {
    static let moves = CatMove.allCases.map { ($0, CatArt.animation(for: $0)) }

    @Test func everyFrameOfEveryMoveIsThirtyTwoByTwentyFour() {
        for (move, animation) in Self.moves {
            for (index, frame) in animation.frames.enumerated() {
                #expect((frame.width, frame.height) == (32, 24), "\(move) frame \(index)")
            }
        }
        #expect((CatArt.width, CatArt.height) == (32, 24))
    }

    @Test func everyMoveHasTheFramesTheBrainCountsOn() {
        for (move, animation) in Self.moves {
            #expect(animation.frames.count == move.frameCount, "\(move)")
            #expect(animation.fps == move.fps)
            #expect(animation.loops == move.loops)
            #expect(animation.advance == move.advance)
        }
    }

    @Test func theMovesHaveTheFramesTheyWereAskedFor() {
        let asked: [CatMove: Int] = [
            .walk: 8, .trot: 6, .sitDown: 4, .standUp: 4, .lieDown: 4, .stretch: 6, .groom: 6, .scratch: 6, .tailSwish: 6, .lookLeft: 1,
            .lookRight: 1, .lookUp: 1, .pounce: 8, .chase: 6, .yarn: 6, .peek: 4, .yawn: 4, .sleep: 4, .startled: 4, .purr: 4, .dance: 6,
            .frantic: 6, .loaf: 2, .sit: 4, .blink: 1,
        ]
        for move in CatMove.allCases { #expect(Self.moves.first { $0.0 == move }?.1.frames.count == asked[move], "\(move)") }
        #expect(Self.moves.reduce(0) { $0 + $1.1.frames.count } >= 110)
        #expect(PropArt.moth.frames.count == 2 && PropArt.yarn.frames.count == 4)
    }

    @Test func noMoveIsPlayedFasterThanTwelveFramesASecondAtItsOwnPaceAndTheSlowOnesSlower() {
        for (move, animation) in Self.moves { #expect(animation.fps <= 12, "\(move)") }
        for move in [CatMove.walk, .trot, .chase, .frantic] { #expect(move.fps == 12) }
        for move in [CatMove.sit, .sleep, .loaf] { #expect(move.fps == 2, "a breath takes its time") }
    }

    @Test func theCatMovesAtThePaceOfItsStride() {
        // A cat that goes two points in a frame of a walk at 12 frames a second goes 24 points a second.
        #expect(CatMove.walk.speed == 24 && CatMove.trot.speed == 48 && CatMove.chase.speed == 60 && CatMove.frantic.speed == 72)
    }

    // MARK: Colours

    static let everyLetter: Set<Character> = Set(moves.flatMap { $0.1.frames.flatMap(\.cells) }).union(
        (PropArt.moth.frames + PropArt.yarn.frames).flatMap(\.cells)
    ).subtracting(["."])

    @Test func everyColourTheArtUsesIsInEveryCoatsPalette() {
        for coat in CatCoat.allCases {
            for letter in Self.everyLetter { #expect(coat.palette.isKnown(letter), "\(coat) has no \(letter)") }
        }
    }

    @Test func everyColourOfThePaletteIsDrawnSomewhere() {
        for letter in CatCoat.tabby.palette.colors.keys { #expect(Self.everyLetter.contains(letter), "\(letter) is never drawn") }
    }

    @Test func theCoatsAreThreeAndNamedInVietnamese() {
        #expect(CatCoat.allCases == [.tabby, .tuxedo, .grey])
        #expect(CatCoat.allCases.map(\.displayName) == ["Mèo vàng", "Mèo đen trắng", "Mèo xám"])
        #expect(Set(CatCoat.allCases.map { $0.palette.colors["O"] }).count == 3, "three different coats")
    }

    // MARK: A cat at a glance

    @Test func everyFrameHasALightRimAllRoundTheCatAndNothingElseTouchesTheGround() {
        for (move, animation) in Self.moves {
            for (index, frame) in animation.frames.enumerated() {
                var rim = 0
                for y in 0..<frame.height {
                    for x in 0..<frame.width where frame[x, y] != "." {
                        if frame[x, y] == "R" { rim += 1 }
                        guard frame[x, y] != "R", frame[x, y] != "V" else { continue }
                        // A pixel of the cat itself (or what floats by it) never touches clear air: the rim is between.
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

    @Test func theRimIsLightAndTheLineInsideItIsDarkSoOneOfThemReadsOnAnyGround() {
        let grounds: [(name: String, colour: UInt32)] = [
            ("black", 0x000000), ("dark glass", 0x2A2A30), ("light glass", 0xDCDCE0), ("white", 0xFFFFFF),
        ]
        for coat in CatCoat.allCases {
            let colours = coat.palette.colors
            let (rim, line) = (colours["R"]!, colours["K"]!)
            for ground in grounds {
                let best = max(contrast(rim, ground.colour), contrast(line, ground.colour))
                #expect(best >= 3, "\(coat) on \(ground.name): \(best)")
            }
            #expect(contrast(rim, 0x000000) >= 10, "\(coat)'s rim on black")
            #expect(contrast(line, 0xFFFFFF) >= 10, "\(coat)'s line on white")
        }
    }

    @Test func theEdgeOfTheCatReadsAgainstEveryGroundInEveryFrame() {
        let grounds: [UInt32] = [0x000000, 0x2A2A30, 0xDCDCE0, 0xFFFFFF]
        for coat in CatCoat.allCases {
            for ground in grounds {
                var weak: [String] = []
                for (move, animation) in Self.moves {
                    for frame in animation.frames {
                        // Where the rim meets the cat: a pair of pixels of which one has to stand out from the ground.
                        var pairs = 0
                        var readable = 0
                        for y in 0..<frame.height {
                            // A head that peeks is cut by the strip's edge, which is not an edge of the cat.
                            for x in 0..<frame.width where frame[x, y] == "R" && !(move == .peek && y == frame.height - 1) {
                                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where (0..<frame.width).contains(x + dx) && (0..<frame.height).contains(y + dy) {
                                    let inner = frame[x + dx, y + dy]
                                    guard inner != ".", inner != "R", inner != "V", let colour = coat.palette.colors[inner] else { continue }
                                    pairs += 1
                                    if max(contrast(coat.palette.colors["R"]!, ground), contrast(colour, ground)) >= 3 { readable += 1 }
                                }
                            }
                        }
                        if pairs > 0, Double(readable) / Double(pairs) < 0.9 { weak.append("\(move)") }
                    }
                }
                #expect(weak.isEmpty, "\(coat) on \(String(ground, radix: 16)): \(Set(weak))")
            }
        }
    }

    @Test func theCatIsBigEnoughToMakeOutAndTheTuxedoHasAWhiteChest() {
        func box(_ frame: PixelFrame) -> (width: Int, height: Int) {
            let ink = (0..<frame.height).flatMap { y in (0..<frame.width).compactMap { x in frame[x, y] == "." ? nil : (x, y) } }
            let xs = ink.map(\.0), ys = ink.map(\.1)
            return (xs.max()! - xs.min()! + 1, ys.max()! - ys.min()! + 1)
        }
        #expect(box(CatArt.animation(for: .sit).frames[0]).height >= 22)
        #expect(box(CatArt.animation(for: .sit).frames[0]).width >= 26, "whiskers and tail count")
        for frame in CatArt.animation(for: .walk).frames { #expect(box(frame).width >= 28) }
        #expect(CatArt.animation(for: .sit).frames[0].cells.filter { $0 == "W" }.count >= 20, "a white chest, paws and muzzle")
    }

    @Test func theHeadHasEarsWithPinkInEyesWithAShineAndWhiskers() {
        let open = CatArt.head(.open)
        #expect(open.joined().filter { $0 == "P" }.count >= 12, "pink ears and a nose")
        #expect(open.joined().filter { $0 == "L" }.count == 2, "a shine in each eye")
        #expect(open.allSatisfy { $0.count == 13 } && open.count == 11)
        for face in [CatArt.Face.open, .blink, .happy, .yawn, .wide, .lookLeft, .lookRight, .lookUp, .sleep, .squint] {
            let rows = CatArt.head(face)
            #expect(rows.count == 11 && rows.allSatisfy { $0.count == 13 }, "\(face)")
        }
        // Whiskers are drawn after the rim, on both sides of a head that faces the viewer.
        let sit = CatArt.animation(for: .sit).frames[0]
        let (left, right) = ((0..<12).flatMap { x in (0..<24).filter { sit[x, $0] == "V" } }, (20..<32).flatMap { x in (0..<24).filter { sit[x, $0] == "V" } })
        #expect(left.count >= 4 && right.count >= 4)
    }

    @Test func theFacesAreEachOtherAndNotTheSame() {
        let faces = [CatArt.Face.open, .blink, .happy, .yawn, .wide, .lookLeft, .lookRight, .lookUp].map { CatArt.head($0) }
        #expect(Set(faces).count == faces.count)
        // A look to the left has the eyes to the left of where they are in front, and the other way for the right.
        func eyes(_ rows: [String]) -> [Int] { rows[6].enumerated().filter { $0.element == "E" }.map(\.offset) }
        #expect(eyes(CatArt.head(.lookLeft)).min()! < eyes(CatArt.head(.open)).min()!)
        #expect(eyes(CatArt.head(.lookRight)).max()! > eyes(CatArt.head(.open)).max()!)
    }

    // MARK: Moves

    @Test func theMovesThatMoveHaveFramesThatDiffer() {
        let distinct: [CatMove: Int] = [
            .walk: 8, .trot: 6, .frantic: 6, .chase: 6, .pounce: 8, .stretch: 6, .groom: 6, .scratch: 6, .tailSwish: 6, .dance: 6, .purr: 4,
            .sleep: 4, .yawn: 4, .lieDown: 4, .sitDown: 4, .standUp: 4, .yarn: 5, .peek: 4, .startled: 4,
        ]
        for (move, animation) in Self.moves {
            #expect(Set(animation.frames.map(\.cells)).count >= distinct[move] ?? 1, "\(move) is \(Set(animation.frames.map(\.cells)).count) pictures")
            if animation.frames.count > 1 { #expect(Set(animation.frames.map(\.cells)).count > 1, "\(move) moves") }
        }
    }

    @Test func sittingDownAndGettingUpAreTheSamePicturesBothWays() {
        #expect(CatArt.animation(for: .standUp).frames == CatArt.animation(for: .sitDown).frames.reversed())
        // Down ends sitting facing the viewer, which is where the sit begins; up begins there.
        #expect(CatArt.animation(for: .sitDown).frames.last == CatArt.animation(for: .sit).frames.first)
        #expect(CatArt.animation(for: .standUp).frames.first == CatArt.animation(for: .sit).frames.first)
    }

    @Test func theMovesThatSayWhatTheyAreAreDrawnWithWhatTheySayIt() {
        func uses(_ move: CatMove, _ letter: Character) -> Bool { CatArt.animation(for: move).frames.contains { $0.cells.contains(letter) } }
        #expect(uses(.sleep, "Z") && !uses(.sit, "Z"))
        #expect(uses(.purr, "H") && !uses(.walk, "H"))
        #expect(uses(.dance, "N"))
        #expect(uses(.frantic, "S") && !uses(.chase, "S"), "a sweat drop for the frantic run only")
        #expect(uses(.startled, "B"), "a bang")
    }

    func topOfCat(_ frame: PixelFrame) -> Int? {
        (0..<frame.height).first { y in (0..<frame.width).contains { ["K", "O", "D", "W", "P", "E"].contains(frame[$0, y]) } }
    }

    @Test func theStartledCatLeavesTheGroundAtTheTopOfItsJumpAndComesDown() throws {
        let frames = CatArt.animation(for: .startled).frames
        let tops = frames.compactMap(topOfCat)
        #expect(tops.count == 4)
        #expect(tops[2] <= tops[0] - 3, "the top of the jump is three rows above the crouch")
        #expect(tops[3] > tops[2], "and it comes down")
    }

    @Test func aPeekComesUpFromBelowTheEdge() throws {
        let frames = CatArt.animation(for: .peek).frames
        let tops = try #require(Optional(frames.compactMap(topOfCat)))
        #expect(tops == tops.sorted(by: >), "each frame shows more than the last")
        #expect(tops[0] >= 19, "first only the ears")
        // Cut off by the edge: the last row of the cat's own picture (the one above the rim) is head, from the second frame on, and the
        // rim's own row is under it, to be cut off by the strip.
        for frame in frames.dropFirst() {
            #expect((0..<frame.width).contains { ["O", "K", "P", "D"].contains(frame[$0, frame.height - 2]) }, "the head reaches the edge")
        }
        #expect((0..<32).contains { ["K", "P"].contains(frames[0][$0, frames[0].height - 2]) }, "even the ears")
    }

    @Test func theCatFacesRightAndMirroredFacesLeft() throws {
        let frame = CatArt.animation(for: .walk).frames[0]
        // The tail is at the left of the picture and the head at the right; the mirror image has them the other way.
        func columns(_ frame: PixelFrame, _ letter: Character) -> [Int] {
            (0..<frame.width).filter { x in (0..<frame.height).contains { frame[x, $0] == letter } }
        }
        #expect(try #require(columns(frame, "E").min()) > 14)
        #expect(try #require(columns(frame.mirrored, "E").max()) < 17)
    }

    @Test func aCatThatDoesNotMoveSitsWithItsEyesOpenAndThenShut() {
        #expect(CatArt.restingFrames.count == 2)
        #expect(CatArt.restingFrames[0] == CatArt.animation(for: .sit).frames[0])
        #expect(CatArt.restingFrames[1] == CatArt.animation(for: .blink).frames[0])
        #expect(CatArt.restingFrames[0] != CatArt.restingFrames[1])
    }

    // MARK: Props

    @Test func theMothFluttersAndTheYarnRollsAndBothAreRimmed() {
        #expect(PropArt.moth.frames[0] != PropArt.moth.frames[1])
        #expect(Set(PropArt.yarn.frames.map(\.cells)).count == 4)
        for frame in PropArt.moth.frames + PropArt.yarn.frames {
            #expect(frame.cells.contains("K"), "a dark line, for a light ground")
        }
        for frame in PropArt.yarn.frames { #expect(frame.cells.contains("R"), "and a light rim, for a dark one") }
        #expect(PropArt.mothSize == CGSize(width: 11, height: 7))
        #expect(PropArt.yarnSize == CGSize(width: 12, height: 12))
    }

    // MARK: Strips and memory

    @Test func stripsAreMadeOnceForEveryMoveFacingAndCoatHoweverOftenTheyAreAsked() {
        let sheets = CatSheets()
        for _ in 0..<5 { _ = sheets.strip(for: .walk, facing: .right, coat: .tabby) }
        #expect(sheets.builds == 1)
        _ = sheets.strip(for: .walk, facing: .left, coat: .tabby)
        _ = sheets.strip(for: .walk, facing: .right, coat: .tuxedo)
        #expect(sheets.builds == 3, "another facing and another coat are strips of their own")
        let strip = sheets.strip(for: .walk, facing: .right, coat: .tabby)
        #expect(strip.frameCount == 8)
        #expect((strip.frameWidth, strip.frameHeight) == (32, 24))
        _ = sheets.restingStrip(coat: .tabby)
        _ = sheets.restingStrip(coat: .tabby)
        _ = sheets.propStrip(.moth)
        _ = sheets.propStrip(.moth)
        #expect(sheets.builds == 5)
    }

    @Test func theWholeSheetOfOneCoatFacingOneWayIsUnderHalfAMegabyteAndAllOfThemUnderThreeMegabytes() {
        let sheets = CatSheets()
        for move in CatMove.allCases { _ = sheets.strip(for: move, facing: .right, coat: .tabby) }
        _ = sheets.restingStrip(coat: .tabby)
        _ = sheets.propStrip(.moth)
        _ = sheets.propStrip(.yarn)
        #expect(sheets.bytes < 450_000, "\(sheets.bytes) bytes")
        for move in CatMove.allCases {
            for coat in CatCoat.allCases { for facing in [Facing.left, .right] { _ = sheets.strip(for: move, facing: facing, coat: coat) } }
        }
        #expect(sheets.bytes < 3_000_000, "\(sheets.bytes) bytes")
    }

    @Test func aStripIsAsWideAsItsFramesAndTheirMarginsAndNothingElse() throws {
        let strip = CatSheets().strip(for: .walk, facing: .right, coat: .tabby)
        #expect(strip.image.width == 8 * (32 + 2 * PixelStrip.margin))
        #expect(strip.image.height == 24 + 2 * PixelStrip.margin)
        #expect(strip.byteCount == strip.image.width * strip.image.height * 4)
    }

    @Test func aCoatChangesTheColoursAndNotTheShape() throws {
        let sheets = CatSheets()
        let tabby = sheets.strip(for: .sit, facing: .right, coat: .tabby)
        let tuxedo = sheets.strip(for: .sit, facing: .right, coat: .tuxedo)
        #expect(tabby.image.width == tuxedo.image.width && tabby.image.height == tuxedo.image.height)
        func bytes(_ strip: PixelStrip) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: strip.byteCount)
            CGContext(
                data: &data, width: strip.image.width, height: strip.image.height, bitsPerComponent: 8, bytesPerRow: strip.image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.draw(strip.image, in: CGRect(x: 0, y: 0, width: strip.image.width, height: strip.image.height))
            return data
        }
        let (one, other) = (bytes(tabby), bytes(tuxedo))
        let alpha = { (data: [UInt8]) in stride(from: 3, to: data.count, by: 4).map { data[$0] } }
        #expect(alpha(one) == alpha(other), "the same pixels are drawn")
        #expect(one != other, "in other colours")
    }
}
