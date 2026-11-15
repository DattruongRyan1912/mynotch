import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import MediaModule
@testable import YouTubeBridgeKit

/// The module with several sources: what the notch follows, what the tab shows, and where each control goes.
@Suite final class MediaSourcesModuleTests {
    static let spotifyID = "com.spotify.client"
    static let musicID = "com.apple.Music"

    let source = FakeNowPlayingSource()
    let client = FakeHTTPClient()
    let environment = FakeAppEnvironment()
    let music = FakeAppPlayerControl(.music)
    let spotify = FakeAppPlayerControl(.spotify)
    let module: MediaModule
    let harness: RegistryHarness
    /// Unix socket paths are limited to 104 bytes, so the folder is short and outside the sandboxed temp dir.
    let socketDirectory = ScratchFolders.shared.reserveShort()
    let storageBase: URL

    var socketPath: String { socketDirectory.appending(path: "youtube.sock").path }
    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }
    var store: NowPlayingStore { module.store }

    init() {
        module = MediaModule(
            source: source, spectrum: FakeSpectrumSource(), lyricsClient: client, tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }, youtubeSocketPath: socketDirectory.appending(path: "youtube.sock").path,
            appControls: [music, spotify], appEnvironment: environment.environment
        )
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
        allow(.music, .notDetermined)
        allow(.spotify, .notDetermined)
    }

    deinit {
        try? FileManager.default.removeItem(at: socketDirectory)
        try? FileManager.default.removeItem(at: storageBase)
    }

    func allow(_ player: KnownPlayer, _ status: PermissionStatus = .granted) {
        harness.permissions.statuses[.automation(bundleID: player.bundleID)] = status
    }

    func settle(until condition: () -> Bool = { false }) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    /// Music paused, and the system playing Spotify: two sources, the notch on Spotify.
    func musicPausedSpotifyPlaying() async {
        await harness.registry.bootstrap()
        environment.music("Paused", name: "Music song", artist: "Music artist")
        source.emit(AdapterLines.track("Spotify song", artist: "Spotify artist", bundle: Self.spotifyID))
    }

    var chipIDs: [MediaSourceID] { module.sources.model.chips.map(\.id) }

    // MARK: one source is what it always was

    @Test func withTheSystemsSessionAloneNothingChangesAndThereAreNoChips() async {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track("Song", artist: "Artist"))
        #expect(store.state.title == "Song")
        #expect(module.sources.book.primaryID == .app("com.example.Player"))
        #expect(!module.sources.model.showsChips)
        #expect(module.displayStore.state == .empty, "the player reads the store itself")
        #expect(module.sources.model.displayIsPrimary)
        #expect(harness.activities.current?.id == "media/nowPlaying")
        source.emit(AdapterLines.empty)
        harness.scheduler.advance(by: .milliseconds(300))
        #expect(store.state == .empty)
        #expect(harness.activities.current == nil)
    }

    // MARK: two sources

    @Test func theNotchFollowsThePrimaryAndTheChipsListBothSources() async {
        await musicPausedSpotifyPlaying()
        #expect(store.state.title == "Spotify song")
        #expect(module.sources.model.showsChips)
        #expect(chipIDs == [.app(Self.spotifyID), .app(Self.musicID)])
        #expect(module.sources.book.primaryID == .app(Self.spotifyID))
        #expect(module.displayStore.state == .empty)
    }

    @Test func choosingAChipShowsThatSourceInThePlayerAndLeavesTheNotchWhereItWas() async {
        await musicPausedSpotifyPlaying()
        module.sources.model.select(.app(Self.musicID))
        #expect(module.displayStore.state.title == "Music song")
        #expect(module.displayStore.state.artist == "Music artist")
        #expect(!module.sources.model.displayIsPrimary)
        #expect(store.state.title == "Spotify song", "the notch, the lock screen and the lyrics follow the primary source")
        #expect(harness.activities.current?.id == "media/nowPlaying")
        // The primary again: the player goes back to the store, and the other store lets go of the cover.
        module.sources.model.select(.app(Self.spotifyID))
        #expect(module.sources.model.displayIsPrimary)
        #expect(module.displayStore.state == .empty)
    }

    @Test func theTabsControlsActOnTheSourceItShowsAndEverythingElseOnThePrimary() async {
        await musicPausedSpotifyPlaying()
        allow(.music)
        environment.running = [Self.musicID, Self.spotifyID]
        module.sources.model.select(.app(Self.musicID))

        module.tabActions.send(.togglePlayPause)
        module.tabActions.seek(42)
        await settle { music.performed.count == 2 }
        #expect(music.performed == [.togglePlayPause, .seek(seconds: 42)])
        #expect(source.sent.isEmpty && source.seeks.isEmpty, "not MediaRemote: that is Spotify's")

        // The lock screen and the hotkeys are the notch's: the primary source, whatever the tab shows.
        module.lockScreenTransport.togglePlayPause()
        module.actions.send(.nextTrack)
        module.actions.seek(7)
        #expect(source.sent == [.togglePlayPause, .nextTrack])
        #expect(source.seeks == [7])
        #expect(harness.hotkeyBackend.trigger("media_mediaPlayPause"))
        #expect(source.sent == [.togglePlayPause, .nextTrack, .togglePlayPause])
        #expect(music.performed.count == 2)
    }

    @Test func theButtonsOfTheTabPressForTheSourceTheTabShows() async {
        await musicPausedSpotifyPlaying()
        allow(.music)
        environment.running = [Self.musicID]
        module.sources.model.select(.app(Self.musicID))
        module.tabActions.press(.next)
        await settle { !music.performed.isEmpty }
        #expect(music.performed == [.next])
        // Music's notification does not say where the player is, so there is nowhere to seek from: the button does nothing.
        module.tabActions.press(.rewind)
        await settle()
        #expect(music.performed == [.next])
        // Shuffle and repeat are the system's: a source it does not play has none.
        module.tabActions.press(.shuffle)
        module.tabActions.press(.repeatMode)
        #expect(source.shuffles.isEmpty && source.repeats.isEmpty)
        // The notch's own source: its buttons are the system's.
        module.actions.press(.next)
        #expect(source.sent == [.nextTrack])
    }

    @Test func aPressForASourceThatIsTheSystemsGoesToTheSystemWhateverTheTabShows() async {
        await musicPausedSpotifyPlaying()
        // The tab shows Spotify (the system's): its seek and play go through MediaRemote.
        module.tabActions.send(.togglePlayPause)
        module.tabActions.seek(12)
        #expect(source.sent == [.togglePlayPause])
        #expect(source.seeks == [12])
        #expect(music.performed.isEmpty)
    }

    @Test func aPlayerThatIsNotRunningOrNotAllowedIsNeverSentAnythingAndNobodyIsAskedAtTheStart() async {
        await musicPausedSpotifyPlaying()
        #expect(harness.permissions.requested.isEmpty)
        environment.running = [] // Music quit without telling: nothing is sent, nothing is asked
        module.sources.model.select(.app(Self.musicID))
        module.tabActions.send(.togglePlayPause)
        await settle()
        #expect(music.performed.isEmpty)
        #expect(harness.permissions.requested.isEmpty)
    }

    @Test func theFirstPressOnAnAppThatHasNotBeenAskedAsksAndThenDoesIt() async {
        await musicPausedSpotifyPlaying()
        environment.running = [Self.musicID]
        harness.permissions.requestResult = .granted
        module.sources.model.select(.app(Self.musicID))
        await settle { !harness.permissions.requested.isEmpty }
        #expect(harness.permissions.requested == [.automation(bundleID: Self.musicID)])
        module.tabActions.send(.nextTrack)
        await settle { music.performed == [.next] }
        #expect(music.performed == [.next])
        #expect(harness.permissions.requested.count == 1)
    }

    // MARK: the primary source: pinned, and going away

    @Test func pinningASourceMakesTheNotchFollowItWhateverElseStartsAndReleasingItGivesTheNotchBack() async {
        await musicPausedSpotifyPlaying()
        module.sources.model.togglePin(.app(Self.musicID))
        #expect(store.state.title == "Music song", "the closed notch, the lock screen and the hotkeys now follow Music")
        #expect(module.sources.model.primaryID == .app(Self.musicID))
        #expect(harness.activities.current?.id == "media/nowPlaying")
        // Something else starts playing: Music keeps the place.
        source.emit(AdapterLines.track("Another", artist: "X", bundle: "org.videolan.vlc"))
        #expect(store.state.title == "Music song")
        module.sources.model.togglePin(.app(Self.musicID))
        #expect(store.state.title == "Another", "the most recent to start playing")
    }

    @Test func thePinGoesWhenThatSourceGoesAwayAndTheNotchFollowsWhatPlays() async {
        await musicPausedSpotifyPlaying()
        module.sources.model.togglePin(.app(Self.musicID))
        environment.quit(Self.musicID)
        #expect(module.sources.book.pinnedID == .app(Self.musicID), "kept for a moment, as a blink would be")
        #expect(store.state.title == "Music song")
        harness.scheduler.advance(by: .seconds(MediaSourceBook.releaseGrace + 0.5))
        #expect(module.sources.book.pinnedID == nil)
        #expect(store.state.title == "Spotify song")
        environment.music("Paused", name: "Music song")
        #expect(module.sources.book.pinnedID == nil, "it does not come back pinned")
        #expect(store.state.title == "Spotify song")
    }

    @Test func pausingTheOnlySourceKeepsItAndPausingOneWhileAnotherPlaysHandsTheNotchOn() async {
        await harness.registry.bootstrap()
        environment.music("Playing", name: "Music song")
        source.emit(AdapterLines.track("Spotify song", artist: "S", bundle: Self.spotifyID))
        harness.scheduler.advance(by: .seconds(MediaSourceBook.defaultSwitchDelay + 0.5))
        #expect(store.state.title == "Spotify song")
        source.emit(AdapterLines.playing(false))
        #expect(store.state.title == "Music song", "Music plays, and the paused primary gives the place up")
        environment.music("Paused", name: "Music song")
        #expect(store.state.title == "Music song", "nothing plays now: the primary stays")
        #expect(!store.state.isPlaying)
    }

    @Test func theActivityPublishedForANotchFollowingANonSystemSourceIsTheSameActivity() async {
        await harness.registry.bootstrap()
        environment.music("Playing", name: "Only Music")
        #expect(harness.activities.current?.id == "media/nowPlaying")
        #expect(store.state.title == "Only Music")
        #expect(store.activityIsPlaying)
        environment.music("Paused", name: "Only Music")
        #expect(!store.activityIsPlaying)
        harness.scheduler.advance(by: .seconds(6))
        #expect(harness.activities.current == nil, "the pause grace, as for any source")
    }

    // MARK: lyrics follow the primary source

    @Test func lyricsAreLookedUpForThePrimarySourceNotForTheOneTheTabShows() async {
        harness.settings.set(true, for: keys.lyrics)
        client.reply(LrclibReplies.found())
        await harness.registry.bootstrap()
        environment.music("Paused", name: "Music song", artist: "Music artist", album: "Album")
        source.emit(AdapterLines.track("Spotify song", artist: "Spotify artist", bundle: Self.spotifyID))
        await settle { !client.requests.isEmpty }
        let before = client.requests.count
        module.sources.model.select(.app(Self.musicID))
        await settle()
        #expect(client.requests.count == before, "showing another source asks for nothing")
        #expect(module.displayStore.lyricRow == .reserved, "its row keeps its place, empty")
        #expect(store.lyricRow != .absent)
        let asked = client.requests.compactMap { $0.url?.absoluteString }.joined(separator: " ")
        #expect(asked.contains("Spotify"))
        #expect(!asked.contains("Music%20song"))
    }

    // MARK: Apple Events: nothing while hidden, and a refusal

    @Test func nothingRunsWhileTheTabIsHidden() async {
        allow(.music)
        allow(.spotify)
        environment.running = [Self.musicID, Self.spotifyID]
        await harness.registry.bootstrap()
        environment.music("Paused")
        environment.spotify("Paused")
        harness.scheduler.advance(by: .seconds(20))
        await settle()
        #expect(music.readCount == 0 && spotify.readCount == 0)
        #expect(harness.permissions.requested.isEmpty)
    }

    @Test func theTabBeingOnScreenIsWhatMakesTheAppsWorthReadingAndLeavingItStopsIt() async {
        allow(.music)
        environment.running = [Self.musicID]
        await harness.registry.bootstrap()
        environment.music("Paused")
        module.sources.model.setTabVisible(true)
        await settle { music.readCount == 1 }
        #expect(music.readCount == 1)
        module.sources.model.setTabVisible(false)
        harness.scheduler.advance(by: .seconds(10))
        await settle()
        #expect(music.readCount == 1)
    }

    @Test func aRefusedAppIsHiddenAndNamedAndTheSystemsSessionForItIsNot() async {
        allow(.music, .denied)
        environment.running = [Self.musicID]
        await harness.registry.bootstrap()
        environment.music("Paused", name: "Hidden")
        #expect(module.sources.book.entries.isEmpty)
        #expect(module.sources.model.deniedApps == ["Music"])
        #expect(MediaSettingsView.deniedAppsHint(for: ["Music"]) == "MyNotch chưa được phép điều khiển Music. Bật lại trong Quyền riêng tư & Bảo mật › Tự động hóa.")
        #expect(MediaSettingsView.deniedAppsHint(for: ["Music", "Spotify"]).contains("Music và Spotify"))
        // What else leaves the Mac for the sources is said too: Spotify's cover, from Spotify's own image service.
        #expect(MediaSettingsView.sourcesExplanation.contains("scdn.co") && MediaSettingsView.sourcesExplanation.contains("Apple Events"))
        source.emit(AdapterLines.track("Playing", artist: "A", bundle: Self.musicID))
        #expect(store.state.title == "Playing")
        #expect(module.sources.book.entries.map(\.isSystemBacked) == [true])
    }

    // MARK: the lock screen cannot ask

    @Test func theLockScreensButtonsNeverBringUpTheAutomationQuestionButTheNotchesDoAndAskedOnceTheLockScreenWorks() async {
        allow(.music, .notDetermined)
        environment.running = [Self.musicID]
        harness.permissions.requestResult = .granted
        await harness.registry.bootstrap()
        environment.music("Paused", name: "Music song")
        let transport = module.lockScreenTransport
        transport.togglePlayPause()
        transport.skipForward()
        transport.skipBack()
        await settle()
        #expect(harness.permissions.requested.isEmpty, "nobody is at the lock screen to answer")
        #expect(music.performed.isEmpty, "and what was pressed there did nothing")
        // Opening the Media tab is an interaction at the open notch: the question is put then.
        module.sources.model.setTabVisible(true)
        await settle { !harness.permissions.requested.isEmpty }
        #expect(harness.permissions.requested == [.automation(bundleID: Self.musicID)])
        await settle { harness.permissions.status(of: .automation(bundleID: Self.musicID)) == .granted }
        // Allowed now, the lock screen controls it.
        transport.togglePlayPause()
        await settle { !music.performed.isEmpty }
        #expect(music.performed == [.togglePlayPause])
        #expect(harness.permissions.requested.count == 1)
    }

    @Test func aPressOnTheOpenNotchIsWhatAsksTheFirstTime() async {
        allow(.music, .notDetermined)
        environment.running = [Self.musicID]
        harness.permissions.requestResult = .granted
        await harness.registry.bootstrap()
        environment.music("Paused", name: "Music song")
        module.send(.togglePlayPause)
        await settle { music.performed.count == 1 }
        #expect(harness.permissions.requested == [.automation(bundleID: Self.musicID)])
        #expect(music.performed == [.togglePlayPause])
    }

    // MARK: failing and stopping

    @Test func whenTheAdapterGivesUpTheOtherSourcesStayAndOnlyAnEmptyNotchSaysSo() async {
        await harness.registry.bootstrap()
        environment.music("Playing", name: "Music song")
        source.emit(AdapterLines.track("Spotify song", artist: "S", bundle: Self.spotifyID))
        source.fail("the adapter was blocked")
        #expect(store.failureMessage == nil)
        #expect(store.state.title == "Music song")
        #expect(module.sources.book.entries.map(\.id) == [.app(Self.musicID)])
    }

    @Test func whenTheAdapterGivesUpWithNothingElseTheNotchSaysSo() async {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        source.fail("the adapter was blocked")
        #expect(store.failureMessage == MediaModule.blockedMessage)
        #expect(store.state == .empty)
        environment.music("Playing", name: "Then Music")
        #expect(store.failureMessage == nil, "a source that works brings the player back")
        #expect(store.state.title == "Then Music")
    }

    @Test func stoppingTheModuleLetsGoOfEverySource() async {
        await musicPausedSpotifyPlaying()
        module.sources.model.select(.app(Self.musicID))
        #expect(environment.observerCount > 0)
        await harness.registry.shutdown()
        #expect(environment.observerCount == 0)
        #expect(module.sources.book.entries.isEmpty)
        #expect(module.displayStore.state == .empty)
        #expect(store.state == .empty)
    }

    @Test func theTabIsBuiltWithTheSourcesAndTheDisplayStoreAndKeepsItsDeclaredHeight() async throws {
        await harness.registry.bootstrap()
        let tab = try #require(harness.registry.tabs.first)
        #expect(tab.preferredHeight == 160)
    }
}
