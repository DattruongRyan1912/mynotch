import Foundation
import Testing
@testable import MediaModule

/// Synthetic documents only, shaped like Apple's TTML with placeholder words.
@Suite struct TTMLLyricsParserTests {
    static let namespaces = #"xmlns="http://www.w3.org/ns/ttml" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" xmlns:ttm="http://www.w3.org/ns/ttml#metadata""#

    func document(timing: String?, body: String, head: String = "") -> String {
        let attribute = timing.map { #" itunes:timing="\#($0)""# } ?? ""
        return #"<?xml version="1.0" encoding="UTF-8"?><tt \#(Self.namespaces)\#(attribute) xml:lang="en"><head>\#(head)</head><body>\#(body)</body></tt>"#
    }

    func word(_ text: String, _ begin: Double, _ end: Double) -> LyricWord { LyricWord(text: text, begin: begin, end: end) }

    // MARK: line timing

    @Test func lineTimingGivesOneLinePerParagraph() {
        let ttml = document(timing: "Line", body: """
        <div><p begin="1.5" end="4" itunes:key="L1">line one</p><p begin="5.25" end="8" itunes:key="L2">line two</p></div>
        <div><p begin="0:09.000" end="12" itunes:key="L3">la la</p></div>
        """)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([
            LyricLine(time: 1.5, text: "line one"), LyricLine(time: 5.25, text: "line two"), LyricLine(time: 9, text: "la la"),
        ]))
    }

