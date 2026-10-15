import Foundation

/// How long a text is, in the units a person counts in: characters (an accented letter, or an emoji with its joiners, is one),
/// words (runs of anything that is not blank) and lines (a line break at the very end does not start another).
nonisolated struct ClipboardTextStats: Equatable, Sendable {
    let characters: Int
    let words: Int
    let lines: Int

    init(characters: Int, words: Int, lines: Int) {
        self.characters = characters
        self.words = words
        self.lines = lines
    }

    init(_ text: String) {
        characters = text.count
        words = text.split(whereSeparator: \.isWhitespace).count
        var lineCount = 0
        if !text.isEmpty {
            let parts = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            lineCount = parts.last?.isEmpty == true ? parts.count - 1 : parts.count
        }
        lines = lineCount
    }

    /// The same, off the main actor: counting a 2 MB copy takes long enough to be felt.
    @concurrent static func load(_ text: String) async -> ClipboardTextStats {
        ClipboardTextStats(text)
    }
}
