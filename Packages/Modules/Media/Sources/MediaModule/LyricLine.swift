import Foundation

/// One word, or one syllable of a word, of a line: sung from `begin` to `end` seconds into the track.
nonisolated struct LyricWord: Equatable, Codable, Sendable {
    /// Its characters, with the space that follows it when there is one, so that the words of a line read as the line.
    var text: String
    var begin: Double
    var end: Double

    /// How much of the word is sung at `position`, 0…1: nothing before `begin`, all of it from `end`, and evenly
    /// between. A word with no length is sung in an instant.
    func progress(at position: Double) -> Double {
        guard !position.isNaN else { return 0 }
        guard end > begin else { return position >= begin ? 1 : 0 }
        return min(max((position - begin) / (end - begin), 0), 1)
    }
}

/// One line of synced lyrics, sung from `time` seconds into the track. Empty `text` marks a pause between lines.
nonisolated struct LyricLine: Equatable, Codable, Sendable {
    var time: Double
    var text: String
    /// When the words are timed too (Apple Music's syllable lyrics, enhanced LRC): in order, never overlapping, and
    /// their texts joined are `text`. nil for a line that is timed as a whole, which is then shown as it always was.
    var words: [LyricWord]?

    init(time: Double, text: String, words: [LyricWord]? = nil) {
        self.time = time
        self.text = text
        self.words = words
    }

    /// A line made of its words: its text is theirs joined.
    init(time: Double, words: [LyricWord]) {
        self.init(time: time, text: words.map(\.text).joined(), words: words)
    }
}
