import AppKit
import Foundation
import Testing
@testable import ClipboardModule

/// The coloured stretches of a code text in the units a text view counts in (UTF-16), cut at a bound so a big copy costs a bounded
/// amount, and the colours they are drawn with.
@Suite struct ClipboardPreviewHighlightTests {
    typealias Highlight = ClipboardPreviewHighlight

    func pieces(_ text: String, _ language: CodeLanguage) -> [(String, CodeTokenKind)] {
        let ns = text as NSString
        // A range outside the text would raise an exception and take the whole test process down, so it is shown as a mark instead.
        return Highlight.runs(for: text, language: language).map { run in
            (run.range.upperBound <= ns.length ? ns.substring(with: run.range) : "<outside the text>", run.kind)
        }
    }

    @Test func eachTokenIsARunOverTheCharactersItNames() {
        let found = pieces("let x = 42 // hi", .swift)
        #expect(found.map(\.0) == ["let", "=", "42", "// hi"])
        #expect(found.map(\.1) == [.keyword, .punctuation, .number, .comment])
    }

    @Test func runsCountInUTF16NotInBytes() {
        // "é" is two bytes and one unit, "😀" four bytes and two units: a byte offset would land on the wrong characters.
        let found = pieces("é = 1 // ế", .swift)
        #expect(found.map(\.0) == ["=", "1", "// ế"])
        let emoji = pieces("😀 = 1 // x", .swift)
        #expect(emoji.map(\.0) == ["=", "1", "// x"])
        #expect(pieces("let s = \"Việt Nam 🇻🇳\" // ok", .swift).map(\.0) == ["let", "=", "\"Việt Nam 🇻🇳\"", "// ok"])
    }

    @Test func runsAreOrderedAndInsideTheTextForEverySample() {
        for sample in CodeSamples.code {
            let language = sample.language ?? .generic
            let runs = Highlight.runs(for: sample.text, language: language)
            let length = sample.text.utf16.count
            var end = 0
            for run in runs {
                #expect(run.range.length > 0 && run.range.location >= end && run.range.upperBound <= length, "\(sample.name)")
                end = run.range.upperBound
            }
        }
    }

    @Test func aTextPastTheBoundIsColouredOnlyAsFarAsTheBound() {
        let line = "let x = 1 // é\n"
        let text = String(repeating: line, count: Highlight.maxBytes / line.utf8.count * 3)
        let runs = Highlight.runs(for: text, language: .swift)
        #expect(!runs.isEmpty)
        let bound = Highlight.bounded(text).utf16.count
        #expect(runs.allSatisfy { $0.range.upperBound <= bound })
        // And it did reach near the bound, rather than stopping early.
        #expect(runs.last!.range.upperBound > bound - 100)
    }

    @Test func theBoundNeverSplitsACharacter() {
        let text = String(repeating: "ế", count: Highlight.maxBytes)
        let runs = Highlight.runs(for: text, language: .swift)
        // No tokens in plain letters; the point is that cutting inside the three-byte character did not crash or invent one.
        #expect(runs.allSatisfy { $0.range.upperBound <= text.utf16.count })
        let cut = Highlight.bounded(text)
        #expect(cut.utf8.count <= Highlight.maxBytes)
        #expect(cut.utf8.count > Highlight.maxBytes - 3)
        #expect(text.hasPrefix(cut))
    }

    @Test func aTextUnderTheBoundIsNotCut() {
        #expect(Highlight.bounded("let x = 1") == "let x = 1")
        #expect(Highlight.bounded("") == "")
    }

    @Test func anEmptyTextAndPlainWordsHaveNoRuns() {
        #expect(Highlight.runs(for: "", language: .swift).isEmpty)
        #expect(Highlight.runs(for: "xin chào cả nhà", language: .generic).isEmpty)
    }

    // MARK: Colours

    @Test func eachKindHasItsOwnColourInEachPalette() {
        let kinds: [CodeTokenKind] = [.keyword, .string, .comment, .number, .punctuation]
        for palette in [CodePalette.dark, .adaptive] {
            let colors = kinds.map { palette.nsColor(for: $0) }
            #expect(Set(colors.map { $0.usingColorSpace(.sRGB)?.hexLike ?? "" }).count == 5, "\(palette)")
        }
    }

    @Test func theDarkPaletteIsTheNumbersTheCardsAreMeasuredWith() throws {
        for kind: CodeTokenKind in [.keyword, .string, .comment, .number, .punctuation] {
            let rgb = CodePalette.rgb(for: kind, in: .dark)
            let color = try #require(CodePalette.dark.nsColor(for: kind).usingColorSpace(.sRGB))
            #expect(abs(color.redComponent - rgb.red) < 0.001 && abs(color.greenComponent - rgb.green) < 0.001 && abs(color.blueComponent - rgb.blue) < 0.001)
        }
    }

    @Test func theAdaptivePaletteFollowsTheAppearanceItIsDrawnIn() throws {
        let color = CodePalette.adaptive.nsColor(for: .keyword)
        func resolved(_ name: NSAppearance.Name) throws -> NSColor {
            var result: NSColor?
            try #require(NSAppearance(named: name)).performAsCurrentDrawingAppearance { result = color.usingColorSpace(.sRGB) }
            return try #require(result)
        }
        let dark = try resolved(.darkAqua), light = try resolved(.aqua)
        let darkRGB = CodePalette.rgb(for: .keyword, in: .dark), lightRGB = CodePalette.rgb(for: .keyword, in: .light)
        #expect(abs(dark.redComponent - darkRGB.red) < 0.001)
        #expect(abs(light.redComponent - lightRGB.red) < 0.001)
        #expect(abs(dark.redComponent - light.redComponent) > 0.1)
    }
}

private extension NSColor {
    var hexLike: String { String(format: "%.3f-%.3f-%.3f", redComponent, greenComponent, blueComponent) }
}
