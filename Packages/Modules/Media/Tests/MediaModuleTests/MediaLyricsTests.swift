import Foundation
import MyNotchCore
import MyNotchTestSupport
import Observation
import Testing
@testable import MediaModule

@Suite final class MediaLyricsTests {
    let source = FakeNowPlayingSource()
    let client = FakeHTTPClient()
    let module: MediaModule
    let harness: RegistryHarness
    /// Where the harness's modules keep their files; the disk cache of lyrics ends up here.
    let storageBase: URL

    init() {
        module = MediaModule(source: source, spectrum: FakeSpectrumSource(), lyricsClient: client, lookUpApp: { _ in nil })
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
    }

    deinit { try? FileManager.default.removeItem(at: storageBase) }

    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }
    var store: NowPlayingStore { module.store }

    /// Lets the settings loop and the fetch task run after a settings write or a track change.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func enableLyrics() {
        harness.settings.set(true, for: keys.lyrics)
    }

    func queryValue(_ name: String, of request: URLRequest) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    func playTrack(_ title: String = "Song", album: String? = "Album") {
        source.emit(AdapterLines.track(title, album: album))
    }

    // MARK: off by default

    @Test func lyricsAreOffByDefault() {
        #expect(keys.lyrics.defaultValue == false)
        #expect(keys.lyrics.name == "module.media.lyrics")
    }

    @Test func whileOffTheServiceIsNeverAsked() async {
        await harness.registry.bootstrap()
        playTrack()
        playTrack("Another")
        source.emit(AdapterLines.position(40))
        await settle { !client.requests.isEmpty }
        #expect(client.requests.isEmpty)
        #expect(store.syncedLyrics == nil)
    }

    @Test func turningItOnAndOffAgainSendsNothingWhileOff() async {
        await harness.registry.bootstrap()
        playTrack()
        client.reply(LrclibReplies.found())
        enableLyrics()
        await settle { store.syncedLyrics != nil }
        #expect(client.requests.count == 1)

        harness.settings.set(false, for: keys.lyrics)
        await settle { store.syncedLyrics == nil }
        #expect(store.syncedLyrics == nil)
        harness.scheduler.advance(by: .seconds(1))
        playTrack("Another")
        await settle { client.requests.count > 1 }
        #expect(client.requests.count == 1)
    }

    // MARK: fetching

    @Test func fetchesWhenTheTrackStartsAndShowsTheSyncedLines() async throws {
        enableLyrics()
        client.reply(LrclibReplies.found())
        await harness.registry.bootstrap()
        playTrack()
        await settle { store.syncedLyrics != nil }
        #expect(store.syncedLyrics == LrclibReplies.syncedLines)

        let request = try #require(client.requests.first)
        #expect(client.requests.count == 1)
        #expect(queryValue("track_name", of: request) == "Song")
        #expect(queryValue("artist_name", of: request) == "Artist")
        #expect(queryValue("album_name", of: request) == "Album")
        #expect(queryValue("duration", of: request) == "200")
    }

    @Test func enablingWhileATrackPlaysFetchesThatTrack() async {
        await harness.registry.bootstrap()
        playTrack()
        client.reply(LrclibReplies.found())
        enableLyrics()
        await settle { store.syncedLyrics != nil }
        #expect(store.syncedLyrics == LrclibReplies.syncedLines)
    }

    @Test func positionAndPlayStateChangesDoNotFetchAgain() async {
        enableLyrics()
        client.reply(LrclibReplies.found())
        await harness.registry.bootstrap()
        playTrack()
        await settle { store.syncedLyrics != nil }

        source.emit(AdapterLines.position(31))
        source.emit(AdapterLines.playing(false))
        source.emit(AdapterLines.playing(true))
        source.emit(AdapterLines.position(2))
        await settle { client.requests.count > 1 }
        #expect(client.requests.count == 1)
        #expect(store.syncedLyrics == LrclibReplies.syncedLines)
    }

    @Test func anotherTrackClearsTheOldLyricsAndFetchesItsOwn() async {
        enableLyrics()
        client.reply(LrclibReplies.found())
        await harness.registry.bootstrap()
        playTrack("First")
        await settle { store.syncedLyrics != nil }

        let second = LrclibReplies.lyricLines(4, tag: "Other")
        client.reply(LrclibReplies.found(synced: LrclibReplies.lrcText(4, tag: "Other")))
        playTrack("Second")
        #expect(store.syncedLyrics == nil)
        // The service spaces requests 300 ms apart.
        harness.scheduler.advance(by: .milliseconds(300))
        await settle { store.syncedLyrics != nil }
        #expect(store.syncedLyrics == second)
        #expect(client.requests.count == 2)
    }

    @Test func tracksSkippedBeforeTheirTurnAreNeverLookedUp() async {
        enableLyrics()
        client.reply(LrclibReplies.found())
        await harness.registry.bootstrap()
        playTrack("A")
        await settle { store.syncedLyrics != nil }

        // Within the 300 ms after A's answer: B is superseded by C before its request could go out.
        playTrack("B")
        playTrack("C")
        harness.scheduler.advance(by: .milliseconds(300))
        await settle { client.requests.count == 2 }
        #expect(client.requests.compactMap { queryValue("track_name", of: $0) } == ["A", "C"])
        harness.scheduler.advance(by: .seconds(1))
        await settle { false }
        #expect(client.requests.count == 2)
    }

    @Test func advertisementsAndTracksWithoutALengthAreNeverLookedUp() async {
        enableLyrics()
        client.reply(LrclibReplies.found())
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track("Ad", isAdvertisement: true))
        source.emit(AdapterLines.track("Live stream", duration: 0))
        await settle { !client.requests.isEmpty }
        #expect(client.requests.isEmpty)
        #expect(store.syncedLyrics == nil)
    }

    @Test func nothingIsShownForInstrumentalMissingOrUnavailable() async {
        enableLyrics()
        await harness.registry.bootstrap()
        // A missing track is asked four times, each after the spacing; the others once.
        let answers = [(LrclibReplies.instrumental, 1), (LrclibReplies.notFound, 4), (HTTPReply(status: 500), 1)]
        var asked = 0
        for (index, (answer, requests)) in answers.enumerated() {
            client.reply(answer)
            playTrack("Track \(index)")
            for _ in 0...requests {
                await settle { false }
                harness.scheduler.advance(by: .milliseconds(300))
            }
            asked += requests
            #expect(client.requests.count == asked)
            #expect(store.syncedLyrics == nil)
            #expect(!store.lyricsAreUnsynced)
        }
    }

    @Test func plainLyricsOnlyMarkTheTrackAsUnsynced() async {
        enableLyrics()
        await harness.registry.bootstrap()
        // Plain-only records are a fallback: the chain runs to its end (two lookups by name, two searches) first.
        client.handler = { request in
            request.url!.path() == "/api/get" ? LrclibReplies.found(synced: nil, plain: "La la") : LrclibReplies.results([])
        }
        playTrack("Plain")
        for _ in 0..<5 {
            await settle { store.lyricsAreUnsynced }
            harness.scheduler.advance(by: .milliseconds(300))
        }
        #expect(client.requests.count == 4)
        #expect(store.lyricsAreUnsynced)
        #expect(store.syncedLyrics == nil)

        // The next track starts clean.
        client.reply(LrclibReplies.instrumental)
        harness.scheduler.advance(by: .milliseconds(300))
        playTrack("Other")
        await settle { !store.lyricsAreUnsynced }
        #expect(!store.lyricsAreUnsynced)
    }

    @Test func aTrackChangeWhileFetchingNeverShowsTheOldAnswer() async {
        enableLyrics()
        let gate = Gate()
        var isFirst = true
        client.handler = { [gate] _ in
            if isFirst {
                isFirst = false
                await gate.wait()
                return LrclibReplies.found(synced: LrclibReplies.lrcText(4, tag: "Old song"))
            }
            return LrclibReplies.found(synced: LrclibReplies.lrcText(4, tag: "New song"))
        }
        await harness.registry.bootstrap()
        playTrack("Old")
        await settle { gate.isWaiting }
        playTrack("New")

        gate.open()
        await settle { store.syncedLyrics != nil }
        #expect(store.syncedLyrics == nil)
        harness.scheduler.advance(by: .milliseconds(300))
        await settle { store.syncedLyrics != nil }
        #expect(store.syncedLyrics == LrclibReplies.lyricLines(4, tag: "New song"))
        #expect(client.requests.count == 2)
    }

    @Test func aStoppedSourceClearsTheLyrics() async {
        enableLyrics()
        client.reply(LrclibReplies.found())
        await harness.registry.bootstrap()
        playTrack()
        await settle { store.syncedLyrics != nil }
        source.fail("gave up")
        #expect(store.syncedLyrics == nil)
    }

    // MARK: rate limits

    @Test func aRateLimitedTrackIsAskedAgainWhenTheCooldownEnds() async {
        enableLyrics()
        client.reply(LrclibReplies.busy(retryAfter: "10"))
        await harness.registry.bootstrap()
        playTrack()
        await settle { !client.requests.isEmpty }
        await settle { false }
        #expect(client.requests.count == 1)

        client.reply(LrclibReplies.found())
        harness.scheduler.advance(by: .seconds(9))
        await settle { client.requests.count > 1 }
        #expect(client.requests.count == 1)
        harness.scheduler.advance(by: .seconds(1))
        await settle { store.syncedLyrics != nil }
        #expect(store.syncedLyrics == LrclibReplies.syncedLines)
        #expect(client.requests.count == 2)
    }

    @Test func theRetryHappensOnlyOnce() async {
        enableLyrics()
        client.reply(LrclibReplies.busy(retryAfter: "10"))
        await harness.registry.bootstrap()
        playTrack()
        await settle { !client.requests.isEmpty }
        harness.scheduler.advance(by: .seconds(10))
        await settle { client.requests.count == 2 }
        #expect(client.requests.count == 2)
        await settle { false }
        harness.scheduler.advance(by: .seconds(3600))
        await settle { client.requests.count > 2 }
        #expect(client.requests.count == 2)
    }

    @Test func otherFailuresAreNotRetried() async {
        enableLyrics()
        client.reply(HTTPReply(status: 500))
        await harness.registry.bootstrap()
        playTrack()
        await settle { !client.requests.isEmpty }
        await settle { false }
        harness.scheduler.advance(by: .seconds(3600))
        await settle { client.requests.count > 1 }
        #expect(client.requests.count == 1)
    }

    @Test func aTrackChangeDuringTheCooldownDropsTheOldRetry() async {
        enableLyrics()
        client.reply(LrclibReplies.busy(retryAfter: "10"))
        await harness.registry.bootstrap()
        playTrack("A")
        await settle { !client.requests.isEmpty }
        await settle { false }

        // B waits out the cooldown too and gets its own retry; A's is gone.
        playTrack("B")
        harness.scheduler.advance(by: .seconds(1))
        await settle { false }
        client.reply(LrclibReplies.found())
        harness.scheduler.advance(by: .seconds(9))
        await settle { store.syncedLyrics != nil }
        #expect(client.requests.compactMap { queryValue("track_name", of: $0) } == ["A", "B"])
    }

    // MARK: lifecycle

    @Test func stoppingClearsTheLyricsAndDropsAnAnswerStillOnItsWay() async {
        enableLyrics()
        let gate = Gate()
        client.handler = { [gate] _ in
            await gate.wait()
            return LrclibReplies.found()
        }
        await harness.registry.bootstrap()
        playTrack()
        await settle { gate.isWaiting }

        await harness.registry.setEnabled(false, for: "media")
        gate.open()
        await settle { store.syncedLyrics != nil }
        #expect(store.syncedLyrics == nil)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func answersAreCachedAcrossARestart() async {
        enableLyrics()
        client.reply(LrclibReplies.found())
        await harness.registry.bootstrap()
        playTrack()
        await settle { store.syncedLyrics != nil }

        await harness.registry.setEnabled(false, for: "media")
        #expect(store.syncedLyrics == nil)
        await harness.registry.setEnabled(true, for: "media")
        playTrack()
        await settle { store.syncedLyrics != nil }
        #expect(store.syncedLyrics == LrclibReplies.syncedLines)
        #expect(client.requests.count == 1)
    }

    // MARK: settings

    @Test func theSettingExplainsWhatIsSent() {
        #expect(MediaSettingsView.lyricsExplanation == "Khi bật, tên bài, nghệ sĩ, album và thời lượng của mỗi bài mới (kể cả video phát trong trình duyệt) được gửi tới lrclib.net để lấy lời.")
    }
}

