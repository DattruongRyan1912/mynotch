import Foundation

/// Turns Dictionary Services' flat paragraph into a card. The New Oxford American Dictionary, which a Mac has, writes
/// `headword | pronunciation | part of speech 1 sense: example. • sub-sense 2 sense ... ORIGIN ...`; another
/// dictionary's answer, without that shape, is still shown, trimmed, under the word that was looked up.
nonisolated enum DictionaryParser {
    static let maxSenses = 3
    static let maxSenseLength = 90

    private static let partsOfSpeech = [
        "modal verb", "auxiliary verb", "combining form", "noun", "verb", "adjective", "adverb", "pronoun", "preposition",
        "conjunction", "exclamation", "interjection", "determiner", "abbreviation", "prefix", "suffix", "symbol", "contraction",
    ]
    private static let partOfSpeech = partsOfSpeech.joined(separator: "|")
    /// What follows the senses: where a card has nothing more to take.
    private static let trailingSections = "ORIGIN|PHRASES|PHRASAL VERBS|DERIVATIVES|USAGE|ETYMOLOGY"
    /// Notes on how a word is inflected, which come before the senses and say nothing about them.
    private static let inflection = "pl\\.|plural|also|pres\\.|past|comparative|superlative|Brit\\.|N\\. Amer\\.|US"

    private static let junk = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".;:,"))

    static func entry(from definition: String, for term: String) -> DictionaryEntry? {
        let text = flatten(definition)
        guard !text.isEmpty else { return nil }
        let (headword, rest) = split(text)
        var body = rest.trimmingCharacters(in: junk)
        body = cut(body, atHomographOf: headword)
        body = cut(body, atFirst: "(?<!\\p{L})(?:\(trailingSections))(?!\\p{L})", options: [])
        let part = takePartOfSpeech(from: &body)
        body = cut(body, atFirst: "(?:^|\\s)(?:\(partOfSpeech))\\s+(?:\\(|\\[|\\d)", options: [])
        body = cut(body, atFirst: "[.!?;]\\s+(?:\(partOfSpeech))\\s+\\p{Ll}", options: [])
        let senses = senses(in: body)
        guard !senses.isEmpty else { return nil }
        return DictionaryEntry(term: term, headword: headword.isEmpty ? term : headword, partOfSpeech: part, senses: senses)
    }

    /// At most `limit` characters, cut at a word when there is one to cut at, with an ellipsis when something was left out.
    static func trimmed(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        var kept = String(text.prefix(limit))
        let cutsAtAWord = text[text.index(text.startIndex, offsetBy: limit)] == " "
        if !cutsAtAWord, let space = kept.lastIndex(of: " ") { kept = String(kept[..<space]) }
        return kept.trimmingCharacters(in: junk) + "…"
    }

    /// One line of words: a line break ends a sense or a heading, which the rules below read as a full stop.
    private static func flatten(_ definition: String) -> String {
        let lines = definition.split(whereSeparator: \.isNewline).map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        var text = ""
        for line in lines where !line.isEmpty {
            if let last = text.last { text += ".;:,|!?".contains(last) ? " " : ". " }
            text += line
        }
        return text
    }

    /// The headword before the first bar and everything after the pronunciation between the first two. Without bars
    /// there is no headword to read.
    private static func split(_ text: String) -> (headword: String, rest: String) {
        guard let first = text.firstIndex(of: "|") else { return ("", text) }
        let headword = text[..<first].trimmingCharacters(in: .whitespaces)
        let afterFirst = text[text.index(after: first)...]
        guard let second = afterFirst.firstIndex(of: "|") else { return (headword, String(afterFirst)) }
        return (headword, String(afterFirst[afterFirst.index(after: second)...]))
    }

    /// An entry of the same spelling further on is another word (a homograph), not more senses of this one.
    private static func cut(_ text: String, atHomographOf headword: String) -> String {
        guard !headword.isEmpty else { return text }
        let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: headword))\\s*\\|"
        return cut(text, atFirst: pattern, options: .caseInsensitive)
    }

    private static func cut(_ text: String, atFirst pattern: String, options: NSRegularExpression.Options) -> String {
        guard let match = firstMatch(pattern, in: text, options: options), let range = Range(match.range, in: text) else { return text }
        return String(text[..<range.lowerBound]).trimmingCharacters(in: junk)
    }

    /// The part of speech the body starts with, if any, behind notes like "(also hallo, hullo)"; removed from `body`.
    private static func takePartOfSpeech(from body: inout String) -> String? {
        guard let match = firstMatch("^(?:\\([^)]*\\)\\s*)*(\(partOfSpeech))\\b", in: body, options: .caseInsensitive),
              let name = Range(match.range(at: 1), in: body), let whole = Range(match.range, in: body) else { return nil }
        let part = body[name].lowercased()
        body = String(body[whole.upperBound...]).trimmingCharacters(in: junk)
        return part
    }

    /// Numbered senses when the body opens with "1" (after notes like "(runs, running, ran)"), else the whole body as one.
    private static func senses(in body: String) -> [String] {
        let afterNotes = body.replacingOccurrences(of: "^(?:\\([^)]*\\)\\s*)*", with: "", options: .regularExpression)
        let segments: [String]
        if afterNotes.hasPrefix("1 ") {
            segments = numberedSegments(of: afterNotes)
        } else {
            segments = [dropInflection(from: body)]
        }
        return Array(segments.compactMap(sense(from:)).prefix(maxSenses))
    }

    /// The text of sense 1, 2, 3 ... in turn; a number inside a sense ("in 1990") is not the next sense's.
    private static func numberedSegments(of text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?<!\\S)(\\d{1,2})(?!\\S)") else { return [text] }
        var starts: [(marker: Range<String.Index>, number: Int)] = []
        var expected = 1
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), Int(text[range]) == expected else { continue }
            starts.append((range, expected))
            expected += 1
        }
        return starts.enumerated().map { index, start in
            let end = index + 1 < starts.count ? starts[index + 1].marker.lowerBound : text.endIndex
            return String(text[start.marker.upperBound..<end])
        }
    }

    private static func dropInflection(from text: String) -> String {
        var text = text
        while let range = text.range(of: "^\\((?:\(inflection))[^)]*\\)\\s*", options: .regularExpression) {
            text.removeSubrange(range)
        }
        return text
    }

    /// One sense for the card: without its sub-senses, grammar notes and example, capitalised and short.
    private static func sense(from segment: String) -> String? {
        var text = segment
        if let bullet = text.firstIndex(of: "•") { text = String(text[..<bullet]) }
        text = text.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let colon = text.range(of: ": "), text.distance(from: text.startIndex, to: colon.lowerBound) >= 8 {
            text = String(text[..<colon.lowerBound])
        }
        text = text.trimmingCharacters(in: junk)
        guard let first = text.first else { return nil }
        return trimmed(first.uppercased() + text.dropFirst(), to: maxSenseLength)
    }

    private static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options) -> NSTextCheckingResult? {
        try? NSRegularExpression(pattern: pattern, options: options)
            .firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
