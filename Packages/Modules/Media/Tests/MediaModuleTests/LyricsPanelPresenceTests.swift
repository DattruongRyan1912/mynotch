import AppKit
import Foundation
import NotchUI
import Observation
import SwiftUI
import Testing
@testable import MediaModule

/// Whether the panel can be seen: the window shown and not covered, the displays awake and the screen not locked. While it
/// cannot, its timeline stands still and its sweep is taken away.
@Suite struct LyricsPanelPresenceTests {
    nonisolated final class Flag: @unchecked Sendable {
        nonisolated(unsafe) var isSet = false
    }

    @Test func aNewPanelIsNotSeenUntilItsWindowIs() {
        let presence = LyricsPanelPresence()
        #expect(!presence.isOnScreen)
        presence.setWindowVisible(true)
        #expect(presence.isOnScreen)
    }

    @Test func aCoveredOrHiddenWindowIsNotSeen() {
        let presence = LyricsPanelPresence()
        presence.setWindowVisible(true)
        presence.setWindowVisible(false)
        #expect(!presence.isOnScreen)
    }

    @Test func sleepingDisplaysAndALockedScreenTakeItOffScreenAndWakingBringsItBack() {
        let presence = LyricsPanelPresence()
        presence.setWindowVisible(true)
        presence.apply(.displaysSlept)
        #expect(!presence.isOnScreen)
        presence.apply(.displaysWoke)
        #expect(presence.isOnScreen)
        presence.apply(.screenLocked)
        #expect(!presence.isOnScreen)
        presence.apply(.screenUnlocked)
        #expect(presence.isOnScreen)
    }

    @Test func itNeedsEveryConditionAtOnce() {
        let presence = LyricsPanelPresence()
        presence.setWindowVisible(true)
        presence.apply(.displaysSlept)
        presence.apply(.screenLocked)
        presence.apply(.displaysWoke)
        // Awake, but still locked.
        #expect(!presence.isOnScreen)
        presence.apply(.screenUnlocked)
        #expect(presence.isOnScreen)
    }

    @Test func resettingForgetsEverythingSoTheNextPanelStartsClean() {
        let presence = LyricsPanelPresence()
        presence.setWindowVisible(true)
        presence.apply(.displaysSlept)
        presence.reset()
        #expect(!presence.isOnScreen)
        presence.setWindowVisible(true)
        #expect(presence.isOnScreen)
    }

    @Test func aViewHearsOnlyOfRealChanges() {
        let presence = LyricsPanelPresence()
        let invalidated = Flag()
        withObservationTracking { _ = presence.isOnScreen } onChange: { invalidated.isSet = true }
        presence.setWindowVisible(false)
        presence.apply(.displaysWoke)
        presence.apply(.screenUnlocked)
        #expect(!invalidated.isSet)
        presence.setWindowVisible(true)
        #expect(invalidated.isSet)
    }

    @Test func theSystemSourceStartsAndStopsListening() {
        // Real notification centers, nothing posted: it must start and stop without a sound.
        let stop = SystemPresenceEvents.system.start { _ in }
        stop()
        stop()
    }
}

/// The lyric views' timeline: at the lines, never four times a second, and still while the notch or the panel cannot be seen.
@Suite struct LyricTimelineTests {
    final class Counter {
        var count = 0
    }

    func makeStore(lines: [LyricLine], elapsed: Double = 0) -> NowPlayingStore {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(elapsed: elapsed), receivedAt: Date())
        store.showLyrics(lines)
        return store
    }

    func host<Content: View>(_ content: Content) -> (NSView, NSWindow) {
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 40), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    func run(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Evaluations of the timeline's content in `seconds`, once it has settled.
    func evaluations(store: NowPlayingStore, onScreen: Bool = true, seconds: TimeInterval = 0.8) -> Int {
        let counter = Counter()
        let (_, window) = host(LyricTimeline(store: store) { _ in
            counter.count += 1
            return Color.clear
        }.environment(\.notchIsOnScreen, onScreen))
        run(for: 0.1)
        let before = counter.count
        run(for: seconds)
        window.contentView = nil
        return counter.count - before
    }

    @Test func lyricsWithoutWordTimingTickWhenALineBeginsNotFourTimesASecond() {
        // A line 0.3 s on and the next far off: one tick in 0.8 s, where four a second would be three.
        let store = makeStore(lines: [LyricLine(time: 0, text: "a"), LyricLine(time: 0.3, text: "b"), LyricLine(time: 60, text: "c")])
        let ticks = evaluations(store: store)
        #expect(ticks >= 1 && ticks <= 2, "\(ticks)")
    }

    @Test func lyricsWithWordTimingTickAtLinesToo() {
        let words = [LyricWord(text: "la ", begin: 0.3, end: 0.5), LyricWord(text: "la", begin: 0.5, end: 0.9)]
        let store = makeStore(lines: [LyricLine(time: 0, text: "a"), LyricLine(time: 0.3, words: words), LyricLine(time: 60, text: "c")])
        let ticks = evaluations(store: store)
        #expect(ticks >= 1 && ticks <= 2, "\(ticks)")
    }

    @Test func aTrackThatStandsStillDoesNotTickAtAll() {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(playing: false, elapsed: 1), receivedAt: Date())
        store.showLyrics([LyricLine(time: 0, text: "a"), LyricLine(time: 1.1, text: "b")])
        #expect(evaluations(store: store) == 0)
    }

    @Test func whileTheNotchOrThePanelCannotBeSeenTheTimelineStandsStill() {
        let store = makeStore(lines: [LyricLine(time: 0, text: "a"), LyricLine(time: 0.3, text: "b"), LyricLine(time: 0.6, text: "c")])
        #expect(evaluations(store: store, onScreen: false) == 0)
    }

    @Test func withoutLyricsTheTimelineShowsOnceAndWaitsForTheStore() {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(elapsed: 0), receivedAt: Date())
        #expect(evaluations(store: store) == 0)
    }
}

@Suite struct KaraokeStyleTests {
    @Test func thePanelAndTheRowsShareOneStyleOfFill() {
        #expect(KaraokeStyle.strip.fontSize == 12)
        #expect(KaraokeStyle.row.fontSize == 11)
        #expect(KaraokeStyle.strip.lit != KaraokeStyle.strip.dim)
    }
}
