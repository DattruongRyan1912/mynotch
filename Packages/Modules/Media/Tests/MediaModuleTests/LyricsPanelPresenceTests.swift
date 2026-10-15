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
    /// What the timeline's content was evaluated for.
    final class Evaluations {
        var dates: [Date] = []
        /// How many evaluations there were once the run loop had gone quiet, so what comes later is what was not expected.
        var settledCount = 0

        /// In order and without repeats: a view may well evaluate the same entry twice.
        var distinctDates: [Date] {
            dates.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }

        var afterSettling: Int { dates.count - settledCount }
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

    /// What the timeline's content is evaluated for, with the run loop doing what the display would. It waits for the
    /// first evaluation and, when the timeline is to tick at `tick`, for that one (a busy machine can be slow to either),
    /// and then watches `seconds` more for evaluations that nobody expects.
    func watch(store: NowPlayingStore, onScreen: Bool = true, tick: Date? = nil, seconds: TimeInterval = 0.8) -> Evaluations {
        let evaluations = Evaluations()
        let (_, window) = host(LyricTimeline(store: store) { date in
            evaluations.dates.append(date)
            return Color.clear
        }.environment(\.notchIsOnScreen, onScreen))
        let started = runLoop { !evaluations.dates.isEmpty }
        #expect(started, "the timeline was never evaluated")
        if let tick, let first = evaluations.dates.first, first < tick {
            #expect(runLoop { evaluations.dates.contains { $0 >= tick } }, "the timeline did not tick at the line")
        }
        runLoopUntilQuiet { evaluations.dates.count }
        evaluations.settledCount = evaluations.dates.count
        run(for: seconds)
        window.contentView = nil
        return evaluations
    }

    /// When the timeline ticks for a line that begins `seconds` into the song: a hair after, as `LyricTickSchedule` does.
    func tickDate(of store: NowPlayingStore, forLineAt seconds: Double) throws -> Date {
        let anchor = try #require(store.state.elapsedAnchor)
        return anchor.timestamp + (seconds - anchor.elapsedSeconds) / anchor.rate + LyricTickSchedule.settle
    }

    /// The dates of a timeline that began before the tick and so ticked once; `tick` itself when it began after.
    func expectOneTick(at tick: Date, in evaluations: Evaluations) {
        let dates = evaluations.distinctDates
        guard let first = dates.first else { return }
        if first < tick {
            #expect(dates.count == 2, "\(dates)")
            #expect(dates.count == 2 && abs(dates[1].timeIntervalSince(tick)) < 0.001, "the tick is not at the line: \(dates)")
        } else {
            #expect(dates.count == 1, "it began after the line, so nothing is left to tick for: \(dates)")
        }
    }

    @Test func lyricsWithoutWordTimingTickWhenALineBeginsNotFourTimesASecond() throws {
        // A line 0.3 s on and the next far off: one tick in 0.8 s, where four a second would be three.
        let store = makeStore(lines: [LyricLine(time: 0, text: "a"), LyricLine(time: 0.3, text: "b"), LyricLine(time: 60, text: "c")])
        let tick = try tickDate(of: store, forLineAt: 0.3)
        expectOneTick(at: tick, in: watch(store: store, tick: tick))
    }

    @Test func lyricsWithWordTimingTickAtLinesToo() throws {
        let words = [LyricWord(text: "la ", begin: 0.3, end: 0.5), LyricWord(text: "la", begin: 0.5, end: 0.9)]
        let store = makeStore(lines: [LyricLine(time: 0, text: "a"), LyricLine(time: 0.3, words: words), LyricLine(time: 60, text: "c")])
        let tick = try tickDate(of: store, forLineAt: 0.3)
        expectOneTick(at: tick, in: watch(store: store, tick: tick))
    }

    @Test func aTrackThatStandsStillDoesNotTickAtAll() {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(playing: false, elapsed: 1), receivedAt: Date())
        store.showLyrics([LyricLine(time: 0, text: "a"), LyricLine(time: 1.1, text: "b")])
        let dates = watch(store: store).distinctDates
        #expect(dates.count == 1, "only the start, never a tick: \(dates)")
    }

    @Test func whileTheNotchOrThePanelCannotBeSeenTheTimelineStandsStill() {
        let store = makeStore(lines: [LyricLine(time: 0, text: "a"), LyricLine(time: 0.3, text: "b"), LyricLine(time: 0.6, text: "c")])
        #expect(watch(store: store, onScreen: false).afterSettling == 0)
    }

    @Test func withoutLyricsTheTimelineShowsOnceAndWaitsForTheStore() {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(elapsed: 0), receivedAt: Date())
        let dates = watch(store: store).distinctDates
        #expect(dates.count == 1, "only the start, never a tick: \(dates)")
    }
}

@Suite struct KaraokeStyleTests {
    @Test func thePanelAndTheRowsShareOneStyleOfFill() {
        #expect(KaraokeStyle.strip.fontSize == 12)
        #expect(KaraokeStyle.row.fontSize == 11)
        #expect(KaraokeStyle.strip.lit != KaraokeStyle.strip.dim)
    }
}
