import Foundation

/// Turns what a parser found in a line, pieces of text with the times they were given, into the words of its karaoke.
/// Both sources go through it, so a word means the same whichever one it came from.
nonisolated enum LyricWordTiming {
    /// Text and the time it starts and ends, as far as the source said. nil `begin` is text nobody timed (a space between
    /// two spans); nil `end` is an end the source left out.
    struct Piece: Equatable, Sendable {
        var text: String
        var begin: Double?
        var end: Double?

        /// The same piece `seconds` later (earlier when negative), never before the start of the track.
        func shifted(by seconds: Double) -> Piece {
            Piece(text: text, begin: begin.map { max($0 + seconds, 0) }, end: end.map { max($0 + seconds, 0) })
        }
    }

    /// How long a last word with no end is sung, when nothing later says otherwise.
    static let lastWordDuration = 1.0

    /// The words of a line, nil when the pieces say nothing about words: none is timed, or the only one has a begin and
    /// nothing else (which the line's own time says already).
    ///
    /// Text nobody timed joins the word before it (the one after it at the start of the line), whitespace is collapsed
    /// and trimmed at both ends of the line, so the words joined read as the line. A word with no end ends where the next
    /// begins; the last one at `endsAt` (the line's end, when the source has it), else after `lastWordDuration` but not
    /// past `before` (where the next line starts). Words are kept in order and apart: one that begins before the previous
    /// one begins is raised to it, and one that begins before the previous one ends cuts it short.
    static func words(from pieces: [Piece], endsAt: Double? = nil, before: Double? = nil) -> [LyricWord]? {
        let timed = attachUntimedText(pieces)
        let words = normalised(timed)
        guard let last = words.last, words.count > 1 || last.end != nil || endsAt != nil else { return nil }
        return ordered(words, endsAt: endsAt, before: before)
    }

    private struct Timed {
        var text: String
        var begin: Double
        var end: Double?
    }

    private static func attachUntimedText(_ pieces: [Piece]) -> [Timed] {
        var timed: [Timed] = []
        var leading = ""
        for piece in pieces {
            if let begin = piece.begin {
                timed.append(Timed(text: leading + piece.text, begin: begin, end: piece.end))
                leading = ""
            } else if timed.isEmpty {
                leading += piece.text
            } else {
                timed[timed.count - 1].text += piece.text
            }
        }
        return timed
    }

    /// Whitespace runs are one space, never two in a row across words and none at the start or the end of the line; a word
    /// of nothing but space joins the one before it, or is dropped.
    private static func normalised(_ timed: [Timed]) -> [Timed] {
        var words: [Timed] = []
        var previousEndsWithSpace = true
        for item in timed {
            var text = collapsed(item.text)
            if previousEndsWithSpace, text.hasPrefix(" ") { text.removeFirst() }
            if text.isEmpty { continue }
            if text == " " {
                // Only here when the previous word does not end with a space.
                words[words.count - 1].text += " "
                previousEndsWithSpace = true
                continue
            }
            words.append(Timed(text: text, begin: item.begin, end: item.end))
            previousEndsWithSpace = text.hasSuffix(" ")
        }
        if let last = words.last, last.text.hasSuffix(" ") { words[words.count - 1].text.removeLast() }
        return words
    }

    private static func collapsed(_ text: String) -> String {
        var result = ""
        var inSpace = false
        for character in text {
            if character.isWhitespace {
                if !inSpace { result.append(" ") }
                inSpace = true
            } else {
                result.append(character)
                inSpace = false
            }
        }
        return result
    }

    private static func ordered(_ words: [Timed], endsAt: Double?, before: Double?) -> [LyricWord] {
        var result: [LyricWord] = []
        for (index, item) in words.enumerated() {
            var begin = item.begin
            if let previous = result.last { begin = max(begin, previous.begin) }
            var end: Double
            if let explicit = item.end {
                end = explicit
            } else if index + 1 < words.count {
                end = words[index + 1].begin
            } else {
                end = endsAt ?? min(begin + lastWordDuration, before ?? .infinity)
            }
            end = max(end, begin)
            if let previous = result.last { result[result.count - 1].end = min(previous.end, begin) }
            result.append(LyricWord(text: item.text, begin: begin, end: end))
        }
        return result
    }
}
