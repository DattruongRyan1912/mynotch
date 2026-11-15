import Foundation

/// What the dictionary card shows for a word or short phrase: the headword, its part of speech when the entry names
/// one, and the first few senses, trimmed to fit a glance.
nonisolated struct DictionaryEntry: Equatable, Sendable {
    /// What was looked up, which is what Dictionary opens at.
    var term: String
    /// The entry's own spelling: "run" for "ran".
    var headword: String
    var partOfSpeech: String?
    var senses: [String]

    /// `dict://` is Dictionary's own scheme; the word is escaped so a space or an ampersand cannot cut it short.
    var dictionaryURL: URL? {
        term.addingPercentEncoding(withAllowedCharacters: Self.unreserved).flatMap { URL(string: "dict://\($0)") }
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}

/// Which selections get a dictionary card: one word or a short phrase, never a sentence, a number or a block of text.
nonisolated enum DictionaryQuery {
    static let maxWords = 3
    static let maxLength = 48

    /// The text to look up, without the quotes or full stop the selection may carry; nil when it is not a word or
    /// a short phrase.
    static func term(in text: String) -> String? {
        let edges = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
        let trimmed = text.trimmingCharacters(in: edges)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline), trimmed.contains(where: \.isLetter) else { return nil }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        let term = words.joined(separator: " ")
        guard words.count <= maxWords, term.count <= maxLength else { return nil }
        return term
    }
}
