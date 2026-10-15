import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import MediaModule

/// The buttons beside play and pause, driven through the module with a fake source and a fake output device.
@Suite final class MediaControlRowTests {
    let source = FakeNowPlayingSource()
    let hardware = FakeVolumeHardware(level: 0.4)
    let volumeQueue = ManualVolumeQueue()
    let client = FakeHTTPClient()
    let module: MediaModule
    let harness: RegistryHarness
    let storageBase: URL

    init() {
        module = MediaModule(
            source: source, spectrum: FakeSpectrumSource(), lyricsClient: client, tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil },
            volume: VolumeModel(hardware: hardware, queue: volumeQueue)
        )
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
    }

    deinit { try? FileManager.default.removeItem(at: storageBase) }

    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }
    var store: NowPlayingStore { module.store }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    /// A track whose player reports what the buttons need.
    func play(_ extra: [String: Any] = [:], bundle: String = "com.example.Player", elapsed: Double = 30, duration: Double = 200) {
        source.emit(AdapterLines.track(bundle: bundle, elapsed: elapsed, duration: duration, extra: extra))
    }

    // MARK: the layout

    @Test func theRowStartsAsItAlwaysLookedAndFollowsTheSetting() async {
        #expect(keys.controlButtons.defaultValue == .standard)
        await harness.registry.bootstrap()
        #expect(store.controlLayout == .standard)
        let chosen = MediaControlLayout(slots: [.shuffle, .previous, .next, .repeatMode])
        harness.settings.set(chosen, for: keys.controlButtons)
        await settle { store.controlLayout == chosen }
        #expect(store.controlLayout == chosen)
    }

    @Test func aLayoutChosenBeforeTheModuleStartsIsUsedFromTheStart() async {
        let chosen = MediaControlLayout(slots: [.rewind, .volume, .lyrics, .forward])
        harness.settings.set(chosen, for: keys.controlButtons)
        await harness.registry.bootstrap()
        #expect(store.controlLayout == chosen)
    }

    @Test func theChoiceIsKeptInTheSettings() {
        let chosen = MediaControlLayout(slots: [.shuffle, .none, .like, .repeatMode])
        harness.settings.set(chosen, for: keys.controlButtons)
        #expect(harness.settings.value(keys.controlButtons) == chosen)
        harness.settings.reset(keys.controlButtons)
        #expect(harness.settings.value(keys.controlButtons) == .standard)
    }

    // MARK: pressing

    @Test func previousAndNextSendTheirCommandsToTheSource() async {
        await harness.registry.bootstrap()
        play()
        module.press(.previous)
        module.press(.next)
        #expect(source.sent == [.previousTrack, .nextTrack])
    }

    @Test func aSkipTheButtonsRefuseIsNotSent() async {
        await harness.registry.bootstrap()
        play(["prohibitsSkip": true])
        module.press(.previous)
        module.press(.next)
        #expect(source.sent.isEmpty)
    }

    @Test func theSeekButtonsSeekFifteenSecondsFromTheClock() async throws {
        await harness.registry.bootstrap()
        play(elapsed: 100, duration: 200)
        module.press(.forward)
        // The player reports its position again (here still 100 s), which ends the wait for the first seek.
        play(elapsed: 100, duration: 200)
        module.press(.rewind)
        let forward = try #require(source.seeks.first)
        let back = try #require(source.seeks.last)
        // The position moves on with the clock between the line and the press.
        #expect(abs(forward - 115) < 5)
        #expect(abs(back - 85) < 5)
        #expect(source.sent.isEmpty, "a seek is not a MediaRemote command")
    }

    @Test func seekTargetsAreClampedToTheTrackWhenPressed() async {
        await harness.registry.bootstrap()
        play(elapsed: 4, duration: 200)
        module.press(.rewind)
        #expect(source.seeks == [0])
        play(elapsed: 199, duration: 200)
        module.press(.forward)
        #expect(source.seeks == [0, 200])
    }

    /// The moment the player's last report put the track at its position, so the clock gives exactly that position.
    var clockNow: Date { store.state.elapsedAnchor!.timestamp }

    @Test func quickRepeatedSeekTapsAddUpFromTheTargetStillWaitingForThePlayer() async {
        await harness.registry.bootstrap()
        play(elapsed: 30, duration: 200)
        let start = clockNow
        module.press(.forward, at: start)
        module.press(.forward, at: start + 0.2)
        module.press(.forward, at: start + 0.4)
        #expect(source.seeks == [45, 60, 75], "three taps move 45 s, not 15")
        module.press(.rewind, at: start + 0.6)
        #expect(source.seeks == [45, 60, 75, 60])
    }

    @Test func accumulatedSeeksStayInsideTheTrack() async {
        await harness.registry.bootstrap()
        play(elapsed: 180, duration: 200)
        let start = clockNow
        for tap in 0..<3 { module.press(.forward, at: start + Double(tap) * 0.2) }
        #expect(source.seeks == [195, 200, 200])
        play(elapsed: 20, duration: 200)
        let again = clockNow
        for tap in 0..<3 { module.press(.rewind, at: again + Double(tap) * 0.2) }
        #expect(source.seeks.suffix(3) == [5, 0, 0])
    }

    @Test func aSeekThatWasNotAnsweredForTwoSecondsIsForgotten() async {
        await harness.registry.bootstrap()
        play(elapsed: 30, duration: 200)
        let start = clockNow
        module.press(.forward, at: start)
        module.press(.forward, at: start + 3)
        // Three seconds on, the clock itself is at 33 s.
        #expect(source.seeks == [45, 48])
    }

    @Test func thePlayersNewReportReplacesTheWaitingTarget() async {
        await harness.registry.bootstrap()
        play(elapsed: 30, duration: 200)
        let start = clockNow
        module.press(.forward, at: start)
        source.emit(AdapterLines.position(45))
        let reported = clockNow
        module.press(.forward, at: reported)
        #expect(source.seeks == [45, 60], "from the position the player reported, which is the same here")
        source.emit(AdapterLines.position(100))
        module.press(.forward, at: clockNow)
        #expect(source.seeks == [45, 60, 115])
    }

    @Test func aSeekFromTheProgressBarIsWhereTheNextButtonTapStartsFrom() async {
        await harness.registry.bootstrap()
        play(elapsed: 30, duration: 200)
        let start = clockNow
        module.seek(toSeconds: 100, at: start)
        module.press(.forward, at: start + 0.3)
        #expect(source.seeks == [100, 115])
    }

    @Test func aNewTrackStartsFromItsOwnClock() async {
        await harness.registry.bootstrap()
        play(elapsed: 30, duration: 200)
        module.press(.forward, at: clockNow)
        source.emit(AdapterLines.track("Another", elapsed: 5, duration: 100))
        module.press(.forward, at: clockNow)
        #expect(source.seeks == [45, 20])
    }

    @Test func shuffleSetsTheOppositeModeAndTheNextReportFollows() async {
        await harness.registry.bootstrap()
        play(["shuffleMode": 1])
        module.press(.shuffle)
        #expect(source.shuffles == [.tracks])
        source.emit(AdapterLines.diff(["shuffleMode": 3]))
        module.press(.shuffle)
        #expect(source.shuffles == [.tracks, .off])
        #expect(source.sent.isEmpty)
    }

    @Test func repeatCyclesThroughTheModesThePlayerReports() async {
        await harness.registry.bootstrap()
        play(["repeatMode": 1])
        module.press(.repeatMode)
        source.emit(AdapterLines.diff(["repeatMode": 3]))
        module.press(.repeatMode)
        source.emit(AdapterLines.diff(["repeatMode": 2]))
        module.press(.repeatMode)
        #expect(source.repeats == [.playlist, .track, .off])
    }

    @Test func shuffleAndRepeatDoNothingForAPlayerThatDoesNotReportThem() async {
        await harness.registry.bootstrap()
        play()
        module.press(.shuffle)
        module.press(.repeatMode)
        #expect(source.shuffles.isEmpty)
        #expect(source.repeats.isEmpty)
    }

    @Test func likeIsSentOnlyWhenThePlayerSupportsItAndTheSourceCanSendIt() async {
        await harness.registry.bootstrap()
        play(["supportsIsLiked": true])
        module.press(.like)
        #expect(source.sent == [.likeTrack])
        play()
        module.press(.like)
        #expect(source.sent == [.likeTrack], "the player says it does not support it")
    }

    @Test func aSourceThatCannotLikeKeepsTheButtonDisabledWhateverThePlayerSays() async {
        source.canLike = false
        await harness.registry.bootstrap()
        #expect(!store.canLike)
        play(["supportsIsLiked": true])
        module.press(.like)
        #expect(source.sent.isEmpty)
    }

    @Test func theRealAdapterCannotLikeYet() {
        let adapter = AdapterProcess(
            script: URL(filePath: "/App/mediaremote-adapter.pl"), framework: URL(filePath: "/App/MediaRemoteAdapter.framework"),
            scheduler: harness.scheduler
        )
        #expect(!adapter.canLike, "its `send` accepts the commands 0 to 13 only (vendor/…/send.m)")
    }

    @Test func pressingTheVolumeButtonSendsNothingToThePlayerOrTheDevice() async {
        await harness.registry.bootstrap()
        play()
        module.press(.volume)
        module.press(.none)
        #expect(source.sent.isEmpty)
        #expect(source.seeks.isEmpty)
        #expect(hardware.levelWrites.isEmpty)
        #expect(volumeQueue.pendingCount == 0)
    }

    @Test func pressesAreIgnoredWhileStopped() {
        module.press(.next)
        module.press(.shuffle)
        #expect(source.sent.isEmpty)
        #expect(source.shuffles.isEmpty)
    }

    @Test func aPressAfterTheSourceFailedDoesNotReachIt() async {
        await harness.registry.bootstrap()
        play(["shuffleMode": 1, "repeatMode": 1])
        source.fail("gave up")
        module.press(.next)
        module.press(.shuffle)
        module.press(.repeatMode)
        #expect(source.sent.isEmpty)
        #expect(source.shuffles.isEmpty)
        #expect(source.repeats.isEmpty)
    }

    @Test func theTabsActionsPressThroughTheModule() async {
        await harness.registry.bootstrap()
        play(["shuffleMode": 1])
        module.actions.press(.shuffle)
        module.actions.press(.next)
        #expect(source.shuffles == [.tracks])
        #expect(source.sent == [.nextTrack])
    }

    // MARK: the volume

    @Test func theModuleOffersTheDeviceItWasGiven() {
        module.volume.refresh()
        volumeQueue.drain()
        #expect(module.volume.level == 0.4)
        module.volume.set(0.7)
        volumeQueue.drain()
        #expect(hardware.levelWrites == [0.7])
    }

    @Test func stoppingTheModuleStopsListeningToTheDevice() async {
        await harness.registry.bootstrap()
        module.volume.startWatching()
        volumeQueue.drain()
        #expect(hardware.observerCount == 1)
        await harness.registry.setEnabled(false, for: "media")
        volumeQueue.drain()
        #expect(hardware.observerCount == 0)
    }

    // MARK: lyrics

    func lyricsPlaying() async {
        client.reply(LrclibReplies.found())
        harness.settings.set(true, for: keys.lyrics)
        harness.settings.set(true, for: keys.lyricsUnderNotch)
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track("Song", album: "Album"))
        await settle { store.syncedLyrics != nil }
    }

    @Test func theLyricsButtonHidesTheRowAndTheStripForTheSessionAndShowsThemAgain() async {
        await lyricsPlaying()
        #expect(store.lyricRow == .synced)
        #expect(harness.activities.current?.activity.hasBottom == true)

        module.press(.lyrics)
        #expect(store.lyricsHidden)
        #expect(store.lyricRow == .reserved, "empty, but in its place: the player does not move")
        #expect(harness.activities.current?.activity.hasBottom == false, "the strip under the notch goes too")

        module.press(.lyrics)
        #expect(!store.lyricsHidden)
        #expect(store.lyricRow == .synced)
        #expect(harness.activities.current?.activity.hasBottom == true)
    }

    @Test func hidingTheLyricsKeepsTheLyricsThemselvesAndWritesNothingToTheSettings() async {
        await lyricsPlaying()
        let before = store.syncedLyrics
        module.press(.lyrics)
        #expect(store.syncedLyrics == before)
        #expect(harness.settings.value(keys.lyrics), "the lyrics source stays on")
        #expect(harness.settings.value(keys.lyricsUnderNotch))
    }

    @Test func theLyricsButtonDoesNothingWhileNoLyricsSourceIsOn() async {
        await harness.registry.bootstrap()
        play()
        module.press(.lyrics)
        #expect(!store.lyricsHidden)
        #expect(store.lyricRow == .absent)
    }

    @Test func switchingTheLyricsSourceOffWhileHiddenLeavesNoRowAtAll() async {
        await lyricsPlaying()
        module.press(.lyrics)
        harness.settings.set(false, for: keys.lyrics)
        await settle { !store.lyricsAreOn }
        #expect(store.lyricRow == .absent)
    }

    @Test func lyricsHiddenForTheSessionStayHiddenForTheNextTrack() async {
        await lyricsPlaying()
        module.press(.lyrics)
        source.emit(AdapterLines.track("Another song", album: "Album"))
        #expect(store.lyricRow == .reserved)
    }
}
