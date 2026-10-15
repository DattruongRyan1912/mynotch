import Testing
@testable import MediaModule

/// Enhanced LRC, the kind lrclib sometimes returns: `<mm:ss.xx>` before a word says when it starts. Placeholder words only.
@Suite struct LRCWordTimingTests {
    func word(_ text: String, _ begin: Double, _ end: Double) -> LyricWord { LyricWord(text: text, begin: begin, end: end) }

    @Test func eachStampStartsTheTextAfterItAndEndsTheTextBeforeIt() {
        let lines = LRCParser.parse("[00:10.00] <00:10.00>Hello <00:10.50>big <00:11.00>world <00:11.50>")
        #expect(lines == [LyricLine(time: 10, words: [word("Hello ", 10, 10.5), word("big ", 10.5, 11), word("world", 11, 11.5)])])
        #expect(lines.first?.text == "Hello big world")
    }

    @Test func spacesAroundTheStampsDoNotChangeTheText() {
        let lines = LRCParser.parse("[00:10.00] <00:10.00>Hello <00:10.50>big <00:11.00> world <00:11.50>")
        #expect(lines.first?.text == "Hello big world")
        #expect(lines.first?.words?.map(\.text) == ["Hello ", "big ", "world"])
    }

    @Test func textBeforeTheFirstStampStartsWithTheLine() {
        let lines = LRCParser.parse("[00:10.00]Oh <00:10.40>my <00:10.80>word <00:11.00>")
        #expect(lines.first?.words == [word("Oh ", 10, 10.4), word("my ", 10.4, 10.8), word("word", 10.8, 11)])
    }

    @Test func theLastWordWithoutAClosingStampGetsASecondOrEndsWhereTheNextLineStarts() {
        let roomy = LRCParser.parse("[00:10.00] <00:10.00>one <00:10.50>two\n[00:20.00] next")
        #expect(roomy.first?.words?.last == word("two", 10.5, 11.5))
        let tight = LRCParser.parse("[00:10.00] <00:10.00>one <00:10.50>two\n[00:11.00] next")
        #expect(tight.first?.words?.last == word("two", 10.5, 11))
    }

    @Test func aPauseLineAfterwardsAlsoEndsTheLastWord() {
        let lines = LRCParser.parse("[00:10.00] <00:10.00>one <00:10.50>two\n[00:10.75]\n[00:30.00] later")
        #expect(lines.first?.words?.last == word("two", 10.5, 10.75))
    }

    @Test func aLineWithOnlyAStampAtItsStartHasNoWordTiming() {
        #expect(LRCParser.parse("[00:10.00] <00:10.00>Hello big world") == [LyricLine(time: 10, text: "Hello big world")])
        #expect(LRCParser.parse("[00:10.00] <00:10.00>Hello big world <00:12.00>") == [LyricLine(time: 10, words: [word("Hello big world", 10, 12)])])
    }

    @Test func linesWithoutStampsStayLinesAmongLinesWithThem() {
        let lines = LRCParser.parse("[00:01.00] plain\n[00:05.00] <00:05.00>one <00:05.50>two <00:06.00>\n[00:08.00] plain again")
        #expect(lines.map(\.text) == ["plain", "one two", "plain again"])
        #expect(lines.map { $0.words != nil } == [false, true, false])
    }

    @Test func aLineWithSeveralTimestampsRepeatsItsWordsFromEachOne() {
        let lines = LRCParser.parse("[00:10.00][00:40.00] <00:10.00>one <00:10.50>two <00:11.00>")
        #expect(lines == [
            LyricLine(time: 10, words: [word("one ", 10, 10.5), word("two", 10.5, 11)]),
            LyricLine(time: 40, words: [word("one ", 40, 40.5), word("two", 40.5, 41)]),
        ])
    }

    @Test func theOffsetMovesTheWordsWithTheLine() {
        let lines = LRCParser.parse("[offset:+500]\n[00:10.00] <00:10.00>one <00:10.50>two <00:11.00>")
        #expect(lines == [LyricLine(time: 9.5, words: [word("one ", 9.5, 10), word("two", 10, 10.5)])])
        let early = LRCParser.parse("[offset:+500]\n[00:00.20] <00:00.20>one <00:00.40>two <00:00.60>")
        #expect(early.first?.words?.first == word("one ", 0, 0))
    }

    @Test func angleBracketsThatAreNotStampsStayInTheWords() {
        let lines = LRCParser.parse("[00:10.00] <00:10.00>I <3 <00:10.50>you <00:xx.00>too <00:11.00>")
        #expect(lines.first?.text == "I <3 you <00:xx.00>too")
        #expect(lines.first?.words?.count == 2)
    }

    @Test func stampsOutOfOrderOrOverlappingNeverMakeWordsOverlap() {
        let lines = LRCParser.parse("[00:10.00] <00:10.50>one <00:10.20>two <00:10.90>three <00:10.70>")
        let words = lines.first?.words ?? []
        #expect(words.map(\.text) == ["one ", "two ", "three"])
        for (earlier, later) in zip(words, words.dropFirst()) {
            #expect(earlier.begin <= earlier.end)
            #expect(earlier.end <= later.begin)
        }
    }

    @Test func emptyStampsBetweenWordsAreIgnored() {
        let lines = LRCParser.parse("[00:10.00] <00:10.00><00:10.10>one <00:10.50><00:10.60>two <00:11.00>")
        #expect(lines.first?.text == "one two")
        #expect(lines.first?.words?.map(\.begin) == [10.1, 10.6])
    }

    @Test func aLineOfOnlyStampsIsAPause() {
        #expect(LRCParser.parse("[00:10.00] <00:10.00> <00:11.00>") == [LyricLine(time: 10, text: "")])
    }

    @Test func theTextOfEveryLineIsItsWordsJoined() {
        let source = """
        [00:01.00] <00:01.00>a <00:01.10>b <00:01.20>
        [00:02.00]x <00:02.10>  y   <00:02.30>z<00:02.40>
        [00:03.00]  <00:03.00>spaced <00:03.50>  out  <00:04.00>
        """
        for line in LRCParser.parse(source) {
            #expect(line.words?.map(\.text).joined() == line.text, "\(line)")
        }
    }
}
