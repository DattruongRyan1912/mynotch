import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShelfModule

/// Every file here is generated in code under a temporary folder.
@Suite struct ImageCodecTests {
    /// A machine without a HEIC encoder skips those tests rather than failing them.
    nonisolated static let canWriteHEIC = (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(UTType.heic.identifier)
    nonisolated static let lossyFormats: [ImageFormat] = canWriteHEIC ? [.jpeg, .heic] : [.jpeg]

    /// Detailed enough that the quality setting changes the size.
    static func noisyImage(width: Int = 160, height: Int = 160) -> CGImage {
        var generator = SplitMix(seed: 7)
        var bytes = (0..<width * height * 4).map { _ in UInt8(truncatingIfNeeded: generator.next()) }
        for index in stride(from: 3, to: bytes.count, by: 4) { bytes[index] = 255 }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    // MARK: Loading

    @Test func anImageStoredSidewaysIsLoadedUpright() throws {
        let folder = try makeTempDirectory()
        // Orientation 6: the picture is shown turned a quarter clockwise, so its left edge ends up on top.
        let url = try SyntheticFiles.write(SyntheticFiles.image(width: 200, height: 100), as: .jpeg, named: "a.jpg", in: folder, properties: [kCGImagePropertyOrientation: 6])
        let loaded = try ImageCodec.load(url, longestSide: nil)
        #expect(loaded.image.width == 100 && loaded.image.height == 200)
        let top = SyntheticFiles.pixel(of: loaded.image, x: 50, y: 10), bottom = SyntheticFiles.pixel(of: loaded.image, x: 50, y: 190)
        #expect(top.r > 200 && top.b < 60)
        #expect(bottom.b > 200 && bottom.r < 60)
        #expect(try ImageCodec.uprightSize(of: url) == CGSize(width: 100, height: 200))
    }

    @Test func theLongestSideIsLimitedAndAnImageIsNeverEnlarged() throws {
        let folder = try makeTempDirectory()
        let url = try SyntheticFiles.write(SyntheticFiles.image(width: 200, height: 100), as: .png, named: "a.png", in: folder)
        let small = try ImageCodec.load(url, longestSide: 50)
        #expect(small.image.width == 50 && small.image.height == 25)
        let same = try ImageCodec.load(url, longestSide: 5000)
        #expect(same.image.width == 200 && same.image.height == 100)
    }

    @Test func aFileThatIsNotAnImageOrIsCutShortIsNotAnImage() throws {
        let folder = try makeTempDirectory()
        let text = try makeTempFile(in: folder)
        #expect(throws: FileActionError.notAnImage) { try ImageCodec.load(text, longestSide: nil) }
        let whole = try SyntheticFiles.write(Self.noisyImage(), as: .jpeg, named: "whole.jpg", in: folder)
        let cut = folder.appending(path: "cut.jpg")
        try Data(contentsOf: whole).prefix(400).write(to: cut)
        #expect(throws: FileActionError.notAnImage) { try ImageCodec.load(cut, longestSide: nil) }
        let empty = folder.appending(path: "empty.png")
        try Data().write(to: empty)
        #expect(throws: FileActionError.notAnImage) { try ImageCodec.load(empty, longestSide: nil) }
    }

    @Test func aMissingFileAndAnUnreadableFileAreToldApart() throws {
        let folder = try makeTempDirectory()
        #expect(throws: FileActionError.missing) { try ImageCodec.load(folder.appending(path: "nope.png"), longestSide: nil) }
        let locked = try SyntheticFiles.write(SyntheticFiles.image(width: 8, height: 8), as: .png, named: "locked.png", in: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        #expect(throws: FileActionError.unreadable) { try ImageCodec.load(locked, longestSide: nil) }
    }

    @Test func theFormatOfAFileIsFoundFromItsContentNotItsName() throws {
        let folder = try makeTempDirectory()
        let url = try SyntheticFiles.write(SyntheticFiles.image(width: 8, height: 8), as: .png, named: "looks-like.jpg", in: folder)
        #expect(try ImageCodec.load(url, longestSide: nil).format == .png)
        let gif = try SyntheticFiles.write(SyntheticFiles.image(width: 8, height: 8), as: .gif, named: "a.gif", in: folder)
        #expect(try ImageCodec.load(gif, longestSide: nil).format == nil)
    }

    // MARK: Encoding

    @Test(arguments: [ImageFormat.png, .jpeg, .tiff])
    func encodesTheFormatAskedFor(format: ImageFormat) throws {
        let data = try ImageCodec.encode(SyntheticFiles.image(width: 40, height: 20), as: format, quality: 0.85, properties: [:], stripLocation: true)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect((CGImageSourceGetType(source) as String?) == format.utType.identifier)
        #expect(CGImageSourceGetCount(source) == 1)
    }

    @Test(.enabled(if: ImageCodecTests.canWriteHEIC))
    func encodesHEIC() throws {
        let data = try ImageCodec.encode(SyntheticFiles.image(width: 64, height: 64), as: .heic, quality: 0.85, properties: [:], stripLocation: true)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect((CGImageSourceGetType(source) as String?) == UTType.heic.identifier)
    }

    @Test(arguments: ImageCodecTests.lossyFormats)
    func aLowerQualityMakesASmallerFile(format: ImageFormat) throws {
        let image = Self.noisyImage()
        let high = try ImageCodec.encode(image, as: format, quality: 0.95, properties: [:], stripLocation: true)
        let low = try ImageCodec.encode(image, as: format, quality: 0.2, properties: [:], stripLocation: true)
        #expect(low.count < high.count)
    }

    @Test func transparencyBecomesWhiteInAJPEG() throws {
        let data = try ImageCodec.encode(SyntheticFiles.image(width: 40, height: 40, alpha: true), as: .jpeg, quality: 0.95, properties: [:], stripLocation: true)
        let image = try SyntheticFiles.decoded(data)
        // The right half is transparent on top and blue at the bottom.
        let top = SyntheticFiles.pixel(of: image, x: 30, y: 5)
        #expect(top.r > 240 && top.g > 240 && top.b > 240)
        let bottom = SyntheticFiles.pixel(of: image, x: 30, y: 35)
        #expect(bottom.b > 200 && bottom.r < 60)
    }

    @Test func transparencySurvivesInAPNG() throws {
        let data = try ImageCodec.encode(SyntheticFiles.image(width: 40, height: 40, alpha: true), as: .png, quality: 0.85, properties: [:], stripLocation: true)
        let image = try SyntheticFiles.decoded(data)
        #expect(SyntheticFiles.pixel(of: image, x: 30, y: 5).a == 0)
    }

    @Test func theLocationIsStrippedByDefaultAndKeptWhenAsked() throws {
        let folder = try makeTempDirectory()
        let url = try SyntheticFiles.write(
            SyntheticFiles.image(width: 40, height: 20), as: .jpeg, named: "gps.jpg", in: folder,
            properties: [kCGImagePropertyGPSDictionary: SyntheticFiles.gps, kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Máy ảnh"]]
        )
        #expect(try SyntheticFiles.properties(of: url)[kCGImagePropertyGPSDictionary] != nil)
        let loaded = try ImageCodec.load(url, longestSide: nil)

        let stripped = try ImageCodec.encode(loaded.image, as: .png, quality: 0.85, properties: loaded.properties, stripLocation: true)
        let strippedURL = folder.appending(path: "stripped.png")
        try stripped.write(to: strippedURL)
        #expect(try SyntheticFiles.properties(of: strippedURL)[kCGImagePropertyGPSDictionary] == nil)

        let kept = try ImageCodec.encode(loaded.image, as: .jpeg, quality: 0.85, properties: loaded.properties, stripLocation: false)
        let keptURL = folder.appending(path: "kept.jpg")
        try kept.write(to: keptURL)
        let gps = try #require(SyntheticFiles.properties(of: keptURL)[kCGImagePropertyGPSDictionary] as? [CFString: Any])
        #expect(gps[kCGImagePropertyGPSLatitudeRef] as? String == "N")
        // The other metadata goes along either way.
        let tiff = try #require(SyntheticFiles.properties(of: keptURL)[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect(tiff[kCGImagePropertyTIFFMake] as? String == "Máy ảnh")
    }

    @Test func placeNamesAreStrippedWithTheLocationButTheRestOfTheCaptionStays() throws {
        let folder = try makeTempDirectory()
        let url = try SyntheticFiles.write(
            SyntheticFiles.image(width: 40, height: 20), as: .jpeg, named: "iptc.jpg", in: folder,
            properties: [kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCCity: "Đà Nẵng", kCGImagePropertyIPTCCountryPrimaryLocationName: "Việt Nam",
                kCGImagePropertyIPTCCaptionAbstract: "Chuyến đi",
            ]]
        )
        let loaded = try ImageCodec.load(url, longestSide: nil)
        try #require((loaded.properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any])?[kCGImagePropertyIPTCCity] != nil)

        func iptc(stripping: Bool) throws -> [CFString: Any] {
            let data = try ImageCodec.encode(loaded.image, as: .jpeg, quality: 0.9, properties: loaded.properties, stripLocation: stripping)
            let file = folder.appending(path: "out-\(stripping).jpg")
            try data.write(to: file)
            return try SyntheticFiles.properties(of: file)[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        }
        let stripped = try iptc(stripping: true)
        #expect(stripped[kCGImagePropertyIPTCCity] == nil && stripped[kCGImagePropertyIPTCCountryPrimaryLocationName] == nil)
        #expect(stripped[kCGImagePropertyIPTCCaptionAbstract] as? String == "Chuyến đi")
        let kept = try iptc(stripping: false)
        #expect(kept[kCGImagePropertyIPTCCity] as? String == "Đà Nẵng")
    }

    @Test(arguments: [ImageFormat.png, .tiff, .jpeg])
    func aWideGamutColourProfileSurvivesAConversion(format: ImageFormat) throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try #require(CGContext(
            data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: p3, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        let folder = try makeTempDirectory()
        let source = try SyntheticFiles.write(try #require(context.makeImage()), as: .png, named: "p3.png", in: folder)
        let loaded = try ImageCodec.load(source, longestSide: nil)
        let data = try ImageCodec.encode(loaded.image, as: format, quality: 0.9, properties: loaded.properties, stripLocation: true)
        let image = try SyntheticFiles.decoded(data)
        #expect(image.colorSpace?.name == CGColorSpace.displayP3 as CFString)
    }

    @Test func aTurnedImageIsWrittenUprightWithNoOrientationLeftToApplyTwice() throws {
        let folder = try makeTempDirectory()
        let url = try SyntheticFiles.write(
            SyntheticFiles.image(width: 200, height: 100), as: .jpeg, named: "turned.jpg", in: folder,
            properties: [kCGImagePropertyOrientation: 6, kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: 6]]
        )
        let loaded = try ImageCodec.load(url, longestSide: nil)
        let out = folder.appending(path: "out.jpg")
        try ImageCodec.encode(loaded.image, as: .jpeg, quality: 0.9, properties: loaded.properties, stripLocation: true).write(to: out)
        let properties = try SyntheticFiles.properties(of: out)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect(((properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFOrientation] as? Int ?? 1) == 1)
        let decoded = try SyntheticFiles.decoded(out)
        #expect(decoded.width == 100 && decoded.height == 200)
        #expect(SyntheticFiles.pixel(of: decoded, x: 50, y: 10).r > 200)
    }
}

/// A small seeded generator, so the "noise" is the same on every run.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
