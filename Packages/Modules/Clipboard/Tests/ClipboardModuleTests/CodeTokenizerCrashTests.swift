import Foundation
import Testing
@testable import ClipboardModule

/// Texts that end right after a backslash, a quote or an opener. A scanner that moves two bytes past a backslash lands
/// beyond the end and builds a range that ends before it starts, which traps.
@Suite struct CodeTokenizerCrashTests {
    /// The reviewer's crashers (the first two), then the same ending in every construct that skips a byte.
    nonisolated static let texts: [String] = [
        #""\("""\"#,
        "let s = \"value: \\(String(\"\"\"\n    line one\\",
        #""\("""\\"#,
        #"'''\"#, #""""\"#, #"`\"#, #""\"#, #"'\"#, #"r#"\"#, #"#"\"#, #"@"\"#, #"$@"\"#, #"/*\"#, #"'\u"#, #"<a b="\"#, #"${"\"#,
        #"`${`\"#, #""\(""\"#, "\"\"\"\n\\", #"'\\"#, #""\\"#, #"b"\"#, #"br#"\"#, "```\n\\",
    ]

    @Test(arguments: texts)
    func aBackslashAtTheEndOfTheTextNeverMakesAnInvalidRange(text: String) {
        let count = text.utf8.count
        for language in CodeLanguage.allCases {
            let tokens = CodeTokenizer.tokens(in: text, language: language)
            #expect(tokens.allSatisfy { $0.range.lowerBound >= 0 && $0.range.lowerBound < $0.range.upperBound && $0.range.upperBound <= count }, "\(language)")
            _ = CodeHighlighter.highlight(text, language: language, palette: .dark)
        }
    }

    @Test func theReportedCrashStillColoursWhatCanBeColoured() {
        let tokens = CodeTokenizer.tokens(in: #""\("""\"#, language: .swift)
        #expect(!tokens.isEmpty)
        #expect(tokens.first?.kind == .string)
    }

    /// A long run of `#` that opens no string used to be counted again from each byte, which grows with the square of its
    /// length; 200,000 of them would have taken minutes.
    @Test(arguments: [CodeLanguage.swift, .rust, .c, .shell, .python])
    func aLongRunOfHashesIsOneToken(language: CodeLanguage) {
        let run = String(repeating: "#", count: 200_000)
        let tokens = CodeTokenizer.tokens(in: run, language: language)
        #expect(tokens.map(\.range) == [0..<200_000])
        // A run followed by a quote does open a raw string, which only a run of the same length closes.
        #expect(CodeTokenizer.tokens(in: run + "\"x\"" + run, language: .swift).map(\.kind) == [.string])
        #expect(CodeTokenizer.tokens(in: run + " x " + run, language: .swift).map(\.range) == [0..<200_000, 200_003..<400_003])
        #expect(CodeTokenizer.tokens(in: "x" + run + " y", language: .rust).map(\.range) == [1..<200_001])
    }
}
