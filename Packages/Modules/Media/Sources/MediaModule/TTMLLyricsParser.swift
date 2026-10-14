import Foundation

/// Parses the TTML that Apple Music's lyrics endpoints send in `data[0].attributes.ttml`.
nonisolated enum TTMLLyricsParser {
    /// `.synced` for line and word timing, one line per paragraph, `.plain` for no timing; nil when the text is no TTML,
    /// is malformed, or holds no lyrics, which the caller treats as "not found".
    ///
    /// A paragraph's text is everything written in it, the spans of one word run together and the whitespace between
    /// words kept, so a word sung in syllables reads as one word. Background vocals, translations and transliterations
    /// are left out, and so is the head with its metadata (songwriters, translations).
    static func parse(_ ttml: String) -> LyricsResult? {
        let reader = Reader()
        let parser = XMLParser(data: Data(ttml.utf8))
        parser.delegate = reader
        guard parser.parse(), reader.isTTML else { return nil }
        return reader.result
    }

    /// Seconds from a TTML time: `12.345`, `1:02.345`, `01:02:03.456` or `12.3s`. Digits after the milliseconds are dropped.
    static func seconds(_ text: String?) -> Double? {
        guard var text = text else { return nil }
        if text.hasSuffix("s") { text.removeLast() }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        let secondParts = parts[parts.count - 1].split(separator: ".", omittingEmptySubsequences: false)
        guard secondParts.count <= 2, let whole = number(secondParts[0]) else { return nil }
        var milliseconds = 0
        if secondParts.count == 2 {
            guard number(secondParts[1]) != nil else { return nil }
            milliseconds = Int(String(secondParts[1].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0))!
        }
        var seconds = 0
        for part in parts.dropLast() {
            guard let value = number(part) else { return nil }
            seconds = seconds * 60 + value
        }
        return Double((seconds * 60 + whole) * 1000 + milliseconds) / 1000
    }

    private static func number(_ text: Substring) -> Int? {
        guard (1...9).contains(text.count), text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(text)
    }

    /// Spans that are not the sung words of the line.
    private static let ignoredRoles: Set<String> = ["x-bg", "x-translation", "x-roman"]

    private final class Reader: NSObject, XMLParserDelegate {
        private(set) var isTTML = false
        private var timing: String?
        private var paragraphs: [(time: Double?, text: String)] = []
        private var isInHead = false
        private var isInParagraph = false
        private var begin: Double?
        private var firstSpanBegin: Double?
        private var text = ""
        /// Spans open inside an ignored one, itself included.
        private var ignoredDepth = 0
        private var sawRoot = false

        func parser(
            _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
            attributes: [String: String]
        ) {
            if !sawRoot {
                sawRoot = true
                isTTML = name == "tt"
                timing = attributes["itunes:timing"]
            }
            switch name {
            case "head":
                isInHead = true
            case "p" where !isInHead && !isInParagraph:
                isInParagraph = true
                begin = TTMLLyricsParser.seconds(attributes["begin"])
                firstSpanBegin = nil
                text = ""
            case "span" where isInParagraph:
                if ignoredDepth > 0 || TTMLLyricsParser.ignoredRoles.contains(attributes["ttm:role"] ?? "") {
                    ignoredDepth += 1
                } else if firstSpanBegin == nil {
                    firstSpanBegin = TTMLLyricsParser.seconds(attributes["begin"])
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "head":
                isInHead = false
            case "p" where isInParagraph:
                isInParagraph = false
                // Whitespace collapsed like a renderer would, and like the LRC parser does.
                let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                paragraphs.append((begin ?? firstSpanBegin, words))
            case "span" where isInParagraph && ignoredDepth > 0:
                ignoredDepth -= 1
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if isInParagraph && ignoredDepth == 0 { text += string }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if isInParagraph && ignoredDepth == 0 { text += String(decoding: CDATABlock, as: UTF8.self) }
        }

        /// The lyrics, or nil when there are none. Timing "None" is plain text, "Line" and "Word" (any case) are synced;
        /// without the attribute, timed paragraphs make it synced.
        var result: LyricsResult? {
            let withText = paragraphs.filter { !$0.text.isEmpty }
            let isSynced: Bool
            switch timing?.lowercased() {
            case "none": isSynced = false
            case "line", "word": isSynced = true
            default: isSynced = withText.contains { $0.time != nil }
            }
            guard isSynced else {
                let plain = withText.map(\.text).joined(separator: "\n")
                return plain.isEmpty ? nil : .plain(plain)
            }
            let lines = withText.compactMap { paragraph in paragraph.time.map { LyricLine(time: $0, text: paragraph.text) } }
            // Equal times keep their order in the document.
            let sorted = lines.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element)
            return sorted.isEmpty ? nil : .synced(sorted)
        }
    }
}
