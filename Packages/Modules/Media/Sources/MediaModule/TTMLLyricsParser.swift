import Foundation

/// Parses the TTML that Apple Music's lyrics endpoints send in `data[0].attributes.ttml`.
nonisolated enum TTMLLyricsParser {
    /// `.synced` for line and word timing, one line per paragraph, `.plain` for no timing; nil when the text is no TTML,
    /// is malformed, or holds no lyrics, which the caller treats as "not found".
    ///
    /// A paragraph's text is everything written in it, the spans of one word run together and the whitespace between
    /// words kept, so a word sung in syllables reads as one word. Background vocals, translations and transliterations
    /// are left out, and so is the head with its metadata (songwriters, translations).
    ///
    /// With word timing, a paragraph whose spans have a `begin` also has `words`: one per span, from its `begin` to its
    /// `end` (see `LyricWordTiming` for a missing end and for spans that overlap). Line timing has none.
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
        private var paragraphs: [Paragraph] = []
        private var isInHead = false
        private var isInParagraph = false
        private var begin: Double?
        private var end: Double?
        private var firstSpanBegin: Double?
        /// What the paragraph holds so far: the timed spans, and between them the text nobody timed.
        private var pieces: [LyricWordTiming.Piece] = []
        /// The timed span being read, as an index into `pieces`; its characters, nested spans' included, are the word's.
        private var openWord: Int?
        /// Spans open inside the timed one, itself included.
        private var timedDepth = 0
        /// Spans open inside an ignored one, itself included.
        private var ignoredDepth = 0
        private var sawRoot = false

        private struct Paragraph {
            var time: Double?
            var end: Double?
            var pieces: [LyricWordTiming.Piece]
            /// All its text, whitespace collapsed.
            var text: String
        }

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
                end = TTMLLyricsParser.seconds(attributes["end"])
                firstSpanBegin = nil
                pieces = []
                openWord = nil
                timedDepth = 0
            case "span" where isInParagraph:
                if ignoredDepth > 0 || TTMLLyricsParser.ignoredRoles.contains(attributes["ttm:role"] ?? "") {
                    ignoredDepth += 1
                } else if openWord != nil {
                    timedDepth += 1
                } else if let spanBegin = TTMLLyricsParser.seconds(attributes["begin"]) {
                    if firstSpanBegin == nil { firstSpanBegin = spanBegin }
                    pieces.append(LyricWordTiming.Piece(text: "", begin: spanBegin, end: TTMLLyricsParser.seconds(attributes["end"])))
                    openWord = pieces.count - 1
                    timedDepth = 1
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
                let text = pieces.map(\.text).joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
                paragraphs.append(Paragraph(time: begin ?? firstSpanBegin, end: end, pieces: pieces, text: text))
            case "span" where isInParagraph:
                if ignoredDepth > 0 {
                    ignoredDepth -= 1
                } else if openWord != nil {
                    timedDepth -= 1
                    if timedDepth == 0 { openWord = nil }
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            append(string)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            append(String(decoding: CDATABlock, as: UTF8.self))
        }

        private func append(_ string: String) {
            guard isInParagraph, ignoredDepth == 0 else { return }
            if let openWord {
                pieces[openWord].text += string
            } else if let last = pieces.indices.last, pieces[last].begin == nil {
                pieces[last].text += string
            } else {
                pieces.append(LyricWordTiming.Piece(text: string, begin: nil, end: nil))
            }
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
            let timed = withText.compactMap { paragraph in paragraph.time.map { (time: $0, paragraph: paragraph) } }
            // Equal times keep their order in the document.
            let sorted = timed.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element)
            // Spans are timed words unless the document says that only its lines are timed.
            let hasWords = timing?.lowercased() != "line"
            let lines = sorted.enumerated().map { index, entry in
                let next = index + 1 < sorted.count ? sorted[index + 1].time : nil
                return line(entry.paragraph, at: entry.time, before: next, hasWords: hasWords)
            }
            return lines.isEmpty ? nil : .synced(lines)
        }

        /// The paragraph as a line, with its words when it has them. They are its own text cut up: a paragraph whose words
        /// do not add up to it stays a line.
        private func line(_ paragraph: Paragraph, at time: Double, before next: Double?, hasWords: Bool) -> LyricLine {
            guard hasWords, let words = LyricWordTiming.words(from: paragraph.pieces, endsAt: paragraph.end, before: next),
                  words.map(\.text).joined() == paragraph.text else {
                return LyricLine(time: time, text: paragraph.text)
            }
            return LyricLine(time: time, text: paragraph.text, words: words)
        }
    }
}
