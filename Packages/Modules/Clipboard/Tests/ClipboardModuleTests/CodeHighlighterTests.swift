import Foundation
import SwiftUI
import Testing
@testable import ClipboardModule

/// Remembers where a computation ran, from whichever thread that was.
private nonisolated final class ComputeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var threads: [Bool] = []

    func record() {
        lock.withLock { threads.append(Thread.isMainThread) }
    }

    var ranOnMain: [Bool] { lock.withLock { threads } }
}

@Suite struct CodeHighlighterTests {
    /// The text of each run with its colour, plain runs having none.
    private func runs(_ text: String, _ language: CodeLanguage, _ palette: CodePalette = .dark) -> [(String, Color?)] {
        let attributed = CodeHighlighter.highlight(text, language: language, palette: palette)
        return attributed.runs.map { (String(attributed[$0.range].characters), $0.foregroundColor) }
    }

    @Test func eachKindOfTokenTakesItsColourFromThePalette() {
        let palette = CodePalette.dark
        let found = runs("let x = 42 // hi", .swift)
        #expect(found.map(\.0) == ["let", " x ", "=", " ", "42", " ", "// hi"])
        #expect(found.map(\.1) == [
            palette.color(for: .keyword), nil, palette.color(for: .punctuation), nil, palette.color(for: .number), nil,
            palette.color(for: .comment),
        ])
        let string = runs(#"print("a")"#, .swift)
        #expect(string.contains { $0.0 == #""a""# && $0.1 == palette.color(for: .string) })
    }

    @Test func thePaletteHasFiveDistinctColoursInBothAppearances() {
        let kinds: [CodeTokenKind] = [.keyword, .string, .comment, .number, .punctuation]
        for palette in [CodePalette.dark, .adaptive] {
            #expect(Set(kinds.map { palette.color(for: $0) }).count == 5)
        }
        #expect(CodePalette.dark.color(for: .keyword) != CodePalette.adaptive.color(for: .keyword))
    }

    private func luminance(_ color: CodePalette.RGB) -> Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    private func contrast(_ foreground: CodePalette.RGB, on background: Double) -> Double {
        let backgroundLuminance = luminance(CodePalette.RGB(red: background, green: background, blue: background))
        let light = max(luminance(foreground), backgroundLuminance), dark = min(luminance(foreground), backgroundLuminance)
        return (light + 0.05) / (dark + 0.05)
    }

    /// WCAG's 4.5:1 for text of this size, on the greys the colours land on: white, the window grey (#ECECEC), a popover
    /// (#F0F0F0) in light mode; black (the notch), the dark window (#1E1E1E) and a lighter dark grey in dark mode.
    @Test func everyColourReadsAtFourPointFiveToOneOnItsBackgrounds() {
        let kinds: [CodeTokenKind] = [.keyword, .string, .comment, .number, .punctuation]
        for kind in kinds {
            let light = CodePalette.rgb(for: kind, in: .light), dark = CodePalette.rgb(for: kind, in: .dark)
            for background in [1.0, 0.925, 0.941] { #expect(contrast(light, on: background) >= 4.5, "\(kind) light on \(background)") }
            for background in [0.0, 30.0 / 255, 40.0 / 255] { #expect(contrast(dark, on: background) >= 4.5, "\(kind) dark on \(background)") }
        }
    }

    @Test func theTextIsKeptCharacterForCharacter() {
        let text = "let ế = \"Hôm nay 日本語 🙏\" // đẹp\n\tvar y = 1"
        let attributed = CodeHighlighter.highlight(text, language: .swift, palette: .dark)
        #expect(String(attributed.characters) == text)
    }

    @Test func multiByteCharactersAreColouredWhole() {
        let found = runs("// đẹp ế\nlet x = \"日本\"", .swift)
        #expect(found.map(\.0).joined() == "// đẹp ế\nlet x = \"日本\"")
        #expect(found.first?.0 == "// đẹp ế")
        #expect(found.contains { $0.0 == "\"日本\"" })
    }

    // MARK: Bounds

    @Test func aTextIsCutAtTwoHundredLines() {
        let lines = (1...1_000).map { "line \($0)" }
        let bounded = CodeHighlighter.bounded(lines.joined(separator: "\n"))
        #expect(bounded == lines.prefix(200).joined(separator: "\n"))
    }

    @Test func aTextIsCutAtTwentyKilobytes() {
        let bounded = CodeHighlighter.bounded(String(repeating: "a", count: 100_000))
        #expect(bounded.utf8.count == 20 * 1024)
    }

    @Test func theCutNeverSplitsACharacter() {
        let bounded = CodeHighlighter.bounded(String(repeating: "ế", count: 30_000))
        #expect(bounded.utf8.count <= 20 * 1024 && bounded.utf8.count > 20 * 1024 - 3)
        #expect(bounded.allSatisfy { $0 == "ế" })
    }

    @Test func aShortTextIsKeptWhole() {
        #expect(CodeHighlighter.bounded("a\nb\n") == "a\nb\n")
        #expect(CodeHighlighter.bounded("") == "")
    }

    @Test func onlyTheStartOfALongTextIsColoured() {
        let text = (1...1_000).map { "let x\($0) = \($0)" }.joined(separator: "\n")
        let attributed = CodeHighlighter.highlight(text, language: .swift, palette: .dark)
        #expect(String(attributed.characters) == CodeHighlighter.bounded(text))
        #expect(attributed.characters.count(where: { $0 == "\n" }) == 199)
    }
}

@Suite struct CodeHighlightCacheTests {
    private func key(_ text: String, _ language: CodeLanguage = .swift, _ palette: CodePalette = .dark) -> CodeHighlightCache.Key {
        CodeHighlightCache.Key(text: text, language: language, palette: palette)
    }

    @Test func aSmallTextIsColouredAtOnceAndOnlyOnce() {
        let cache = CodeHighlightCache()
        let first = cache.immediate(key("let x = 1"))
        #expect(first != nil)
        #expect(cache.computeCount == 1)
        #expect(cache.immediate(key("let x = 1")) == first)
        #expect(cache.cached(key("let x = 1")) == first)
        #expect(cache.computeCount == 1)
    }

    @Test func theLanguageAndThePaletteArePartsOfTheKey() {
        let cache = CodeHighlightCache()
        _ = cache.immediate(key("let x = 1"))
        _ = cache.immediate(key("let x = 1", .rust))
        _ = cache.immediate(key("let x = 1", .swift, .adaptive))
        #expect(cache.computeCount == 3)
    }

    @Test func aLargeTextIsNotColouredOnTheMainActor() async {
        let log = ComputeLog()
        let cache = CodeHighlightCache(compute: { key in
            log.record()
            return CodeHighlighter.highlight(key.text, language: key.language, palette: key.palette)
        })
        let large = String(repeating: "let value = compute(input) // note\n", count: 100)
        #expect(large.utf8.count > CodeHighlightCache.inlineLimit)
        #expect(cache.immediate(key(large)) == nil)
        #expect(cache.computeCount == 0)

        let colored = await cache.highlighted(key(large))
        #expect(String(colored.characters) == large)
        #expect(log.ranOnMain == [false])
        #expect(cache.cached(key(large)) == colored)
        #expect(cache.immediate(key(large)) == colored)
        #expect(cache.computeCount == 1)
    }

    @Test func aSmallTextIsColouredOnTheMainActor() async {
        let log = ComputeLog()
        let cache = CodeHighlightCache(compute: { key in
            log.record()
            return CodeHighlighter.highlight(key.text, language: key.language, palette: key.palette)
        })
        _ = cache.immediate(key("let x = 1"))
        #expect(log.ranOnMain == [true])
    }

    @Test func twoRequestsForTheSameTextShareOneComputation() async {
        let cache = CodeHighlightCache()
        let large = String(repeating: "let value = compute(input) // note\n", count: 100)
        async let first = cache.highlighted(key(large))
        async let second = cache.highlighted(key(large))
        let results = await [first, second]
        #expect(results[0] == results[1])
        #expect(cache.computeCount == 1)
    }

    @Test func theOldestEntryLeavesWhenTheCacheIsFull() {
        let cache = CodeHighlightCache(capacity: 2)
        _ = cache.immediate(key("a = 1"))
        _ = cache.immediate(key("b = 2"))
        _ = cache.cached(key("a = 1"))
        _ = cache.immediate(key("c = 3"))
        #expect(cache.cached(key("a = 1")) != nil)
        #expect(cache.cached(key("b = 2")) == nil)
        #expect(cache.cached(key("c = 3")) != nil)
    }
}
