import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct OCRServiceTests {
    static let vietnamese = "Xin chào thế giới — Tiếng Việt có dấu"
    static let english = "Hello OCR 2026"

    /// Black text on white drawn with CoreText at `pointSize` on a `scale`× bitmap: one line per entry, whose
    /// fragments start 700 pt apart.
    static func render(_ lines: [[String]], pointSize: CGFloat = 32, scale: CGFloat = 2, minimumPixelHeight: Int = 0) throws -> CGImage {
        let lineHeight = pointSize * 2 * scale
        let columns = CGFloat(lines.map(\.count).max() ?? 1)
        let width = Int((200 + 700 * columns) * scale)
        let height = max(Int(lineHeight * CGFloat(lines.count + 1)), minimumPixelHeight)
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateUIFontForLanguage(.system, pointSize * scale, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): try #require(font),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        for (row, fragments) in lines.enumerated() {
            for (column, text) in fragments.enumerated() {
                context.textPosition = CGPoint(x: (40 + 700 * CGFloat(column)) * scale, y: CGFloat(height) - lineHeight * CGFloat(row + 1))
                CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
            }
        }
        return try #require(context.makeImage())
    }

    static func blank(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// Collapses whitespace and folds dashes: Vision reads the em dash as "-", while letters and diacritics stay exact.
    static func normalised(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "—", with: "-").replacingOccurrences(of: "–", with: "-")
    }

    @Test func recognisesVietnameseAndEnglishText() async throws {
        let text = try await OCRService().recognize(Self.render([[Self.vietnamese], [Self.english]]), languages: OCRService.defaultLanguages)
        #expect(Self.normalised(text).contains(Self.normalised(Self.vietnamese)))
        #expect(Self.normalised(text).contains(Self.english))
        #expect(text.split(separator: "\n").count == 2)
    }

    @Test func recognisesTextInSmallImages() async throws {
        let image = try Self.render([[Self.english]], pointSize: 14, scale: 1)
        #expect(min(image.width, image.height) < 600)
        let text = try await OCRService().recognize(image, languages: ["en-US"])
        #expect(Self.normalised(text).contains(Self.english))
    }

    @Test func recognisesLargeImagesWithoutUpscaling() async throws {
        let image = try Self.render([[Self.english]], minimumPixelHeight: 600)
        #expect(OCRService.preparedForRecognition(image) === image)
        let text = try await OCRService().recognize(image, languages: ["en-US"])
        #expect(Self.normalised(text) == Self.english)
    }

    @Test func joinsWordsOnOneLineWithASpace() async throws {
        let text = try await OCRService().recognize(Self.render([["Hello", "World"], [Self.english]]), languages: ["en-US"])
        #expect(text.components(separatedBy: "\n").map(Self.normalised) == ["Hello World", Self.english])
    }

    @Test func blankImageHasNoText() async throws {
        #expect(try await OCRService().recognize(Self.blank(width: 800, height: 300), languages: OCRService.defaultLanguages) == "")
    }

    @Test func unsupportedLanguagesAreSkipped() async throws {
        let text = try await OCRService().recognize(Self.render([[Self.english]]), languages: ["xx-YY", "en-US"])
        #expect(Self.normalised(text).contains(Self.english))
        let fallback = try await OCRService().recognize(Self.render([[Self.english]]), languages: ["xx-YY"])
        #expect(Self.normalised(fallback).contains(Self.english))
    }

    @Test func matchesLanguagesByLanguageCode() {
        let supported = ["en-US", "fr-FR", "vi-VT", "zh-Hans", "zh-Hant"].map(Locale.Language.init(identifier:))
        let matched = OCRService.recognitionLanguages(for: ["vi-VN", "en-US", "xx-YY", "zh-Hant", "en-GB", ""], supported: supported)
        #expect(matched == ["vi-VT", "en-US", "zh-Hant"].map(Locale.Language.init(identifier:)))
    }

    @Test func upscalesImagesWithAShortSideUnder600Pixels() throws {
        let small = OCRService.preparedForRecognition(try Self.blank(width: 1000, height: 599))
        #expect((small.width, small.height) == (2000, 1198))
        let large = try Self.blank(width: 700, height: 600)
        #expect(OCRService.preparedForRecognition(large) === large)
    }

    @Test func groupsFragmentsIntoLinesTopToBottom() {
        // Vision boxes are normalised with the origin at the bottom-left.
        let fragments: [(text: String, box: CGRect)] = [
            ("third", CGRect(x: 0.1, y: 0.10, width: 0.3, height: 0.1)),
            ("second", CGRect(x: 0.1, y: 0.40, width: 0.3, height: 0.1)),
            ("first right", CGRect(x: 0.6, y: 0.72, width: 0.3, height: 0.1)),
            ("first left", CGRect(x: 0.1, y: 0.70, width: 0.3, height: 0.1)),
        ]
        #expect(OCRService.lines(from: fragments) == ["first left first right", "second", "third"])
    }
}
