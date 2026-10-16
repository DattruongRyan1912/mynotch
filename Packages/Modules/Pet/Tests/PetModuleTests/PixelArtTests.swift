import CoreGraphics
import Testing
@testable import PetModule

@Suite struct PixelArtTests {
    let palette = PixelPalette(colors: ["A": 0xFF0000, "B": 0x00FF00])

    @Test func parsesRowsIntoCellsAndGivesThemBack() throws {
        let frame = try PixelFrame(rows: ["A.B", ".B."], palette: palette)
        #expect((frame.width, frame.height) == (3, 2))
        #expect(frame[0, 0] == "A")
        #expect(frame[2, 0] == "B")
        #expect(frame[1, 1] == "B")
        #expect(frame.rows == ["A.B", ".B."])
        #expect(frame.inkCount == 3)
    }

    @Test func refusesRowsOfDifferentLengths() {
        #expect(throws: PixelArtError.ragged(row: 1, width: 1, expected: 2)) { try PixelFrame(rows: ["A.", "B"], palette: palette) }
    }

    @Test func refusesACharacterThePaletteDoesNotHave() {
        #expect(throws: PixelArtError.unknownCharacter("X", row: 1, column: 0)) { try PixelFrame(rows: ["A.", "X."], palette: palette) }
    }

    @Test func refusesNothingAtAll() {
        #expect(throws: PixelArtError.empty) { try PixelFrame(rows: [], palette: palette) }
        #expect(throws: PixelArtError.empty) { try PixelFrame(rows: [""], palette: palette) }
    }

    @Test func mirroringSwapsLeftAndRightAndBackAgainIsTheSamePicture() throws {
        let frame = try PixelFrame(rows: ["AB.", ".AB"], palette: palette)
        #expect(frame.mirrored.rows == [".BA", "BA."])
        #expect(frame.mirrored.mirrored == frame)
    }

    @Test func aPieceDrawnOverAFrameLeavesWhatItsClearPixelsDoNotCoverAndLosesWhatFallsOutside() throws {
        let base = try PixelFrame(rows: ["AAA", "AAA", "AAA"], palette: palette)
        let piece = try PixelFrame(rows: ["B.", ".B"], palette: palette)
        #expect(base.drawing(piece, atX: 1, y: 0).rows == ["ABA", "AAB", "AAA"])
        #expect(base.drawing(piece, atX: 2, y: 2).rows == ["AAA", "AAA", "AAB"])
        #expect(base.drawing(piece, atX: -1, y: -1).rows == ["BAA", "AAA", "AAA"])
        #expect(base.drawing(piece, atX: 9, y: 9) == base)
    }

    // MARK: Strips

