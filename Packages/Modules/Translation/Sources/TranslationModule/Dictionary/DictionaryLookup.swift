import AppKit
import CoreServices
import Foundation

/// Where definitions come from: the Mac's Dictionary Services, which reads the dictionaries on the disk and sends nothing
/// anywhere. A protocol so tests use a fake and never depend on which dictionaries a Mac has.
nonisolated protocol DictionaryLooking: Sendable {
    /// The dictionaries' answer for `term`, or nil when none of them has one (or none is installed).
    func definition(of term: String) async -> String?
}

/// `DCSCopyTextDefinition` over every dictionary the user has on. It reads its index from disk the first time, so it
/// runs off the main actor.
nonisolated struct SystemDictionary: DictionaryLooking {
    func definition(of term: String) async -> String? {
        await Self.lookUp(term)
    }

    @concurrent private static func lookUp(_ term: String) async -> String? {
        let range = CFRange(location: 0, length: (term as NSString).length)
        return DCSCopyTextDefinition(nil, term as CFString, range)?.takeRetainedValue() as String?
    }
}

/// The dictionary card's source: asks only for a word or a short phrase, and keeps an answer only when it is about that.
nonisolated struct DictionaryFinder: Sendable {
    private let source: any DictionaryLooking

    init(_ source: any DictionaryLooking) {
        self.source = source
    }

    /// The entry for the selection, nil when it is not a word or short phrase or the dictionaries have nothing on it.
    func entry(for text: String) async -> DictionaryEntry? {
        guard let term = DictionaryQuery.term(in: text), let definition = await source.definition(of: term),
              let entry = DictionaryParser.entry(from: definition, for: term) else { return nil }
        // Looking up a phrase that is no entry answers with the entry of its first word, which says nothing about the phrase.
        let isPhrase = term.contains(" ")
        guard !isPhrase || entry.headword.split(whereSeparator: \.isWhitespace).count == term.split(whereSeparator: \.isWhitespace).count
        else { return nil }
        return entry
    }
}

/// How the module asks the system to open a URL, so tests never launch an app.
protocol URLOpening {
    func open(_ url: URL)
}

struct WorkspaceURLOpener: URLOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
