import Foundation
import Testing
@testable import MediaModule

/// How the pieces of a line that a parser found become the words of its karaoke. Placeholder words only.
@Suite struct LyricWordTimingTests {
    typealias Piece = LyricWordTiming.Piece

    func piece(_ text: String, _ begin: Double?, _ end: Double? = nil) -> Piece { Piece(text: text, begin: begin, end: end) }

    func word(_ text: String, _ begin: Double, _ end: Double) -> LyricWord { LyricWord(text: text, begin: begin, end: end) }

    // MARK: the model

    @Test func aLineMadeOfWordsReadsAsTheirTextJoined() {
        let line = LyricLine(time: 1, words: [word("one ", 1, 2), word("two", 2, 3)])
        #expect(line.text == "one two")
        #expect(line.time == 1)
        #expect(line.words?.count == 2)
    }

    @Test func aLineWithoutWordsHasNone() {
        #expect(LyricLine(time: 1, text: "one two").words == nil)
    }

    @Test func linesWithWordsSurviveTheCacheAndOldCacheEntriesStillDecode() throws {
        let line = LyricLine(time: 1, words: [word("one ", 1, 2), word("two", 2, 3)])
        let result = LyricsResult.synced([line, LyricLine(time: 4, text: "plain line")])
        let decoded = try JSONDecoder().decode(LyricsResult.self, from: JSONEncoder().encode(result))
        #expect(decoded == result)
        // What a version before word timing wrote: no `words` key at all.
        let old = #"{"synced":{"_0":[{"time":1.5,"text":"old line"}]}}"#
        #expect(try JSONDecoder().decode(LyricsResult.self, from: Data(old.utf8)) == .synced([LyricLine(time: 1.5, text: "old line")]))
    }

    // MARK: ends

    @Test func aWordWithoutAnEndEndsWhereTheNextOneBegins() {
        let words = LyricWordTiming.words(from: [piece("a ", 1), piece("b ", 1.5), piece("c", 2.5, 3)])
        #expect(words == [word("a ", 1, 1.5), word("b ", 1.5, 2.5), word("c", 2.5, 3)])
    }

    @Test func theLastWordWithoutAnEndGetsASecond() {
        let words = LyricWordTiming.words(from: [piece("a ", 1, 1.5), piece("b", 1.5)])
        #expect(words == [word("a ", 1, 1.5), word("b", 1.5, 2.5)])
    }

    @Test func theLastWordWithoutAnEndStopsWhereTheNextLineStarts() {
        let words = LyricWordTiming.words(from: [piece("a ", 1, 1.5), piece("b", 1.5)], before: 1.9)
        #expect(words?.last == word("b", 1.5, 1.9))
        // A next line that is further off than a second changes nothing.
        #expect(LyricWordTiming.words(from: [piece("a ", 1, 1.5), piece("b", 1.5)], before: 20)?.last == word("b", 1.5, 2.5))
    }

    @Test func aKnownEndOfTheLineIsTheEndOfItsLastWord() {
        let words = LyricWordTiming.words(from: [piece("a ", 1, 1.5), piece("b", 1.5)], endsAt: 4.25)
        #expect(words?.last == word("b", 1.5, 4.25))
    }

    @Test func anEndBeforeTheBeginIsTheBegin() {
        #expect(LyricWordTiming.words(from: [piece("a ", 2, 1), piece("b", 3, 4)])?.first == word("a ", 2, 2))
    }

    // MARK: order

    @Test func aWordThatBeginsBeforeTheEndOfThePreviousOneCutsItShort() {
        let words = LyricWordTiming.words(from: [piece("a ", 1, 3), piece("b", 2, 4)])
        #expect(words == [word("a ", 1, 2), word("b", 2, 4)])
    }

    @Test func aWordThatBeginsBeforeThePreviousOneIsRaisedToIt() {
        let words = LyricWordTiming.words(from: [piece("a ", 5, 6), piece("b ", 4, 7), piece("c", 8, 9)])
        #expect(words == [word("a ", 5, 5), word("b ", 5, 7), word("c", 8, 9)])
    }

    @Test func wordsAreNeverOutOfOrderWhateverTheInput() {
        let begins: [Double] = [3, 1, 2, 2, 9, 0, 4]
        let pieces = begins.enumerated().map { piece("w\($0.offset) ", $0.element, $0.element + 5) }
        let words = LyricWordTiming.words(from: pieces) ?? []
        #expect(words.count == begins.count)
        for (earlier, later) in zip(words, words.dropFirst()) {
            #expect(earlier.begin <= earlier.end)
            #expect(earlier.end <= later.begin)
        }
        #expect(words.last.map { $0.begin <= $0.end } == true)
    }

    // MARK: text

    @Test func textThatNoTimeWasGivenJoinsTheWordBeforeIt() {
        let words = LyricWordTiming.words(from: [piece("one", 1, 2), piece(" ", nil), piece("two", 2, 3)])
        #expect(words == [word("one ", 1, 2), word("two", 2, 3)])
    }

    @Test func untimedTextBeforeTheFirstWordJoinsIt() {
        #expect(LyricWordTiming.words(from: [piece("oh ", nil), piece("one", 1, 2)])?.first == word("oh one", 1, 2))
    }

    @Test func whitespaceIsCollapsedAcrossWordsAndTrimmedAtBothEnds() {
        let words = LyricWordTiming.words(from: [piece("  one \n ", 1, 2), piece("  two\t", 2, 3), piece("  ", 3, 4)])
        #expect(words == [word("one ", 1, 2), word("two", 2, 3)])
        #expect(words?.map(\.text).joined() == "one two")
    }

    @Test func aTimedPieceOfNothingButSpaceJoinsThePreviousWordOrIsDropped() {
        let words = LyricWordTiming.words(from: [piece(" ", 0.5, 1), piece("a", 1, 1.5), piece(" ", 1.5, 2), piece("b", 2, 3)])
        #expect(words == [word("a ", 1, 1.5), word("b", 2, 3)])
    }

    @Test func syllablesOfOneWordStayApartWithoutASpace() {
        let words = LyricWordTiming.words(from: [piece("la", 1, 1.4), piece("la", 1.4, 2), piece(" ", nil), piece("land", 2, 3)])
        #expect(words == [word("la", 1, 1.4), word("la ", 1.4, 2), word("land", 2, 3)])
    }

    // MARK: when there are no words

    @Test func nothingTimedGivesNoWords() {
        #expect(LyricWordTiming.words(from: []) == nil)
        #expect(LyricWordTiming.words(from: [piece("just text", nil)]) == nil)
        #expect(LyricWordTiming.words(from: [piece("  ", 1, 2)]) == nil)
    }

    @Test func oneWordThatSaysNothingOfItsLengthIsNoTimingAtAll() {
        // A lone stamp at the start of a line says when it begins, which the line's own time says already.
        #expect(LyricWordTiming.words(from: [piece("whole line", 1)]) == nil)
        #expect(LyricWordTiming.words(from: [piece("whole line", 1, 3)]) == [word("whole line", 1, 3)])
        #expect(LyricWordTiming.words(from: [piece("whole line", 1)], endsAt: 3) == [word("whole line", 1, 3)])
    }
}