@Suite struct NowPlayingStoreLyricsTests {
    let lines = [LyricLine(time: 10, text: "a"), LyricLine(time: 31, text: "b"), LyricLine(time: 40, text: "")]

    func makeStore(playing: Bool = true) -> NowPlayingStore {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(playing: playing, elapsed: 30), receivedAt: Date())
        store.showLyrics(lines)
        return store
    }

    @Test func noLyricsByDefault() {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        #expect(store.syncedLyrics == nil)
        #expect(store.lyric(at: Date()) == nil)
    }

    @Test func theLineFollowsThePlaybackClock() throws {
        let store = makeStore()
        let anchor = try #require(store.state.elapsedAnchor).timestamp
        #expect(store.lyric(at: anchor)?.text == "a")
        #expect(store.lyric(at: anchor + 1.5)?.text == "b")
        #expect(store.lyric(at: anchor + 10)?.text == "")
    }

    @Test func aPausedTrackStaysOnItsLine() throws {
        let store = makeStore(playing: false)
        let anchor = try #require(store.state.elapsedAnchor).timestamp
        #expect(store.lyric(at: anchor + 60)?.text == "a")
    }

    @Test func nothingBeforeTheFirstLine() throws {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(elapsed: 3), receivedAt: Date())
        store.showLyrics(lines)
        let anchor = try #require(store.state.elapsedAnchor).timestamp
        #expect(store.lyric(at: anchor) == nil)
    }

    @Test func nothingWithoutAKnownPosition() {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.showLyrics(lines)
        #expect(store.lyric(at: Date()) == nil)
    }

    @Test func unsyncedLyricsAreFlaggedUntilTheyAreReplaced() {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.showUnsyncedLyrics()
        #expect(store.lyricsAreUnsynced)
        #expect(store.syncedLyrics == nil)
        store.showLyrics(lines)
        #expect(!store.lyricsAreUnsynced)
        store.showUnsyncedLyrics()
        store.reset()
        #expect(!store.lyricsAreUnsynced)
    }

    @Test func resetForgetsTheLyrics() {
        let store = makeStore()
        store.reset()
        #expect(store.syncedLyrics == nil)
    }

    @Test func showingTheSameLyricsAgainChangesNothing() {
        let store = makeStore()
        // onChange is @Sendable but runs synchronously on the writing (main) thread in this test.
        nonisolated(unsafe) var changes = 0
        withObservationTracking { _ = store.syncedLyrics } onChange: { changes += 1 }
        store.showLyrics(lines)
        #expect(changes == 0)
        store.showLyrics(nil)
        #expect(changes == 1)
    }
}
