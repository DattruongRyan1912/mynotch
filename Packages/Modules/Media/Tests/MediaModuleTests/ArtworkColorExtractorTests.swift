import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MediaModule

/// Images made of known pixels, so what the extractor says can be checked against what was drawn.
enum SyntheticImage {
    typealias Pixel = (red: Double, green: Double, blue: Double, alpha: Double)

    static func make(width: Int, height: Int, pixel: (_ x: Int, _ y: Int) -> Pixel) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (red, green, blue, alpha) = pixel(x, y)
                let offset = (y * width + x) * 4
                // Premultiplied, as the context below declares.
                bytes[offset] = UInt8((red * alpha * 255).rounded())
                bytes[offset + 1] = UInt8((green * alpha * 255).rounded())
                bytes[offset + 2] = UInt8((blue * alpha * 255).rounded())
                bytes[offset + 3] = UInt8((alpha * 255).rounded())
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    static func solid(_ color: SRGBColor, size: Int = 32) -> CGImage {
        make(width: size, height: size) { _, _ in (color.red, color.green, color.blue, 1) }
    }

    /// The left half in `left`, the right half in `right`.
    static func twoTone(_ left: SRGBColor, _ right: SRGBColor, size: Int = 32) -> CGImage {
        make(width: size, height: size) { x, _ in
            let color = x < size / 2 ? left : right
            return (color.red, color.green, color.blue, 1)
        }
    }

    static func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

extension SRGBColor {
    static let fullRed = SRGBColor(red: 1, green: 0, blue: 0)
    static let fullGreen = SRGBColor(red: 0, green: 1, blue: 0)
    static let fullBlue = SRGBColor(red: 0, green: 0, blue: 1)
    static let white = SRGBColor(red: 1, green: 1, blue: 1)
    static let black = SRGBColor(red: 0, green: 0, blue: 0)

    /// Within `tolerance` of `other` in every channel.
    func isClose(to other: SRGBColor, tolerance: Double = 0.03) -> Bool {
        abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance && abs(blue - other.blue) <= tolerance
    }
}

@Suite struct SRGBColorTests {
    @Test func channelsAreKeptInsideZeroToOne() {
        let color = SRGBColor(red: -0.4, green: 0.5, blue: 3)
        #expect(color == SRGBColor(red: 0, green: 0.5, blue: 1))
    }

    @Test func luminanceFollowsTheStandardWeights() {
        #expect(SRGBColor.black.luminance == 0)
        #expect(abs(SRGBColor.white.luminance - 1) < 1e-9)
        #expect(abs(SRGBColor.fullRed.luminance - 0.2126) < 1e-4)
        #expect(abs(SRGBColor.fullGreen.luminance - 0.7152) < 1e-4)
        #expect(abs(SRGBColor.fullBlue.luminance - 0.0722) < 1e-4)
    }

    @Test func contrastOnBlackIsWhatTheMinimumLuminanceMeans() {
        #expect(abs(SRGBColor.white.contrastOnBlack - 21) < 1e-9)
        #expect(SRGBColor.black.contrastOnBlack == 1)
        // The clamp is three to one against black, the contrast that graphics need.
        let atMinimum = SRGBColor.black.lifted(toLuminance: SRGBColor.minimumLuminance)
        #expect(atMinimum.contrastOnBlack >= 3 - 1e-6)
    }

    @Test func aBrightColourIsLeftAlone() {
        let color = SRGBColor(red: 0.9, green: 0.4, blue: 0.1)
        #expect(color.lifted(toLuminance: SRGBColor.minimumLuminance) == color)
    }

    @Test func blackBecomesAGreyJustBrightEnough() {
        let lifted = SRGBColor.black.lifted(toLuminance: 0.1)
        #expect(lifted.luminance >= 0.1 - 1e-6)
        #expect(lifted.luminance < 0.11)
        #expect(abs(lifted.red - lifted.green) < 1e-9 && abs(lifted.green - lifted.blue) < 1e-9)
    }

    @Test func aDarkColourKeepsItsHueWhenItIsLifted() {
        let navy = SRGBColor(red: 0, green: 0.05, blue: 0.3)
        let lifted = navy.lifted(toLuminance: 0.1)
        #expect(lifted.luminance >= 0.1 - 1e-6)
        #expect(lifted.blue > lifted.green && lifted.green > lifted.red, "still blue")
        #expect(lifted.luminance < 0.12, "no more than needed")
    }

    @Test func pureBlueNeedsALittleWhiteBecauseBrightnessAloneCannotReachTheMinimum() {
        let lifted = SRGBColor.fullBlue.lifted(toLuminance: 0.1)
        #expect(lifted.luminance >= 0.1 - 1e-6)
        #expect(lifted.blue == 1)
        #expect(lifted.red > 0)
    }

