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

    @Test func aRimIsAPixelOfLightAllRoundWhateverTouchesThePictureCornersIncluded() throws {
        let frame = try PixelFrame(rows: ["A.", ".A"], palette: palette)
        #expect(frame.padded(by: 1).rows == ["....", ".A..", "..A.", "...."])
        #expect(frame.rimmed(with: "B").rows == ["BBB.", "BABB", "BBAB", ".BBB"])
        #expect(frame.rimmed(with: "B").width == frame.width + 2)
    }

    @Test func aRimIsNotDrawnOverWhatIsThereAndThePictureStaysWhereItWas() throws {
        let frame = try PixelFrame(rows: ["AB", "BA"], palette: palette)
        let rimmed = frame.rimmed(with: "A")
        #expect(rimmed.drawing(PixelFrame(width: 1, height: 1), atX: 0, y: 0)[1, 1] == "A")
        #expect([rimmed[1, 1], rimmed[2, 1], rimmed[1, 2], rimmed[2, 2]] == ["A", "B", "B", "A"])
    }

    @Test func frames_ofDifferentSizesMakeNoStrip() throws {
        let small = try PixelFrame(rows: ["A"], palette: palette)
        let wide = try PixelFrame(rows: ["AA"], palette: palette)
        #expect(PixelStrip(frames: [small, wide], palette: palette) == nil)
        #expect(PixelStrip(frames: [], palette: palette) == nil)
    }
}

