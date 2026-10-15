import Testing
@testable import MediaModule

/// The three lines of the floating panel. The words are placeholders.
@Suite struct LyricPanelLinesTests {
    let lyrics = [
        LyricLine(time: 5, text: "a"), LyricLine(time: 10, text: "b"), LyricLine(time: 14, text: ""),
        LyricLine(time: 20, text: "c"), LyricLine(time: 25, text: "d"),
    ]

    func lines(at position: Double?) -> LyricPanelLines { LyricPanelLines(lines: lyrics, position: position) }

    func texts(_ lines: LyricPanelLines) -> [String?] { [lines.previous?.text, lines.current?.text, lines.next?.text] }

    @Test func whileALineIsSungItsNeighboursAreAroundIt() {
        #expect(texts(lines(at: 11)) == ["a", "b", "c"])
        #expect(texts(lines(at: 21)) == ["b", "c", "d"])
    }

    @Test func theFirstLineHasNothingBeforeIt() {
        #expect(texts(lines(at: 6)) == [nil, "a", "b"])
    }

    @Test func theLastLineHasNothingAfterIt() {
        #expect(texts(lines(at: 99)) == ["c", "d", nil])
    }

    @Test func beforeTheFirstLineOnlyTheNextOneIsShown() {
        #expect(texts(lines(at: 1)) == [nil, nil, "a"])
        #expect(texts(lines(at: -4)) == [nil, nil, "a"])
    }

    @Test func inAPauseTheLineJustSungIsBeforeAndTheNextOneIsAfter() {
        #expect(texts(lines(at: 16)) == ["b", nil, "c"])
    }

    @Test func pausesAreNeverShownAsLines() {
        // After the pause: the line before "c" is "b", not the empty line between.
        #expect(texts(lines(at: 22)) == ["b", "c", "d"])
        for position in stride(from: 0.0, through: 30, by: 0.5) {
            let shown = lines(at: position)
            #expect(shown.previous?.text.isEmpty != true)
            #expect(shown.next?.text.isEmpty != true)
        }
    }

    @Test func withoutAPositionOrLinesThereIsNothing() {
        #expect(texts(lines(at: nil)) == [nil, nil, nil])
        #expect(texts(LyricPanelLines(lines: [], position: 4)) == [nil, nil, nil])
    }

    @Test func theCurrentLineKeepsItsWords() {
        let sung = [LyricLine(time: 1, words: [LyricWord(text: "la ", begin: 1, end: 2), LyricWord(text: "la", begin: 2, end: 3)])]
        #expect(LyricPanelLines(lines: sung, position: 1.5).current?.words?.count == 2)
    }
}
