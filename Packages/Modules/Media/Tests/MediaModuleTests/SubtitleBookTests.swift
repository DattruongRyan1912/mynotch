import Foundation
import MyNotchTestSupport
import Testing
@testable import MediaModule

@MainActor @Suite final class SubtitleBookTests {
    let directory = ScratchFolders.shared.reserveShort()
    let srt = Data("1\n00:00:01,000 --> 00:00:02,000\nHello\n".utf8)

    deinit { try? FileManager.default.removeItem(at: directory) }

    func state(_ title: String, bundle: String = "com.google.Chrome") -> NowPlayingState {
        NowPlayingState(bundleIdentifier: bundle, title: title)
    }

    func book() -> SubtitleBook {
        let book = SubtitleBook()
        book.open(directory: directory)
        return book
    }

    @Test func theKeyIsThePlayerAndTheTitleWhateverItsCaseAndSpacing() {
        #expect(SubtitleBook.key(for: state("The  Intern")) == SubtitleBook.key(for: state("the intern")))
        #expect(SubtitleBook.key(for: state("The Intern")) != SubtitleBook.key(for: state("The Intern", bundle: "com.colliderli.iina")))
        #expect(SubtitleBook.key(for: .empty) == nil)
    }

    @Test func aLoadedFileIsKeptForThatVideoAndComesBackAfterARestart() {
        let first = book()
        first.setCurrentKey(SubtitleBook.key(for: state("The Intern")))
        #expect(first.load(srt, name: "intern.srt"))
        first.shift(by: 1.5)

        let second = book()
        second.setCurrentKey(SubtitleBook.key(for: state("the intern")))
        #expect(second.current?.name == "intern.srt")
        #expect(second.current?.delay == 1.5)
        #expect(second.current?.cues == [SubtitleCue(start: 1, end: 2, text: "Hello")])
        second.setCurrentKey(SubtitleBook.key(for: state("Another film")))
        #expect(second.current == nil)
    }

    @Test func aFileWithNoSubtitleChangesNothingAndIsNamedUntilTheVideoChanges() {
        let book = book()
        book.setCurrentKey(SubtitleBook.key(for: state("Film")))
        book.load(srt, name: "good.srt")
        #expect(!book.load(Data("nothing".utf8), name: "bad.txt"))
        #expect(book.current?.name == "good.srt")
        #expect(book.unreadableName == "bad.txt")
        book.setCurrentKey(SubtitleBook.key(for: state("Other")))
        #expect(book.unreadableName == nil)
    }

    @Test func stepsAddUpExactlyAndTheDelayResets() {
        let book = book()
        book.setCurrentKey(SubtitleBook.key(for: state("Film")))
        book.load(srt, name: "a.srt")
        for _ in 0..<3 { book.shift(by: -SubtitleBook.smallStep) }
        #expect(book.current?.delay == -1.5)
        book.resetDelay()
        #expect(book.current?.delay == 0)
    }

    @Test func removingForgetsOnlyTheCurrentVideo() {
        let book = book()
        book.setCurrentKey(SubtitleBook.key(for: state("A")))
        book.load(srt, name: "a.srt")
        book.setCurrentKey(SubtitleBook.key(for: state("B")))
        book.load(srt, name: "b.srt")
        book.remove()
        #expect(book.current == nil)
        #expect(self.book().entries.count == 1)
    }

    @Test func theOldestFilmsAreLetGoPastTheLimit() {
        var clock = Date(timeIntervalSince1970: 0)
        let book = SubtitleBook(now: { clock })
        book.open(directory: directory)
        for index in 0...SubtitleBook.maxEntries {
            clock += 1
            book.setCurrentKey(SubtitleBook.key(for: state("Film \(index)")))
            book.load(srt, name: "\(index).srt")
        }
        #expect(book.entries.count == SubtitleBook.maxEntries)
        #expect(book.entries[SubtitleBook.key(for: state("Film 0"))!] == nil)
    }
}
