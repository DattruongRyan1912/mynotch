import Foundation

/// Parses LRC text, which is what lrclib's `syncedLyrics` holds: `[mm:ss.xx] text` lines.
nonisolated enum LRCParser {
    /// Lines sorted by time. A line with several stamps (`[00:12.00][00:45.00] chorus`) yields one entry per stamp, and
    /// lines that are not a stamp followed by text are skipped.
    ///
    /// Enhanced LRC has a word stamp before each word (`<00:12.00>Hello <00:12.50>world <00:13.00>`): the line then has
    /// `words`, each from its stamp to the next (see `LyricWordTiming` for what is left out). A line with several stamps
    /// repeats the words of the first at each of them. Lines without word stamps are timed as a whole.
    ///
    /// `[offset:+500]` makes every line appear 500 ms sooner (the LRC convention); it counts wherever it is declared.
    static func parse(_ lrc: String) -> [LyricLine] {
        var entries: [Entry] = []
        var offsetMilliseconds: Int?
        for rawLine in lrc.split(whereSeparator: \.isNewline) {
            var rest = rawLine.drop(while: \.isWhitespace)
            var times: [Double] = []
            // Only leading tags count, so `[Chorus]` in the lyric itself stays text.
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                guard let time = timestamp(tag) else {
                    if times.isEmpty, offsetMilliseconds == nil { offsetMilliseconds = offset(tag) }
                    break
                }
                times.append(time)
                rest = rest[rest.index(after: close)...]
            }
            guard let first = times.first else { continue }
            let (pieces, hasWordStamps) = splitAtWordStamps(rest, lineStart: first)
            let text = pieces.map(\.text).joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            entries += times.map { time in
                Entry(time: time, text: text, pieces: hasWordStamps ? pieces.map { $0.shifted(by: time - first) } : [])
            }
        }
        let shift = Double(offsetMilliseconds ?? 0) / 1000
        let sorted = entries
            .enumerated()
            .map { (index: $0.offset, entry: $0.element.shifted(by: -shift)) }
            // Equal times keep their order in the text.
            .sorted { ($0.entry.time, $0.index) < ($1.entry.time, $1.index) }
            .map(\.entry)
        return sorted.enumerated().map { index, entry in
            let next = index + 1 < sorted.count ? sorted[index + 1].time : nil
            return entry.line(before: next)
        }
    }

    /// A line as read, before its words are worked out: they need the time the next line starts.
    private nonisolated struct Entry {
        var time: Double
        var text: String
        /// Empty for a line with no word stamps.
        var pieces: [LyricWordTiming.Piece]

        func shifted(by seconds: Double) -> Entry {
            Entry(time: max(time + seconds, 0), text: text, pieces: pieces.map { $0.shifted(by: seconds) })
        }

        func line(before next: Double?) -> LyricLine {
            // The words are the line's own text, cut up: a line they do not add up to stays a line.
            guard let words = LyricWordTiming.words(from: pieces, before: next), words.map(\.text).joined() == text else {
                return LyricLine(time: time, text: text)
            }
            return LyricLine(time: time, text: text, words: words)
        }
    }

    /// `mm:ss`, `mm:ss.x`, `mm:ss.xx` or `mm:ss.xxx` in seconds. Whole milliseconds first, so `05.05` is exactly 5.05.
    private static func timestamp(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let secondParts = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard secondParts.count <= 2,
              let minutes = number(parts[0], maxDigits: 4),
              let seconds = number(secondParts[0], maxDigits: 2), seconds < 60 else { return nil }
        var fraction = 0
        if secondParts.count == 2 {
            guard let digits = number(secondParts[1], maxDigits: 3) else { return nil }
            fraction = digits * Int(pow(10, Double(3 - secondParts[1].count)))
        }
        return Double((minutes * 60 + seconds) * 1000 + fraction) / 1000
    }

    /// The value of an `offset:` tag in milliseconds, nil for any other tag.
    private static func offset(_ tag: Substring) -> Int? {
        guard let colon = tag.firstIndex(of: ":"), tag[..<colon].lowercased() == "offset" else { return nil }
        return Int(tag[tag.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    }

    private static func number(_ text: Substring, maxDigits: Int) -> Int? {
        guard (1...maxDigits).contains(text.count), text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(text)
    }

    /// `text` cut at its `<mm:ss.xx>` stamps, which are no part of it; other angle brackets ("I <3 you") stay. A stamp is
    /// when the text after it starts and when the text before it ends; text before the first stamp starts with the line.
    private static func splitAtWordStamps(_ text: Substring, lineStart: Double) -> (pieces: [LyricWordTiming.Piece], hasStamps: Bool) {
        var pieces: [LyricWordTiming.Piece] = []
        var current = ""
        var begin = lineStart
        var hasStamps = false
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "<", let close = text[index...].firstIndex(of: ">"),
               let stamp = timestamp(text[text.index(after: index)..<close]) {
                if !current.isEmpty { pieces.append(LyricWordTiming.Piece(text: current, begin: begin, end: stamp)) }
                current = ""
                begin = stamp
                hasStamps = true
                index = text.index(after: close)
            } else {
                current.append(text[index])
                index = text.index(after: index)
            }
        }
        if !current.isEmpty { pieces.append(LyricWordTiming.Piece(text: current, begin: begin, end: nil)) }
        return (pieces, hasStamps)
    }
}

extension Array where Element == LyricLine {
    /// The line being sung at `seconds`: the last one that started at or before it, found by binary search.
    /// nil before the first line. Needs the order `LRCParser.parse` gives.
    func line(at seconds: Double) -> LyricLine? {
        indexOfLine(at: seconds).map { self[$0] }
    }

    /// The line being sung at `seconds` (as `line(at:)`: nil before the first line, an empty one during a pause) and
    /// the next line with words after it, which skips pauses. `next` is nil after the last line with words.
    func lines(around seconds: Double) -> (current: LyricLine?, next: LyricLine?) {
        let index = indexOfLine(at: seconds)
        let upcoming = self[(index.map { $0 + 1 } ?? 0)...]
        return (index.map { self[$0] }, upcoming.first { !$0.text.isEmpty })
    }

    /// The index of the line `line(at:)` finds.
    nonisolated func indexOfLine(at seconds: Double) -> Int? {
        var low = 0
        var high = count
        // `low` ends as the first index whose line starts after `seconds`.
        while low < high {
            let middle = (low + high) / 2
            if self[middle].time <= seconds { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? low - 1 : nil
    }
}
