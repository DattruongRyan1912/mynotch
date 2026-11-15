import Foundation

/// One subtitle of a film: shown from `start` to `end` seconds into the video.
nonisolated struct SubtitleCue: Equatable, Codable, Sendable {
    var start: Double
    var end: Double
    var text: String
}

/// Reads SRT and WebVTT files, which share their cue shape: a timing line "start --> end" and the cue's text lines under it,
/// up to a blank line.
nonisolated enum SubtitleParser {
    /// A gap shorter than this between a cue's end and the next cue's start is no gap: the line stays up until the next.
    static let gapTolerance = 0.05

    /// The cues of a file in any of the encodings subtitles come in, nil when it holds none.
    static func cues(from data: Data) -> [SubtitleCue]? {
        guard let text = decode(data) else { return nil }
        let cues = cues(from: text)
        return cues.isEmpty ? nil : cues
    }

    /// The cues sorted by start. A cue whose times do not read or that has no text is left out.
    static func cues(from text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).makeIterator()
        while let line = lines.next() {
            guard let (start, end) = timing(line) else { continue }
            var parts: [String] = []
            while let next = lines.next(), !next.trimmingCharacters(in: .whitespaces).isEmpty {
                parts.append(String(next))
            }
            let text = clean(parts.joined(separator: " "))
            if !text.isEmpty { cues.append(SubtitleCue(start: start, end: max(end, start), text: text)) }
        }
        // A stable sort, so cues at one time keep the file's order.
        return cues.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element)
    }

    /// One line per cue at its start, moved by `delay` (positive: later), and a blank line at a cue's end when the next one
    /// does not follow right away, so a subtitle does not stay up through the silence after it.
    static func lines(from cues: [SubtitleCue], delay: Double) -> [LyricLine] {
        lines(from: cues, delays: cues.map { _ in delay })
    }

    /// The same, each cue moved by the delay of the part of the video it falls in.
    @MainActor static func lines(for entry: SubtitleBook.Entry) -> [LyricLine] {
        lines(from: entry.cues, delays: entry.cues.map { entry.delay(for: $0) })
    }

    private static func lines(from cues: [SubtitleCue], delays: [Double]) -> [LyricLine] {
        var lines: [LyricLine] = []
        for (index, cue) in cues.enumerated() {
            lines.append(LyricLine(time: cue.start + delays[index], text: cue.text))
            if index == cues.count - 1 || (cues[index + 1].start + delays[index + 1]) - (cue.end + delays[index]) > gapTolerance {
                lines.append(LyricLine(time: cue.end + delays[index], text: ""))
            }
        }
        // Where a later part starts sooner than the one before ends, the lines are put back in order.
        return lines.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element)
    }

    // MARK: -

    /// "00:01:11,640 --> 00:01:14,530", with "." or "," before the milliseconds, hours left out (WebVTT) and cue settings after.
    private static func timing(_ line: Substring) -> (Double, Double)? {
        let sides = line.components(separatedBy: "-->")
        guard sides.count == 2,
              let start = seconds(sides[0].trimmingCharacters(in: .whitespaces)),
              let endField = sides[1].split(whereSeparator: \.isWhitespace).first,
              let end = seconds(String(endField)) else { return nil }
        return (start, end)
    }

    private static func seconds(_ field: String) -> Double? {
        let parts = field.replacingOccurrences(of: ",", with: ".").split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// Without the HTML-like tags (<i>, <font …>) and the ASS overrides ({\an8}) players put in subtitles, and with runs of spaces as one.
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Unicode with a byte order mark, else UTF-8, else the Windows code page for Vietnamese and then for Western languages,
    /// which is what subtitles that are not Unicode are mostly written in.
    private static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16) }
        if let text = String(data: data, encoding: .utf8) { return text }
        let vietnamese = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsVietnamese.rawValue))
        )
        return String(data: data, encoding: vietnamese) ?? String(data: data, encoding: .windowsCP1252)
    }
}