    @Test func mixingMovesOneColourTowardsAnother() {
        #expect(SRGBColor.black.mixed(with: .white, amount: 0.5) == SRGBColor(red: 0.5, green: 0.5, blue: 0.5))
        #expect(SRGBColor.fullRed.mixed(with: .fullBlue, amount: 0) == .fullRed)
        #expect(SRGBColor.fullRed.mixed(with: .fullBlue, amount: 1) == .fullBlue)
        #expect(SRGBColor.fullRed.mixed(with: .fullBlue, amount: 7) == .fullBlue, "the amount is kept inside 0...1")
    }

    @Test func saturationIsZeroForGreysAndOneForPureColours() {
        #expect(SRGBColor(red: 0.4, green: 0.4, blue: 0.4).saturation == 0)
        #expect(SRGBColor.fullRed.saturation == 1)
        #expect(SRGBColor.black.saturation == 0)
    }

    @Test func aColourIsStoredAsItsThreeChannelsAndReadBackClamped() throws {
        let color = SRGBColor(red: 0.25, green: 0.5, blue: 0.75)
        let data = try JSONEncoder().encode(color)
        #expect(try JSONDecoder().decode(SRGBColor.self, from: data) == color)
        let wild = Data(#"{"red":2,"green":-1,"blue":0.5}"#.utf8)
        #expect(try JSONDecoder().decode(SRGBColor.self, from: wild) == SRGBColor(red: 1, green: 0, blue: 0.5))
    }
}

@Suite struct ArtworkColorExtractorTests {
    @Test func aSolidImageGivesItsColourAndNoSecond() throws {
        let palette = try #require(ArtworkColorExtractor.palette(of: SyntheticImage.solid(.fullRed)))
        #expect(palette.primary.isClose(to: .fullRed))
        #expect(palette.secondary == nil)
    }

