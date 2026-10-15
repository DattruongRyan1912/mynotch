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
            let wide = "func f() {\n" + String(repeating: "\(filler) = 1;\n", count: 3_000)
            #expect(ClipboardCodeDetector.detect(text: wide).language != nil)
        }
    }

    /// The goal is under 1 ms for 4 KB in an optimised build (measured with a release benchmark, 0.5 ms on a quiet machine).
    /// `swift test` builds without optimisation, which is ten to fifty times slower, so the bound here only catches a text
    /// that is read more than once per line or more than its first 4 KB.
    @Test func aFourKilobyteTextIsDecidedQuickly() {
        let code = String(repeating: "    let value = compute(input, 42) + offset // note\n", count: 80)
        let prose = String(repeating: "Hôm nay trời đẹp, mình đi dạo công viên (nếu rảnh) nhé.\n", count: 70)
        #if DEBUG
        let limit = Duration.milliseconds(300)
        #else
        let limit = Duration.milliseconds(3)
        #endif
        for text in [code, prose] {
            #expect(text.utf8.count >= 4_000)
            let clock = ContinuousClock()
            let elapsed = clock.measure { for _ in 0..<20 { _ = ClipboardCodeDetector.detect(text: text) } } / 20
            #expect(elapsed < limit, "\(elapsed)")
        }
    }

    @Test func aHugeJSONDocumentIsNotParsedWhole() {
        let json = "[" + String(repeating: #"{"id": 1, "name": "An"},"#, count: 100_000) + #"{"id": 2}]"#
        #expect(json.utf8.count > 2_000_000)
        let clock = ContinuousClock()
        var detection = CodeDetection.notCode
        let elapsed = clock.measure { detection = ClipboardCodeDetector.detect(text: json) }
        #expect(detection == .code(.json))
        #expect(elapsed < .milliseconds(200), "\(elapsed)")
    }
}
