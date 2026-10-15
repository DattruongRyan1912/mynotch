import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import ShelfModule

/// The pure parts of the Vision wrappers, and the few real Vision runs that give the same answer every time.
@Suite struct VisionTests {
    @Test func vietnameseIsMatchedUnderTheRegionVisionReportsIt() {
        let supported = [Locale.Language(identifier: "en-US"), Locale.Language(identifier: "vi-VT")]
        let matched = VisionTextRecognizer.recognitionLanguages(for: VisionTextRecognizer.languages, supported: supported)
        #expect(matched == [Locale.Language(identifier: "vi-VT"), Locale.Language(identifier: "en-US")])
        #expect(VisionTextRecognizer.recognitionLanguages(for: ["xx-YY", "vi-VN", "vi-VN"], supported: supported) == [Locale.Language(identifier: "vi-VT")])
    }

    @Test func fragmentsOnTheSameRowShareALineAndRowsReadTopToBottom() {
        let lines = VisionTextRecognizer.lines(from: [
            (text: "dưới", box: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.1)),
            (text: "phải", box: CGRect(x: 0.6, y: 0.51, width: 0.2, height: 0.1)),
            (text: "trái", box: CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.1)),
        ])
        #expect(lines == ["trái phải", "dưới"])
    }

    @Test func aMaskedPictureKeepsItsTransparencyWhenMadeIntoAnImage() throws {
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, 4, 2, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        let base = try #require(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
        for row in 0..<2 {
            for column in 0..<4 {
                let pixel = base + row * rowBytes + column * 4
                // Opaque red on the left half, clear on the right half (BGRA, premultiplied).
                (pixel[0], pixel[1], pixel[2], pixel[3]) = column < 2 ? (0, 0, 255, 255) : (0, 0, 0, 0)
            }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])

        let image = try #require(VisionForegroundCutter.cgImage(from: pixels))
        #expect(image.width == 4 && image.height == 2)
        let left = SyntheticFiles.pixel(of: image, x: 0, y: 0), right = SyntheticFiles.pixel(of: image, x: 3, y: 0)
        #expect(left.a == 255 && left.r > 240 && left.b < 15)
        #expect(right.a == 0)
    }

    @Test func visionReadsEnglishTextDrawnInCode() async throws {
        let text = try await VisionTextRecognizer().recognize(SyntheticFiles.textImage("Hello World 2026"), languages: VisionTextRecognizer.languages)
        // Not the whole string, which a newer Vision model might space or case differently.
        #expect(text.localizedCaseInsensitiveContains("hello") && text.contains("2026"))
    }

    @Test func visionReadsVietnameseWithItsAccents() async throws {
        let text = try await VisionTextRecognizer().recognize(SyntheticFiles.textImage("Xin chào Việt Nam 123"), languages: VisionTextRecognizer.languages)
        let normalised = text.precomposedStringWithCanonicalMapping
        #expect(normalised.localizedCaseInsensitiveContains("Việt") && normalised.localizedCaseInsensitiveContains("chào"))
    }

    @Test func visionFindsNoSubjectInAPlainPicture() async throws {
        await #expect(throws: FileActionError.noSubject) { try await VisionForegroundCutter().cutOut(SyntheticFiles.flat(width: 400, height: 300)) }
    }
}
