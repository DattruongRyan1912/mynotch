import Foundation

/// Turns what a browser reports for a video ("Artist - Song (Official Video)", channel "ArtistVEVO") into the
/// artist and song name lrclib knows. Pure text work; diacritics are kept.
nonisolated enum VideoTitleParser {
    /// Tracks longer than this are mixes or full albums, not songs lrclib has lyrics for.
    static let maximumSongSeconds = 15 * 60
    /// "Mix" in a title means a compilation only above this length: "Little Mix" and "(Original Mix)" are songs.
    static let minimumMixSeconds = 6 * 60

    /// What a bracketed group or a `|`-separated segment may consist of before it counts as noise
    /// ("(Official Video)", "[M/V]", "| OFFICIAL MUSIC VIDEO", "| Lyrics"). A group with other words stays,
    /// unless it starts with "Official" or "Prod." ("(Official Video Remastered)", "(Prod. by X)").
    private static let noiseStart = #"^(official|prod\.?|produced)\b"#
    private static let noiseWord = #"\b(official|music|video|mv|m/v|lyrics?|audio|visualizer|live|4k|hd|hq|clip|vietsub|engsub|upgrade|\d{3,4}p)\b"#
    private static let trailingNoise = #"(?i)[\s\-–—,:]*\b(official\s+(music\s+|lyric\s+)?(video|mv|m/v|audio)|music\s+video|lyrics?(\s+video)?|lyric\s+video|4k|hd|hq|mv|m/v|audio|visualizer)\s*$"#
    private static let brackets = #"\([^()]*\)|\[[^\[\]]*\]|【[^】]*】"#
    /// What splits "Artist - Song"; a title with one is worth cleaning even from a player that is no browser.
    static let separators = [" - ", " – ", " — "]
    private static let quotes = CharacterSet(charactersIn: "'\"‘’“”‚„`")

    /// The artist and song to look up. The channel stands in for the artist when the title has no "Artist - Song" shape.
    /// - Parameter splitsOnDash: false when the player reported an album, so `channel` is the real artist and a dash
    ///   belongs to the title ("Song - Remastered 2011"): only the noise goes, and the artist is kept as reported.
    static func parse(title: String, channel: String, splitsOnDash: Bool = true) -> (artist: String, title: String) {
        let cleaned = removeNoise(from: title)
        if splitsOnDash, let (left, right) = splitOnFirstSeparator(cleaned) {
            let artist = tidy(removeFeaturing(from: left))
            let song = tidy(removeFeaturing(from: right))
            if !artist.isEmpty, !song.isEmpty { return (artist, song) }
        }
        let artist = splitsOnDash ? cleanChannel(channel) : channel
        let segments = cleaned.split(whereSeparator: { "|｜∣".contains($0) }).map { tidy(String($0)) }.filter { !$0.isEmpty }
        // "SONG | ARTIST": the artist's own name is not part of the song.
        let rest = segments.filter { $0.compare(artist, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame }
        let song = tidy(removeFeaturing(from: (rest.isEmpty ? segments : rest).joined(separator: " | ")))
        return (artist, song.isEmpty ? tidy(title) : song)
    }

    /// True for what is no song: longer than 15 minutes, or a playlist, hour-long or non-stop compilation, or a mix
    /// (a word of its own or "megamix", so "Remix" and "Mixtape" are songs) that runs longer than 6 minutes.
    static func isLongOrMix(title: String, durationSeconds: Int) -> Bool {
        if durationSeconds > maximumSongSeconds { return true }
        if title.range(of: #"(?i)playlist|\b1\s*(hour|giờ)|non[\s-]?stop|tuyển tập"#, options: .regularExpression) != nil { return true }
        return durationSeconds > minimumMixSeconds && title.range(of: #"(?i)\b(mega)?mix(es)?\b"#, options: .regularExpression) != nil
    }

    // MARK: cleaning

    /// Bracketed noise, noise-only `|` segments and trailing noise words.
    private static func removeNoise(from title: String) -> String {
        var text = replacingMatches(of: brackets, in: title) { isNoiseOnly(String($0.dropFirst().dropLast())) }
        let segments = text.split(whereSeparator: { "|｜∣".contains($0) }).map { String($0) }
        let kept = segments.filter { !isNoiseOnly($0) }
        // Nothing but noise ("Live", "Audio"): the text is the song's name after all.
        if !kept.isEmpty { text = kept.joined(separator: " | ") }
        while let range = text.range(of: trailingNoise, options: .regularExpression), range.lowerBound > text.startIndex {
            text.removeSubrange(range)
        }
        // "Song (Official Video" leaves its opening bracket behind.
        text = text.replacingOccurrences(of: #"[\s(\[【]+$"#, with: "", options: .regularExpression)
        return tidy(text)
    }

    private static func isNoiseOnly(_ segment: String) -> Bool {
        let lowered = segment.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lowered.range(of: noiseStart, options: .regularExpression) != nil { return true }
        let rest = lowered.replacingOccurrences(of: noiseWord, with: "", options: .regularExpression)
        return !rest.contains { $0.isLetter || $0.isNumber }
    }

    /// Removes the matches of `pattern` that `shouldRemove` accepts, leaving a space in their place.
    private static func replacingMatches(of pattern: String, in text: String, where shouldRemove: (String) -> Bool) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed()
            where shouldRemove(result.substring(with: match.range)) {
            result = result.replacingCharacters(in: match.range, with: " ") as NSString
        }
        return result as String
    }

    /// "Song (feat. X)", "Song ft. X": everything from the featuring mark on goes.
    private static func removeFeaturing(from text: String) -> String {
        var result = text.replacingOccurrences(
            of: #"(?i)[\(\[]\s*(ft|feat|featuring)\b\.?[^\)\]]*[\)\]]"#, with: " ", options: .regularExpression
        )
        if let range = result.range(of: #"(?i)\s(ft|feat|featuring)\b\.?\s.*$"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result
    }

    private static func splitOnFirstSeparator(_ text: String) -> (String, String)? {
        let first = separators.compactMap { text.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
        guard let first else { return nil }
        return (String(text[..<first.lowerBound]), String(text[first.upperBound...]))
    }

    /// The channel without " - Topic", "VEVO", "Official" and "Music"; the channel as it is when nothing would be left.
    private static func cleanChannel(_ channel: String) -> String {
        var text = channel.replacingOccurrences(of: #"(?i)\s*-\s*topic\s*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)vevo"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)\b(official|music)\b"#, with: " ", options: .regularExpression)
        let cleaned = tidy(text)
        return cleaned.isEmpty ? tidy(channel) : cleaned
    }

    /// Collapses whitespace and trims leftovers: stray separators and quotes around the whole text.
    private static func tidy(_ text: String) -> String {
        var result = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let edge = CharacterSet(charactersIn: "-–—|｜,:;·").union(.whitespaces)
        result = result.trimmingCharacters(in: edge)
        if let first = result.unicodeScalars.first, let last = result.unicodeScalars.last, result.unicodeScalars.count > 1,
           quotes.contains(first), quotes.contains(last) {
            result = String(result.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}
