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
    let recorder = LogRecorder()

    var socketPath: String { socketDirectory.appending(path: "youtube.sock").path }
    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }
    var store: NowPlayingStore { module.store }

    init() {
        let path = socketDirectory.appending(path: "youtube.sock").path
        module = MediaModule(
            source: source, spectrum: FakeSpectrumSource(), lyricsClient: client, tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }, youtubeSocketPath: path,
            youtubeLog: recorder.log
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

    @Test func theLyricRowIsReservedWhileCaptionsAreOnEvenWithLyricsOff() async {
        await harness.registry.bootstrap()
        #expect(store.lyricRow == .absent)
        enableCaptions()
        await settle { store.lyricsAreOn }
        #expect(store.lyricRow == .reserved)
        harness.settings.set(false, for: keys.youtubeCaptions)
        await settle { !store.lyricsAreOn }
        #expect(store.lyricRow == .absent)
    }

    // MARK: showing captions

    @Test func captionsOfTheVideoInChromeBecomeTheLyrics() async {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
        #expect(client.requests.isEmpty, "lyrics from the web are off, and nothing goes to it")
    }

    @Test func captionsGiveTheStripUnderTheNotchToo() async {
        harness.settings.set(true, for: keys.lyricsUnderNotch)
        await bootstrapWithCaptions()
        playInChrome()
        #expect(harness.activities.current?.activity.hasBottom == false)
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
        #expect(harness.activities.current?.activity.hasBottom == true)
    }

    @Test func aChangeOfVideoKeepsTheStripWhileTheNextCaptionsAreAwaited() async throws {
        harness.settings.set(true, for: keys.lyricsUnderNotch)
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        #expect(harness.activities.current?.activity.hasBottom == true)

        source.emit(AdapterLines.empty)
        playInChrome(title: "Next video")
        #expect(store.syncedLyrics == nil)
        #expect(harness.activities.current?.activity.hasBottom == true, "held while the extension has not sent the next captions")
        let held = try #require(harness.activities.current)

        receive(YouTubeTestMessages.playback("bbbbbbbbbbb", title: "Next video"), YouTubeTestMessages.captions("bbbbbbbbbbb"))
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
        #expect(harness.activities.current == held, "the captions arrive into the same strip")
        harness.scheduler.advance(by: .seconds(10))
        #expect(harness.activities.current == held)
    }

    @Test func captionsThatNeverComeLetTheStripGoOnceAfterThreeSeconds() async throws {
        harness.settings.set(true, for: keys.lyricsUnderNotch)
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())

        source.emit(AdapterLines.empty)
        playInChrome(title: "Next video")
        harness.scheduler.advance(by: .milliseconds(2900))
        #expect(harness.activities.current?.activity.hasBottom == true)
        harness.scheduler.advance(by: .milliseconds(200))
        #expect(harness.activities.current?.activity.id == "nowPlaying")
        #expect(harness.activities.current?.activity.hasBottom == false)
        let hidden = try #require(harness.activities.current)
        harness.scheduler.advance(by: .seconds(10))
        #expect(harness.activities.current == hidden)
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
        #expect(module.youtubeBridge.lastPageMessageAt == nil)
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

    @Test func everyMessageFromThePageUpdatesWhenTheExtensionWasLastHeard() async {
        await bootstrapWithCaptions()
        #expect(module.youtubeBridge.lastPageMessageAt == nil)
        let arrival = Date(timeIntervalSince1970: 1_800_000_000)
        receive(YouTubeTestMessages.playback(), at: arrival)
        #expect(module.youtubeBridge.lastPageMessageAt == arrival)
        #expect(module.youtubeBridge.status(at: arrival + 10) == .connected)
        #expect(module.youtubeBridge.status(at: arrival + 40) == .notInstalled)
        for (index, message) in [
            YouTubeTestMessages.captions(), YouTubeTestMessages.clear(),
            YouTubeTestMessages.diag("content-start", from: .content), YouTubeTestMessages.diag("page-seen fetch", from: .page),
        ].enumerated() {
            let later = arrival + Double(index + 1)
            receive(message, at: later)
            #expect(module.youtubeBridge.lastPageMessageAt == later)
        }
    }

    @Test func theServiceWorkersDiagnosticsAloneDoNotMakeTheStatusConnected() async {
        await bootstrapWithCaptions()
        let arrival = Date(timeIntervalSince1970: 1_800_000_000)
        receive(
            YouTubeTestMessages.diag("sw-start v=0.1.2"), YouTubeTestMessages.diag("sw-access youtube=withheld"),
            YouTubeTestMessages.diag("sw-inject tabs=0 injected=0 failed=0"), at: arrival
        )
        #expect(module.youtubeBridge.lastPageMessageAt == nil)
        #expect(module.youtubeBridge.status(at: arrival + 1) != .connected)
        #expect(module.youtubeBridge.accessWithheld, "the notice shows next to a status that is not green")
        // The first thing the page sends turns it green.
        receive(YouTubeTestMessages.diag("content-start", from: .content), at: arrival + 2)
        #expect(module.youtubeBridge.status(at: arrival + 3) == .connected)
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

    // MARK: the log

    /// The matching decisions logged so far, in order.
    var decisions: [String] { recorder.lines.filter { $0.hasPrefix("match ") } }

    @Test func aMatchingDecisionIsLoggedWhenItChangesWithTheRuleThatFailed() async {
        await bootstrapWithCaptions()
        playInChrome(bundle: "com.spotify.client")
        #expect(decisions == ["match not-matched reason=not-browser"])
        playInChrome()
        #expect(decisions.last == "match not-matched reason=no-playback")
        receive(YouTubeTestMessages.playback(title: "A different video"))
        #expect(decisions.last == "match not-matched reason=title-mismatch")
        receive(YouTubeTestMessages.playback(playing: false))
        #expect(decisions.last == "match not-matched reason=no-captions")
        receive(YouTubeTestMessages.captions())
        #expect(decisions.last == "match not-matched reason=paused")
        receive(YouTubeTestMessages.playback(playing: true), at: Date().addingTimeInterval(-30))
        #expect(decisions.last == "match not-matched reason=stale-playback")
        receive(YouTubeTestMessages.playback(playing: true))
        #expect(decisions.last == "match matched")
        let count = decisions.count
        // Updates that change nothing say nothing: a position, a pause that keeps the captions, the same playback again.
        source.emit(AdapterLines.position(31))
        receive(YouTubeTestMessages.playback(playing: false))
        receive(YouTubeTestMessages.playback(playing: true))
        #expect(decisions.count == count)
        #expect(decisions == [
            "match not-matched reason=not-browser", "match not-matched reason=no-playback", "match not-matched reason=title-mismatch",
            "match not-matched reason=no-captions", "match not-matched reason=paused", "match not-matched reason=stale-playback", "match matched",
        ])
        receive(YouTubeTestMessages.clear())
        #expect(decisions.last == "match not-matched reason=no-captions")
    }

    @Test func nothingIsDecidedOrLoggedWhileTheSettingIsOff() async {
        await harness.registry.bootstrap()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        #expect(decisions.isEmpty)
        #expect(recorder.lines.isEmpty)
    }

    @Test func turningTheSettingOffAndOnLogsTheDecisionAgain() async {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        #expect(decisions.last == "match matched")
        harness.settings.set(false, for: keys.youtubeCaptions)
        await settle { !FileManager.default.fileExists(atPath: socketPath) }
        enableCaptions()
        await settle { FileManager.default.fileExists(atPath: socketPath) }
        playInChrome()
        #expect(decisions.last == "match not-matched reason=no-playback")
        #expect(decisions.filter { $0 == "match matched" }.count == 1)
    }

    @Test func theReceiverReportsItselfThroughTheSameLog() async {
        await bootstrapWithCaptions()
        #expect(recorder.lines.contains("app listening"))
        harness.settings.set(false, for: keys.youtubeCaptions)
        await settle { recorder.lines.contains("app stopped") }
        #expect(recorder.lines.contains("app stopped"))
    }

    @Test func theDriftBetweenTheVideosClockAndTheNotchsIsLoggedAtMostEveryTenSeconds() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        func drifts() -> [String] { recorder.lines.filter { $0.hasPrefix("playback drift=") } }
        #expect(drifts().count == 1, "the playback that started the match")

        /// A playback for the shown video at `date`, whose time is `offset` seconds from where the notch's clock is then.
        func playback(at date: Date, offset: Double) throws {
            let position = try #require(store.position(at: date))
            receive(YouTubeTestMessages.playback(time: position + offset), at: date)
        }
        let first = Date().addingTimeInterval(11)
        try playback(at: first, offset: 0.42)
        #expect(drifts().last == "playback drift=+0.42s")
        #expect(drifts().count == 2)

        try playback(at: first.addingTimeInterval(1), offset: 9)
        try playback(at: first.addingTimeInterval(9.9), offset: 9)
        #expect(drifts().count == 2, "one line per ten seconds")

        try playback(at: first.addingTimeInterval(10), offset: -0.3)
        #expect(drifts().last == "playback drift=-0.30s")
        try playback(at: first.addingTimeInterval(20), offset: 0)
        #expect(drifts().last == "playback drift=+0.00s")
        #expect(drifts().count == 4)
    }

    @Test func noDriftIsLoggedForAVideoWhoseCaptionsAreNotShown() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        receive(YouTubeTestMessages.playback())
        receive(YouTubeTestMessages.playback(time: 99))
        #expect(recorder.lines.filter { $0.contains("drift=") }.isEmpty)
        // Another video than the one whose captions are shown.
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        let shown = recorder.lines.filter { $0.contains("drift=") }.count
        receive(YouTubeTestMessages.playback("bbbbbbbbbbb", title: "Other video", time: 5), at: Date().addingTimeInterval(30))
        #expect(recorder.lines.filter { $0.contains("drift=") }.count == shown)
    }

    @Test func aDiagnosticDecidesNothingAboutTheLyrics() async {
        await bootstrapWithCaptions()
        playInChrome()
        let decided = decisions
        receive(YouTubeTestMessages.diag("sw-start v=0.1.1"))
        receive(YouTubeTestMessages.diag("content-start", from: .content))
        #expect(store.syncedLyrics == nil)
        #expect(decisions == decided, "a diagnostic is no reason to decide again")
        // And it changes nothing about captions that are shown.
        receive(YouTubeTestMessages.captions(), YouTubeTestMessages.playback())
        receive(YouTubeTestMessages.diag("content-cc off", from: .content))
        #expect(store.syncedLyrics == YouTubeTestMessages.lines)
    }

    // MARK: next and previous

    /// A host as Chrome's helper is, connected to the socket and having sent the page's playback; waits until the module has it.
    func connectHost(title: String = YouTubeTestMessages.title) async throws -> YouTubeTestClient {
        let host = try #require(YouTubeTestClient(path: socketPath))
        host.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.playback(title: title)))
        await waitUntil { module.youtubeBridge.lastPageMessageAt != nil }
        return host
    }

    func pressHotkey(_ id: String) throws {
        let registration = try #require(harness.hotkeys.registrations.first { $0.id == id })
        #expect(harness.hotkeyBackend.trigger(registration.name.rawValue))
    }

    /// What the extension says once it has done a command.
    func answer(_ action: String, _ outcome: String = "ok") {
        receive(YouTubeTestMessages.diag("content-command \(action) \(outcome)", from: .content))
    }

    var fallbacks: [String] { recorder.lines.filter { $0.hasPrefix("skip fallback") } }

    @Test func nextAndPreviousGoToTheExtensionWhenChromePlaysAVideoItReports() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        module.send(.nextTrack)
        module.send(.previousTrack)
        #expect(host.receiveFrames(count: 2) == [YouTubeCommand.next.json, YouTubeCommand.previous.json])
        #expect(source.sent.isEmpty, "MediaRemote is not asked while the extension may still answer")
        #expect(module.skipRoute() == .bridge)
    }

    @Test func theTabButtonsAndTheHotkeysTakeTheSameRoute() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        module.actions.press(.next)
        module.actions.press(.previous)
        try pressHotkey("media_mediaNext")
        try pressHotkey("media_mediaPrevious")
        #expect(host.receiveFrames(count: 4) == [YouTubeCommand.next, .previous, .next, .previous].map(\.json))
        #expect(source.sent.isEmpty)
    }

    @Test func everythingButNextAndPreviousStillGoesToMediaRemote() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        for command in [MediaCommand.togglePlayPause, .play, .pause] { module.send(command) }
        module.seek(toSeconds: 30)
        #expect(source.sent == [.togglePlayPause, .play, .pause])
        #expect(source.seeks == [30])
        #expect(!host.hasData(within: 0.2))
    }

    @Test func aPlayerThatIsNoBrowserKeepsMediaRemoteWhateverTheExtensionHasSaid() async throws {
        await bootstrapWithCaptions()
        playInChrome(bundle: "com.spotify.client")
        let host = try await connectHost()
        module.send(.nextTrack)
        module.send(.previousTrack)
        #expect(source.sent == [.nextTrack, .previousTrack])
        #expect(!host.hasData(within: 0.2))
        #expect(module.skipRoute() == .mediaRemote)
        #expect(fallbacks.isEmpty, "that is the usual route, not a fallback")
    }

    @Test func chromeWithoutALiveSessionSendsMediaRemoteFromTheButtonsAndTheHotkeysAlike() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        #expect(module.skipRoute() == .mediaRemote)
        module.actions.press(.next)
        module.actions.press(.previous)
        try pressHotkey("media_mediaNext")
        try pressHotkey("media_mediaPrevious")
        #expect(source.sent == [.nextTrack, .previousTrack, .nextTrack, .previousTrack])
        #expect(fallbacks.isEmpty)
        harness.scheduler.advance(by: .seconds(5))
        #expect(source.sent.count == 4, "nothing waits for an answer that was never asked for")
    }

    @Test func chromeWithTheSettingOffAndAnotherBrowserKeepMediaRemote() async throws {
        await harness.registry.bootstrap()
        playInChrome()
        module.send(.nextTrack)
        #expect(source.sent == [.nextTrack])
        // Another browser with the setting on, whatever the extension said about Chrome's video.
        enableCaptions()
        await settle { FileManager.default.fileExists(atPath: socketPath) }
        playInChrome(bundle: "com.apple.Safari")
        module.send(.previousTrack)
        #expect(source.sent == [.nextTrack, .previousTrack])
    }

    @Test func anotherTitleThanTheExtensionsPlaybackMeansNoLiveSession() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        _ = try await connectHost(title: "Another video")
        module.send(.nextTrack)
        #expect(source.sent == [.nextTrack], "not the extension's video, so not its tab")
    }

    @Test func aSessionThePageHasNotSpokenForInAWhileIsNoLongerLive() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        _ = try await connectHost()
        #expect(module.skipRoute(at: Date().addingTimeInterval(SkipRoute.liveWindow - 5)) == .bridge)
        #expect(module.skipRoute(at: Date().addingTimeInterval(SkipRoute.liveWindow + 5)) == .mediaRemote)
    }

    // MARK: a quick second press

    /// A press the extension took and answered, which is what makes the title of what plays change a moment later.
    func skipThroughTheExtension(_ host: YouTubeTestClient, _ command: MediaCommand = .nextTrack) {
        module.send(command)
        #expect(host.receiveFrames(count: 1).count == 1)
        answer(command == .nextTrack ? "next" : "previous")
    }

    @Test func aSecondPressWhileOnlyTheSystemKnowsTheNewTitleStillGoesToTheExtension() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        skipThroughTheExtension(host)
        // MediaRemote's title moves first; the page has not said the new video yet.
        playInChrome(title: "Next video")
        #expect(module.skipRoute() == .bridge)
        module.send(.nextTrack)
        #expect(host.receiveFrames(count: 1) == [YouTubeCommand.next.json])
        #expect(source.sent.isEmpty, "MediaRemote would do nothing for a video in Chrome")
    }

    @Test func aSecondPressWhileOnlyThePageKnowsTheNewTitleStillGoesToTheExtension() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        skipThroughTheExtension(host)
        // The page moves first; the system still says the old title.
        receive(YouTubeTestMessages.playback("bbbbbbbbbbb", title: "Next video"))
        #expect(module.skipRoute() == .bridge)
        module.send(.previousTrack)
        #expect(host.receiveFrames(count: 1) == [YouTubeCommand.previous.json])
        #expect(source.sent.isEmpty)
    }

    @Test func theSessionStaysMatchedThroughAWholeRunOfPresses() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        for index in 1...4 {
            skipThroughTheExtension(host)
            playInChrome(title: "Video \(index)")
        }
        #expect(source.sent.isEmpty)
        #expect(fallbacks.isEmpty)
    }

    @Test func theTitleIsForgivenOnlyForAFewSecondsAfterThePress() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        skipThroughTheExtension(host)
        playInChrome(title: "Next video")
        #expect(module.skipRoute(at: Date().addingTimeInterval(3)) == .bridge)
        #expect(module.skipRoute(at: Date().addingTimeInterval(30)) == .mediaRemote, "the title that differs is no longer the skip's doing")
    }

    @Test func aStateEmptyForAMomentBetweenTwoVideosStillGoesToTheExtensionAfterAPress() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        skipThroughTheExtension(host)
        source.emit(AdapterLines.empty)
        module.send(.nextTrack)
        #expect(host.receiveFrames(count: 1) == [YouTubeCommand.next.json])
        #expect(source.sent.isEmpty)
    }

    @Test func nothingIsForgivenWithoutAPressTheExtensionTook() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        _ = try await connectHost()
        playInChrome(title: "Another video")
        source.emit(AdapterLines.empty)
        #expect(module.skipRoute() == .mediaRemote)
        playInChrome(title: "Another video")
        #expect(module.skipRoute() == .mediaRemote)
    }

    @Test func aPressThatFellBackToMediaRemoteDoesNotForgiveTheNextTitle() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        module.send(.nextTrack)
        #expect(host.receiveFrames(count: 1).count == 1)
        harness.scheduler.advance(by: .seconds(1))
        #expect(source.sent == [.nextTrack])
        playInChrome(title: "Next video")
        #expect(module.skipRoute() == .mediaRemote, "the extension did nothing, so its title change was not expected")
    }

    @Test func theForgivenessStaysWithThePlayerThatWasSkipped() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        skipThroughTheExtension(host)
        playInChrome(title: "Next video", bundle: "com.spotify.client")
        #expect(module.skipRoute() == .mediaRemote)
        playInChrome(title: "Next video", bundle: "com.apple.Safari")
        #expect(module.skipRoute() == .mediaRemote)
        playInChrome(title: "Next video")
        #expect(module.skipRoute() == .bridge)
    }

    @Test func turningTheSettingOffForgetsThePress() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        skipThroughTheExtension(host)
        harness.settings.set(false, for: keys.youtubeCaptions)
        await settle { !FileManager.default.fileExists(atPath: socketPath) }
        enableCaptions()
        await settle { FileManager.default.fileExists(atPath: socketPath) }
        _ = try await connectHost(title: "Next video")
        playInChrome()
        #expect(module.skipRoute() == .mediaRemote, "the page's title is another one and nothing was skipped since")
    }

    // MARK: the extension's answer, and what happens without one

    @Test func whenTheExtensionAnswersNothingElseHappens() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        module.send(.nextTrack)
        #expect(host.receiveFrames(count: 1) == [YouTubeCommand.next.json])
        answer("next", "unavailable")
        harness.scheduler.advance(by: .seconds(5))
        #expect(source.sent.isEmpty, "unavailable is an answer: no fallback skip")
        #expect(!host.hasData(within: 0.2), "and the command is not sent again")
        #expect(fallbacks.isEmpty)
        module.send(.previousTrack)
        answer("previous", "ok")
        harness.scheduler.advance(by: .seconds(5))
        #expect(source.sent.isEmpty)
    }

    @Test func aHostOrExtensionThatDoesNotAnswerWithinASecondFallsBackToMediaRemoteForThatPress() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        module.send(.nextTrack)
        #expect(host.receiveFrames(count: 1) == [YouTubeCommand.next.json], "the command was sent first")
        harness.scheduler.advance(by: .milliseconds(990))
        #expect(source.sent.isEmpty)
        harness.scheduler.advance(by: .milliseconds(20))
        #expect(source.sent == [.nextTrack])
        #expect(fallbacks == ["skip fallback=mediaremote reason=no-answer"])
        // A late answer changes nothing more.
        answer("next")
        harness.scheduler.advance(by: .seconds(5))
        #expect(source.sent == [.nextTrack])
        #expect(fallbacks.count == 1)
    }

    @Test func aHostThatCannotBeWrittenToFallsBackAtOnce() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        do { _ = try await connectHost() }
        await waitUntil { module.youtubeServerConnectionCount == 0 }
        module.send(.previousTrack)
        #expect(source.sent == [.previousTrack], "no waiting for an answer that cannot come")
        #expect(fallbacks == ["skip fallback=mediaremote reason=no-host"])
        #expect(!recorder.lines.contains { $0.hasPrefix("command sent") })
    }

    @Test func eachPressWaitsForItsOwnAnswerAndAnAnswerForAnotherCommandDoesNotCountForIt() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        module.send(.nextTrack)
        module.send(.nextTrack)
        module.send(.previousTrack)
        #expect(host.receiveFrames(count: 3).count == 3)
        answer("next")
        answer("previous", "unavailable")
        harness.scheduler.advance(by: .seconds(1))
        #expect(source.sent == [.nextTrack], "the second next was never answered")
        #expect(fallbacks == ["skip fallback=mediaremote reason=no-answer"])
    }

    @Test func anAnswerCancelsItsTimerAndSoDoesGivingUpTheBridge() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        let idle = harness.scheduler.pendingCount
        module.send(.nextTrack)
        #expect(harness.scheduler.pendingCount == idle + 1)
        answer("next")
        #expect(harness.scheduler.pendingCount == idle, "an answered press leaves no timer behind")

        module.send(.previousTrack)
        #expect(harness.scheduler.pendingCount == idle + 1)
        harness.settings.set(false, for: keys.youtubeCaptions)
        await settle { !FileManager.default.fileExists(atPath: socketPath) }
        #expect(harness.scheduler.pendingCount == idle, "nor does a bridge that was turned off")
        withExtendedLifetime(host) {}
    }

    @Test func aServiceWorkerAnswerMeansNothingWasDeliveredSoThatPressGoesToMediaRemote() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        module.send(.nextTrack)
        module.send(.previousTrack)
        #expect(host.receiveFrames(count: 2).count == 2)
        // The worker does not say which command it could not hand over: it is the oldest press still waiting.
        receive(YouTubeTestMessages.diag("sw-command-no-tab"))
        #expect(source.sent == [.nextTrack])
        receive(YouTubeTestMessages.diag("sw-reject invalid command"))
        #expect(source.sent == [.nextTrack, .previousTrack])
        #expect(fallbacks == Array(repeating: "skip fallback=mediaremote reason=worker", count: 2))
        harness.scheduler.advance(by: .seconds(5))
        #expect(source.sent == [.nextTrack, .previousTrack], "answered presses leave no timer to fall back a second time")
    }

    @Test func aServiceWorkerAnswerWithNoPressWaitingDoesNothing() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        _ = try await connectHost()
        receive(YouTubeTestMessages.diag("sw-command-no-tab"))
        #expect(source.sent.isEmpty)
        #expect(fallbacks.isEmpty)
    }

    @Test func otherDiagnosticsAreNoAnswer() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        module.send(.nextTrack)
        #expect(host.receiveFrames(count: 1).count == 1)
        receive(
            YouTubeTestMessages.diag("sw-msg playback"), YouTubeTestMessages.diag("content-alive videoid-present=true playing=true", from: .content),
            YouTubeTestMessages.diag("sw-start v=0.1.3")
        )
        harness.scheduler.advance(by: .seconds(1))
        #expect(source.sent == [.nextTrack])
    }

    @Test func turningTheSettingOffOrStoppingDropsTheWaitingPresses() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        let host = try await connectHost()
        module.send(.nextTrack)
        #expect(host.receiveFrames(count: 1).count == 1)
        harness.settings.set(false, for: keys.youtubeCaptions)
        await settle { !FileManager.default.fileExists(atPath: socketPath) }
        harness.scheduler.advance(by: .seconds(5))
        #expect(source.sent.isEmpty, "the press was the bridge's and nobody answers for it any more")
        #expect(fallbacks.isEmpty)
    }

    @Test func commandsAreIgnoredWhileTheModuleIsStopped() async throws {
        await bootstrapWithCaptions()
        playInChrome()
        _ = try await connectHost()
        await harness.registry.setEnabled(false, for: "media")
        module.send(.nextTrack)
        harness.scheduler.advance(by: .seconds(5))
        #expect(source.sent.isEmpty)
    }

    @Test func eachCommandAndFallbackIsLoggedWithItsWordsAndNothingElse() async throws {
        await bootstrapWithCaptions()
        playInChrome(title: "Zebra Quartz Secret Title")
        let host = try await connectHost(title: "Zebra Quartz Secret Title")
        module.send(.nextTrack)
        module.send(.previousTrack)
        #expect(host.receiveFrames(count: 2).count == 2)
        answer("next")
        harness.scheduler.advance(by: .seconds(1))
        #expect(recorder.lines.filter { $0.hasPrefix("command") || $0.hasPrefix("skip") } == [
            "command sent action=next", "command sent action=previous", "skip fallback=mediaremote reason=no-answer",
        ])
        recorder.expectNothingPrivate(["Zebra", "Quartz", "Secret", YouTubeTestMessages.videoID, socketPath])
    }

    // MARK: site access

    @Test func theExtensionsAccessReportShowsOrClearsTheWithheldNotice() async {
        await bootstrapWithCaptions()
        #expect(!module.youtubeBridge.accessWithheld)
        receive(YouTubeTestMessages.diag("sw-access youtube=withheld"))
        #expect(module.youtubeBridge.accessWithheld)
        // Other diagnostics of the service worker do not touch it.
        receive(YouTubeTestMessages.diag("sw-start v=0.1.2"), YouTubeTestMessages.diag("sw-msg playback"))
        #expect(module.youtubeBridge.accessWithheld)
        // Chrome gave the access back.
        receive(YouTubeTestMessages.diag("sw-access youtube=granted"))
        #expect(!module.youtubeBridge.accessWithheld)
    }

    @Test func trafficFromThePageClearsTheWithheldNoticeBecauseItProvesTheAccessWorks() async {
        await bootstrapWithCaptions()
        // Chrome gave the access (the user reloaded the tab) without the extension's permission events firing.
        for page in [
            YouTubeTestMessages.playback(), YouTubeTestMessages.captions(), YouTubeTestMessages.clear(),
            YouTubeTestMessages.diag("content-start", from: .content), YouTubeTestMessages.diag("page-wrap fetch=true xhr=true", from: .page),
        ] {
            receive(YouTubeTestMessages.diag("sw-access youtube=withheld"))
            #expect(module.youtubeBridge.accessWithheld)
            receive(page)
            #expect(!module.youtubeBridge.accessWithheld, "\(page)")
        }
    }

    @Test func theServiceWorkersOtherDiagnosticsDoNotClearTheWithheldNotice() async {
        await bootstrapWithCaptions()
        receive(YouTubeTestMessages.diag("sw-access youtube=withheld"))
        receive(
            YouTubeTestMessages.diag("sw-start v=0.1.2"), YouTubeTestMessages.diag("sw-inject tabs=0 injected=0 failed=0"),
            YouTubeTestMessages.diag("sw-reconnect after=host-not-found failures=1")
        )
        #expect(module.youtubeBridge.accessWithheld)
    }

    @Test func aWithheldReportAfterTheTrafficShowsTheNoticeAgain() async {
        await bootstrapWithCaptions()
        receive(YouTubeTestMessages.playback())
        receive(YouTubeTestMessages.diag("sw-access youtube=withheld"))
        #expect(module.youtubeBridge.accessWithheld, "the service worker's own word on the access decides while it speaks")
    }

    @Test func onlyTheServiceWorkersAccessReportCounts() async {
        await bootstrapWithCaptions()
        receive(YouTubeTestMessages.diag("sw-access youtube=withheld", from: .content), YouTubeTestMessages.diag("sw-access youtube=withheld", from: .page))
        #expect(!module.youtubeBridge.accessWithheld)
    }

    @Test func theWithheldNoticeDoesNotDecideAnythingAboutTheLyrics() async {
        await bootstrapWithCaptions()
        playInChrome()
        let decided = decisions
        receive(YouTubeTestMessages.diag("sw-access youtube=withheld"))
        #expect(decisions == decided)
        #expect(store.syncedLyrics == nil)
    }

    @Test func turningTheSettingOffForgetsTheWithheldNoticeAndItIsIgnoredWhileOff() async {
        await bootstrapWithCaptions()
        receive(YouTubeTestMessages.diag("sw-access youtube=withheld"))
        #expect(module.youtubeBridge.accessWithheld)
        harness.settings.set(false, for: keys.youtubeCaptions)
        await settle { !module.youtubeBridge.accessWithheld }
        #expect(!module.youtubeBridge.accessWithheld)
        receive(YouTubeTestMessages.diag("sw-access youtube=withheld"))
        #expect(!module.youtubeBridge.accessWithheld, "a message that arrives while the setting is off is ignored")
    }

    @Test func noLineHoldsATitleAVideoIdCaptionTextOrAUrl() async throws {
        await bootstrapWithCaptions()
        let secretID = "abcdefghijk"
        let secretTitle = "Zebra Quartz Secret Title"
        let secretWords = "hidden caption words"
        let events = [CaptionEvent(time: 1, duration: 2, text: secretWords)]
        // Every decision, a drift and a diagnostic, with a title, an id and caption text that must not show.
        playInChrome(title: secretTitle, bundle: "com.spotify.client")
        playInChrome(title: secretTitle)
        receive(YouTubeTestMessages.playback(secretID, title: "Another " + secretTitle))
        receive(YouTubeTestMessages.playback(secretID, title: secretTitle, playing: false))
        receive(YouTubeTestMessages.captions(secretID, events))
        receive(YouTubeTestMessages.playback(secretID, title: secretTitle, playing: true), at: Date().addingTimeInterval(-30))
        receive(YouTubeTestMessages.playback(secretID, title: secretTitle, playing: true, time: 40))
        receive(YouTubeTestMessages.diag("page-timedtext json3 events=1", from: .page))
        receive(YouTubeTestMessages.clear(secretID))
        // And through the socket, with frames that are refused.
        let host = try #require(YouTubeTestClient(path: socketPath))
        host.sendFrame(Data(#"{"v":1,"type":"playback","videoId":"abcdefghijk","title":"Zebra Quartz Secret Title","time":-1,"playing":true,"rate":1}"#.utf8))
        host.sendFrame(Data(#"{"v":1,"type":"diag","where":"content","event":"content-tick-error https://www.youtube.com/watch?v=abcdefghijk"}"#.utf8))
        host.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.playback(secretID, title: secretTitle)))
        await waitUntil { !recorder.lines(containing: "app rejected frame: invalid-diag").isEmpty }
        await harness.registry.setEnabled(false, for: "media")

        #expect(decisions.count >= 5, "\(decisions)")
        #expect(recorder.lines.contains { $0.hasPrefix("playback drift=") })
        #expect(recorder.lines.count >= 12, "\(recorder.lines)")
        recorder.expectNothingPrivate([secretID, secretTitle, "Zebra", "Quartz", "Secret", secretWords, "hidden", "youtube", "/tmp", socketPath])
    }
}