    @Test func aTwoToneImageGivesBothColours() throws {
        let palette = try #require(ArtworkColorExtractor.palette(of: SyntheticImage.twoTone(.fullRed, .fullGreen)))
        let found = [palette.primary, try #require(palette.secondary)]
        #expect(found.contains { $0.isClose(to: .fullRed) })
        #expect(found.contains { $0.isClose(to: .fullGreen) })
    }

    @Test func theColourThatCoversMoreComesFirstWhenBothAreAsVivid() throws {
        // Three quarters green, one quarter red.
        let image = SyntheticImage.make(width: 32, height: 32) { x, _ in
            x < 24 ? (0, 1, 0, 1) : (1, 0, 0, 1)
        }
        let palette = try #require(ArtworkColorExtractor.palette(of: image))
        #expect(palette.primary.isClose(to: .fullGreen))
        #expect(try #require(palette.secondary).isClose(to: .fullRed))
    }

    @Test func aVividColourBeatsABigGreyArea() throws {
        // Seventy per cent grey and thirty per cent orange: the tint should be the orange.
        let orange = SRGBColor(red: 1, green: 0.5, blue: 0)
        let image = SyntheticImage.make(width: 32, height: 32) { x, _ in
            x < 22 ? (0.3, 0.3, 0.3, 1) : (orange.red, orange.green, orange.blue, 1)
        }
        let palette = try #require(ArtworkColorExtractor.palette(of: image))
        #expect(palette.primary.isClose(to: orange))
    }

    @Test func aGradientGivesTwoDistinctColoursFromAlongIt() throws {
        // Red to yellow, left to right.
        let image = SyntheticImage.make(width: 64, height: 16) { x, _ in (1, Double(x) / 63, 0, 1) }
        let palette = try #require(ArtworkColorExtractor.palette(of: image))
        let secondary = try #require(palette.secondary)
        #expect(palette.primary.distance(to: secondary) >= ArtworkColorExtractor.minimumSeparation)
        for color in [palette.primary, secondary] {
            #expect(color.red > 0.95 && color.blue < 0.05)
            #expect(color.green > 0.05 && color.green < 0.95, "from inside the gradient, not an end of it")
        }
    }

    @Test func aNearBlackImageIsLiftedToTheMinimumLuminanceAndStaysNeutral() throws {
        let image = SyntheticImage.solid(SRGBColor(red: 0.02, green: 0.02, blue: 0.02))
        let palette = try #require(ArtworkColorExtractor.palette(of: image))
        #expect(palette.primary.luminance >= SRGBColor.minimumLuminance - 1e-6)
        #expect(palette.primary.luminance < SRGBColor.minimumLuminance + 0.02)
        #expect(abs(palette.primary.red - palette.primary.blue) < 0.01)
        #expect(palette.secondary == nil)
    }

    @Test func twoNearBlackShadesBecomeOneColourOnceLifted() throws {
        let image = SyntheticImage.twoTone(SRGBColor(red: 0.01, green: 0.01, blue: 0.01), SRGBColor(red: 0.04, green: 0.04, blue: 0.05))
        let palette = try #require(ArtworkColorExtractor.palette(of: image))
        #expect(palette.primary.luminance >= SRGBColor.minimumLuminance - 1e-6)
        #expect(palette.secondary == nil)
    }

    @Test func everyColourReturnedHasTheContrastOnBlack() throws {
        for (left, right) in [(SRGBColor.fullBlue, SRGBColor.black), (SRGBColor(red: 0, green: 0, blue: 0.2), SRGBColor(red: 0.1, green: 0, blue: 0)), (.fullRed, .fullGreen)] {
            let palette = try #require(ArtworkColorExtractor.palette(of: SyntheticImage.twoTone(left, right)))
            for color in [palette.primary, palette.secondary].compactMap({ $0 }) {
                #expect(color.luminance >= SRGBColor.minimumLuminance - 1e-6, "\(color)")
            }
        }
    }

    @Test func aDarkBlueKeepsItsHueWhenItIsClamped() throws {
        let palette = try #require(ArtworkColorExtractor.palette(of: SyntheticImage.solid(SRGBColor(red: 0, green: 0.05, blue: 0.3))))
        #expect(palette.primary.blue > palette.primary.green && palette.primary.green >= palette.primary.red)
        #expect(palette.primary.luminance >= SRGBColor.minimumLuminance - 1e-6)
    }

    @Test func transparentPixelsDoNotCount() throws {
        let image = SyntheticImage.make(width: 32, height: 32) { x, _ in x < 16 ? (1, 0, 0, 0) : (0, 1, 0, 1) }
        let palette = try #require(ArtworkColorExtractor.palette(of: image))
        #expect(palette.primary.isClose(to: .fullGreen))
        #expect(palette.secondary == nil)
    }

    @Test func aFullyTransparentImageHasNoColour() {
        let image = SyntheticImage.make(width: 8, height: 8) { _, _ in (1, 0, 0, 0) }
        #expect(ArtworkColorExtractor.palette(of: image) == nil)
    }

    @Test func theSameImageGivesTheSameAnswerEveryTime() throws {
        let image = SyntheticImage.make(width: 64, height: 64) { x, y in (Double(x) / 63, Double(y) / 63, Double((x + y) % 7) / 6, 1) }
        let first = ArtworkColorExtractor.palette(of: image)
        for _ in 0..<5 { #expect(ArtworkColorExtractor.palette(of: image) == first) }
        #expect(first != nil)
    }

    @Test func aBigImageIsReadFromAThumbnailNoLargerThanSixtyFour() throws {
        #expect(ArtworkColorExtractor.sampleSize(for: CGSize(width: 1000, height: 500)) == CGSize(width: 64, height: 32))
        #expect(ArtworkColorExtractor.sampleSize(for: CGSize(width: 500, height: 1000)) == CGSize(width: 32, height: 64))
        #expect(ArtworkColorExtractor.sampleSize(for: CGSize(width: 3000, height: 3000)) == CGSize(width: 64, height: 64))
        #expect(ArtworkColorExtractor.sampleSize(for: CGSize(width: 10, height: 6)) == CGSize(width: 10, height: 6), "never enlarged")
        #expect(ArtworkColorExtractor.sampleSize(for: CGSize(width: 5000, height: 1)) == CGSize(width: 64, height: 1), "at least a pixel")
        #expect(ArtworkColorExtractor.sampleSize(for: .zero) == nil)

        let big = SyntheticImage.twoTone(.fullRed, .fullGreen, size: 1200)
        let palette = try #require(ArtworkColorExtractor.palette(of: big))
        #expect([palette.primary, try #require(palette.secondary)].contains { $0.isClose(to: .fullRed, tolerance: 0.05) })
    }

    @Test func imageDataIsDecodedToAThumbnailAndGivesTheSameColours() throws {
        let image = SyntheticImage.twoTone(.fullRed, .fullGreen, size: 200)
        let fromData = try #require(ArtworkColorExtractor.palette(imageData: SyntheticImage.png(image)))
        let fromImage = try #require(ArtworkColorExtractor.palette(of: image))
        #expect(fromData.primary.isClose(to: fromImage.primary, tolerance: 0.05))
        #expect(try #require(fromData.secondary).isClose(to: try #require(fromImage.secondary), tolerance: 0.05))
    }

    @Test func dataThatIsNoImageHasNoColour() {
        #expect(ArtworkColorExtractor.palette(imageData: Data([1, 2, 3])) == nil)
        #expect(ArtworkColorExtractor.palette(imageData: Data()) == nil)
    }

    // MARK: near-white, one pixel, and covers too big to read

    @Test func aNearWhiteCoverNeedsNoClampAndStaysAsItIs() throws {
        let white = SRGBColor(red: 0.98, green: 0.98, blue: 0.98)
        let palette = try #require(ArtworkColorExtractor.palette(of: SyntheticImage.solid(white)))
        #expect(palette.primary.isClose(to: white, tolerance: 0.01))
        #expect(palette.secondary == nil)
        let pure = try #require(ArtworkColorExtractor.palette(of: SyntheticImage.solid(.white)))
        #expect(pure.primary.isClose(to: .white, tolerance: 0.005))
    }

    @Test func aWhiteCoverWithAColouredEmblemTakesTheEmblemAsItsSecondColour() throws {
        let image = SyntheticImage.make(width: 32, height: 32) { x, y in
            x < 8 && y < 8 ? (0, 0.6, 1, 1) : (0.97, 0.97, 0.97, 1)
        }
        let palette = try #require(ArtworkColorExtractor.palette(of: image))
        #expect(palette.primary.isClose(to: SRGBColor(red: 0.97, green: 0.97, blue: 0.97), tolerance: 0.02))
        #expect(try #require(palette.secondary).isClose(to: SRGBColor(red: 0, green: 0.6, blue: 1), tolerance: 0.03))
    }

    @Test func aOnePixelImageIsItsOwnColour() throws {
        let orange = SRGBColor(red: 1, green: 0.5, blue: 0)
        let palette = try #require(ArtworkColorExtractor.palette(of: SyntheticImage.solid(orange, size: 1)))
        #expect(palette.primary.isClose(to: orange))
        #expect(palette.secondary == nil)
        #expect(ArtworkColorExtractor.palette(of: SyntheticImage.make(width: 1, height: 1) { _, _ in (1, 0, 0, 0) }) == nil)
    }

    @Test func aOnePixelImageFromDataWorksToo() throws {
        let png = SyntheticImage.png(SyntheticImage.solid(SRGBColor(red: 0, green: 1, blue: 0), size: 1))
        #expect(try #require(ArtworkColorExtractor.palette(imageData: png)).primary.isClose(to: .fullGreen, tolerance: 0.05))
    }

    @Test func theLimitOnASourceImageIsOnItsPixelsAndNeverOverflows() {
        #expect(ArtworkColorExtractor.acceptsSourceSize(width: 4000, height: 4000))
        #expect(ArtworkColorExtractor.acceptsSourceSize(width: 1, height: 1))
        #expect(!ArtworkColorExtractor.acceptsSourceSize(width: 20_000, height: 20_000))
        #expect(!ArtworkColorExtractor.acceptsSourceSize(width: Int.max, height: Int.max))
        #expect(!ArtworkColorExtractor.acceptsSourceSize(width: 0, height: 100))
        #expect(!ArtworkColorExtractor.acceptsSourceSize(width: -5, height: 100))
    }

    /// A black gray-scale image of `size` by `size`, which PNG squeezes to a few kilobytes however big it is.
    func blackPNG(size: Int) -> Data {
        let provider = CGDataProvider(data: Data(count: size * size) as CFData)!
        let image = CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return SyntheticImage.png(image)
    }

    @Test func theSizeOfAnImageIsReadFromItsHeaderAlone() throws {
        let real = SyntheticImage.png(SyntheticImage.solid(.fullRed, size: 40))
        let small = try #require(ArtworkColorExtractor.pixelSize(ofImageData: real))
        #expect(small.width == 40 && small.height == 40)
        #expect(ArtworkColorExtractor.pixelSize(ofImageData: Data([1, 2, 3])) == nil)
        #expect(ArtworkColorExtractor.pixelSize(ofImageData: Data()) == nil)
    }

    @Test func aCoverAboveTheLimitGivesNoTintInsteadOfBeingDecoded() throws {
        // 7000 x 7000 is 49 million pixels, 196 MB as RGBA. A black image would give a palette (a grey) if it were read, so
        // nothing coming back is the guard at work.
        let png = blackPNG(size: 7_000)
        #expect(png.count < 5_000_000, "a few kilobytes on disk, hundreds of megabytes decoded")
        let size = try #require(ArtworkColorExtractor.pixelSize(ofImageData: png))
        #expect(size.width == 7_000 && size.height == 7_000)
        #expect(ArtworkColorExtractor.palette(imageData: png) == nil)
        #expect(ArtworkColorExtractor.palette(imageData: blackPNG(size: 300)) != nil, "the same image below the limit is read")
    }

    @Test func aBigCoverThatIsWithinTheLimitIsReadFromAThumbnail() throws {
        let png = SyntheticImage.png(SyntheticImage.twoTone(.fullRed, .fullGreen, size: 1000))
        let palette = try #require(ArtworkColorExtractor.palette(imageData: png))
        #expect([palette.primary, try #require(palette.secondary)].contains { $0.isClose(to: .fullRed, tolerance: 0.05) })
    }
}
