import Foundation
import SwiftUI

/// Colours the start of a code text. Bounded, so the cost never depends on how much was copied.
nonisolated enum CodeHighlighter {
    static let maxLines = 200
    static let maxBytes = 20 * 1024

    /// The first 200 lines or 20 KB of `text`, whichever ends first, cut between characters.
    static func bounded(_ text: String) -> String {
        var bytes = 0, lines = 0
        let kept = text.unicodeScalars.prefix { scalar in
            bytes += UTF8.width(scalar)
            if scalar == "\n" { lines += 1 }
            return bytes <= maxBytes && lines < maxLines
        }
        return String(kept)
    }

    static func highlight(_ text: String, language: CodeLanguage, palette: CodePalette) -> AttributedString {
        let part = bounded(text)
        var result = AttributedString(part)
        let tokens = CodeTokenizer.tokens(in: part, language: language)
        guard !tokens.isEmpty else { return result }
        // The tokens count UTF-8 bytes; one walk over the characters turns them into positions in the result. All the
        // positions are found before the first colour is set.
        let scalars = result.unicodeScalars
        var position = scalars.startIndex
        var offset = 0
        func advance(to target: Int) -> AttributedString.Index {
            while offset < target, position < scalars.endIndex {
                offset += UTF8.width(scalars[position])
                position = scalars.index(after: position)
            }
            return position
        }
        let ranges = tokens.map { token in
            let start = advance(to: token.range.lowerBound)
            return (start..<advance(to: token.range.upperBound), token.kind)
        }
        for (range, kind) in ranges { result[range].foregroundColor = palette.color(for: kind) }
        return result
    }
}

/// Coloured texts, kept so scrolling past a card again costs nothing. A small text is coloured at once, where it is asked
/// for; a larger one on a background task, so the main actor never waits for it.
final class CodeHighlightCache {
    nonisolated struct Key: Hashable, Sendable {
        let text: String
        let language: CodeLanguage
        let palette: CodePalette
    }

    typealias Compute = @Sendable (Key) -> AttributedString

    /// The one the views share.
    static let shared = CodeHighlightCache()
    /// Up to this many UTF-8 bytes a text is coloured on the main actor.
    static let inlineLimit = 2_048

    nonisolated static func highlight(_ key: Key) -> AttributedString {
        CodeHighlighter.highlight(key.text, language: key.language, palette: key.palette)
    }

    private let capacity: Int
    private let compute: Compute
    private var entries: [Key: AttributedString] = [:]
    /// Least recently used first.
    private var order: [Key] = []
    private var inflight: [Key: Task<AttributedString, Never>] = [:]
    /// How many texts were coloured, so tests can prove one is not coloured twice.
    private(set) var computeCount = 0

    init(capacity: Int = 64, compute: @escaping Compute = CodeHighlightCache.highlight) {
        self.capacity = capacity
        self.compute = compute
    }

    func cached(_ key: Key) -> AttributedString? {
        guard let hit = entries[key] else { return nil }
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
            order.append(key)
        }
        return hit
    }

    /// The coloured text if it is cached or small enough to colour now; nil for a large one, which `highlighted` colours.
    func immediate(_ key: Key) -> AttributedString? {
        if let hit = cached(key) { return hit }
        guard key.text.utf8.count <= Self.inlineLimit else { return nil }
        computeCount += 1
        let result = compute(key)
        store(result, for: key)
        return result
    }

    /// Colours off the main actor. Asking for the same text while it is being coloured waits for that one.
    func highlighted(_ key: Key) async -> AttributedString {
        if let hit = cached(key) { return hit }
        let compute = compute
        let task: Task<AttributedString, Never>
        if let running = inflight[key] {
            task = running
        } else {
            computeCount += 1
            task = Task.detached(priority: .userInitiated) { compute(key) }
            inflight[key] = task
        }
        let result = await task.value
        inflight[key] = nil
        store(result, for: key)
        return result
    }

    private func store(_ result: AttributedString, for key: Key) {
        if entries.updateValue(result, forKey: key) != nil, let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
        while order.count > capacity { entries[order.removeFirst()] = nil }
    }
}
