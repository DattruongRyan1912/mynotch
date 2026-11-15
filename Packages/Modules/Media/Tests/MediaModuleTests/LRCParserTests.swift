import Testing
@testable import MediaModule

@Suite struct LRCParserTests {
    func line(_ time: Double, _ text: String) -> LyricLine { LyricLine(time: time, text: text) }

    @Test func parsesTimestampsWithOneToThreeFractionDigits() {
        let lines = LRCParser.parse("""
        [00:01.5] one digit
        [00:02.50] two digits
        [00:03.250] three digits
        [01:04] no fraction
        [00:05.05] leading zero
        """)
        #expect(lines == [
            line(1.5, "one digit"), line(2.5, "two digits"), line(3.25, "three digits"),
            line(5.05, "leading zero"), line(64, "no fraction"),
        ])
    }

    @Test func minutesMayPassTwoDigits() {
        #expect(LRCParser.parse("[100:05.00] long one") == [line(6005, "long one")])
    }

    @Test func aLineWithSeveralTimestampsRepeatsForEachOne() {
        let lines = LRCParser.parse("""
        [00:12.00][00:45.50] chorus
        [00:20.00] verse
        """)
        #expect(lines == [line(12, "chorus"), line(20, "verse"), line(45.5, "chorus")])
    }

    @Test func linesOutOfOrderAreSortedAndEqualTimesKeepTheirOrder() {
        let lines = LRCParser.parse("""
        [00:30.00] c
        [00:10.00] a
        [00:10.00] b
        """)
        #expect(lines.map(\.text) == ["a", "b", "c"])
    }

    @Test func positiveOffsetShowsLinesSoonerAndNegativeLater() {
        let sooner = LRCParser.parse("[offset:+500]\n[00:10.00] a\n[00:00.20] b")
        #expect(sooner == [line(0, "b"), line(9.5, "a")])
        let later = LRCParser.parse("[00:10.00] a\n[offset: -250]")
        #expect(later == [line(10.25, "a")])
    }

    @Test func offsetAppliesToEveryLineWhereverItIsDeclared() {
        let lines = LRCParser.parse("[00:10.00][00:20.00] a\n[offset:1000]\n[00:30.00] b")
        #expect(lines == [line(9, "a"), line(19, "a"), line(29, "b")])
    }

    @Test func otherMetadataTagsAreIgnored() {
        let lines = LRCParser.parse("""
        [ti:Song]
        [ar:Artist]
        [al:Album]
        [by:someone]
        [length: 03:20]
        [00:01.00] first
        """)
        #expect(lines == [line(1, "first")])
    }

    @Test func wordTimestampsAreNotPartOfTheText() {
        let lines = LRCParser.parse("[00:10.00] <00:10.00>Hello <00:10.50>big <00:11.00> world <00:11.50>")
        #expect(lines.map(\.text) == ["Hello big world"])
        #expect(lines.map(\.time) == [10])
    }

    @Test func angleBracketsThatAreNotTimestampsStay() {
        #expect(LRCParser.parse("[00:10.00] I <3 you") == [line(10, "I <3 you")])
    }

    @Test func bracketsInTheTextAfterTheTimestampStay() {
        #expect(LRCParser.parse("[00:10.00][Chorus] la la") == [line(10, "[Chorus] la la")])
        #expect(LRCParser.parse("[00:10.00] [Chorus]") == [line(10, "[Chorus]")])
    }

    @Test func blankLinesWithATimestampMarkAPauseAndAreKept() {
        let lines = LRCParser.parse("[00:10.00] a\n[00:14.00]\n[00:20.00] b")
        #expect(lines == [line(10, "a"), line(14, ""), line(20, "b")])
    }

    @Test func malformedLinesAreSkipped() {
        let lines = LRCParser.parse("""
        just some text
        [00:xx.00] letters
        [0:5.0:1] too many colons
        [00:75.00] seconds out of range
        [00:01.1234] four fraction digits
        [00:] empty seconds
        [:05.00] empty minutes
        [00:10.00 unclosed
        []
        [00:01.00] good
        """)
        #expect(lines == [line(1, "good")])
    }

    @Test func windowsLineEndingsAndSurroundingSpaceAreHandled() {
        let lines = LRCParser.parse("  [00:01.00]   spaced   out  \r\n\r\n[00:02.00] next\r\n")
        #expect(lines == [line(1, "spaced out"), line(2, "next")])
    }

    @Test func emptyAndGarbageInputGiveNoLines() {
        #expect(LRCParser.parse("").isEmpty)
        #expect(LRCParser.parse("\n\n").isEmpty)
        #expect(LRCParser.parse("[offset:500]").isEmpty)
    }

    @Test func aNegativeTimeAfterTheOffsetStartsAtZero() {
        #expect(LRCParser.parse("[offset:5000]\n[00:01.00] a") == [line(0, "a")])
    }

    // MARK: lookup

    let lyrics = [LyricLine(time: 5, text: "a"), LyricLine(time: 10, text: "b"), LyricLine(time: 10.5, text: "c")]

    @Test func lookupBeforeTheFirstLineFindsNothing() {
        #expect(lyrics.line(at: 0) == nil)
        #expect(lyrics.line(at: 4.999) == nil)
        #expect(lyrics.line(at: -3) == nil)
        #expect([LyricLine]().line(at: 3) == nil)
    }

    @Test func lookupAtAndAroundBoundaries() {
        #expect(lyrics.line(at: 5)?.text == "a")
        #expect(lyrics.line(at: 9.999)?.text == "a")
        #expect(lyrics.line(at: 10)?.text == "b")
        #expect(lyrics.line(at: 10.4)?.text == "b")
        #expect(lyrics.line(at: 10.5)?.text == "c")
        #expect(lyrics.line(at: 9999)?.text == "c")
    }

    @Test func lookupWithEqualTimesFindsTheLastOne() {
        let tied = [LyricLine(time: 1, text: "x"), LyricLine(time: 1, text: "y"), LyricLine(time: 2, text: "z")]
        #expect(tied.line(at: 1)?.text == "y")
    }

    @Test func lookupOfNotANumberFindsNothing() {
        #expect(lyrics.line(at: .nan) == nil)
    }

    @Test func lookupMatchesALinearScanOverManyLines() {
        let many = (0..<500).map { LyricLine(time: Double($0) * 2.5, text: "line \($0)") }
        let mismatches = stride(from: -1.0, through: 1300, by: 0.7).filter { seconds in
            many.line(at: seconds) != many.last { $0.time <= seconds }
        }
        #expect(mismatches.isEmpty)
    }
}