    @Test func linesAreSortedByTime() {
        let ttml = document(timing: "Line", body: #"<div><p begin="9">late</p><p begin="2">early</p></div>"#)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([LyricLine(time: 2, text: "early"), LyricLine(time: 9, text: "late")]))
    }

    @Test func aParagraphWithoutTimeOrTextIsSkipped() {
        let ttml = document(timing: "Line", body: #"<div><p>no time</p><p begin="3"></p><p begin="4"> </p><p begin="5">kept</p></div>"#)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([LyricLine(time: 5, text: "kept")]))
    }

    @Test func whitespaceInsideATextIsCollapsed() {
        let ttml = document(timing: "Line", body: "<div><p begin=\"1\">  line\n   one\t</p></div>")
        #expect(TTMLLyricsParser.parse(ttml) == .synced([LyricLine(time: 1, text: "line one")]))
    }

    @Test func entitiesAreDecoded() {
        let ttml = document(timing: "Line", body: #"<div><p begin="1">la &amp; la &lt;3 &#233;</p></div>"#)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([LyricLine(time: 1, text: "la & la <3 é")]))
    }

    // MARK: word timing

    @Test func syllablesOfOneWordJoinWithoutASpace() {
        let ttml = document(timing: "Word", body: """
        <div><p begin="1.0" end="3.0"><span begin="1.0" end="1.4">la</span><span begin="1.4" end="2.0">la</span> <span begin="2.0" end="3.0">land</span></p></div>
        """)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([
            LyricLine(time: 1, words: [word("la", 1, 1.4), word("la ", 1.4, 2), word("land", 2, 3)]),
        ]))
    }

    @Test func whitespaceNodesBetweenSpansAreKept() {
        let ttml = document(timing: "Word", body: """
        <div><p begin="1"><span begin="1">one</span>
        <span begin="2">two</span> <span begin="3">three</span></p></div>
        """)
        let result = TTMLLyricsParser.parse(ttml)
        guard case .synced(let lines)? = result else { Issue.record("not synced: \(String(describing: result))"); return }
        #expect(lines.map(\.text) == ["one two three"])
        #expect(lines.first?.words?.map(\.text) == ["one ", "two ", "three"])
    }

    @Test func backgroundVocalsAreSkipped() {
        let ttml = document(timing: "Word", body: """
        <div><p begin="1"><span begin="1">main</span> <span ttm:role="x-bg"><span begin="2">(<span>echo</span>)</span></span> <span begin="3">words</span></p>
        <p begin="5"><span ttm:role="x-bg"><span begin="5">(only</span> <span begin="6">echo)</span></span></p></div>
        """)
        // The second paragraph holds nothing but a background vocal, so there is no line for it.
        let result = TTMLLyricsParser.parse(ttml)
        guard case .synced(let lines)? = result else { Issue.record("not synced: \(String(describing: result))"); return }
        #expect(lines.map(\.text) == ["main words"])
        // Nor are the echo's syllables among the words.
        #expect(lines.first?.words?.map(\.text) == ["main ", "words"])
    }

    @Test func translationsAndTransliterationsInsideAParagraphAreSkipped() {
        let ttml = document(timing: "Word", body: """
        <div><p begin="1"><span begin="1" end="2">sung</span><span ttm:role="x-translation">other words</span><span ttm:role="x-roman">more words</span></p></div>
        """)
        let result = TTMLLyricsParser.parse(ttml)
        guard case .synced(let lines)? = result else { Issue.record("not synced: \(String(describing: result))"); return }
        #expect(lines.map(\.text) == ["sung"])
        #expect(lines.first?.words?.map(\.text) == ["sung"])
    }

    @Test func aParagraphWithoutABeginTakesItsFirstSpansTime() {
        let ttml = document(timing: "Word", body: #"<div><p><span begin="2.5">one</span> <span begin="3">two</span></p></div>"#)
        let result = TTMLLyricsParser.parse(ttml)
        guard case .synced(let lines)? = result else { Issue.record("not synced: \(String(describing: result))"); return }
        #expect(lines.map(\.time) == [2.5])
        #expect(lines.map(\.text) == ["one two"])
    }

    @Test func theTimingIsReadWhateverItsCase() {
        let ttml = document(timing: "word", body: #"<div><p begin="1"><span begin="1" end="2">one</span></p></div>"#)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([LyricLine(time: 1, words: [word("one", 1, 2)])]))
    }

    // MARK: word times

    @Test func eachSpanIsAWordFromItsBeginToItsEnd() {
        let ttml = document(timing: "Word", body: """
        <div><p begin="1.0" end="3.5"><span begin="1.0" end="1.5">one</span> <span begin="1.5" end="2.25">two</span> <span begin="2.5" end="3.5">three</span></p></div>
        """)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([
            LyricLine(time: 1, words: [word("one ", 1, 1.5), word("two ", 1.5, 2.25), word("three", 2.5, 3.5)]),
        ]))
    }

    @Test func aSpanWithoutAnEndEndsWhereTheNextOneBegins() {
        let ttml = document(timing: "Word", body: #"<div><p begin="1"><span begin="1">one</span> <span begin="2.5" end="3">two</span></p></div>"#)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([LyricLine(time: 1, words: [word("one ", 1, 2.5), word("two", 2.5, 3)])]))
    }

    @Test func theLastSpanWithoutAnEndEndsWithTheParagraphOrElseAfterASecond() {
        let withEnd = document(timing: "Word", body: #"<div><p begin="1" end="4"><span begin="1" end="2">one</span> <span begin="2">two</span></p></div>"#)
        #expect(TTMLLyricsParser.parse(withEnd) == .synced([LyricLine(time: 1, words: [word("one ", 1, 2), word("two", 2, 4)])]))
        let without = document(timing: "Word", body: #"<div><p begin="1"><span begin="1" end="2">one</span> <span begin="2">two</span></p></div>"#)
        #expect(TTMLLyricsParser.parse(without) == .synced([LyricLine(time: 1, words: [word("one ", 1, 2), word("two", 2, 3)])]))
    }

    @Test func theLastSpanWithoutAnEndStopsWhereTheNextParagraphBegins() {
        let ttml = document(timing: "Word", body: """
        <div><p begin="1"><span begin="1" end="1.2">one</span> <span begin="1.2">two</span></p><p begin="1.5"><span begin="1.5" end="2">next</span> <span begin="2" end="3">one</span></p></div>
        """)
        guard case .synced(let lines)? = TTMLLyricsParser.parse(ttml) else { Issue.record("not synced"); return }
        #expect(lines.first?.words?.last == word("two", 1.2, 1.5))
    }

    @Test func spansThatOverlapOrRunBackwardsNeverMakeWordsOverlap() {
        let ttml = document(timing: "Word", body: """
        <div><p begin="1"><span begin="1" end="3">one</span> <span begin="2" end="4">two</span> <span begin="1.5" end="5">three</span> <span begin="6" end="5">four</span></p></div>
        """)
        guard case .synced(let lines)? = TTMLLyricsParser.parse(ttml), let words = lines.first?.words else { Issue.record("no words"); return }
        #expect(words.map(\.text) == ["one ", "two ", "three ", "four"])
        for (earlier, later) in zip(words, words.dropFirst()) {
            #expect(earlier.begin <= earlier.end)
            #expect(earlier.end <= later.begin)
        }
        #expect(words[0] == word("one ", 1, 2))
    }

    @Test func aSpanWithoutABeginIsTextOfTheWordBeforeIt() {
        let ttml = document(timing: "Word", body: #"<div><p begin="1"><span begin="1" end="2">one</span><span> two</span> <span begin="3" end="4">three</span></p></div>"#)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([LyricLine(time: 1, words: [word("one two ", 1, 2), word("three", 3, 4)])]))
    }

    @Test func wordsAreReadFromSpansNestedInASpanToo() {
        let ttml = document(timing: "Word", body: #"<div><p begin="1"><span begin="1" end="2"><span>on</span>e</span> <span begin="2" end="3">two</span></p></div>"#)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([LyricLine(time: 1, words: [word("one ", 1, 2), word("two", 2, 3)])]))
    }

    @Test func lineTimingGivesNoWordsEvenWhereSpansHaveTimes() {
        let ttml = document(timing: "Line", body: #"<div><p begin="1"><span begin="1" end="2">one</span> <span begin="2" end="3">two</span></p></div>"#)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([LyricLine(time: 1, text: "one two")]))
    }

    @Test func spansWithNoTimeAtAllGiveALineWithoutWords() {
        let ttml = document(timing: "Word", body: #"<div><p begin="1"><span>one</span> <span>two</span></p></div>"#)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([LyricLine(time: 1, text: "one two")]))
    }

    @Test func aParagraphWithoutSpansAmongOnesWithThemStaysALine() {
        let ttml = document(timing: "Word", body: """
        <div><p begin="1"><span begin="1" end="2">one</span> <span begin="2" end="3">two</span></p><p begin="4">plain</p></div>
        """)
        guard case .synced(let lines)? = TTMLLyricsParser.parse(ttml) else { Issue.record("not synced"); return }
        #expect(lines.map { $0.words != nil } == [true, false])
        #expect(lines.last == LyricLine(time: 4, text: "plain"))
    }

    @Test func entitiesAndCDATAInSpansAreInTheWords() {
        let ttml = document(timing: "Word", body: #"<div><p begin="1"><span begin="1" end="2">la &amp;</span> <span begin="2" end="3"><![CDATA[<3]]></span></p></div>"#)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([LyricLine(time: 1, words: [word("la & ", 1, 2), word("<3", 2, 3)])]))
    }

    @Test func theTextOfEveryLineIsItsWordsJoined() {
        let ttml = document(timing: "Word", body: """
        <div><p begin="1">  <span begin="1" end="2">  one </span>
        <span begin="2" end="3">two</span><span begin="3" end="4">  three</span>  </p></div>
        """)
        guard case .synced(let lines)? = TTMLLyricsParser.parse(ttml), let line = lines.first else { Issue.record("not synced"); return }
        #expect(line.text == "one two three")
        #expect(line.words?.map(\.text).joined() == line.text)
    }

    // MARK: no timing

    @Test func noTimingGivesPlainLinesJoinedByNewlines() {
        let ttml = document(timing: "None", body: """
        <div><p itunes:key="L1">line one</p><p itunes:key="L2">line two</p></div><div><p itunes:key="L3"> </p><p itunes:key="L4">la la</p></div>
        """)
        #expect(TTMLLyricsParser.parse(ttml) == .plain("line one\nline two\nla la"))
    }

    @Test func noTimingIgnoresBeginAttributes() {
        let ttml = document(timing: "None", body: #"<div><p begin="1">line one</p></div>"#)
        #expect(TTMLLyricsParser.parse(ttml) == .plain("line one"))
    }

    @Test func aMissingTimingIsReadFromTheParagraphs() {
        #expect(TTMLLyricsParser.parse(document(timing: nil, body: #"<div><p begin="2">timed</p></div>"#)) == .synced([LyricLine(time: 2, text: "timed")]))
        #expect(TTMLLyricsParser.parse(document(timing: nil, body: "<div><p>untimed</p></div>")) == .plain("untimed"))
    }

    // MARK: head

    @Test func theHeadIsIgnored() {
        let head = """
        <metadata><ttm:agent type="person" xml:id="v1"/><iTunesMetadata xmlns="http://music.apple.com/lyric-ttml-internal">
        <songwriters><songwriter>Some Writer</songwriter></songwriters>
        <translations><translation type="subtitle" xml:lang="vi"><text for="L1">translated words</text></translation></translations>
        </iTunesMetadata></metadata>
        <p begin="0">not a lyric</p>
        """
        let ttml = document(timing: "Line", body: #"<div><p begin="1" itunes:key="L1">line one</p></div>"#, head: head)
        #expect(TTMLLyricsParser.parse(ttml) == .synced([LyricLine(time: 1, text: "line one")]))
    }

    // MARK: times

    @Test(arguments: [
        ("12.345", 12.345), ("12", 12), ("0.5", 0.5), ("1:02.345", 62.345), ("1:02", 62), ("01:02:03.456", 3723.456),
        ("0:00:07.5", 7.5), ("12.3s", 12.3), ("12s", 12), ("00:01.050", 1.05), ("3.2", 3.2), ("1:02.3456", 62.345),
    ])
    func timeFormats(text: String, seconds: Double) {
        #expect(TTMLLyricsParser.seconds(text) == seconds)
    }

    @Test(arguments: ["", "s", "abc", "1:", ":5", "1::2", "1:2:3:4", "-1", "1.2.3", "1.", ".5", "1,5", "1e3", "12 s", "1:xx", "99999999999"])
    func badTimes(text: String) {
        #expect(TTMLLyricsParser.seconds(text) == nil)
        #expect(TTMLLyricsParser.seconds(nil) == nil)
    }

    // MARK: malformed

    @Test(arguments: [
        "", "   ", "not xml at all", "<html><body><p>Sign in</p></body></html>",
        #"<tt xmlns="http://www.w3.org/ns/ttml" itunes:timing="Line"><body><div><p begin="1">unclosed</div></body></tt>"#,
        #"<tt xmlns="http://www.w3.org/ns/ttml" itunes:timing="Line"><body><div><p begin="1">cut off"#,
        #"<tt xmlns="http://www.w3.org/ns/ttml" itunes:timing="Line"><body></body></tt>"#,
        #"<tt xmlns="http://www.w3.org/ns/ttml" itunes:timing="None"><body><div><p> </p></div></body></tt>"#,
    ])
    func malformedOrEmptyIsNil(text: String) {
        #expect(TTMLLyricsParser.parse(text) == nil)
    }

    @Test func lineTimingWithoutAnyTimedParagraphIsNil() {
        #expect(TTMLLyricsParser.parse(document(timing: "Line", body: "<div><p>no time</p></div>")) == nil)
    }
}
