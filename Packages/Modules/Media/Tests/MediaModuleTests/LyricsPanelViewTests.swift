import AppKit
import SwiftUI
import Testing
@testable import MediaModule

@Suite struct LyricsPanelViewTests {
    let timed = LyricLine(time: 10, words: [
        LyricWord(text: "one ", begin: 10, end: 11), LyricWord(text: "two ", begin: 11, end: 12), LyricWord(text: "three", begin: 12, end: 14),
    ])
    let plain = LyricLine(time: 20, text: "a plain line")
    let pause = LyricLine(time: 16, text: "")

    func makeStore(elapsed: Double?, karaoke: Bool = true, lyrics: [LyricLine]? = nil, lyricsOn: Bool = true) -> NowPlayingStore {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        if let elapsed { store.apply(line: AdapterLines.track(elapsed: elapsed), receivedAt: Date()) }
        store.setLyricsOn(lyricsOn)
        if let lyrics { store.showLyrics(lyrics) }
        store.setKaraokeEnabled(karaoke)
        return store
    }

    func host<Content: View>(_ content: Content) -> (NSView, NSWindow) {
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 130), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    /// A panel whose window is seen, awake and unlocked.
    func visible() -> LyricsPanelPresence {
        let presence = LyricsPanelPresence()
        presence.setWindowVisible(true)
        return presence
    }

    func run(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func karaokeViews(in view: NSView) -> [KaraokeLineView] {
        (view as? KaraokeLineView).map { [$0] } ?? view.subviews.flatMap { karaokeViews(in: $0) }
    }

    // MARK: what it shows

    @Test func withLyricsItShowsTheThreeLines() {
        let store = makeStore(elapsed: 21, lyrics: [timed, pause, plain, LyricLine(time: 30, text: "after")])
        guard case .lines(let lines) = store.lyricsPanelContent(at: Date()) else { Issue.record("no lines"); return }
        #expect(lines.previous?.text == "one two three")
        #expect(lines.current?.text == "a plain line")
        #expect(lines.next?.text == "after")
    }

    @Test func withoutSyncedLyricsItSaysWhy() {
        func message(_ store: NowPlayingStore) -> String? {
            if case .message(let text) = store.lyricsPanelContent(at: Date()) { text } else { nil }
        }
        #expect(message(makeStore(elapsed: nil)) == "Không có gì đang phát")
        #expect(message(makeStore(elapsed: 5, lyricsOn: false)) == "Bật nguồn lời bài hát trong Cài đặt")
        #expect(message(makeStore(elapsed: 5)) == "Chưa có lời đồng bộ cho bài này")
        let unsynced = makeStore(elapsed: 5)
        unsynced.showUnsyncedLyrics()
        #expect(message(unsynced) == "Chỉ có lời không đồng bộ")
    }

    @Test func theMessageGivesWayToTheLinesAsSoonAsThereAreSome() {
        let store = makeStore(elapsed: 11)
        #expect(store.lyricsPanelContent(at: Date()) == .message("Chưa có lời đồng bộ cho bài này"))
        store.showLyrics([timed])
        if case .lines = store.lyricsPanelContent(at: Date()) {} else { Issue.record("still a message") }
    }

    @Test func theLyricsHiddenFromTheNotchAreStillInThePanel() {
        let store = makeStore(elapsed: 11, lyrics: [timed])
        store.toggleLyricsHidden()
        if case .lines = store.lyricsPanelContent(at: Date()) {} else { Issue.record("hidden with the notch's") }
    }

    // MARK: the fill

    @Test func theCurrentLineIsFilledWordByWord() throws {
        let store = makeStore(elapsed: 11.5, lyrics: [timed, plain])
        let (hosting, window) = host(LyricsPanelView(store: store, model: LyricsPanelModel(fontSize: 22), presence: visible()))
        let view = try #require(karaokeViews(in: hosting).first)
        #expect(karaokeViews(in: hosting).count == 1)
        #expect((view.litLayer.string as? String) == "one two three")
        #expect(view.litLayer.fontSize == 22)
        window.contentView = nil
    }

    @Test func withKaraokeOffOrWithoutWordTimingTheLineIsPlainText() {
        for (elapsed, karaoke) in [(11.5, false), (21.0, true), (17.0, true)] {
            let store = makeStore(elapsed: elapsed, karaoke: karaoke, lyrics: [timed, pause, plain])
            let (hosting, window) = host(LyricsPanelView(store: store, model: LyricsPanelModel(fontSize: 22), presence: visible()))
            #expect(karaokeViews(in: hosting).isEmpty, "\(elapsed) \(karaoke)")
            window.contentView = nil
        }
    }

    @Test func theFontSizeSettingIsTheCurrentLinesAndTheNeighboursAreSmaller() throws {
        #expect(LyricsPanelView.neighbourSize(for: 30) == 21)
        #expect(LyricsPanelView.neighbourSize(for: 12) == LyricsPanelView.minimumNeighbourSize)
        let store = makeStore(elapsed: 11.5, lyrics: [timed])
        let model = LyricsPanelModel(fontSize: 22)
        let (hosting, window) = host(LyricsPanelView(store: store, model: model, presence: visible()))
        model.fontSize = 30
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(try #require(karaokeViews(in: hosting).first).litLayer.fontSize == 30)
        window.contentView = nil
    }

    @Test func whileThePanelCannotBeSeenTheSweepStandsStillAndItComesBackWithThePanel() throws {
        let store = makeStore(elapsed: 11.5, lyrics: [timed, plain])
        let presence = LyricsPanelPresence()
        let (hosting, window) = host(LyricsPanelView(store: store, model: LyricsPanelModel(fontSize: 22), presence: presence))
        run(for: 0.1)
        // The views are made again when the panel goes out of sight and comes back, so each step looks them up anew.
        func isAnimating() throws -> Bool { try #require(karaokeViews(in: hosting).first).isAnimating }
        // The window has not been seen yet.
        #expect(try !isAnimating())
        presence.setWindowVisible(true)
        run(for: 0.1)
        #expect(try isAnimating())
        presence.apply(.screenLocked)
        run(for: 0.1)
        #expect(try !isAnimating())
        presence.apply(.screenUnlocked)
        run(for: 0.1)
        #expect(try isAnimating())
        presence.apply(.displaysSlept)
        run(for: 0.1)
        #expect(try !isAnimating())
        presence.apply(.displaysWoke)
        presence.setWindowVisible(false)
        run(for: 0.1)
        #expect(try !isAnimating())
        window.contentView = nil
    }

    @Test func thePanelFillsTheWindowItIsIn() {
        let store = makeStore(elapsed: 11.5, lyrics: [timed])
        let (hosting, window) = host(LyricsPanelView(store: store, model: LyricsPanelModel(fontSize: 22), presence: visible()))
        #expect(hosting.frame.size == CGSize(width: 420, height: 130))
        window.contentView = nil
    }

    @Test func theSizeSettingStaysWithinWhatFits() {
        #expect(LyricsPanelModel.fontSizeRange.contains(LyricsPanelModel.defaultFontSize))
        #expect(LyricsPanelModel(fontSize: 3).fontSize == LyricsPanelModel.fontSizeRange.lowerBound)
        #expect(LyricsPanelModel(fontSize: 300).fontSize == LyricsPanelModel.fontSizeRange.upperBound)
    }
}
