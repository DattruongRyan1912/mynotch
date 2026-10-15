import Foundation

nonisolated enum CodeTokenKind: Sendable, Hashable {
    case keyword, string, comment, number, punctuation
}

/// One coloured stretch of a text. What lies between tokens (names, spaces, line breaks) has no colour of its own.
nonisolated struct CodeToken: Equatable, Sendable {
    let kind: CodeTokenKind
    /// UTF-8 offsets into the text, always on character boundaries.
    let range: Range<Int>
}

/// Splits code into coloured tokens with a small scanner per language family: no grammar, so it never fails and never
/// waits; a construct it does not know is simply left plain. Reads each byte about once, so a 20 KB text takes a
/// fraction of a millisecond.
nonisolated enum CodeTokenizer {
    static func tokens(in text: String, language: CodeLanguage) -> [CodeToken] {
        var text = text
        return text.withUTF8 { bytes in
            switch language {
            case .xml: return MarkupScanner.xml(bytes)
            case .markdown: return MarkupScanner.markdown(bytes)
            default:
                var scanner = CodeScanner(bytes: bytes, syntax: CodeSyntax.of(language))
                return scanner.run()
            }
        }
    }
}
