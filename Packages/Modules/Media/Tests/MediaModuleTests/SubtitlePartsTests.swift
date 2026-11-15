import Foundation
import MyNotchTestSupport
import Testing
@testable import MediaModule

/// A film with an advertisement spliced in: what follows it plays later, the subtitles a part of their own.
@MainActor @Suite final class SubtitlePartsTests {
    let directory = ScratchFolders.shared.reserveShort()
    /// A line at 10 s and one at 100 s of the film.
    let srt = Data("1\n00:00:10,000 --> 00:00:12,000\nBefore\n\n2\n00:01:40,000 --> 00:01:42,000\nAfter\n".utf8)

    deinit { try? FileManager.default.removeItem(at: directory) }

    func book() -> SubtitleBook {
        let book = SubtitleBook()
        book.open(directory: directory)
        book.setCurrentKey(SubtitleBook.key(for: NowPlayingState(bundleIdentifier: "com.google.Chrome", title: "Film")))
        book.load(srt, name: "film.srt")
        return book
    }

    @Test func subtitlesNeverMovedAreMovedAllThroughByWhatListeningFound() {
        let book = book()
        book.setDelay(3.5, from: 60, at: 70)
        #expect(book.current?.delay == 3.5)
        #expect(book.current?.parts == [])
    }

    @Test func aDelayFarFromTheOneInForceIsANewPartFromWhereListeningStarted() throws {
        let book = book()
        book.shift(by: 3.5)
        // A 25 s advertisement somewhere before 60 s.
        book.setDelay(28.5, from: 60, at: 90)
        let entry = try #require(book.current)
        #expect(entry.delay == 3.5)
        #expect(entry.parts == [.init(from: 60, delay: 28.5)])
        #expect(entry.delay(at: 30) == 3.5)
        #expect(entry.delay(at: 95) == 28.5)
        #expect(entry.delay(at: nil) == 3.5)
        // The first line stays where it was, the second follows the advertisement.
        #expect(SubtitleParser.lines(for: entry).map(\.time) == [13.5, 15.5, 128.5, 130.5])
    }

    @Test func aDelayCloseToTheOneInForceOnlySetsThatPartRight() throws {
        let book = book()
        book.shift(by: 3.5)
        book.setDelay(28.5, from: 60, at: 90)
        book.setDelay(28.9, from: 120, at: 150)
        let entry = try #require(book.current)
        #expect(entry.parts == [.init(from: 60, delay: 28.9)])
        #expect(entry.delay == 3.5)
    }

    @Test func aNudgeMovesThePartPlayingOnly() throws {
        let book = book()
        book.shift(by: 3.5)
        book.setDelay(28.5, from: 60, at: 90)
        book.shift(by: 0.5, at: 95)
        #expect(book.current?.parts == [.init(from: 60, delay: 29)])
        book.shift(by: -0.5, at: 20)
        #expect(book.current?.delay == 3)
    }

    @Test func aNewAdvertisementLetsGoThePartsWorkedOutAfterIt() throws {
        let book = book()
        book.shift(by: 1)
        book.setDelay(20, from: 60, at: 90)
        book.setDelay(40, from: 300, at: 320)
        book.setDelay(10, from: 200, at: 230)
        #expect(book.current?.parts == [.init(from: 60, delay: 20), .init(from: 200, delay: 10)])
    }

    @Test func resettingTakesThePartsAwayAndTheyAreRemembered() throws {
        let book = book()
        book.shift(by: 3.5)
        book.setDelay(28.5, from: 60, at: 90)
        let again = SubtitleBook()
        again.open(directory: directory)
        again.setCurrentKey(SubtitleBook.key(for: NowPlayingState(bundleIdentifier: "com.google.Chrome", title: "Film")))
        #expect(again.current?.parts == [.init(from: 60, delay: 28.5)])
        again.resetDelay()
        #expect(again.current?.isMoved == false)
    }

    @Test func aFileFromBeforeThereWerePartsReadsAsOnePart() throws {
        let old = Data(#"{"name":"a.srt","cues":[{"start":1,"end":2,"text":"Hi"}],"delay":2,"usedAt":0}"#.utf8)
        let entry = try JSONDecoder().decode(SubtitleBook.Entry.self, from: old)
        #expect(entry.delay == 2)
        #expect(entry.parts.isEmpty)
    }
}
