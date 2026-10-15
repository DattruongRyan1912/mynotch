import Foundation
import Testing
@testable import ClipboardModule

/// A small deterministic generator, so a failure can be run again from its seed.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// Random texts built from the pieces that make scanners misbehave: quotes of every kind, backslashes, openers and closers
/// of comments and interpolations, raw-string fences, tags, multi-byte characters, and plain words. Every language family
/// gets tens of thousands of them, and none may crash or return a range outside the text.
@Suite struct CodeFuzzTests {
    nonisolated static let pieces: [String] = [
        "\"", "'", "`", "\\", "\"\"\"", "'''", "\\(", "${", "$", "{", "}", "(", ")", "[", "]", "#", "##", "#\"", "\"#", "r#\"", "r\"",
        "b\"", "f\"", "@\"", "$@\"", "/*", "*/", "//", "/", "*", "--", "-->", "<!--", "<", ">", "</", "/>", "<?", "?>", "<!", "<![CDATA[",
        "]]>", "```", "~~~", "=", ":", ";", ",", ".", "..", "-", "+", "!", "?", "&", "|", "%", "^", "~", "@", "\n", "\r\n", "\r", " ",
        "  ", "\t", "0", "1", "42", "0x", "0xFF", "1e", "1e+", ".5", "1.", "-1", "a", "word", "let", "func", "if", "def", "end", "null",
        "true", "SELECT", "from", "ế", "日本", "🙏", "\u{0}", "\u{FFFD}", "é", "`json:\"id\"`", "<?php", "#include", "@interface", "'a",
        "'\\n'", "'x'", "\\u{1F600}", "{{", "}}", "))", "((", "\"\"", "''",
    ]

    nonisolated static var iterations: Int {
        ProcessInfo.processInfo.environment["CODE_FUZZ_ITERATIONS"].flatMap(Int.init) ?? 100_000
    }

    /// Many failures sit at the very end of a text: an escape, a quote or an opener with nothing after it.
    nonisolated static let endings: [String] = [
        "\\", "\\\\", "\"\"\"\\", "\\(", "${", "/*", "<!--", "'", "\"", "`", "r#\"", "\\u", "\\\"", "#\"", "(\"\"\"\\", "\\(\"\"\"\\",
    ]

    nonisolated static func randomText(_ generator: inout SplitMix64) -> String {
        let count = Int.random(in: 0...24, using: &generator)
        var text = ""
        for _ in 0..<count { text += pieces.randomElement(using: &generator) ?? "" }
        if Int.random(in: 0..<3, using: &generator) == 0 { text += endings.randomElement(using: &generator) ?? "" }
        return text
    }

    /// Runs `count` inputs from `seed` through the tokenizer of every language in turn; returns what went wrong, if anything.
    nonisolated static func fuzzTokenizer(seed: UInt64, count: Int) -> [String] {
        var generator = SplitMix64(seed: seed)
        let languages = CodeLanguage.allCases
        var failures: [String] = []
        for index in 0..<count {
            let text = randomText(&generator)
            let language = languages[index % languages.count]
            let bytes = Array(text.utf8)
            var end = 0
            for token in CodeTokenizer.tokens(in: text, language: language) {
                let range = token.range
                guard range.lowerBound >= end, range.lowerBound < range.upperBound, range.upperBound <= bytes.count else {
                    failures.append("\(language) \(text.debugDescription): invalid range \(range) after \(end)")
                    break
                }
                end = range.upperBound
                // A token that starts or ends inside a character would not decode back to the text.
                let slice = String(decoding: bytes[range], as: UTF8.self)
                if slice.contains("\u{FFFD}"), !text.contains("\u{FFFD}") {
                    failures.append("\(language) \(text.debugDescription): token splits a character at \(range)")
                    break
                }
            }
            if failures.count >= 5 { break }
        }
        return failures
    }

    nonisolated static func fuzzHighlighterAndDetector(seed: UInt64, count: Int) -> [String] {
        var generator = SplitMix64(seed: seed)
        let languages = CodeLanguage.allCases
        var failures: [String] = []
        for index in 0..<count {
            let text = randomText(&generator)
            let language = languages[index % languages.count]
            // Colouring is the slow part, so it takes every fourth input; the detector takes all of them.
            if index % 4 == 0 {
                let colored = CodeHighlighter.highlight(text, language: language, palette: .dark)
                if String(colored.characters) != CodeHighlighter.bounded(text) {
                    failures.append("\(language) \(text.debugDescription): the highlighted text differs")
                }
            }
            _ = ClipboardCodeDetector.detect(text: text)
            if failures.count >= 5 { break }
        }
        return failures
    }

    @Test func noRandomTextCrashesTheTokenizerOrMakesAnInvalidRange() async {
        let workers = 8
        let share = Self.iterations / workers
        let failures = await withTaskGroup(of: [String].self) { group in
            for worker in 0..<workers {
                group.addTask { Self.fuzzTokenizer(seed: 0xC0DE + UInt64(worker), count: share) }
            }
            var all: [String] = []
            for await result in group { all += result }
            return all
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }

    @Test func noRandomTextCrashesTheHighlighterOrTheDetector() async {
        let workers = 8
        let share = Self.iterations / workers
        let failures = await withTaskGroup(of: [String].self) { group in
            for worker in 0..<workers {
                group.addTask { Self.fuzzHighlighterAndDetector(seed: 0xFACE + UInt64(worker), count: share) }
            }
            var all: [String] = []
            for await result in group { all += result }
            return all
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }

    @Test func theGeneratorIsDeterministic() {
        var first = SplitMix64(seed: 7), second = SplitMix64(seed: 7)
        #expect((0..<5).map { _ in Self.randomText(&first) } == (0..<5).map { _ in Self.randomText(&second) })
    }
}
