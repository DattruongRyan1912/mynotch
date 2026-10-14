import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import MediaModule

@Suite struct LyricStripLinesTests {
    // The words are placeholders; only the timing and the empty lines matter here.
    let lyrics = [
        LyricLine(time: 5, text: "a"), LyricLine(time: 10, text: "b"),
        LyricLine(time: 14, text: ""), LyricLine(time: 20, text: "c"),
    ]

    @Test func beforeTheFirstLineNothingIsSungAndTheFirstIsNext() {
        for position in [0.0, 4.999, -3] {
            let around = lyrics.lines(around: position)
            #expect(around.current == nil)
            #expect(around.next?.text == "a")
        }
    }

    @Test func atExactTimestampsTheLineStartsAndTheNextOneFollows() {
        #expect(lyrics.lines(around: 5).current?.text == "a")
        #expect(lyrics.lines(around: 5).next?.text == "b")
        #expect(lyrics.lines(around: 9.999).current?.text == "a")
        #expect(lyrics.lines(around: 10).current?.text == "b")
    }

    @Test func theNextLineSkipsPauses() {
        // After "b" comes a pause, so "c" is the one coming up.
        #expect(lyrics.lines(around: 10).next?.text == "c")
        #expect(lyrics.lines(around: 13.9).next?.text == "c")
    }

    @Test func insideAPauseTheCurrentLineIsTheEmptyOneAndTheNextIsTheLineAfter() {
        for position in [14.0, 17, 19.999] {
            let around = lyrics.lines(around: position)
            #expect(around.current == LyricLine(time: 14, text: ""))
            #expect(around.next?.text == "c")
        }
    }

    @Test func afterTheLastLineThereIsNothingNext() {
        for position in [20.0, 99, 9999] {
            let around = lyrics.lines(around: position)
            #expect(around.current?.text == "c")
            #expect(around.next == nil)
        }
    }

    @Test func aPauseAfterTheLastLineLeavesNothingNext() {
        let trailing = [LyricLine(time: 5, text: "a"), LyricLine(time: 9, text: "")]
        let around = trailing.lines(around: 12)
        #expect(around.current == LyricLine(time: 9, text: ""))
        #expect(around.next == nil)
    }

    @Test func aFirstLineThatIsAPauseStillComesBeforeTheFirstWords() {
        let opening = [LyricLine(time: 0, text: ""), LyricLine(time: 3, text: "a")]
        #expect(opening.lines(around: 1).current == LyricLine(time: 0, text: ""))
        #expect(opening.lines(around: 1).next?.text == "a")
        #expect(opening.lines(around: -1).current == nil)
        #expect(opening.lines(around: -1).next?.text == "a")
    }

    @Test func withoutLinesOrWithOnlyPausesThereIsNothing() {
        let none = [LyricLine]().lines(around: 12)
        #expect(none.current == nil && none.next == nil)
        let pauses = [LyricLine(time: 1, text: ""), LyricLine(time: 4, text: "")]
        #expect(pauses.lines(around: 0).next == nil)
        #expect(pauses.lines(around: 2).next == nil)
    }

    @Test func equalTimesTakeTheLastOneAsCurrent() {
        let tied = [LyricLine(time: 1, text: "x"), LyricLine(time: 1, text: "y"), LyricLine(time: 2, text: "z")]
        #expect(tied.lines(around: 1).current?.text == "y")
        #expect(tied.lines(around: 1).next?.text == "z")
    }

    @Test func aPositionThatIsNotANumberIsBeforeTheFirstLine() {
        let around = lyrics.lines(around: .nan)
        #expect(around.current == nil)
        #expect(around.next?.text == "a")
    }

    @Test func theCurrentLineIsTheOneTheCurrentLyricRowShows() {
        let many = (0..<200).map { LyricLine(time: Double($0) * 2.5, text: $0 % 7 == 3 ? "" : "line \($0)") }
        let mismatches = stride(from: -1.0, through: 520, by: 0.7).filter { seconds in
            many.lines(around: seconds).current != many.line(at: seconds)
        }
        #expect(mismatches.isEmpty)
    }

