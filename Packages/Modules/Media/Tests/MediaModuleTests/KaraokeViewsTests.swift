import AppKit
import MyNotchCore
import NotchUI
import SwiftUI
import Testing
@testable import MediaModule

/// The strip under the notch and the Media tab's row, in hosting views that are never shown, with and without a karaoke line.
@Suite struct KaraokeViewsTests {
    let timed = LyricLine(time: 10, words: [
        LyricWord(text: "one ", begin: 10, end: 11), LyricWord(text: "two ", begin: 11, end: 12), LyricWord(text: "three", begin: 12, end: 14),
    ])
    let plain = LyricLine(time: 20, text: "a plain line")
    let later = LyricLine(time: 30, words: [LyricWord(text: "four ", begin: 30, end: 31), LyricWord(text: "five", begin: 31, end: 32)])

    func makeStore(elapsed: Double, karaoke: Bool = true, lines: [LyricLine]? = nil) -> NowPlayingStore {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(elapsed: elapsed), receivedAt: Date())
        store.setLyricsOn(true)
        store.showLyrics(lines ?? [timed, plain, later])
        store.setKaraokeEnabled(karaoke)
        return store
    }

    func host<Content: View>(_ content: Content) -> (NSView, NSWindow) {
        let hosting = NSHostingView(rootView: content.frame(width: 300))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 80), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    func karaokeView(in view: NSView) -> KaraokeLineView? {
        if let found = view as? KaraokeLineView { return found }
        for subview in view.subviews { if let found = karaokeView(in: subview) { return found } }
        return nil
    }

    // MARK: the strip

    @Test func theStripFillsTheCurrentLineWordByWord() throws {
        let store = makeStore(elapsed: 10.5)
        let (hosting, window) = host(NowPlayingLyricStrip(store: store))
        let view = try #require(karaokeView(in: hosting))
        #expect((view.litLayer.string as? String) == "one two three")
        #expect(view.isAnimating)
        window.contentView = nil
    }

    @Test func theNextLineBelowIsPlainText() throws {
        let store = makeStore(elapsed: 10.5)
        let (hosting, window) = host(NowPlayingLyricStrip(store: store))
        #expect(karaokeViews(in: hosting).count == 1)
        window.contentView = nil
    }

    @Test func withKaraokeOffTheStripIsTheOldTextRow() {
        let store = makeStore(elapsed: 10.5, karaoke: false)
        let (hosting, window) = host(NowPlayingLyricStrip(store: store))
        #expect(karaokeView(in: hosting) == nil)
        window.contentView = nil
    }

    @Test func aLineWithoutWordTimingIsTheOldTextRowEvenWithKaraokeOn() {
        let store = makeStore(elapsed: 21)
        let (hosting, window) = host(NowPlayingLyricStrip(store: store))
        #expect(karaokeView(in: hosting) == nil)
        window.contentView = nil
    }

    @Test func lyricsWithoutAnyWordTimingNeverMakeAKaraokeView() {
        let store = makeStore(elapsed: 21, lines: [LyricLine(time: 10, text: "a"), LyricLine(time: 20, text: "b")])
        let (hosting, window) = host(NowPlayingLyricStrip(store: store))
        #expect(karaokeView(in: hosting) == nil)
        window.contentView = nil
    }

    @Test func beforeTheFirstLineThereIsOnlyTheNote() {
        let store = makeStore(elapsed: 2)
        let (hosting, window) = host(NowPlayingLyricStrip(store: store))
        #expect(karaokeView(in: hosting) == nil)
        window.contentView = nil
    }

    @Test func theStripKeepsItsHeight() {
        for (elapsed, karaoke) in [(10.5, true), (10.5, false), (21.0, true), (2.0, true)] {
            let store = makeStore(elapsed: elapsed, karaoke: karaoke)
            let (hosting, window) = host(NowPlayingLyricStrip(store: store))
            #expect(hosting.fittingSize.height == NowPlayingLyricStrip.height, "\(elapsed) \(karaoke)")
            window.contentView = nil
        }
    }

    // MARK: the Media tab's row

    @Test func theTabsRowFillsTheCurrentLineToo() throws {
        let store = makeStore(elapsed: 12.5)
        let (hosting, window) = host(CurrentLyricView(store: store))
        let view = try #require(karaokeView(in: hosting))
        #expect((view.litLayer.string as? String) == "one two three")
        window.contentView = nil
    }

    @Test func theTabsRowIsTheOldTextRowWithoutKaraokeOrWordTiming() {
        for (elapsed, karaoke) in [(12.5, false), (21.0, true)] {
            let store = makeStore(elapsed: elapsed, karaoke: karaoke)
            let (hosting, window) = host(CurrentLyricView(store: store))
            #expect(karaokeView(in: hosting) == nil, "\(elapsed) \(karaoke)")
            window.contentView = nil
        }
    }

    @Test func theTabsRowKeepsItsHeight() {
        for (elapsed, karaoke) in [(12.5, true), (12.5, false), (21.0, true)] {
            let store = makeStore(elapsed: elapsed, karaoke: karaoke)
            let (hosting, window) = host(CurrentLyricView(store: store))
            #expect(hosting.fittingSize.height == CurrentLyricView.height, "\(elapsed) \(karaoke)")
            window.contentView = nil
        }
    }

    func karaokeViews(in view: NSView) -> [KaraokeLineView] {
        (view as? KaraokeLineView).map { [$0] } ?? view.subviews.flatMap { karaokeViews(in: $0) }
    }
}

/// The looks of the karaoke lines in the places they are shown.
@Suite struct KaraokeStyleTests {
    @Test func thePanelAndTheRowsShareOneStyleOfFill() {
        #expect(KaraokeStyle.strip.fontSize == 12)
        #expect(KaraokeStyle.row.fontSize == 11)
        #expect(KaraokeStyle.strip.lit != KaraokeStyle.strip.dim)
    }
}
