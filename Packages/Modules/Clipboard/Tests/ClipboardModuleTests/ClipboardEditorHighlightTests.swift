import Foundation
import Testing
@testable import ClipboardModule

/// What the editor works out about its words in the background: whether they are code and where the colours go.
@Suite struct ClipboardEditorHighlightTests {
    static let swift = "func add(_ a: Int, _ b: Int) -> Int {\n    // tổng\n    return a + b\n}\n"

    @Test func codeIsRecognisedAndColoured() {
        let analysis = ClipboardEditorHighlight.analysis(of: Self.swift)
        #expect(analysis.language == .swift)
        #expect(!analysis.runs.isEmpty)
        let length = (Self.swift as NSString).length
        #expect(analysis.runs.allSatisfy { $0.range.location >= 0 && $0.range.upperBound <= length })
        #expect(analysis.runs.contains { $0.kind == .keyword } && analysis.runs.contains { $0.kind == .comment })
    }

    @Test func proseHasNoLanguageAndNoColours() {
        let analysis = ClipboardEditorHighlight.analysis(of: "Hôm nay trời đẹp, chúng ta cùng đi dạo quanh hồ nhé.")
        #expect(analysis.language == nil)
        #expect(analysis.runs.isEmpty)
        #expect(ClipboardEditorHighlight.analysis(of: "") == ClipboardEditorHighlight.Analysis(language: nil, runs: []))
    }

    @Test func theColoursCountInTheUnitsATextViewDoesWhateverTheLettersAre() {
        // A Vietnamese comment before a keyword: the keyword's place is counted in UTF-16 units, not bytes.
        let code = "// Xin chào thế giới ạ\nfunc a() {}\n"
        let analysis = ClipboardEditorHighlight.analysis(of: code)
        let keyword = analysis.runs.first { $0.kind == .keyword }
        let range = keyword.map { (code as NSString).substring(with: $0.range) }
        #expect(range == "func")
    }

    @Test func theSameAnswerComesFromOffTheMainActor() async {
        let direct = ClipboardEditorHighlight.analysis(of: Self.swift)
        let background = await ClipboardEditorHighlight.analyze(Self.swift)
        #expect(direct == background)
    }

    @Test func aHugeTextIsOnlyColouredAsFarAsTheBoundGoes() {
        let big = String(repeating: "let x = 1 // một\n", count: 20_000)
        let analysis = ClipboardEditorHighlight.analysis(of: big)
        #expect(analysis.language != nil)
        let bound = (ClipboardPreviewHighlight.bounded(big) as NSString).length
        #expect(analysis.runs.allSatisfy { $0.range.upperBound <= bound })
    }
}
