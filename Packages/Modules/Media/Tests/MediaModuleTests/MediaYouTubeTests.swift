import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import MediaModule
@testable import YouTubeBridgeKit

@Suite final class MediaYouTubeTests {
    let source = FakeNowPlayingSource()
    let client = FakeHTTPClient()
    let module: MediaModule
    let harness: RegistryHarness
    /// Unix socket paths are limited to 104 bytes, so the folder is short and outside the sandboxed temp dir.
    let socketDirectory = URL(filePath: "/tmp/mn-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    let storageBase: URL
    let now = Date()

    var socketPath: String { socketDirectory.appending(path: "youtube.sock").path }
    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }
    var store: NowPlayingStore { module.store }

    init() {
        let path = socketDirectory.appending(path: "youtube.sock").path
        module = MediaModule(
            source: source, spectrum: FakeSpectrumSource(), lyricsClient: client, tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }, youtubeSocketPath: path
        )
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(at: socketDirectory)
        try? FileManager.default.removeItem(at: storageBase)
    }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func enableCaptions() { harness.settings.set(true, for: keys.youtubeCaptions) }
    func enableLyrics() { harness.settings.set(true, for: keys.lyrics) }

    /// The Chrome tab playing the sample video, as the system reports it.
    func playInChrome(title: String = YouTubeTestMessages.title, bundle: String = "com.google.Chrome", playing: Bool = true) {
        source.emit(AdapterLines.track(title, artist: "Channel", playing: playing, bundle: bundle))
    }

    func receive(_ messages: YouTubeMessage..., at date: Date? = nil) {
        for message in messages { module.receiveYouTube(message, at: date ?? Date()) }
    }

    /// Starts the module with the setting on, which is the state every test below needs.
    func bootstrapWithCaptions() async {
        enableCaptions()
        await harness.registry.bootstrap()
    }

    // MARK: setting

    @Test func theSettingIsOffByDefaultAndNothingListensWhileItIs() async {
        #expect(keys.youtubeCaptions.defaultValue == false)
        #expect(keys.youtubeCaptions.name == "module.media.youtubeCaptions")
        await harness.registry.bootstrap()
        #expect(!FileManager.default.fileExists(atPath: socketPath))
        #expect(YouTubeTestClient(path: socketPath) == nil)
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        #expect(store.syncedLyrics == nil)
    }

    @Test func theSocketIsOpenOnlyWhileTheSettingIsOn() async throws {
        await harness.registry.bootstrap()
        enableCaptions()
        await settle { FileManager.default.fileExists(atPath: socketPath) }
        #expect(FileManager.default.fileExists(atPath: socketPath))
        #expect(try FileManager.default.attributesOfItem(atPath: socketPath)[.posixPermissions] as? Int == 0o600)

        harness.settings.set(false, for: keys.youtubeCaptions)
        await settle { !FileManager.default.fileExists(atPath: socketPath) }
        #expect(!FileManager.default.fileExists(atPath: socketPath))

        enableCaptions()
        await settle { FileManager.default.fileExists(atPath: socketPath) }
        #expect(FileManager.default.fileExists(atPath: socketPath))
    }

    @Test func stoppingTheModuleClosesAndUnlinksTheSocket() async {
        await bootstrapWithCaptions()
        #expect(FileManager.default.fileExists(atPath: socketPath))
        await harness.registry.setEnabled(false, for: "media")
        #expect(!FileManager.default.fileExists(atPath: socketPath))
        #expect(YouTubeTestClient(path: socketPath) == nil)
    }

    @Test func aSocketThatCannotBeOpenedIsReportedUntilTheSettingIsToggled() async throws {
        // A file where the folder should be.
        try Data().write(to: socketDirectory)
        await bootstrapWithCaptions()
        #expect(module.youtubeBridge.listenFailed)
        try FileManager.default.removeItem(at: socketDirectory)
        harness.settings.set(false, for: keys.youtubeCaptions)
        await settle { !module.youtubeBridge.listenFailed }
        #expect(!module.youtubeBridge.listenFailed)
        enableCaptions()
        await settle { FileManager.default.fileExists(atPath: socketPath) }
        #expect(FileManager.default.fileExists(atPath: socketPath))
        #expect(!module.youtubeBridge.listenFailed)
    }

    // MARK: showing captions

    @Test func captionsOfTheVideoInChromeBecomeTheLyrics() async {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
        #expect(client.requests.isEmpty, "lyrics from the web are off, and nothing goes to it")
    }

    @Test func theOrderOfTheMessagesAndTheTrackDoesNotMatter() async {
        await bootstrapWithCaptions()
        receive(YouTubeTestMessages.playback(), YouTubeTestMessages.captions())
        #expect(store.syncedLyrics == nil)
        playInChrome()
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
    }

    @Test func captionsArrivingForTheTrackAlreadyPlayingUpdateTheRowAtOnce() async {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.playback())
        #expect(store.syncedLyrics == nil)
        receive(YouTubeTestMessages.captions())
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
        // A second track of captions for the same video (another language) replaces the first.
        let other = [CaptionEvent(time: 1, duration: 1, text: "delta")]
        receive(YouTubeTestMessages.captions(YouTubeTestMessages.videoID, other))
        #expect(store.syncedLyrics == [LyricLine(time: 1, text: "delta"), LyricLine(time: 2, text: "")])
    }

    @Test func theLyricRowFollowsThePlaybackClockThroughTheCaptions() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        let anchor = try #require(store.state.elapsedAnchor).timestamp
        #expect(store.lyric(at: anchor - 40) == nil)
        // The fake track is at 30 s, past the captions' end: the row is blank, not stuck on the last line.
        #expect(store.lyric(at: anchor)?.text == "")
    }

    // MARK: not matching

    @Test func aPlayerThatIsNoBrowserNeverShowsThem() async {
        await bootstrapWithCaptions()
        playInChrome(bundle: "com.spotify.client")
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        #expect(store.syncedLyrics == nil)
    }

    @Test func aPausedOrStalePlaybackDoesNotStartThem() async {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback(playing: false))
        #expect(store.syncedLyrics == nil)
        receive(YouTubeTestMessages.playback(playing: true), at: Date().addingTimeInterval(-30))
        #expect(store.syncedLyrics == nil)
        receive(YouTubeTestMessages.playback(playing: true))
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
    }

    @Test func anotherTitleOrAnotherVideoDoesNotMatch() async {
        await bootstrapWithCaptions()
        playInChrome(title: "A different video")
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        #expect(store.syncedLyrics == nil)
        // The page plays another video whose captions never came.
        playInChrome()
        receive(YouTubeTestMessages.playback("zzzzzzzzzzz"))
        #expect(store.syncedLyrics == nil)
    }

    @Test func theTitleIsComparedNormalised() async {
        await bootstrapWithCaptions()
        playInChrome(title: "  SAMPLE   video ")
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
    }

    // MARK: dropping captions

    @Test func pausingKeepsTheCaptions() async {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        receive(YouTubeTestMessages.playback(playing: false))
        source.emit(AdapterLines.playing(false))
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
    }

    @Test func clearDropsThem() async {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        receive(YouTubeTestMessages.clear())
        #expect(store.syncedLyrics == nil)
        // They stay gone until captions arrive again.
        receive(YouTubeTestMessages.playback())
        #expect(store.syncedLyrics == nil)
        receive(YouTubeTestMessages.captions())
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
    }

    @Test func aChangeOfVideoDropsThem() async {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        // The page moves on: a playback of another video, and then the system's track follows.
        receive(YouTubeTestMessages.playback("bbbbbbbbbbb", title: "Next video"))
        #expect(store.syncedLyrics == nil)
        playInChrome(title: "Next video")
        #expect(store.syncedLyrics == nil)
    }

    @Test func aChangeOfTrackDropsThem() async {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        playInChrome(title: "Another video")
        #expect(store.syncedLyrics == nil)
        // Back to the video: matched again, as the page still says it plays it.
        playInChrome()
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
    }

    @Test func turningTheSettingOffDropsThemAndForgetsThem() async {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        harness.settings.set(false, for: keys.youtubeCaptions)
        await settle { store.syncedLyrics == nil }
        #expect(store.syncedLyrics == nil)
        #expect(module.youtubeBridge.lastMessageAt == nil)
        // Back on: nothing is remembered, so nothing shows until Chrome sends again.
        enableCaptions()
        await settle { FileManager.default.fileExists(atPath: socketPath) }
        playInChrome(title: YouTubeTestMessages.title)
        #expect(store.syncedLyrics == nil)
    }

    @Test func stoppingTheModuleDropsThem() async {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        await harness.registry.setEnabled(false, for: "media")
        #expect(store.syncedLyrics == nil)
    }

    @Test func messagesThatArriveWhileTheSettingIsOffAreIgnored() async {
        await harness.registry.bootstrap()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        #expect(store.syncedLyrics == nil)
        enableCaptions()
        await settle { FileManager.default.fileExists(atPath: socketPath) }
        #expect(store.syncedLyrics == nil)
    }

    // MARK: priority over lrclib and Apple

    @Test func captionsWinOverLyricsAlreadyFetchedFromTheWeb() async {
        enableLyrics()
        client.reply(LrclibReplies.found())
        await bootstrapWithCaptions()
        playInChrome()
        await settle { store.syncedLyrics != nil }
        #expect(store.syncedLyrics == LrclibReplies.syncedLines)

        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
        // Later position updates leave them alone.
        source.emit(AdapterLines.position(31))
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
    }

    @Test func captionsThatAreThereBeforeTheTrackStartsMeanNoRequestAtAll() async {
        enableLyrics()
        client.reply(LrclibReplies.found())
        await bootstrapWithCaptions()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        playInChrome()
        await settle { !client.requests.isEmpty }
        #expect(client.requests.isEmpty)
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
    }

    @Test func anAnswerThatArrivesAfterTheCaptionsDoesNotReplaceThem() async {
        enableLyrics()
        let gate = Gate()
        client.handler = { [gate] _ in
            await gate.wait()
            return LrclibReplies.found()
        }
        await bootstrapWithCaptions()
        playInChrome()
        await settle { gate.isWaiting }
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        gate.open()
        await settle { false }
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
    }

    @Test func whenTheCaptionsGoTheWebLyricsComeBack() async {
        enableLyrics()
        client.reply(LrclibReplies.found())
        await bootstrapWithCaptions()
        playInChrome()
        await settle { store.syncedLyrics != nil }
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        receive(YouTubeTestMessages.clear())
        // Answered from the disk cache, so no new request, and the service's spacing is no obstacle.
        await settle { store.syncedLyrics == LrclibReplies.syncedLines }
        #expect(store.syncedLyrics == LrclibReplies.syncedLines)
        #expect(client.requests.count == 1)
    }

    @Test func withoutCaptionsTheWebLyricsAreAsBefore() async {
        enableLyrics()
        client.reply(LrclibReplies.found())
        await bootstrapWithCaptions()
        playInChrome()
        await settle { store.syncedLyrics != nil }
        #expect(store.syncedLyrics == LrclibReplies.syncedLines)
        #expect(client.requests.count == 1)
    }

    // MARK: memory only

    @Test func captionsAreNeverWrittenToDisk() async {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
        await harness.registry.setEnabled(false, for: "media")
        let files = (FileManager.default.enumerator(at: storageBase, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        #expect(files.isEmpty, "\(files)")
    }

    // MARK: status

    @Test func everyMessageUpdatesWhenTheExtensionWasLastHeard() async {
        await bootstrapWithCaptions()
        #expect(module.youtubeBridge.lastMessageAt == nil)
        let arrival = Date(timeIntervalSince1970: 1_800_000_000)
        receive(YouTubeTestMessages.playback(), at: arrival)
        #expect(module.youtubeBridge.lastMessageAt == arrival)
        #expect(module.youtubeBridge.status(at: arrival + 10) == .connected)
        #expect(module.youtubeBridge.status(at: arrival + 40) == .notInstalled)
    }

    // MARK: through the socket

    @Test func framesFromTheHostThroughTheRealSocketShowAsLyrics() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try #require(YouTubeTestClient(path: socketPath))
        host.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.captions()))
        host.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.playback()))
        await waitUntil { store.syncedLyrics != nil }
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
        #expect(module.youtubeBridge.status(at: Date()) == .connected)

        host.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear()))
        await waitUntil { store.syncedLyrics == nil }
        #expect(store.syncedLyrics == nil)
    }

    @Test func theSettingsRowsAreBuiltForTheModule() throws {
        let environment = try #require(harness.settingsEnvironment(for: "media"))
        let view = try #require(module.makeSettingsView(environment))
        #expect(String(describing: view).hasPrefix("AnyView(MediaSettingsView("))
    }
}
