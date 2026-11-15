import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MediaModule

@MainActor @Suite struct SubtitleQuickControlTests {
    let book = SubtitleBook()

    var controls: SubtitleControls {
        SubtitleControls(book: book, load: { _ in }, shift: { _ in }, resetDelay: {}, remove: {})
    }

    func state(bundle: String = "com.example.Player", duration: Double = 200) -> NowPlayingState {
        NowPlayingState(bundleIdentifier: bundle, title: "Title", durationSeconds: duration)
    }

    @Test func itIsThereForFilmsAndPagesButNotForSongs() {
        #expect(SubtitleQuickControl.isShown(controls, for: state(bundle: "com.google.Chrome")))
        #expect(SubtitleQuickControl.isShown(controls, for: state(duration: 2 * 60 * 60)))
        #expect(!SubtitleQuickControl.isShown(controls, for: state()))
        #expect(!SubtitleQuickControl.isShown(controls, for: .empty))
        #expect(!SubtitleQuickControl.isShown(nil, for: state(bundle: "com.google.Chrome")))
    }

    @Test func aSongWithSubtitlesLoadedKeepsTheControl() {
        let song = state()
        book.setCurrentKey(SubtitleBook.key(for: song))
        book.load(Data("00:00:01,000 --> 00:00:02,000\nla\n".utf8), name: "song.srt")
        #expect(SubtitleQuickControl.isShown(controls, for: song))
    }

    @Test func theFigureIsHowMuchSoonerTheLinesComeAsPlusReads() {
        #expect(SubtitleQuickControl.offsetText(delay: 0) == "0s")
        #expect(SubtitleQuickControl.offsetText(delay: -1.5) == "+1.5s")
        #expect(SubtitleQuickControl.offsetText(delay: 0.5) == "−0.5s")
        #expect(SubtitleQuickControl.offsetText(delay: 4) == "−4s", "four seconds later than the file reads as behind")
        #expect(SubtitleQuickControl.soonerHelp == "Hiện phụ đề sớm hơn 0.5s")
    }

    /// The control's width with the film's subtitles moved by `delay`.
    func width(delay: Double) -> CGFloat {
        let film = state(bundle: "com.google.Chrome")
        book.setCurrentKey(SubtitleBook.key(for: film))
        book.load(Data("00:00:01,000 --> 00:00:02,000\nla\n".utf8), name: "film.srt")
        book.resetDelay()
        book.shift(by: delay)
        return NSHostingView(rootView: SubtitleQuickControl(controls: controls, state: film)).fittingSize.width
    }

    @Test func theButtonsStayPutWhateverTheFigureSays() {
        let widths = [0, 3, 3.5, -0.5, -12.5, 25].map(width(delay:))
        #expect(Set(widths).count == 1, "widths \(widths)")
    }
}