    // MARK: what the strip shows

    @Test func beforeTheFirstLineTheStripShowsTheNoteAndTheFirstLine() {
        #expect(LyricStrip(lines: lyrics, position: 2) == LyricStrip(current: nil, next: "a"))
    }

    @Test func whileALineIsSungTheStripShowsItAndTheNextOne() {
        #expect(LyricStrip(lines: lyrics, position: 6) == LyricStrip(current: "a", next: "b"))
        #expect(LyricStrip(lines: lyrics, position: 10) == LyricStrip(current: "b", next: "c"))
    }

    @Test func duringAPauseTheStripShowsTheNoteAndTheNextLine() {
        #expect(LyricStrip(lines: lyrics, position: 15) == LyricStrip(current: nil, next: "c"))
    }

    @Test func afterTheLastLineTheStripShowsItWithNothingBelow() {
        #expect(LyricStrip(lines: lyrics, position: 30) == LyricStrip(current: "c", next: nil))
    }

    @Test func afterATrailingPauseTheStripShowsOnlyTheNote() {
        let trailing = [LyricLine(time: 5, text: "a"), LyricLine(time: 9, text: "")]
        #expect(LyricStrip(lines: trailing, position: 12) == LyricStrip(current: nil, next: nil))
    }

    @Test func withoutAKnownPositionTheStripShowsOnlyTheNote() {
        #expect(LyricStrip(lines: lyrics, position: nil) == LyricStrip(current: nil, next: nil))
    }

    @Test func theNoteIsAMusicalNote() {
        #expect(LyricStrip.note == "\u{266A}")
    }

    @Test func aStripWaitingForLyricsIsJustTheNote() {
        #expect(LyricStrip.waiting == LyricStrip(current: nil, next: nil))
    }

    @Test func spokenTextIsTheLinesAndNeverTheNote() {
        #expect(LyricStrip(current: "a", next: "b").spoken == "a, b")
        #expect(LyricStrip(current: nil, next: "b").spoken == "b")
        #expect(LyricStrip(current: "a", next: nil).spoken == "a")
        #expect(LyricStrip.waiting.spoken == "")
    }
}

@Suite struct NowPlayingStoreLyricStripTests {
    let lines = [LyricLine(time: 10, text: "a"), LyricLine(time: 31, text: "b"), LyricLine(time: 40, text: "c")]

    func makeStore(playing: Bool = true, elapsed: Double = 30) -> NowPlayingStore {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(playing: playing, elapsed: elapsed), receivedAt: Date())
        store.showLyrics(lines)
        return store
    }

    @Test func noStripWithoutSyncedLyrics() {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        #expect(store.lyricStrip(at: Date()) == nil)
        store.apply(line: AdapterLines.track(), receivedAt: Date())
        #expect(store.lyricStrip(at: Date()) == nil)
    }

    @Test func theStripFollowsThePlaybackClock() throws {
        let store = makeStore()
        let anchor = try #require(store.state.elapsedAnchor).timestamp
        #expect(store.lyricStrip(at: anchor) == LyricStrip(current: "a", next: "b"))
        #expect(store.lyricStrip(at: anchor + 1.5) == LyricStrip(current: "b", next: "c"))
        #expect(store.lyricStrip(at: anchor + 10) == LyricStrip(current: "c", next: nil))
    }

    @Test func aPausedTrackStaysWhereItIs() throws {
        let store = makeStore(playing: false)
        let anchor = try #require(store.state.elapsedAnchor).timestamp
        #expect(store.lyricStrip(at: anchor + 60) == LyricStrip(current: "a", next: "b"))
    }

    @Test func withoutAPositionTheStripIsJustTheNote() {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.showLyrics(lines)
        #expect(store.lyricStrip(at: Date()) == LyricStrip(current: nil, next: nil))
    }
}

