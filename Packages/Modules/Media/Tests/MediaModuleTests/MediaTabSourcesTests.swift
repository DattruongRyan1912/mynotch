import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import MediaModule
@testable import YouTubeBridgeKit

/// Pages of Chrome as sources, through the extension's socket: they are listed, chosen, controlled and forgotten.
@Suite final class MediaTabSourcesTests {
    let source = FakeNowPlayingSource()
    let environment = FakeAppEnvironment()
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
            source: source, spectrum: FakeSpectrumSource(), lyricsClient: FakeHTTPClient(), tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }, youtubeSocketPath: socketDirectory.appending(path: "youtube.sock").path,
            appEnvironment: environment.environment
        )
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(at: socketDirectory)
        try? FileManager.default.removeItem(at: storageBase)
    }

    func settle(until condition: () -> Bool = { false }) async {
        for _ in 0..<400 where !condition() { await Task.yield() }
    }

    /// The module running with the bridge's setting on, which is what listens for the extension.
    func bootstrap() async {
        harness.settings.set(true, for: keys.youtubeCaptions)
        await harness.registry.bootstrap()
    }

    func connect() async throws -> YouTubeTestClient {
        await settle { FileManager.default.fileExists(atPath: socketPath) }
        return try #require(YouTubeTestClient(path: socketPath))
    }

    func send(_ message: YouTubeMessage, from client: YouTubeTestClient, until condition: () -> Bool) async {
        client.sendFrame(YouTubeTestMessages.json(message))
        await settle(until: condition)
    }

    var chipIDs: [MediaSourceID] { module.sources.model.chips.map(\.id) }
    var tabEntries: [MediaSourceEntry] { module.sources.book.entries.filter { $0.tab != nil } }

    @Test func aPageThatReportsIsASourceWhichTheTabCanShowAndControlThroughTheExtension() async throws {
        await bootstrap()
        let client = try await connect()
        source.emit(AdapterLines.track("System song", artist: "System artist", bundle: "com.spotify.client"))
        await send(YouTubeTestMessages.tab(7, title: "Page song", artist: "Page artist", playing: false), from: client) { !tabEntries.isEmpty }
        let ref = try #require(tabEntries.first?.tab)
        #expect(module.sources.model.showsChips)
        #expect(store.state.title == "System song", "a page that is paused does not take the notch from what plays")

        module.sources.model.select(.tab(ref))
        #expect(module.displayStore.state.title == "Page song")
        #expect(module.displayStore.state.artist == "Page artist")

        module.tabActions.send(.togglePlayPause)
        module.tabActions.send(.nextTrack)
        module.tabActions.send(.previousTrack)
        module.tabActions.send(.play)
        module.tabActions.send(.pause)
        module.tabActions.seek(61.5)
        let frames = client.receiveFrames(count: 6)
        #expect(frames == [
            TabCommand(tab: 7, action: .toggle).json, TabCommand(tab: 7, action: .next).json, TabCommand(tab: 7, action: .previous).json,
            TabCommand(tab: 7, action: .play).json, TabCommand(tab: 7, action: .pause).json, TabCommand(tab: 7, action: .seek(seconds: 61.5)).json,
        ])
        #expect(source.sent.isEmpty && source.seeks.isEmpty, "nothing of it went to MediaRemote")

        // What the notch follows is not the tab: its commands do not go there.
        module.actions.send(.togglePlayPause)
        #expect(source.sent == [.togglePlayPause])
        #expect(!client.hasUnreadData)
    }

    @Test func aLikeIsNoCommandForATabAndNothingIsSent() async throws {
        await bootstrap()
        let client = try await connect()
        source.emit(AdapterLines.track("System song", artist: "A", bundle: "com.spotify.client"))
        await send(YouTubeTestMessages.tab(7, playing: false), from: client) { !tabEntries.isEmpty }
        module.sources.model.select(.tab(try #require(tabEntries.first?.tab)))
        module.tabActions.send(.likeTrack)
        #expect(!client.hasUnreadData)
    }

    @Test func aPageThatTheSystemPlaysIsOneSourceControlledThroughTheSystem() async throws {
        await bootstrap()
        let client = try await connect()
        await send(YouTubeTestMessages.tab(7, title: "Same title", artist: "Channel"), from: client) { !tabEntries.isEmpty }
        // The system reports what Chrome plays: the page's own title.
        source.emit(AdapterLines.track("Same title", artist: "Channel", bundle: "com.google.Chrome.helper", parent: "com.google.Chrome"))
        #expect(module.sources.book.entries.count == 1)
        let entry = try #require(module.sources.book.entries.first)
        #expect(entry.tab != nil && entry.isSystemBacked)
        #expect(store.state.bundleIdentifier == "com.google.Chrome.helper")
        module.actions.send(.togglePlayPause)
        #expect(source.sent == [.togglePlayPause], "through the system, as it always was")
        #expect(!client.hasUnreadData)
        // Next without the extension's YouTube session goes to the system too, as before.
        module.actions.send(.nextTrack)
        #expect(source.sent == [.togglePlayPause, .nextTrack])
    }

    @Test func twoChromesWithTheSameTabNumberGetTheirOwnCommands() async throws {
        await bootstrap()
        let first = try await connect()
        let second = try #require(YouTubeTestClient(path: socketPath))
        await send(YouTubeTestMessages.tab(1, title: "In the first"), from: first) { tabEntries.count == 1 }
        await send(YouTubeTestMessages.tab(1, title: "In the second"), from: second) { tabEntries.count == 2 }
        #expect(chipIDs.count == 2)
        let inSecond = try #require(tabEntries.first { $0.state.title == "In the second" }?.tab)
        module.sources.model.select(.tab(inSecond))
        module.tabActions.send(.nextTrack)
        #expect(second.receiveFrames(count: 1) == [TabCommand(tab: 1, action: .next).json])
        #expect(!first.hasUnreadData)
    }

    @Test func aCommandForATabWhoseChromeIsGoneIsDroppedAndNobodyHangs() async throws {
        await bootstrap()
        var client: YouTubeTestClient? = try await connect()
        await send(YouTubeTestMessages.tab(1), from: try #require(client), until: { !tabEntries.isEmpty })
        let ref = try #require(tabEntries.first?.tab)
        module.sources.model.togglePin(.tab(ref))
        client = nil
        // The end of the connection is told: the pinned page is missing now, and the book waits out the grace.
        await settle { module.sources.book.nextExpiry.map { $0 < Date().addingTimeInterval(10) } == true }
        // The pinned page is kept for a moment (it could be a blink), then it is gone with its Chrome.
        harness.scheduler.advance(by: .seconds(MediaSourceBook.releaseGrace + 0.5))
        await settle { tabEntries.isEmpty }
        #expect(tabEntries.isEmpty, "the connection ended: its pages are gone")
        #expect(module.sources.book.pinnedID == nil)
        module.tabActions.send(.nextTrack)
        module.actions.send(.nextTrack)
    }

    @Test func aPageThatSaysItHasNoMediaIsGoneAndAPausedOneStaysAsAPausedSource() async throws {
        await bootstrap()
        let client = try await connect()
        await send(YouTubeTestMessages.tab(3, title: "Page", playing: true), from: client) { !tabEntries.isEmpty }
        // The hub waits a moment between two reports of one page (it uses the newest), and the timer is the test's to run.
        await send(YouTubeTestMessages.tab(3, title: "Page", playing: false), from: client) {
            harness.scheduler.advance(by: .milliseconds(250))
            return tabEntries.first?.isPlaying == false
        }
        #expect(tabEntries.count == 1 && tabEntries[0].isPlaying == false)
        #expect(store.state.title == "Page", "the only source: the notch keeps it, paused")
        await send(.tabGone(tab: 3), from: client) { tabEntries.isEmpty }
        #expect(tabEntries.isEmpty)
        #expect(store.state == .empty)
    }

    @Test func aPageThatPlaysWhileNothingElseDoesIsWhatTheNotchFollowsAndItsControlsAreTheExtensions() async throws {
        await bootstrap()
        let client = try await connect()
        await send(YouTubeTestMessages.tab(5, title: "Lonely page", artist: "Site"), from: client) { !tabEntries.isEmpty }
        #expect(store.state.title == "Lonely page")
        #expect(harness.activities.current?.id == "media/nowPlaying")
        module.actions.send(.togglePlayPause)
        #expect(client.receiveFrames(count: 1) == [TabCommand(tab: 5, action: .toggle).json])
        #expect(source.sent.isEmpty)
        module.lockScreenTransport.skipForward()
        #expect(client.receiveFrames(count: 1) == [TabCommand(tab: 5, action: .next).json])
    }

    @Test func tabsAreForgottenWhenTheBridgeIsSwitchedOffAndNothingIsHeardWhileItIs() async throws {
        await bootstrap()
        let client = try await connect()
        await send(YouTubeTestMessages.tab(1), from: client) { !tabEntries.isEmpty }
        harness.settings.set(false, for: keys.youtubeCaptions)
        await settle { tabEntries.isEmpty }
        #expect(tabEntries.isEmpty)
        module.receiveYouTube(YouTubeTestMessages.tab(2))
        #expect(tabEntries.isEmpty, "ignored while the setting is off, like every message")
    }

    @Test func aPageSendingIsTheExtensionBeingThereButNoCaptionsOrLyrics() async throws {
        await bootstrap()
        let client = try await connect()
        await send(YouTubeTestMessages.tab(1), from: client) { !tabEntries.isEmpty }
        #expect(module.youtubeBridge.lastPageMessageAt != nil)
        #expect(store.syncedLyrics == nil)
        #expect(module.skipRoute() == .mediaRemote, "a page with media is not a YouTube session")
    }

    @Test func aPageWithMediaStandsForNothingToTheSkipRouteOfAYouTubeVideo() async throws {
        await bootstrap()
        let client = try await connect()
        source.emit(AdapterLines.track(YouTubeTestMessages.title, artist: "Channel", bundle: "com.google.Chrome.helper", parent: "com.google.Chrome"))
        await send(YouTubeTestMessages.playback(), from: client) { module.skipRoute() == .bridge }
        #expect(module.skipRoute() == .bridge)
        // A page with media comes: the skip of the video that the system plays is as before.
        await send(YouTubeTestMessages.tab(9, title: "Other page", playing: false), from: client) { tabEntries.count == 1 }
        #expect(module.skipRoute() == .bridge)
    }
}
