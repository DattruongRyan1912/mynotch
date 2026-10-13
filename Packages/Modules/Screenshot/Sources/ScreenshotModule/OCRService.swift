import CoreGraphics
import Foundation
import Vision

/// Recognises text in captures with Vision. Accurate recognition takes around a second, so it runs off the main actor.
nonisolated struct OCRService: Sendable {
    /// Vietnamese is only available at `.accurate`, which is the level used here.
    static let defaultLanguages = ["vi-VN", "en-US"]

    /// The text one visual line per line, top to bottom; "" when there is none. Unsupported `languages` (BCP 47)
    /// are skipped, and when none is supported Vision's default languages apply.
    @concurrent
    func recognize(_ image: CGImage, languages: [String]) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let matched = Self.recognitionLanguages(for: languages, supported: request.supportedRecognitionLanguages)
        if !matched.isEmpty { request.recognitionLanguages = matched }
        let observations = try await request.perform(on: Self.preparedForRecognition(image))
        let fragments = observations.compactMap { observation in
            observation.topCandidates(1).first.map { (text: $0.string, box: observation.boundingBox.cgRect) }
        }
        return Self.lines(from: fragments).joined(separator: "\n")
    }

    /// The languages Vision recognises at `.accurate`, by its own identifiers.
    static let supportedLanguages: [Locale.Language] = RecognizeTextRequest().supportedRecognitionLanguages

    /// The supported language for each requested identifier: an exact match, else one with the same language code
    /// (and the same script when the identifier names one, so Traditional Chinese is not read as Simplified),
    /// because Vision reports some languages under another region (Vietnamese is `vi-VT`, not `vi-VN`).
    static func recognitionLanguages(for identifiers: [String], supported: [Locale.Language]) -> [Locale.Language] {
        var matched: [Locale.Language] = []
        for identifier in identifiers {
            let requested = Locale.Language(identifier: identifier)
            guard let code = requested.languageCode else { continue }
            let candidates = supported.filter { $0.languageCode == code }
            guard let language = candidates.first(where: { $0 == requested })
                ?? candidates.first(where: { requested.script != nil && $0.script == requested.script })
                ?? candidates.first,
                !matched.contains(language) else { continue }
            matched.append(language)
        }
        return matched
    }

    /// Doubles images whose shorter side is under 600 px, because Vision misses small glyphs.
    static func preparedForRecognition(_ image: CGImage) -> CGImage {
        let width = image.width * 2, height = image.height * 2
        guard min(image.width, image.height) < 600,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// Text fragments grouped into lines, top to bottom. Boxes are Vision's normalised rects (origin bottom-left);
    /// fragments whose vertical centres are closer than half the shorter height share a line, read left to right
    /// and joined with a space, as words far apart on one line (a table row) belong together.
    static func lines(from fragments: [(text: String, box: CGRect)]) -> [String] {
        var lines: [[(text: String, box: CGRect)]] = []
        for fragment in fragments.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let first = lines.last?.first,
               abs(first.box.midY - fragment.box.midY) < min(first.box.height, fragment.box.height) / 2 {
                lines[lines.count - 1].append(fragment)
            } else {
                lines.append([fragment])
            }
        }
        return lines.map { line in line.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }
}
