import Foundation

/// One line of synced lyrics, sung from `time` seconds into the track. Empty `text` marks a pause between lines.
nonisolated struct LyricLine: Equatable, Codable, Sendable {
    var time: Double
    var text: String
}

/// Parses LRC text, which is what lrclib's `syncedLyrics` holds: `[mm:ss.xx] text` lines.
nonisolated enum LRCParser {
    /// Lines sorted by time. A line with several stamps (`[00:12.00][00:45.00] chorus`) yields one entry per stamp,
    /// word stamps (`<00:12.00>`) are dropped, and lines that are not a stamp followed by text are skipped.
    ///
    /// `[offset:+500]` makes every line appear 500 ms sooner (the LRC convention); it counts wherever it is declared.
    static func parse(_ lrc: String) -> [LyricLine] {
        var entries: [LyricLine] = []
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
            guard !times.isEmpty else { continue }
            let text = withoutWordStamps(rest).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            entries += times.map { LyricLine(time: $0, text: text) }
        }
        let shift = Double(offsetMilliseconds ?? 0) / 1000
        return entries
            .enumerated()
            .map { (index: $0.offset, line: LyricLine(time: max($0.element.time - shift, 0), text: $0.element.text)) }
            // Equal times keep their order in the text.
            .sorted { ($0.line.time, $0.index) < ($1.line.time, $1.index) }
            .map(\.line)
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

    /// `text` without `<mm:ss.xx>` stamps; other angle brackets ("I <3 you") stay.
    private static func withoutWordStamps(_ text: Substring) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "<", let close = text[index...].firstIndex(of: ">"),
               timestamp(text[text.index(after: index)..<close]) != nil {
                index = text.index(after: close)
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }
        return result
    }
}

extension Array where Element == LyricLine {
    /// The line being sung at `seconds`: the last one that started at or before it, found by binary search.
    /// nil before the first line. Needs the order `LRCParser.parse` gives.
    func line(at seconds: Double) -> LyricLine? {
        var low = 0
        var high = count
        // `low` ends as the first index whose line starts after `seconds`.
        while low < high {
            let middle = (low + high) / 2
            if self[middle].time <= seconds { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? self[low - 1] : nil
    }
}
