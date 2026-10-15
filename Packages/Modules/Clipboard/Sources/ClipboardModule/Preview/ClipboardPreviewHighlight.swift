import Foundation

/// The coloured stretches of a code text, in the units a text view counts in, from the same tokenizer and palette as the cards.
/// Bounded, so a big copy costs a bounded amount; what is past the bound is shown plain.
nonisolated enum ClipboardPreviewHighlight {
    struct Run: Equatable, Sendable {
        /// UTF-16, as `NSAttributedString` counts.
        let range: NSRange
        let kind: CodeTokenKind
    }

    /// How much of the start of a text is coloured. The cards colour 20 KB; a preview shows a whole screen of code and more.
    static let maxBytes = 100 * 1024

    /// The start of `text` of at most `maxBytes` bytes, cut between characters.
    static func bounded(_ text: String) -> String {
        guard text.utf8.count > maxBytes else { return text }
        var bytes = 0
        return String(text.unicodeScalars.prefix { scalar in
            bytes += UTF8.width(scalar)
            return bytes <= maxBytes
        })
    }

    /// The same, worked out off the main actor, for the preview of a text that is large.
    @concurrent static func runsOffMain(for text: String, language: CodeLanguage) async -> [Run] {
        runs(for: text, language: language)
    }

    static func runs(for text: String, language: CodeLanguage) -> [Run] {
        let part = bounded(text)
        let tokens = CodeTokenizer.tokens(in: part, language: language)
        guard !tokens.isEmpty else { return [] }
        // The tokens count UTF-8 bytes and are in order, so one walk over the characters finds every UTF-16 position.
        let scalars = part.unicodeScalars
        var position = scalars.startIndex
        var bytes = 0, units = 0
        func advance(to target: Int) -> Int {
            while bytes < target, position < scalars.endIndex {
                bytes += UTF8.width(scalars[position])
                units += UTF16.width(scalars[position])
                position = scalars.index(after: position)
            }
            return units
        }
        return tokens.map { token in
            let start = advance(to: token.range.lowerBound)
            let end = advance(to: token.range.upperBound)
            return Run(range: NSRange(location: start, length: end - start), kind: token.kind)
        }
    }
}
