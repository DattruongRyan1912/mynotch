import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardCodeDetectorTests {
    @Test(arguments: CodeSamples.code)
    func codeIsRecognisedWithItsLanguage(sample: CodeSample) {
        let detection = ClipboardCodeDetector.detect(text: sample.text)
        if let language = sample.language {
            #expect(detection == .code(language))
        } else {
            #expect(detection.language != nil)
        }
    }

    @Test(arguments: CodeSamples.prose)
    func proseIsNotCode(sample: CodeSample) {
        #expect(ClipboardCodeDetector.detect(text: sample.text) == .notCode)
    }

    @Test func theTableHasEnoughSamplesOfBoth() {
        #expect(CodeSamples.code.count + CodeSamples.prose.count >= 60)
        #expect(CodeSamples.prose.count >= 30)
        #expect(Set(CodeSamples.code.compactMap(\.language)) == Set(CodeLanguage.allCases).subtracting([.generic]))
    }

    @Test func emptyAndBlankTextIsNotCode() {
        #expect(ClipboardCodeDetector.detect(text: "") == .notCode)
        #expect(ClipboardCodeDetector.detect(text: " \n\t\n ") == .notCode)
    }

    @Test func indentationAndSurroundingBlankLinesDoNotMatter() {
        let sample = "\n\n    def add(a, b):\n        return a + b\n\n\n"
        #expect(ClipboardCodeDetector.detect(text: sample) == .code(.python))
    }

    @Test func windowsLineEndingsAreFine() {
        #expect(ClipboardCodeDetector.detect(text: "function f() {\r\n  return 1;\r\n}\r\n") == .code(.javascript))
    }

    @Test func codeWithoutAKnownLanguageIsGeneric() {
        let text = "while (x < 10) {\n  x = x + 1;\n}"
        #expect(ClipboardCodeDetector.detect(text: text) == .code(.generic))
    }

    @Test func aTextAndItsRichTextAreDecidedByTheirPlainText() {
        let rtf = Data("{\\rtf1 x}".utf8)
        #expect(ClipboardCodeDetector.detect(.text("SELECT 1 FROM t;")) == .code(.sql))
        #expect(ClipboardCodeDetector.detect(.richText(plain: "SELECT 1 FROM t;", rtf: rtf)) == .code(.sql))
        #expect(ClipboardCodeDetector.detect(.richText(plain: "Xin chào", rtf: rtf)) == .notCode)
    }

    @Test func otherKindsAreNotTexts() {
        #expect(ClipboardCodeDetector.detect(.link(URL(string: "https://example.com")!)) == nil)
        #expect(ClipboardCodeDetector.detect(.color(hex: "#FF8800")) == nil)
        #expect(ClipboardCodeDetector.detect(.files([URL(fileURLWithPath: "/tmp/a.swift")])) == nil)
        #expect(ClipboardCodeDetector.detect(.image(ClipboardImage(fileName: "a.png", pixelWidth: 1, pixelHeight: 1, byteCount: 1))) == nil)
    }

    // MARK: Bounds

    @Test func onlyTheStartOfALongTextIsLookedAt() {
        let prose = String(repeating: "Hôm nay trời đẹp quá, mình đi dạo nhé.\n", count: 1_000)
        #expect(ClipboardCodeDetector.detect(text: prose + "func f() {\n}\n") == .notCode)
        let code = String(repeating: "let value = compute(input) + 1;\n", count: 50_000)
        #expect(code.utf8.count > 1_500_000)
        #expect(ClipboardCodeDetector.detect(text: code).language != nil)
    }

    @Test func aTextCutInTheMiddleOfACharacterStillWorks() {
        // 4,096 bytes is not a multiple of the 2-byte "ế" or the 3-byte "€".
        for filler in ["ế", "€"] {
            let text = "let a = 1;\n" + String(repeating: filler, count: 5_000)
            _ = ClipboardCodeDetector.detect(text: text)
            let wide = "func f() {\n" + String(repeating: "    print(\"\(filler)\", 1);\n", count: 3_000) + "}"
            #expect(ClipboardCodeDetector.detect(text: wide).language != nil)
        }
    }

    /// The cost of a detection is bounded by what it reads, not by a clock: the sample is the first 4 KB, cut between whole
    /// lines, and holds at most 150 lines. (An optimised build decides 4 KB in well under a millisecond; a throwaway release
    /// benchmark, not a test, measured it.)
    @Test func whateverTheSizeOfATextOnlyItsFirstFourKilobytesAreRead() {
        for text in [String(repeating: "let value = compute(input) + 1\n", count: 100_000), String(repeating: "ế", count: 2_000_000), "x"] {
            let sample = DetectionSample(text)
            #expect(sample.text.utf8.count <= ClipboardCodeDetector.sampleBytes)
            #expect(sample.lines.count <= 150)
            #expect(sample.isCut == (text.utf8.count > ClipboardCodeDetector.sampleBytes))
        }
        let many = String(repeating: "a\n", count: 10_000)
        #expect(DetectionSample(many).lines.count <= 150)
    }

    /// A text above the parse limit is judged by its edges: an invalid document with the edges and a key is called JSON, which
    /// a parse would have refused, so the document was not parsed.
    @Test func aHugeJSONDocumentIsNotParsedWhole() {
        let body = String(repeating: #""id": 1, "name": "An", "#, count: 4_000)
        let broken = "{" + body + "oops}"
        #expect(broken.utf8.count > ClipboardCodeDetector.jsonParseLimit)
        #expect(ClipboardCodeDetector.detect(text: broken) == .code(.json))
        // Under the limit the same text is parsed, and refused.
        #expect(ClipboardCodeDetector.detect(text: "{" + String(repeating: #""id": 1, "#, count: 100) + "oops}") == .notCode)
        let valid = "[" + String(repeating: #"{"id": 1, "name": "An"},"#, count: 100_000) + #"{"id": 2}]"#
        #expect(ClipboardCodeDetector.detect(text: valid) == .code(.json))
    }
}