    /// The image's pixels as 8-bit RGBA, rows from the top.
    func pixels(of image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    @Test func aStripLaysTheFramesSideBySideEachWithAClearMarginAllRound() throws {
        let one = try PixelFrame(rows: ["A.", ".B"], palette: palette)
        let two = try PixelFrame(rows: ["BB", "AA"], palette: palette)
        let strip = try #require(PixelStrip(frames: [one, two], palette: palette))
        #expect((strip.frameWidth, strip.frameHeight, strip.frameCount) == (2, 2, 2))
        #expect(strip.image.width == 2 * (2 + 2 * PixelStrip.margin))
        #expect(strip.image.height == 2 + 2 * PixelStrip.margin)

        let width = strip.image.width
        let bytes = pixels(of: strip.image)
        func rgba(_ x: Int, _ y: Int) -> [UInt8] { Array(bytes[(y * width + x) * 4..<(y * width + x) * 4 + 4]) }
        let cell = 2 + 2 * PixelStrip.margin
        // Frame 0's four pixels, then frame 1's.
        #expect(rgba(1, 1) == [255, 0, 0, 255])
        #expect(rgba(2, 1) == [0, 0, 0, 0])
        #expect(rgba(2, 2) == [0, 255, 0, 255])
        #expect(rgba(cell + 1, 1) == [0, 255, 0, 255])
        #expect(rgba(cell + 1, 2) == [255, 0, 0, 255])
        // The margin is clear: the column and row round every frame.
        for y in 0..<strip.image.height {
            for x in [0, 3, cell - 1, cell, 2 * cell - 1] { #expect(rgba(x, y)[3] == 0, "margin at \(x), \(y)") }
        }
        for x in 0..<width { for y in [0, 3] { #expect(rgba(x, y)[3] == 0, "margin at \(x), \(y)") } }
    }

    @Test func aFramesPlaceInTheStripIsExactlyItsPixelsInTheUnitSquare() throws {
        let one = try PixelFrame(rows: ["A.", ".B"], palette: palette)
        let strip = try #require(PixelStrip(frames: [one, one, one], palette: palette))
        let (width, height) = (Double(strip.image.width), Double(strip.image.height))
        for index in 0..<3 {
            let rect = strip.contentsRect(of: index)
            #expect(abs(rect.minX * width - Double(index * 4 + 1)) < 1e-9)
            #expect(abs(rect.width * width - 2) < 1e-9)
            #expect(abs(rect.minY * height - 1) < 1e-9)
            #expect(abs(rect.height * height - 2) < 1e-9)
        }
    }

    @Test func frames_ofDifferentSizesMakeNoStrip() throws {
        let small = try PixelFrame(rows: ["A"], palette: palette)
        let wide = try PixelFrame(rows: ["AA"], palette: palette)
        #expect(PixelStrip(frames: [small, wide], palette: palette) == nil)
        #expect(PixelStrip(frames: [], palette: palette) == nil)
    }
}

@Suite struct CatArtTests {
    static let animations: [(CatPose, PixelAnimation)] = CatPose.allCases.map { ($0, CatArt.animation(for: $0)) }

    @Test func everyFrameOfEveryAnimationIsTwentyBySixteen() {
        for (pose, animation) in Self.animations {
            for (index, frame) in animation.frames.enumerated() {
                #expect((frame.width, frame.height) == (20, 16), "\(pose) frame \(index)")
            }
        }
    }

    @Test func everyPixelIsClearOrAColourOfThePalette() {
        for (pose, animation) in Self.animations {
            for frame in animation.frames {
                for cell in frame.cells { #expect(CatArt.palette.isKnown(cell), "\(pose) uses \(cell)") }
            }
        }
    }

    @Test func everyColourOfThePaletteIsUsedSomewhere() {
        let used = Set(Self.animations.flatMap { $0.1.frames.flatMap(\.cells) })
        for colour in CatArt.palette.colors.keys { #expect(used.contains(colour), "\(colour) is never drawn") }
    }

    @Test func eachAnimationHasTheFramesItShould() {
        let counts = Dictionary(uniqueKeysWithValues: Self.animations.map { ($0.0, $0.1.frames.count) })
        #expect(counts == [
            .sit: 6, .blink: 1, .walk: 4, .run: 4, .lick: 4, .yawn: 5, .sleep: 4, .startled: 4, .dance: 4, .purr: 4,
        ])
    }

    @Test func noFrameIsEmptyAndAnimationsThatMoveHaveFramesThatDiffer() {
        for (pose, animation) in Self.animations {
            for frame in animation.frames { #expect(frame.inkCount > 40, "\(pose) draws a cat") }
            if animation.frames.count > 1 {
                #expect(Set(animation.frames.map(\.cells)).count > 1, "\(pose) moves")
            }
        }
        // A walk steps out, passes, steps out with the other legs, and passes again: three pictures in four frames; a run too.
        #expect(Set(CatArt.walk.frames.map(\.cells)).count == 3)
        #expect(Set(CatArt.run.frames.map(\.cells)).count == 3)
    }

    @Test func noAnimationPlaysFasterThanTwelveFramesASecondAndTheLivelyOnesAtLeastEight() {
        for (pose, animation) in Self.animations { #expect(animation.fps <= 12, "\(pose)") }
        for animation in [CatArt.walk, CatArt.run, CatArt.startled] { #expect(animation.fps >= 8) }
    }

    @Test func theLoopsLastAsLongAsTheirFramesAtTheirRate() {
        #expect(CatArt.walk.duration == 0.5)
        #expect(CatArt.run.duration == 4.0 / 12)
        #expect(CatArt.sleep.duration == 2)
    }

    @Test func theSleepingCatHasZsThePurringOneHeartsTheDancingOneNotesAndARunStreaks() {
        func uses(_ animation: PixelAnimation, _ colour: Character) -> Bool { animation.frames.contains { $0.cells.contains(colour) } }
        #expect(uses(CatArt.sleep, "Z"))
        #expect(!uses(CatArt.sit, "Z"))
        #expect(uses(CatArt.purr, "H"))
        #expect(uses(CatArt.dance, "N"))
        #expect(uses(CatArt.run, "S"))
        #expect(!uses(CatArt.walk, "S"))
    }

    /// The row of the highest pixel of the cat itself, not of what floats over it.
    func topOfCat(_ frame: PixelFrame) -> Int? {
        (0..<frame.height).first { row in (0..<frame.width).contains { ["K", "O", "D", "W", "P", "E"].contains(frame[$0, row]) } }
    }

    @Test func theStartledCatLeavesTheGroundAtTheTopOfItsJump() throws {
        let sitting = try #require(topOfCat(CatArt.sit.frames[0]))
        let peak = try #require(CatArt.startled.frames.compactMap(topOfCat).min())
        #expect(peak <= sitting - 3, "it jumps at least three pixels")
        // And it comes down: the last frame is as low as sitting.
        #expect(topOfCat(CatArt.startled.frames[3]) == sitting)
    }

    @Test func theCatFacesRightAndMirroredFacesLeft() throws {
        let frame = CatArt.walk.frames[0]
        // The head, with its eyes, is at the right of the picture and at the left of the mirror image.
        func eyes(_ frame: PixelFrame) -> [Int] { (0..<frame.width).filter { column in (0..<frame.height).contains { frame[column, $0] == "E" } } }
        #expect(try #require(eyes(frame).min()) > 10)
        #expect(try #require(eyes(frame.mirrored).max()) < 10)
    }

    @Test func aCatThatDoesNotMoveSitsWithItsEyesOpenAndThenShut() {
        #expect(CatArt.restingFrames.count == 2)
        #expect(CatArt.restingFrames[0] == CatArt.sit.frames[0])
        #expect(CatArt.restingFrames[1] == CatArt.blink.frames[0])
        #expect(CatArt.restingFrames[0] != CatArt.restingFrames[1])
    }

    @Test func stripsAreMadeOnceForEveryPoseAndFacingHoweverOftenTheyAreAsked() {
        let sheets = CatSheets()
        for _ in 0..<5 { _ = sheets.strip(for: .walk, facing: .right) }
        #expect(sheets.builds == 1)
        _ = sheets.strip(for: .walk, facing: .left)
        _ = sheets.strip(for: .run, facing: .right)
        #expect(sheets.builds == 3)
        let strip = sheets.strip(for: .walk, facing: .right)
        #expect(strip.frameCount == 4)
        #expect((strip.frameWidth, strip.frameHeight) == (20, 16))
        _ = sheets.restingStrip()
        _ = sheets.restingStrip()
        #expect(sheets.builds == 4)
    }
}
