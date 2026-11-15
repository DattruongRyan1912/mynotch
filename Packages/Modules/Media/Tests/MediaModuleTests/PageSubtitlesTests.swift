import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
import YouTubeBridgeKit
@testable import MediaModule

@MainActor
@Suite final class PageSubtitlesTests {
    let scheduler = ManualScheduler()
    let store = NowPlayingStore()
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var date: Date
    var sent: [(TabSubtitle, Int)] = []
    lazy var page = PageSubtitles(store: store, scheduler: scheduler, now: { [unowned self] in date }) { [unowned self] subtitle, connection in
        sent.append((subtitle, connection))
        return true
    }
    let film = TabRef(connection: 2, tab: 7)

    init() {
        date = start
    }

    /// The film at 10 s, playing: a line from 11 s to 13 s, nothing, a line from 20 s.
    func play(at seconds: Double = 10, playing: Bool = true) {
        var state = NowPlayingState(
            bundleIdentifier: "com.google.Chrome", parentApplicationBundleIdentifier: "com.google.Chrome", title: "Film", artist: nil,
            album: nil, durationSeconds: 6_000, isPlaying: playing
        )
        state.elapsedAnchor = PlaybackAnchor(elapsedSeconds: seconds, timestamp: date, rate: playing ? 1 : 0)
        _ = store.show(state, source: "test")
        store.showLyrics([LyricLine(time: 11, text: "Bah, humbug!"), LyricLine(time: 13, text: ""), LyricLine(time: 20, text: "Merry Christmas")])
    }

    func pass(_ seconds: Double) {
        date = date.addingTimeInterval(seconds)
        scheduler.advance(by: .milliseconds(Int64(seconds * 1000)))
    }

    var texts: [String] { sent.map(\.0.text) }

    @Test func eachLineGoesToTheTabWhenItIsDueWithHowLongItMayStay() throws {
        play()
        page.update(target: film)
        #expect(texts == [""])
        let first = try #require(sent.first)
        #expect(first.1 == 2 && first.0.tab == 7)
        #expect(abs(first.0.until - 1.3) < 0.01, "until the next line, and a little past it")
        pass(1.01)
        #expect(texts == ["", "Bah, humbug!"])
        pass(2)
        #expect(texts.last == "")
        // A long gap: said again at the heartbeat, then the next line when it is due.
        pass(PageSubtitles.heartbeat)
        #expect(texts.count == 4)
        pass(3)
        #expect(texts.last == "Merry Christmas")
    }

    @Test func aLineThatStandsIsSaidAgainBeforeItsLifetimeIsOver() {
        play(at: 11.5, playing: false)
        page.update(target: film)
        #expect(sent.last?.0.text == "Bah, humbug!")
        #expect(sent.last?.0.until == PageSubtitles.lifetime)
        pass(PageSubtitles.heartbeat)
        #expect(sent.count == 2)
        #expect(PageSubtitles.heartbeat < PageSubtitles.lifetime)
    }

    @Test func theSameUpdateSendsNothingNewAndAnotherTabOrNoneTakesTheLineAway() {
        play()
        page.update(target: film)
        page.update(target: film)
        #expect(sent.count == 1, "nothing changed")
        let other = TabRef(connection: 2, tab: 9)
        page.update(target: other)
        #expect(sent.map { [$0.0.tab, $0.0.text.isEmpty ? 0 : 1] } == [[7, 0], [7, 0], [9, 0]], "the old tab is cleared, the new one told")
        page.update(target: nil)
        #expect(sent.last?.0.tab == 9 && sent.last?.0.text == "")
        let count = sent.count
        pass(30)
        #expect(sent.count == count, "and nothing more is sent")
    }

    @Test func whereAndHowLargeGoWithTheLine() {
        play(at: 11.5)
        page.gap = 0.2
        page.scale = 1.5
        page.update(target: film)
        #expect(sent.last.map { [$0.0.gap, $0.0.scale] } == [0.2, 1.5])
    }
}
