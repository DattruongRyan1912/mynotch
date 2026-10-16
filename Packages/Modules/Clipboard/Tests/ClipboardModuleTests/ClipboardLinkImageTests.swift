import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ClipboardModule

/// A page's picture becomes a small PNG of MyNotch's own, or nothing.
@Suite struct ClipboardLinkImageTests {
    @Test func aBigPictureIsMadeSmall() throws {
        let png = try #require(ClipboardLinkImage.thumbnail(from: TestPictures.png(width: 1_000, height: 500)))
        let size = try #require(TestPictures.size(of: png))
        #expect(size.width == 256)
        #expect(size.height == 128)
        // Always a PNG of ours, whatever the page sent.
        #expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        let tall = try #require(ClipboardLinkImage.thumbnail(from: TestPictures.png(width: 300, height: 900)))
        let tallSize = try #require(TestPictures.size(of: tall))
        #expect(tallSize.height == 256)
        #expect(tallSize.width == 85 || tallSize.width == 86)
    }

    @Test func aSmallPictureIsNotMadeLarger() throws {
        let png = try #require(ClipboardLinkImage.thumbnail(from: TestPictures.png(width: 16, height: 16)))
        let size = try #require(TestPictures.size(of: png))
        #expect(size.width == 16)
        #expect(size.height == 16)
    }

    /// What a page may send: PNG, JPEG, GIF and ICO. Whatever else ImageIO reads, a page has no business handing to a process that is not
    /// sandboxed.
    @Test func theFourKindsAPageMaySendAreReadAndWrittenAsPNG() throws {
        for type in [UTType.jpeg, .gif] {
            let png = try #require(ClipboardLinkImage.thumbnail(from: TestPictures.encoded([(600, 400)], as: type)), "\(type)")
            #expect(try #require(TestPictures.size(of: png)).width == 256)
            #expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        }
        let icon = try #require(ClipboardLinkImage.thumbnail(from: TestPictures.icoThreeFrames))
        #expect(Array(icon.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        #expect(ClipboardLinkImage.acceptedTypes == [UTType.png.identifier, UTType.jpeg.identifier, UTType.gif.identifier, UTType.ico.identifier])
    }

    /// ImageIO reads these, and each is refused by what the bytes are, not by what a server says they are.
    @Test func everyOtherKindIsRefusedEvenThoughImageIOReadsIt() throws {
        let tiff = TestPictures.encoded([(64, 64)], as: .tiff)
        // The control: a decoder that does not look at the kind would make a picture of it.
        let source = try #require(CGImageSourceCreateWithData(tiff as CFData, nil))
        #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
        #expect(ClipboardLinkImage.thumbnail(from: tiff) == nil)

        // WebP: decoded by the same library whose heap overflow was exploited with one crafted picture.
        let webp = TestPictures.webp
        if let webpSource = CGImageSourceCreateWithData(webp as CFData, nil), CGImageSourceGetType(webpSource) != nil {
            #expect(CGImageSourceCreateImageAtIndex(webpSource, 0, nil) != nil, "ImageIO reads WebP on this system")
        }
        #expect(ClipboardLinkImage.thumbnail(from: webp) == nil)

        // HEIC, where this system can make one.
        let heic = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(heic, UTType.heic.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, TestPictures.image(width: 64, height: 64), nil)
            if CGImageDestinationFinalize(destination) { #expect(ClipboardLinkImage.thumbnail(from: heic as Data) == nil) }
        }
    }

    /// An icon file holds several sizes, and the first is often the smallest.
    @Test func theBiggestFrameIsTheOneUsed() throws {
        let png = try #require(ClipboardLinkImage.thumbnail(from: TestPictures.icoThreeFrames))
        #expect(try #require(TestPictures.size(of: png)).width == 128)
    }

    @Test func bytesThatAreNotAPictureAreNothing() {
        #expect(ClipboardLinkImage.thumbnail(from: Data("<html><body>not a picture</body></html>".utf8)) == nil)
        #expect(ClipboardLinkImage.thumbnail(from: Data()) == nil)
        #expect(ClipboardLinkImage.thumbnail(from: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0])) == nil)
        #expect(ClipboardLinkImage.thumbnail(from: Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"/>".utf8)) == nil)
        // A picture cut short is decoded as far as ImageIO can or not at all; either way, no crash and nothing but a PNG of ours comes out.
        var damaged = TestPictures.png(width: 64, height: 64)
        damaged.removeSubrange((damaged.count / 2)...)
        if let png = ClipboardLinkImage.thumbnail(from: damaged) { #expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47]) }
    }

    @Test func tooManyPixelsAreRefusedBeforeDecoding() throws {
        #expect(ClipboardLinkImage.isAcceptable(width: 1, height: 1))
        #expect(ClipboardLinkImage.isAcceptable(width: 5_000, height: 5_000))
        #expect(!ClipboardLinkImage.isAcceptable(width: 5_001, height: 5_000))
        #expect(!ClipboardLinkImage.isAcceptable(width: 16_385, height: 1))
        #expect(!ClipboardLinkImage.isAcceptable(width: 0, height: 10))
        #expect(!ClipboardLinkImage.isAcceptable(width: -5, height: 10))
        // A real picture over the limit: a few kilobytes of PNG that would be 36 million pixels.
        let bomb = TestPictures.png(width: 6_000, height: 6_000)
        #expect(bomb.count < 2 * 1024 * 1024)
        #expect(ClipboardLinkImage.thumbnail(from: bomb) == nil)
    }
}
