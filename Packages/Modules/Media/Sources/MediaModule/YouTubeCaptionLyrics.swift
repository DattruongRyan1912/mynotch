import YouTubeBridgeKit

/// Turns the caption events of a YouTube video into synced lyric lines.
nonisolated enum YouTubeCaptionLyrics {
    /// A silence longer than this after a caption blanks the lyric row, as a gap between lyrics does.
    static let pauseGap = 5.0

    private static let musicNotes: Set<Character> = ["♪", "♫", "♬", "♩", "🎵", "🎶"]

    /// One line per event, at its start. An event that is only a marker ("[Music]", "[Âm nhạc]", "♪") is a blank line, and
    /// a blank line also follows an event whose end is more than `pauseGap` before the next one, or that is the last,
    /// so a caption does not stay up through the silence after it. Events must be sorted by time.
    static func lines(from events: [CaptionEvent]) -> [LyricLine] {
        var lines: [LyricLine] = []
        for (index, event) in events.enumerated() {
            lines.append(LyricLine(time: event.time, text: isMarker(event.text) ? "" : event.text))
            // Without a duration the end is unknown, so no pause is guessed.
            guard event.duration > 0, lines.last?.text.isEmpty == false else { continue }
            let end = event.time + event.duration
            if index == events.count - 1 || events[index + 1].time - end > pauseGap {
                lines.append(LyricLine(time: end, text: ""))
            }
        }
        return lines
    }

    /// Nothing but bracketed notes ("[Music]", "[Music] [Applause]") and music symbols.
    static func isMarker(_ text: String) -> Bool {
        var isInBrackets = false
        var hasMarker = false
        for character in text {
            if isInBrackets {
                if character == "[" { return false }
                if character == "]" {
                    isInBrackets = false
                    hasMarker = true
                }
            } else if character == "[" {
                isInBrackets = true
            } else if musicNotes.contains(character) {
                hasMarker = true
            } else if character == "]" || !character.isWhitespace {
                return false
            }
        }
        return hasMarker && !isInBrackets
    }
}
