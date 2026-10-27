import Foundation
import Testing
@testable import MediaModule

@Suite struct SubtitleParserTests {
    func cue(_ start: Double, _ end: Double, _ text: String) -> SubtitleCue { SubtitleCue(start: start, end: end, text: text) }
    func line(_ time: Double, _ text: String) -> LyricLine { LyricLine(time: time, text: text) }

    // MARK: parsing

    @Test func parsesSRTBlocks() {
        let cues = SubtitleParser.cues(from: """
        1
        00:01:11,640 --> 00:01:14,530
        Freud said, "Love and work.

        2
        00:01:14,720 --> 00:01:16,400
        That's all there is.
        """)
        #expect(cues == [cue(71.64, 74.53, "Freud said, \"Love and work."), cue(74.72, 76.4, "That's all there is.")])
    }

    @Test func parsesWebVTTWithAHeaderShortTimesAndCueSettings() {
        let cues = SubtitleParser.cues(from: """
        WEBVTT

        NOTE a comment

        intro
        00:05.000 --> 00:07.250 align:start position:10%
        Hello
        """)
        #expect(cues == [cue(5, 7.25, "Hello")])
    }

    @Test func joinsTheLinesOfACueAndDropsFormattingTags() {
        let cues = SubtitleParser.cues(from: "1\r\n00:00:01,000 --> 00:00:02,000\r\n{\\an8}<i>Two</i>\r\n<font color=\"#fff\">lines</font>\r\n")
        #expect(cues == [cue(1, 2, "Two lines")])
    }

    @Test func aCueWithNoTextOrBrokenTimesIsSkipped() {
        let cues = SubtitleParser.cues(from: """
        1
        00:00:01,000 --> 00:00:02,000

        2
        00:00:xx,000 --> 00:00:04,000
        broken

        3
        00:00:05,000 --> 00:00:06,000
        kept
        """)
        #expect(cues == [cue(5, 6, "kept")])
    }

    @Test func cuesOutOfOrderAreSorted() {
        let cues = SubtitleParser.cues(from: """
        00:00:09,000 --> 00:00:10,000
        b

        00:00:03,000 --> 00:00:04,000
        a
        """)
        #expect(cues.map(\.text) == ["a", "b"])
    }

    @Test func readsUTF8WithABOMUTF16AndVietnameseWindowsCodePages() throws {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\nXin chào\n"
        let bom = Data([0xEF, 0xBB, 0xBF]) + Data(srt.utf8)
        #expect(SubtitleParser.cues(from: bom)?.first?.text == "Xin chào")
        let utf16 = try #require(srt.data(using: .utf16))
        #expect(SubtitleParser.cues(from: utf16)?.first?.text == "Xin chào")
        // "Tiếng Việt" in Windows-1258: ê is 0xEA, and the tones are combining marks after it (acute 0xEC, dot below 0xF2).
        let vietnamese = Data("1\n00:00:01,000 --> 00:00:02,000\n".utf8)
            + Data([0x54, 0x69, 0xEA, 0xEC, 0x6E, 0x67, 0x20, 0x56, 0x69, 0xEA, 0xF2, 0x74, 0x0A])
        #expect(SubtitleParser.cues(from: vietnamese)?.first?.text.precomposedStringWithCanonicalMapping == "Tiếng Việt")
    }

    @Test func dataWithNoCueIsNotASubtitle() {
        #expect(SubtitleParser.cues(from: Data("just some text".utf8)) == nil)
        #expect(SubtitleParser.cues(from: Data()) == nil)
    }

    // MARK: lines

    @Test func eachCueIsALineAndAGapAfterItIsABlankLine() {
        let lines = SubtitleParser.lines(from: [cue(1, 2, "a"), cue(2, 3, "b"), cue(5, 6, "c")], delay: 0)
        #expect(lines == [line(1, "a"), line(2, "b"), line(3, ""), line(5, "c"), line(6, "")])
    }

    @Test func theDelayMovesEveryLine() {
        let lines = SubtitleParser.lines(from: [cue(10, 12, "a")], delay: -1.5)
        #expect(lines == [line(8.5, "a"), line(10.5, "")])
    }
}