@Suite final class MediaLyricStripTests {
    let source = FakeNowPlayingSource()
    let client = FakeHTTPClient()
    let module: MediaModule
    let harness: RegistryHarness
    let storageBase: URL

    init() {
        module = MediaModule(
            source: source, spectrum: FakeSpectrumSource(), lyricsClient: client, tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }
        )
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
    }

    deinit { try? FileManager.default.removeItem(at: storageBase) }

    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }
    var store: NowPlayingStore { module.store }
    var activity: LiveActivity? { harness.activities.current?.activity }

    /// Lets the settings loop and the fetch task run after a settings write or a track change.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func enableLyrics() { harness.settings.set(true, for: keys.lyrics) }
    func enableStrip() { harness.settings.set(true, for: keys.lyricsUnderNotch) }

    func playTrack(_ title: String = "Song") {
        source.emit(AdapterLines.track(title, album: "Album"))
    }

    /// Lyrics and the strip on, a track playing and its lyrics shown.
    func playWithTheStripOn() async {
        enableLyrics()
        enableStrip()
        client.reply(LrclibReplies.found())
        await harness.registry.bootstrap()
        playTrack()
        await settle { store.syncedLyrics != nil }
    }

    // MARK: setting

    @Test func theSettingIsOffByDefault() {
        #expect(keys.lyricsUnderNotch.defaultValue == false)
        #expect(keys.lyricsUnderNotch.name == "module.media.lyricsUnderNotch")
    }

    @Test func theRowSaysWhatItDoes() {
        #expect(MediaSettingsView.lyricsUnderNotchTitle == "Hiện lời 2 dòng dưới notch")
        #expect(MediaSettingsView.lyricsUnderNotchExplanation == "Khi có lời đồng bộ và nhạc đang phát, notch thu gọn hiện câu đang hát và câu sắp tới.")
    }

    // MARK: when the activity carries the strip

    @Test func whileTheSettingIsOffTheActivityHasNoStrip() async {
        enableLyrics()
        client.reply(LrclibReplies.found())
        await harness.registry.bootstrap()
        playTrack()
        await settle { store.syncedLyrics != nil }
        #expect(store.syncedLyrics != nil)
        #expect(activity?.id == "nowPlaying")
        #expect(activity?.bottom == nil)
        #expect(activity?.bottomHeight == 0)
    }

    @Test func withTheSettingOnSyncedLyricsAndPlaybackTheActivityCarriesTheStrip() async {
        enableLyrics()
        enableStrip()
        client.reply(LrclibReplies.found())
        await harness.registry.bootstrap()
        playTrack()
        // Up at once, and without the strip until the lyrics are there.
        #expect(activity?.id == "nowPlaying")
        #expect(activity?.hasBottom == false)

        await settle { store.syncedLyrics != nil }
        #expect(activity?.hasBottom == true)
        #expect(activity?.bottomHeight == NowPlayingLyricStrip.height)
        #expect(NowPlayingLyricStrip.height == 36)
        #expect(harness.activities.entries.count == 1)
    }

    @Test func withoutSyncedLyricsThereIsNoStrip() async {
        enableStrip()
        await harness.registry.bootstrap()
        playTrack()
        #expect(activity?.id == "nowPlaying")
        #expect(activity?.hasBottom == false)
        #expect(client.requests.isEmpty)
    }

    @Test func instrumentalLyricsGiveNoStrip() async {
        enableLyrics()
        enableStrip()
        client.reply(LrclibReplies.instrumental)
        await harness.registry.bootstrap()
        playTrack()
        await settle { !client.requests.isEmpty }
        await settle { false }
        #expect(activity?.hasBottom == false)
    }

    @Test func aPausedTrackLosesTheStripAfterAMomentAndGetsItBackWhenItPlaysAgain() async {
        await playWithTheStripOn()
        #expect(activity?.hasBottom == true)

        source.emit(AdapterLines.playing(false))
        #expect(activity?.id == "nowPlaying", "the activity itself stays through the pause grace")
        #expect(activity?.hasBottom == true, "a stall shorter than a second must not show as a gap")
        harness.scheduler.advance(by: .milliseconds(900))
        #expect(activity?.hasBottom == true)
        harness.scheduler.advance(by: .milliseconds(200))
        #expect(activity?.id == "nowPlaying")
        #expect(activity?.hasBottom == false)

        source.emit(AdapterLines.playing(true))
        #expect(activity?.hasBottom == true)
        #expect(harness.activities.entries.count == 1)
    }

    @Test func aBriefStallOrASeekNeverRepublishesTheActivity() async throws {
        await playWithTheStripOn()
        let first = try #require(harness.activities.current)

        source.emit(AdapterLines.playing(false))
        source.emit(AdapterLines.position(80))
        harness.scheduler.advance(by: .milliseconds(600))
        source.emit(AdapterLines.playing(true))
        #expect(harness.activities.current == first)

        // The timer that would have ended the stall is gone.
        harness.scheduler.advance(by: .seconds(5))
        #expect(harness.activities.current == first)
        #expect(activity?.hasBottom == true)
    }

    @Test func lyricsThatArriveWhileATrackIsPausedWaitForPlayback() async {
        enableLyrics()
        enableStrip()
        client.reply(LrclibReplies.found())
        await harness.registry.bootstrap()
        playTrack()
        source.emit(AdapterLines.playing(false))
        await settle { store.syncedLyrics != nil }
        #expect(store.syncedLyrics != nil)
        #expect(activity?.id == "nowPlaying")
        #expect(activity?.hasBottom == false)

        source.emit(AdapterLines.playing(true))
        #expect(activity?.hasBottom == true)
    }

    @Test func switchingTheSettingUpdatesTheActivityWhileATrackPlays() async {
        enableLyrics()
        client.reply(LrclibReplies.found())
        await harness.registry.bootstrap()
        playTrack()
        await settle { store.syncedLyrics != nil }
        #expect(activity?.hasBottom == false)

        enableStrip()
        await settle { activity?.hasBottom == true }
        #expect(activity?.hasBottom == true)

        harness.settings.set(false, for: keys.lyricsUnderNotch)
        await settle { activity?.hasBottom == false }
        #expect(activity?.hasBottom == false)
        #expect(activity?.id == "nowPlaying")
    }

    @Test func turningTheLyricsOffTakesTheStripAway() async {
        await playWithTheStripOn()
        harness.settings.set(false, for: keys.lyrics)
        await settle { activity?.hasBottom == false }
        #expect(store.syncedLyrics == nil)
        #expect(activity?.hasBottom == false)
    }

    @Test func positionUpdatesDoNotRepublishTheActivity() async throws {
        await playWithTheStripOn()
        let first = try #require(harness.activities.current)
        source.emit(AdapterLines.position(31))
        source.emit(AdapterLines.position(45))
        source.emit(AdapterLines.playing(true))
        #expect(harness.activities.current == first)
    }

    // MARK: holding the strip across a track change

    /// What the lookup of the track after the first one ends with.
    enum Ending: CaseIterable, CustomTestStringConvertible {
        case notFound, instrumental, unsyncedOnly, rateLimited

        var reply: HTTPReply {
            switch self {
            case .notFound: LrclibReplies.notFound
            case .instrumental: LrclibReplies.instrumental
            case .unsyncedOnly: LrclibReplies.found(synced: nil, plain: "x\ny")
            case .rateLimited: LrclibReplies.busy()
            }
        }

        var testDescription: String { String(describing: self) }
    }

    /// Makes the next request wait at the gate, with `reply` as the answer to it and to any later one (the service falls
    /// back to a second request when the first has no synced lyrics).
    func holdNextLookup(replying reply: HTTPReply = LrclibReplies.found(synced: LrclibReplies.lrcText(4, tag: "Other"))) -> Gate {
        let gate = Gate()
        var waited = false
        client.handler = { _ in
            if !waited {
                waited = true
                await gate.wait()
            }
            return reply
        }
        return gate
    }

    /// Plays "Second" after the first track's strip is up and lets the lookup reach the gate.
    func changeTrack(through gate: Gate) async {
        source.emit(AdapterLines.empty)
        playTrack("Second")
        // The service spaces requests 300 ms apart.
        harness.scheduler.advance(by: .milliseconds(300))
        await settle { gate.isWaiting }
    }

    @Test func aTrackChangeKeepsTheStripWhileTheNewLyricsLoadAndPublishesOnce() async throws {
        await playWithTheStripOn()
        let first = try #require(harness.activities.current)
        let gate = holdNextLookup()

        source.emit(AdapterLines.empty)
        #expect(harness.activities.current == first, "the track change debounce publishes nothing")
        #expect(activity?.hasBottom == true)

        playTrack("Second")
        #expect(store.syncedLyrics == nil, "the old track's lyrics must not stay under the new track")
        #expect(activity?.hasBottom == true, "the strip stays while the new lyrics are looked up")
        #expect(activity?.bottomHeight == NowPlayingLyricStrip.height)
        let second = try #require(harness.activities.current)
        #expect(second != first, "the new track is published, once")

        harness.scheduler.advance(by: .milliseconds(300))
        await settle { gate.isWaiting }
        #expect(activity?.hasBottom == true)

        gate.open()
        await settle { store.syncedLyrics != nil }
        #expect(store.syncedLyrics?.first?.text == "Other 1")
        #expect(activity?.hasBottom == true)
        #expect(harness.activities.current == second, "the lyrics arrive into the same strip without another publish")

        // The hold's timer is gone: nothing hides the strip later.
        harness.scheduler.advance(by: .seconds(10))
        #expect(harness.activities.current == second)
        #expect(activity?.hasBottom == true)
    }

    @Test func aTrackChangeWithCachedLyricsNeverShowsAGap() async throws {
        await playWithTheStripOn()
        client.reply(LrclibReplies.found(synced: LrclibReplies.lrcText(4, tag: "Other")))
        playTrack("Second")
        harness.scheduler.advance(by: .milliseconds(300))
        await settle { store.syncedLyrics?.first?.text == "Other 1" }

        // Back to the first track: its lyrics are cached and arrive one hop after the change.
        source.emit(AdapterLines.empty)
        playTrack("Song")
        #expect(activity?.hasBottom == true)
        await settle { store.syncedLyrics?.first?.text != "Other 1" && store.syncedLyrics != nil }
        #expect(activity?.hasBottom == true)
        #expect(store.syncedLyrics?.count == LrclibReplies.syncedLines.count)
    }

    @Test func noLyricsThreeSecondsAfterATrackChangeHideTheStripOnce() async throws {
        await playWithTheStripOn()
        let gate = holdNextLookup(replying: LrclibReplies.notFound)
        await changeTrack(through: gate)
        let held = try #require(harness.activities.current)
        #expect(activity?.hasBottom == true)

        harness.scheduler.advance(by: .milliseconds(2500))
        #expect(harness.activities.current == held)
        #expect(activity?.hasBottom == true, "still within three seconds of the track change")

        harness.scheduler.advance(by: .milliseconds(600))
        #expect(activity?.id == "nowPlaying")
        #expect(activity?.hasBottom == false, "hidden after the hold, and the activity stays")
        let hidden = try #require(harness.activities.current)
        #expect(hidden != held)

        // The late answer (no lyrics) and the rest of time change nothing more: one hide, no flicker.
        gate.open()
        await settle { false }
        harness.scheduler.advance(by: .seconds(10))
        #expect(harness.activities.current == hidden)
    }

    @Test(arguments: Ending.allCases)
    func aLookupThatEndsWithoutSyncedLyricsReleasesTheStripAtOnce(_ ending: Ending) async throws {
        await playWithTheStripOn()
        let held = holdNextLookup(replying: ending.reply)
        await changeTrack(through: held)
        let before = try #require(harness.activities.current)
        #expect(activity?.hasBottom == true, "held while the lookup is out")

        held.open()
        // A lookup without a hit goes through a few requests, 300 ms apart; all of them are well inside the hold.
        var waitedFor = Duration.zero
        while activity?.hasBottom == true, waitedFor < .seconds(2) {
            await settle { activity?.hasBottom == false }
            harness.scheduler.advance(by: .milliseconds(300))
            waitedFor += .milliseconds(300)
        }
        #expect(store.syncedLyrics == nil)
        #expect(activity?.hasBottom == false)
        #expect(harness.activities.current != before)
        let hidden = try #require(harness.activities.current)

        // Released by the end of the lookup, not by the hold running out, and the hold's own timer does nothing later.
        #expect(waitedFor < .seconds(2))
        harness.scheduler.advance(by: .seconds(5))
        #expect(harness.activities.current == hidden)
    }

    @Test func holdingDoesNotApplyToAStripThatWasNeverUp() async {
        enableLyrics()
        enableStrip()
        let gate = holdNextLookup()
        await harness.registry.bootstrap()
        playTrack()
        harness.scheduler.advance(by: .milliseconds(300))
        await settle { gate.isWaiting }
        #expect(activity?.hasBottom == false, "nothing to hold: the first track starts without a strip")
        gate.open()
        await settle { store.syncedLyrics != nil }
        #expect(activity?.hasBottom == true)
    }

    @Test func turningTheSettingOffEndsTheHoldAtOnce() async {
        await playWithTheStripOn()
        let gate = holdNextLookup()
        await changeTrack(through: gate)
        #expect(activity?.hasBottom == true)

        harness.settings.set(false, for: keys.lyricsUnderNotch)
        await settle { activity?.hasBottom == false }
        #expect(activity?.hasBottom == false)
        gate.open()
        await settle { store.syncedLyrics != nil }
        harness.scheduler.advance(by: .seconds(10))
        #expect(activity?.hasBottom == false)
    }

    @Test func stoppingTheModuleDuringAHoldLeavesNothingBehind() async {
        await playWithTheStripOn()
        let gate = holdNextLookup()
        await changeTrack(through: gate)
        await harness.registry.setEnabled(false, for: "media")
        #expect(activity == nil)
        gate.open()
        harness.scheduler.advance(by: .seconds(10))
        #expect(activity == nil)
    }

    @Test func theActivityGoesAwayWithItsStrip() async {
        await playWithTheStripOn()
        source.emit(AdapterLines.playing(false))
        harness.scheduler.advance(by: .seconds(5))
        #expect(activity == nil)

        // Back after the grace: the track is the same, so the activity comes up with the strip again.
        source.emit(AdapterLines.playing(true))
        #expect(activity?.hasBottom == true)
    }

    @Test func stoppingTheModuleClearsItAndAStartedOneBeginsWithoutAStrip() async {
        await playWithTheStripOn()
        await harness.registry.setEnabled(false, for: "media")
        #expect(activity == nil)

        await harness.registry.setEnabled(true, for: "media")
        playTrack()
        #expect(activity?.id == "nowPlaying")
        #expect(activity?.hasBottom == false)
        await settle { store.syncedLyrics != nil }
        #expect(activity?.hasBottom == true)
    }

    @Test func aStoppedSourceTakesTheStripAway() async {
        await playWithTheStripOn()
        source.fail("gave up")
        #expect(activity == nil)
    }
}
