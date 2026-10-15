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
}
