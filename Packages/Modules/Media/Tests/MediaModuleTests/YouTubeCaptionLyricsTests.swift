import Testing
import YouTubeBridgeKit
@testable import MediaModule

@Suite struct YouTubeCaptionLyricsTests {
    func event(_ time: Double, _ duration: Double, _ text: String) -> CaptionEvent {
        CaptionEvent(time: time, duration: duration, text: text)
    }

    func lines(_ events: CaptionEvent...) -> [LyricLine] {
        YouTubeCaptionLyrics.lines(from: events)
    }

    @Test func eachEventBecomesALineAtItsStart() {
        #expect(lines(event(1, 2, "alpha"), event(3, 2, "beta")) == [
            LyricLine(time: 1, text: "alpha"), LyricLine(time: 3, text: "beta"), LyricLine(time: 5, text: ""),
        ])
    }

    @Test func noEventsNoLines() {
        #expect(YouTubeCaptionLyrics.lines(from: []).isEmpty)
    }

    @Test func aGapOfMoreThanFiveSecondsAfterAnEventsEndAddsAPauseAtItsEnd() {
        #expect(lines(event(1, 2, "alpha"), event(8.01, 1, "beta")) == [
            LyricLine(time: 1, text: "alpha"), LyricLine(time: 3, text: ""),
            LyricLine(time: 8.01, text: "beta"), LyricLine(time: 9.01, text: ""),
        ])
        // Exactly five seconds is not more.
        #expect(lines(event(1, 2, "alpha"), event(8, 1, "beta")) == [
            LyricLine(time: 1, text: "alpha"), LyricLine(time: 8, text: "beta"), LyricLine(time: 9, text: ""),
        ])
    }

    @Test func overlappingEventsAddNoPause() {
        #expect(lines(event(1, 4, "alpha"), event(2, 4, "alpha beta"), event(3, 4, "beta gamma")).map(\.text) == [
            "alpha", "alpha beta", "beta gamma", "",
        ])
    }

    @Test func anEventWithoutADurationAddsNoPauseAfterIt() {
        #expect(lines(event(1, 0, "alpha"), event(20, 0, "beta")) == [
            LyricLine(time: 1, text: "alpha"), LyricLine(time: 20, text: "beta"),
        ])
    }

    @Test func theLastEventsEndIsAPauseSoTheLineDoesNotStayUpForever() {
        #expect(lines(event(10, 3.5, "last")) == [LyricLine(time: 10, text: "last"), LyricLine(time: 13.5, text: "")])
    }

    @Test func markersBecomeEmptyLinesAtTheirStart() {
        for marker in ["[Music]", "[Âm nhạc]", "♪", "♪ ♪", "♫♬", "[ Applause ]", "[Music] [Applause]", "♪ [Music] ♪"] {
            #expect(lines(event(1, 2, "alpha"), event(3, 2, marker), event(5, 1, "beta")) == [
                LyricLine(time: 1, text: "alpha"), LyricLine(time: 3, text: ""),
                LyricLine(time: 5, text: "beta"), LyricLine(time: 6, text: ""),
            ], "\(marker)")
        }
    }

    @Test func textThatOnlyContainsAMarkerStaysText() {
        for text in ["Hello [Music]", "[Music] hello", "(Music)", "[Music", "Music]", "[a[b]]", "♪ la la ♪", "la"] {
            #expect(lines(event(1, 1, text)).first == LyricLine(time: 1, text: text), "\(text)")
        }
    }

    @Test func aMarkerThatIsAlreadyBlankGetsNoSecondBlankAfterIt() {
        #expect(lines(event(1, 1, "alpha"), event(2, 1, "[Music]"), event(30, 1, "beta")) == [
            LyricLine(time: 1, text: "alpha"), LyricLine(time: 2, text: ""),
            LyricLine(time: 30, text: "beta"), LyricLine(time: 31, text: ""),
        ])
        #expect(lines(event(1, 1, "[Music]")) == [LyricLine(time: 1, text: "")])
    }

    @Test func theLinesStayInTimeOrderSoTheLyricLookupWorks() {
        let result = lines(event(1, 1, "a"), event(10, 1, "b"), event(30, 2, "c"), event(31, 1, "d"))
        #expect(result.map(\.time) == result.map(\.time).sorted())
        #expect(result.line(at: 5)?.text == "")
        #expect(result.line(at: 30.5)?.text == "c")
    }
}
