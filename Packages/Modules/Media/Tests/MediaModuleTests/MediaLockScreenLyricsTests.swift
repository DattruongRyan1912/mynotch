import AppKit
import MyNotchCore
import NotchUI
import Observation
import SwiftUI
import Testing
@testable import MediaModule

/// The lyric lines under the track on the lock screen: what they are at a moment (the model), how they are drawn, and what they
/// cost while the lock screen stays on. Hosting views are never shown, and no real lock screen is involved.
@Suite struct LockScreenLyricsTests {
    // MARK: fixtures

    let words = [LyricWord(text: "one ", begin: 10, end: 11), LyricWord(text: "two ", begin: 11, end: 12), LyricWord(text: "three", begin: 12, end: 14)]
    var timed: LyricLine { LyricLine(time: 10, words: words) }
    let plain = LyricLine(time: 20, text: "a plain line")
    let later = LyricLine(time: 30, words: [LyricWord(text: "four ", begin: 30, end: 31), LyricWord(text: "five", begin: 31, end: 32)])
    let pause = LyricLine(time: 15, text: "")

    func lyrics(_ lines: [LyricLine], at position: Double?, sweeps: Bool = true) -> LockScreenLyrics {
        LockScreenLyrics(lines: lines, position: position, sweeps: sweeps)
    }

    // MARK: the model: the line being sung and the one coming

    @Test func aTimedLineIsSweptAndTheNextLineIsText() {
        let shown = lyrics([timed, plain, later], at: 10.5)
        #expect(shown.current == .sweep(timed))
        #expect(shown.next == "a plain line")
    }

    @Test func withTheSweepOffOrNoWordTimingTheLineIsLitWhole() {
        #expect(lyrics([timed, plain], at: 10.5, sweeps: false).current == .whole("one two three"))
        #expect(lyrics([timed, plain, later], at: 21).current == .whole("a plain line"), "this line has no words timed")
        #expect(lyrics([LyricLine(time: 1, text: "a"), LyricLine(time: 5, text: "b")], at: 2).current == .whole("a"))
    }

    @Test func beforeTheFirstLineAndInAPauseTheNoteIsShownAndTheNextLineComes() {
        #expect(lyrics([timed, plain], at: 2).current == .note)
        #expect(lyrics([timed, plain], at: 2).next == "one two three")
        let around = [timed, pause, plain]
        #expect(lyrics(around, at: 16).current == .note, "a pause is never a line")
        #expect(lyrics(around, at: 16).next == "a plain line")
    }

    @Test func theLastLineHasNothingAfterIt() {
        let shown = lyrics([timed, plain], at: 99)
        #expect(shown.current == .whole("a plain line"))
        #expect(shown.next == nil)
    }

    @Test func noLinesOrNoClockMeansTheNoteAndNothingElse() {
        #expect(lyrics([], at: 4) == LockScreenLyrics(current: .note, next: nil))
        #expect(lyrics([timed, plain], at: nil) == LockScreenLyrics(current: .note, next: nil))
    }

    @Test func aRightToLeftLineIsLitWholeEvenWithItsWordsTimed() {
        let arabic = LyricLine(time: 10, words: [LyricWord(text: "مرحبا ", begin: 10, end: 11), LyricWord(text: "بالعالم", begin: 11, end: 12)])
        let hebrew = LyricLine(time: 10, words: [LyricWord(text: "שלום ", begin: 10, end: 11), LyricWord(text: "עולם", begin: 11, end: 12)])
        let mixedFirst = LyricLine(time: 10, words: [
            LyricWord(text: "hello ", begin: 10, end: 11), LyricWord(text: "مرحبا ", begin: 11, end: 12), LyricWord(text: "world", begin: 12, end: 13),
        ])
        let mixedLast = LyricLine(time: 10, words: [LyricWord(text: "שלום ", begin: 10, end: 11), LyricWord(text: "hello", begin: 11, end: 12)])
        for line in [arabic, hebrew, mixedFirst, mixedLast] {
            #expect(lyrics([line], at: 10.5).current == .whole(line.text), "\(line.text)")
        }
    }

    @Test func leftToRightScriptsOtherThanLatinStillSweep() {
        let cjk = LyricLine(time: 10, words: [LyricWord(text: "你好", begin: 10, end: 11), LyricWord(text: "世界", begin: 11, end: 12)])
        let korean = LyricLine(time: 10, words: [LyricWord(text: "안녕 ", begin: 10, end: 11), LyricWord(text: "세계", begin: 11, end: 12)])
        let digits = LyricLine(time: 10, words: [LyricWord(text: "ten, ", begin: 10, end: 11), LyricWord(text: "10!", begin: 11, end: 12)])
        for line in [cjk, korean, digits] {
            #expect(lyrics([line], at: 10.5).current == .sweep(line), "\(line.text)")
        }
    }

    @Test func whatIsReadAloudIsTheLinesAndNeverTheNote() {
        #expect(lyrics([timed, plain], at: 10.5).spoken == "one two three, a plain line")
        #expect(lyrics([timed, plain], at: 2).spoken == "one two three")
        #expect(lyrics([timed], at: 12).spoken == "one two three")
        #expect(lyrics([], at: 2).spoken == "")
    }

    // MARK: the store gives the model

    func makeStore(elapsed: Double = 10.5, karaoke: Bool = true, lines: [LyricLine]? = nil, playing: Bool = true) -> NowPlayingStore {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(playing: playing, elapsed: elapsed), receivedAt: Date())
        store.setLyricsOn(true)
        store.showLyrics(lines ?? [timed, plain, later])
        store.setKaraokeEnabled(karaoke)
        return store
    }

    @Test func theStoreHasNoLockScreenLyricsWithoutSyncedLyrics() {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(elapsed: 10), receivedAt: Date())
        #expect(store.lockScreenLyrics(at: Date()) == nil)
        store.showUnsyncedLyrics()
        #expect(store.lockScreenLyrics(at: Date()) == nil)
    }

    @Test func theStoreSweepsOnlyWhileKaraokeIsActive() {
        #expect(makeStore().lockScreenLyrics(at: Date())?.current == .sweep(timed))
        #expect(makeStore(karaoke: false).lockScreenLyrics(at: Date())?.current == .whole("one two three"), "the Media setting")
        let untimed = makeStore(lines: [LyricLine(time: 10, text: "a"), LyricLine(time: 20, text: "b")])
        #expect(untimed.lockScreenLyrics(at: Date())?.current == .whole("a"))
    }

    @Test func lyricsTheUserHidFromTheNotchAreStillOnTheLockScreen() {
        let store = makeStore()
        store.toggleLyricsHidden()
        #expect(store.lyricsHidden)
        #expect(store.lockScreenLyrics(at: Date())?.current == .sweep(timed), "a setting of its own, as the floating panel")
    }

    // MARK: hosting

    func host<Content: View>(_ content: Content, width: CGFloat = 308) -> (NSView, NSWindow) {
        let hosting = NSHostingView(rootView: content.frame(width: width))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 120), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    func karaokeViews(in view: NSView) -> [KaraokeLineView] {
        (view as? KaraokeLineView).map { [$0] } ?? view.subviews.flatMap { karaokeViews(in: $0) }
    }

    // MARK: how it is drawn

    @Test func aTimedLineIsOneSweepAndTheNextLineIsNotOne() throws {
        let store = makeStore()
        let (hosting, window) = host(LockScreenLyricsView(store: store))
        let views = karaokeViews(in: hosting)
        #expect(views.count == 1)
        let view = try #require(views.first)
        #expect((view.litLayer.string as? String) == "one two three")
        #expect(view.isAnimating, "one animation the render server runs")
        window.contentView = nil
    }

    @Test func withoutASweepTheLineIsPlainText() {
        for store in [makeStore(karaoke: false), makeStore(elapsed: 21), makeStore(elapsed: 2)] {
            let (hosting, window) = host(LockScreenLyricsView(store: store))
            #expect(karaokeViews(in: hosting).isEmpty)
            window.contentView = nil
        }
    }

    @Test func aRightToLeftLineWithItsWordsTimedIsNeverSwept() {
        let arabic = LyricLine(time: 10, words: [LyricWord(text: "مرحبا ", begin: 10, end: 11), LyricWord(text: "بالعالم", begin: 11, end: 14)])
        let store = makeStore(lines: [arabic, plain])
        #expect(store.karaokeIsActive)
        let (hosting, window) = host(LockScreenLyricsView(store: store))
        #expect(karaokeViews(in: hosting).isEmpty, "whole line, bright, no mask and no animation")
        window.contentView = nil
    }

    @Test func theBlockKeepsItsHeightWhateverIsShown() {
        let arabic = LyricLine(time: 10, words: [LyricWord(text: "مرحبا ", begin: 10, end: 11), LyricWord(text: "بالعالم", begin: 11, end: 14)])
        let cases: [(String, NowPlayingStore)] = [
            ("sweep", makeStore()), ("whole", makeStore(karaoke: false)), ("plain", makeStore(elapsed: 21)),
            ("note", makeStore(elapsed: 2)), ("last line, no next", makeStore(elapsed: 40)), ("rtl", makeStore(lines: [arabic, plain])),
            ("a pause", makeStore(elapsed: 16, lines: [timed, pause, plain])),
        ]
        for (name, store) in cases {
            let (hosting, window) = host(LockScreenLyricsView(store: store))
            #expect(hosting.fittingSize.height == LockScreenLyricsView.height, "\(name)")
            window.contentView = nil
        }
    }

    // MARK: in the lock screen's card

    func lockScreenView(_ store: NowPlayingStore, lyricsEnabled: Bool = true) -> some View {
        let transport = LockScreenTransport(store: store, actions: MediaActions(send: { _ in }, seek: { _ in }))
        return NowPlayingLockScreenView(transport: transport).environment(\.lockScreenLyricsEnabled, lyricsEnabled)
    }

    @Test func theCardShowsTheLyricsUnderTheTrackWhenTheLockScreenAllowsThem() {
        let store = makeStore()
        let (hosting, window) = host(lockScreenView(store))
        #expect(karaokeViews(in: hosting).count == 1)
        window.contentView = nil
    }

    @Test func withTheLockScreensLyricsSwitchOffThereIsNoLyricBlockAndNothingMovesOrTicks() {
        let store = makeStore()
        let (on, onWindow) = host(lockScreenView(store))
        let (off, offWindow) = host(lockScreenView(store, lyricsEnabled: false))
        #expect(karaokeViews(in: off).isEmpty)
        #expect(off.fittingSize.height + LockScreenLyricsView.height + 6 == on.fittingSize.height, "the block and its gap, nothing else")
        onWindow.contentView = nil
        offWindow.contentView = nil
    }

    @Test func withoutSyncedLyricsTheCardIsAsShortAsItWas() {
        let bare = NowPlayingStore(lookUpApp: { _ in nil })
        bare.apply(line: AdapterLines.track(elapsed: 10), receivedAt: Date())
        let (hosting, window) = host(lockScreenView(bare))
        let (without, withoutWindow) = host(lockScreenView(makeStore(), lyricsEnabled: false))
        #expect(hosting.fittingSize.height == without.fittingSize.height)
        window.contentView = nil
        withoutWindow.contentView = nil
    }

    @Test func theCardWithLyricsIsNoTallerThanThePanelAllowsAndTheBlockIsWhatMakesItTaller() {
        for store in [makeStore(), makeStore(karaoke: false), makeStore(elapsed: 2)] {
            let (hosting, window) = host(lockScreenView(store))
            // The lock screen's panel is as tall as the card, up to 160 (LockScreenPanel.maximumHeight, which this package cannot
            // see); the card pads 8 each side. About 105 with the lyric lines.
            #expect(hosting.fittingSize.height + 16 <= 160)
            #expect(hosting.fittingSize.height > 49 + LockScreenLyricsView.height, "the cover row, the bar and the block")
            window.contentView = nil
        }
    }

    // MARK: what it costs

    /// What the block's timeline content was evaluated for, with the run loop doing what the display would.
    func watch(
        store: NowPlayingStore, presence: LockScreenPresenceForTests? = nil, until stop: ((LyricTimelineTests.Evaluations) -> Bool)? = nil,
        seconds: TimeInterval = 0.8, then: ((NSView, LyricTimelineTests.Evaluations) -> Void)? = nil
    ) -> LyricTimelineTests.Evaluations {
        let evaluations = LyricTimelineTests.Evaluations()
        let block = LockScreenLyricsView(store: store, onEvaluate: { evaluations.dates.append($0) })
        let (hosting, window) = host(PresenceHost(presence: presence ?? LockScreenPresenceForTests(), content: block))
        #expect(runLoop { !evaluations.dates.isEmpty }, "the block was never evaluated")
        if let stop { #expect(runLoop { stop(evaluations) }, "the timeline did not get where the test needs it") }
        runLoopUntilQuiet { evaluations.dates.count }
        evaluations.settledCount = evaluations.dates.count
        if let then { then(hosting, evaluations) }
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        window.contentView = nil
        return evaluations
    }

    func tickDate(of store: NowPlayingStore, forLineAt seconds: Double) throws -> Date {
        let anchor = try #require(store.state.elapsedAnchor)
        return anchor.timestamp + (seconds - anchor.elapsedSeconds) / anchor.rate + LyricTickSchedule.settle
    }

    /// A song of word-timed lines 0.2 s apart and a last one far off, with the clock at its start.
    func quickSong() -> NowPlayingStore {
        var sung: [LyricLine] = []
        for index in 0..<4 {
            let begin = Double(index) * 0.2
            let first = LyricWord(text: "la ", begin: begin, end: begin + 0.1)
            let second = LyricWord(text: "la", begin: begin + 0.1, end: begin + 0.2)
            sung.append(LyricLine(time: begin, words: [first, second]))
        }
        sung.append(LyricLine(time: 60, text: "end"))
        return makeStore(elapsed: 0, lines: sung)
    }

    @Test func theScheduleTheBlockRunsOnHasOneTickPerLineAndNoneBetween() throws {
        // A fixed clock: the entries from the moment the song's clock began, no wall clock involved. A frame-driven block would
        // have some fifty in the 0.7 s it takes to sing the first four lines, and a 4 Hz one three; this has the start and one per
        // line after it, however long the song, whatever the machine is doing.
        let store = quickSong()
        let anchor = try #require(store.state.elapsedAnchor)
        let entries = Array(LyricTimeline<EmptyView>.schedule(for: store).entries(from: anchor.timestamp, mode: .normal))
        #expect(entries.count == 5, "the start and the four lines after the first: \(entries.count)")
        #expect(entries.first == anchor.timestamp)
        #expect(entries.filter { $0 <= anchor.timestamp + 0.7 }.count == 4)
        for (date, seconds) in zip(entries.dropFirst(), [0.2, 0.4, 0.6, 60]) {
            let late = date.timeIntervalSince(anchor.timestamp) - seconds
            // Dates today are about 8e8 s from the reference date, so a microsecond is the most they can tell apart.
            #expect(late > 0 && late <= LyricTickSchedule.settle + 1e-6, "\(seconds)")
        }
    }

    @Test func aBlockOfAPausedOrUnsyncedTrackHasNothingToTickFor() throws {
        let paused = makeStore(elapsed: 5, playing: false)
        let anchor = try #require(paused.state.elapsedAnchor)
        #expect(Array(LyricTimeline<EmptyView>.schedule(for: paused).entries(from: anchor.timestamp, mode: .normal)) == [anchor.timestamp])
        let bare = NowPlayingStore(lookUpApp: { _ in nil })
        bare.apply(line: AdapterLines.track(elapsed: 5), receivedAt: Date())
        let bareAnchor = try #require(bare.state.elapsedAnchor)
        #expect(Array(LyricTimeline<EmptyView>.schedule(for: bare).entries(from: bareAnchor.timestamp, mode: .normal)) == [bareAnchor.timestamp])
    }

    @Test func theBlockIsEvaluatedAtALineAndNotAgainUntilTheNextOne() throws {
        // Waits for the one tick, however long a busy machine takes to deliver it, so nothing here depends on how fast the run loop is.
        // One line change, 0.2 s on, and the next far off.
        let words = [LyricWord(text: "la ", begin: 0, end: 0.1), LyricWord(text: "la", begin: 0.1, end: 0.2)]
        let next = [LyricWord(text: "na ", begin: 0.2, end: 0.3), LyricWord(text: "na", begin: 0.3, end: 0.4)]
        let store = makeStore(elapsed: 0, lines: [LyricLine(time: 0, words: words), LyricLine(time: 0.2, words: next), LyricLine(time: 60, text: "end")])
        let tick = try tickDate(of: store, forLineAt: 0.2)
        let evaluations = watch(store: store, until: { evaluations in evaluations.dates.contains { $0 >= tick } }, seconds: 0.3)
        let dates = evaluations.distinctDates
        if let first = dates.first, first < tick {
            #expect(dates.count == 2 && abs(dates[1].timeIntervalSince(tick)) < 0.001, "the start and the tick at the line: \(dates)")
        } else {
            #expect(dates.count == 1, "it began after the line, so only a later line can tick: \(dates)")
        }
        #expect(evaluations.dates.count <= 2 * dates.count, "a view may evaluate an entry twice, never more: \(evaluations.dates.count)")
    }

    @Test func aLineBeingSungDoesNotBuildItsSweepAgain() throws {
        let store = makeStore(elapsed: 10.5)
        let (hosting, window) = host(LockScreenLyricsView(store: store))
        let view = try #require(karaokeViews(in: hosting).first)
        let built = view.buildCount
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        #expect(view.buildCount == built, "nothing is made again while the line is sung")
        #expect(built == 1)
        window.contentView = nil
    }

    @Test func aPausedTrackDoesNotTickAtAll() {
        let store = makeStore(elapsed: 1, lines: [LyricLine(time: 0, text: "a"), LyricLine(time: 1.1, text: "b")], playing: false)
        #expect(watch(store: store).distinctDates.count == 1)
    }

    @Test func whileTheLockScreenCannotBeSeenTheBlockStandsStill() {
        let store = makeStore(elapsed: 10.5, lines: [timed, LyricLine(time: 10.8, text: "b"), LyricLine(time: 11.1, text: "c")])
        let off = LockScreenPresenceForTests()
        off.isOnScreen = false
        #expect(watch(store: store, presence: off).afterSettling == 0)
    }

    @Test func whenTheDisplaySleepsAnAnimatingSweepIsTakenAwayAndTheTimelineStops() throws {
        let long = LyricLine(time: 0, words: [LyricWord(text: "la ", begin: 0, end: 30), LyricWord(text: "la", begin: 30, end: 60)])
        let store = makeStore(elapsed: 1, lines: [long, LyricLine(time: 90, text: "far")])
        let presence = LockScreenPresenceForTests()
        var boundaries: [Date] = []
        let evaluations = watch(store: store, presence: presence, seconds: 0, then: { hosting, evaluations in
            #expect(karaokeViews(in: hosting).first?.isAnimating == true, "singing the long line before the display sleeps")
            presence.isOnScreen = false
            // Looked for again each time: the timeline gives way to plain content while the display sleeps, which is a new view.
            #expect(runLoop(until: { karaokeViews(in: hosting).first?.isAnimating == false }, seconds: 30), "the sweep is taken away at once")
            runLoopUntilQuiet { evaluations.dates.count }

            // Only now, with the display asleep, do lines come due: the lyrics are replaced by some that begin 0.4 and 0.8 s from
            // here. That is a change of the store, so the block shows once more (as it was when it left the screen) and the test
            // waits for that. Then it waits, on the wall clock and not for a fixed time, until both lines are past.
            let position = store.position(at: Date()) ?? 0
            store.showLyrics([long, LyricLine(time: position + 0.4, text: "b"), LyricLine(time: position + 0.8, text: "c"), LyricLine(time: 90, text: "far")])
            let before = evaluations.dates.count
            #expect(runLoop(until: { evaluations.dates.count > before }, seconds: 30), "the change of lyrics shows the block once")
            runLoopUntilQuiet { evaluations.dates.count }
            evaluations.settledCount = evaluations.dates.count
            if let anchor = store.state.elapsedAnchor {
                for offset in [0.4, 0.8] {
                    boundaries.append(anchor.timestamp + (position + offset - anchor.elapsedSeconds) / anchor.rate)
                }
            }
            let last = boundaries.last ?? .distantFuture
            #expect(runLoop(until: { Date() > last + 0.3 }, seconds: 30), "both lines are past")
        })
        #expect(boundaries.count == 2)
        #expect(evaluations.afterSettling == 0, "lines reached while the display sleeps evaluate nothing: \(evaluations.afterSettling)")
    }

    @Test func whenTheDisplayWakesTheSweepComesBackFromTheClock() throws {
        let long = LyricLine(time: 0, words: [LyricWord(text: "la ", begin: 0, end: 30), LyricWord(text: "la", begin: 30, end: 60)])
        let store = makeStore(elapsed: 1, lines: [long, LyricLine(time: 90, text: "b")])
        let presence = LockScreenPresenceForTests()
        _ = watch(store: store, presence: presence, seconds: 0.05, then: { hosting, _ in
            presence.isOnScreen = false
            #expect(runLoop(until: { karaokeViews(in: hosting).first?.isAnimating == false }, seconds: 10))
            presence.isOnScreen = true
            #expect(runLoop(until: { karaokeViews(in: hosting).first?.isAnimating == true }, seconds: 10), "the display is back: the fill runs from where the clock says")
        })
    }
}

/// The lock screen's flag, as a test flips it: the block reads it as `notchIsOnScreen`.
@Observable final class LockScreenPresenceForTests {
    var isOnScreen = true
}

private struct PresenceHost<Content: View>: View {
    let presence: LockScreenPresenceForTests
    let content: Content

    var body: some View {
        content.environment(\.notchIsOnScreen, presence.isOnScreen)
    }
}
