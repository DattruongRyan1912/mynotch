import Foundation
import MyNotchCore
import NotchUI
import Observation
import SwiftUI
import YouTubeBridgeKit

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct MediaSettingsKeys {
    static let pauseGraceRange = 0...60

    let showActivity: SettingKey<Bool>
    let pauseGraceSeconds: SettingKey<Int>
    /// Bundle IDs whose playback never shows the live activity.
    let hiddenApps: SettingKey<[String]>
    /// Bars follow the music through a system audio tap, which needs the system audio recording permission.
    let realSpectrum: SettingKey<Bool>
    /// Synced lyrics from lrclib.net. Off by default: it sends each new track's name, artist, album and length there.
    let lyrics: SettingKey<Bool>
    /// Lyrics from the captions the user turned on in a YouTube video in Chrome, which the extension hands over on this
    /// Mac. Off by default; it opens a socket for the helper that Chrome starts, and sends nothing anywhere.
    let youtubeCaptions: SettingKey<Bool>
    /// The current and the next lyric line in a strip under the closed notch. Off by default: it makes the notch taller.
    let lyricsUnderNotch: SettingKey<Bool>
    /// The buttons beside play and pause in the Media tab.
    let controlButtons: SettingKey<MediaControlLayout>
    /// The sung part of a line is filled word by word where the lyrics have the timing for it.
    let karaoke: SettingKey<Bool>
    /// The floating lyrics panel is up. Off by default; the Media tab's button and the hotkey flip it.
    let lyricsPanel: SettingKey<Bool>
    /// The current line's size in the panel, in points; the lines around it are smaller.
    let lyricsPanelFontSize: SettingKey<Double>
    /// How opaque the whole panel is.
    let lyricsPanelOpacity: SettingKey<Double>
    /// The pointer goes through the panel to what is under it, so it can be left over a window.
    let lyricsPanelClickThrough: SettingKey<Bool>
    /// Where the panel was left on each display. Written by the panel, not by a settings row.
    let lyricsPanelFrames: SettingKey<LyricsPanelPlacement>

    init(_ settings: ModuleSettings) {
        showActivity = settings.key("showActivity", default: true)
        pauseGraceSeconds = settings.key("pauseGraceSeconds", default: 5, clampedTo: Self.pauseGraceRange)
        hiddenApps = settings.key("hiddenApps", default: [])
        realSpectrum = settings.key("realSpectrum", default: false)
        lyrics = settings.key("lyrics", default: false)
        youtubeCaptions = settings.key("youtubeCaptions", default: false)
        lyricsUnderNotch = settings.key("lyricsUnderNotch", default: false)
        controlButtons = settings.key("controlButtons", default: .standard)
        karaoke = settings.key("karaoke", default: true)
        lyricsPanel = settings.key("lyricsPanel", default: false)
        lyricsPanelFontSize = settings.key("lyricsPanelFontSize", default: LyricsPanelModel.defaultFontSize, clampedTo: LyricsPanelModel.fontSizeRange)
        lyricsPanelOpacity = settings.key("lyricsPanelOpacity", default: 0.9, clampedTo: LyricsPanelController.opacityRange)
        lyricsPanelClickThrough = settings.key("lyricsPanelClickThrough", default: false)
        lyricsPanelFrames = settings.key("lyricsPanelFrames", default: LyricsPanelPlacement())
    }
}

/// What the tab's controls do, without handing the views the module or the source.
struct MediaActions {
    var send: (MediaCommand) -> Void
    var seek: (Double) -> Void
    /// A button beside play and pause was pressed.
    var press: (MediaControlButton) -> Void = { _ in }
    /// Puts the floating lyrics panel up or takes it down.
    var toggleLyricsPanel: () -> Void = {}
}

/// A next or previous that went to the extension and waits for its answer.
private struct UnansweredSkip {
    var id: Int
    var command: MediaCommand
    var action: YouTubeCommand
    var timer: ScheduledAction
}

/// Now playing from any app: a live activity while music plays and a "Media" tab with the player controls.
public final class MediaModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "media",
        displayName: "Media",
        systemImage: "music.note",
        defaultEnabled: true,
        // Only the real-spectrum switch (off by default) taps system audio; now-playing needs nothing.
        optionalPermissions: [.systemAudio],
        permissionReasons: [.systemAudio: "Vẽ phổ nhạc thật; chỉ cần khi bật “Cột sóng theo phổ âm thanh thật”."],
        order: 200
    )

    static let activityID = "nowPlaying"
    static let blockedMessage = "Không đọc được thông tin phát nhạc (macOS đã chặn adapter)"

    let store: NowPlayingStore
    /// nil when the app was built without the adapter; `start` then reports the module unavailable.
    private let makeSource: ((any Scheduler) -> any NowPlayingSource)?
    private let spectrum: any SpectrumSource
    private let lyricsClient: any HTTPClient
    /// The system output volume the row's slider shows and sets; Core Audio is only called on its queue.
    let volume: VolumeModel
    /// The user's Apple Music sign-in, which Settings shows and lyrics lookups use.
    let appleAccount: AppleMusicAccount
    let appleClient: AppleMusicLyricsClient
    private let signIn: any AppleMusicSignIn
    private var appleWasConnected = false
    #if DEBUG
    /// Runs an Apple lookup for a song id posted from outside, while the module runs.
    private(set) var appleDebugTrigger: AppleLyricsDebugTrigger?
    /// Where the trigger listens; tests put their own in place of the distributed notification center.
    var debugObserve = AppleLyricsDebugTrigger.systemObserve
    #endif
    private var source: (any NowPlayingSource)?
    private var spectrumFeed: SpectrumFeed?
    private var context: ModuleContext?
    private var policy = ActivityPolicy()
    private var showActivity = true
    private var realSpectrum = false
    private var lyricsEnabled = false
    private var lyricsUnderNotch = false
    private var lyricsService: LyricsService?
    /// Track the lyrics were asked for (or are shown for); nil while lyrics are off or the track has no key.
    private var lyricsTrack: TrackKey?
    private var lyricsTask: Task<Void, Never>?
    /// Counts track changes, so a retry planned for an earlier track finds out it is stale.
    private var lyricsEpoch = 0
    /// What the Settings rows show of the Chrome bridge, and where its buttons put the files.
    let youtubeBridge = YouTubeBridgeModel()
    /// nil is the standard place in the module's storage.
    private let youtubeSocketPath: String?
    /// nil is the real installer, which needs the module's storage and so is made with the Settings rows.
    private let youtubeSetup: YouTubeBridgeSetup?
    private var youtubeCaptionsEnabled = false
    /// Where the bridge's diagnostics go (category `youtube-bridge`): the receiver's, the matching decisions, the drift.
    private let youtubeLog: YouTubeBridgeLog
    /// What the last logged matching decision was, so that a decision is logged when it changes and not at every update.
    private var loggedMatchDecision: String?
    /// When the drift of the extension's clock against the notch's was last logged.
    private var lastDriftLoggedAt: Date?
    /// What the extension has sent; memory only.
    private var captionStore = YouTubeCaptionStore()
    /// Set while the setting is on and the socket could be opened.
    private var youtubeServer: YouTubeBridgeServer?
    /// The socket could not be opened; it is tried again only after the setting was switched off and on.
    private var youtubeListenFailed = false
    /// The captions the lyric row shows, nil while it shows something else. Compared, so the row is assigned once per
    /// arrival rather than with every position update.
    private var shownCaptions: (videoID: String, revision: Int)?
    /// Track the published activity belongs to; nil while none is published. Compared so the activity is
    /// set once per track: everything that changes while a track plays is read by its views from `store`.
    private var publishedTrack: TrackIdentity?
    /// Whether the published activity carries the lyric strip. Unlike the track it can change while a track plays
    /// (lyrics arrive, playback pauses), and each change republishes the activity.
    private var publishedStrip = false
    /// Keeps the strip up through a track change, a seek or a stall, so the notch does not shrink and grow again.
    private var stripHold = LyricStripHold()
    private var stripHoldTimer: ScheduledAction?
    private var scheduledStripDeadline: Date?
    /// Skips sent to the extension and not answered yet, oldest first.
    private var unansweredSkips: [UnansweredSkip] = []
    private var unansweredSkipCount = 0
    /// The latest seek, until the player reports the position it moved to: quick taps on a seek button start from it.
    private var pendingSeek: PendingSeek?
    /// The latest press the extension took; it explains a title that is about to change (see `SkipRoute.titleChangeWindow`).
    private var bridgedSkip: SkipRoute.BridgedSkip?
    /// Whether the lock screen view is on offer; its view reads `store`, so it is set once and cleared once.
    private var lockScreenOffered = false
    private var deadlineTimer: ScheduledAction?
    private var scheduledDeadline: Date?
    /// The floating lyrics panel and what it follows, while the module runs.
    private var lyricsPanel: LyricsPanelHost?
    /// Puts the lyrics panel on the screen; tests record it instead.
    var presentLyricsPanel: (NSPanel) -> Void = { $0.orderFrontRegardless() }
    /// The displays the panel is placed on, the main one first; tests give their own.
    var lyricsPanelDisplays: @MainActor () -> [PanelDisplay] = LyricsPanelController.screens
    var lyricsPanelController: LyricsPanelController? { lyricsPanel?.controller }
    var lyricsPanelModel: LyricsPanelModel? { lyricsPanel?.model }

    /// The app passes the bundled mediaremote-adapter script and framework; nil when the build did not include them.
    public convenience init(adapterScript: URL?, adapterFramework: URL?) {
        // Creating the tap object does nothing yet: it touches Core Audio only when it starts.
        let spectrum = SystemAudioTap(bandCount: NowPlayingBars.barCount)
        if let adapterScript, let adapterFramework {
            self.init(
                makeSource: { scheduler in AdapterProcess(script: adapterScript, framework: adapterFramework, scheduler: scheduler) },
                spectrum: spectrum,
                lyricsClient: URLSessionHTTPClient(),
                tokens: KeychainTokenStore(),
                signIn: AppleMusicLoginWindow(),
                volume: .system()
            )
        } else {
            self.init(
                makeSource: nil, spectrum: spectrum, lyricsClient: URLSessionHTTPClient(),
                tokens: KeychainTokenStore(), signIn: AppleMusicLoginWindow(), volume: .system()
            )
        }
    }

    /// For tests: lines come from `source` instead of perl, levels from `spectrum` instead of a system audio tap,
    /// lyrics from `lyricsClient` instead of lrclib.net and Apple, the sign-in from `tokens` instead of the Keychain,
    /// the sign-in window is `signIn`, the output volume is `volume`. No defaults for those but the volume, which is a device
    /// without one, so no test reaches the network, the Keychain or the speakers by accident.
    convenience init(
        source: any NowPlayingSource,
        spectrum: any SpectrumSource,
        lyricsClient: any HTTPClient,
        tokens: any TokenStore,
        signIn: any AppleMusicSignIn,
        lookUpApp: @escaping @MainActor (String) -> PlayerApp? = PlayerApp.installed,
        youtubeSocketPath: String? = nil,
        youtubeSetup: YouTubeBridgeSetup? = nil,
        youtubeLog: YouTubeBridgeLog = .silent,
        volume: VolumeModel = VolumeModel(hardware: NoVolumeHardware(), queue: SerialVolumeQueue())
    ) {
        self.init(
            makeSource: { _ in source }, spectrum: spectrum, lyricsClient: lyricsClient,
            tokens: tokens, signIn: signIn, volume: volume, lookUpApp: lookUpApp, youtubeSocketPath: youtubeSocketPath,
            youtubeSetup: youtubeSetup, youtubeLog: youtubeLog
        )
    }

    private init(
        makeSource: ((any Scheduler) -> any NowPlayingSource)?,
        spectrum: any SpectrumSource,
        lyricsClient: any HTTPClient,
        tokens: any TokenStore,
        signIn: any AppleMusicSignIn,
        volume: VolumeModel,
        lookUpApp: @escaping @MainActor (String) -> PlayerApp? = PlayerApp.installed,
        youtubeSocketPath: String? = nil,
        youtubeSetup: YouTubeBridgeSetup? = nil,
        youtubeLog: YouTubeBridgeLog = .system
    ) {
        self.volume = volume
        self.youtubeSocketPath = youtubeSocketPath
        self.youtubeSetup = youtubeSetup
        self.youtubeLog = youtubeLog
        self.makeSource = makeSource
        self.spectrum = spectrum
        self.lyricsClient = lyricsClient
        appleAccount = AppleMusicAccount(tokens: tokens)
        appleClient = AppleMusicLyricsClient(client: lyricsClient, account: appleAccount)
        self.signIn = signIn
        store = NowPlayingStore(lookUpApp: lookUpApp)
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        guard let makeSource else {
            throw .unavailable(reason: "Thiếu MediaRemoteAdapter trong app")
        }
        self.context = context
        store.reset()
        policy = ActivityPolicy()
        publishedTrack = nil
        publishedStrip = false
        resetStripHold()
        lockScreenOffered = false
        spectrumFeed = SpectrumFeed(source: spectrum, store: store, scheduler: context.scheduler, logger: context.logger)
        lyricsTrack = nil
        appleAccount.load()
        lyricsService = LyricsService(
            client: lyricsClient,
            cacheDirectory: context.storage.cachesDirectory.appending(path: "lyrics", directoryHint: .isDirectory),
            scheduler: context.scheduler,
            apple: appleClient
        )
        #if DEBUG
        if let lyricsService {
            let trigger = AppleLyricsDebugTrigger(
                lookUp: { [weak lyricsService] id in await lyricsService?.appleLookup(forSongID: id) ?? .unavailable("Lyrics service stopped") },
                observe: debugObserve
            )
            trigger.start()
            appleDebugTrigger = trigger
        }
        #endif
        applySettings(context.settings)
        registerHotkeys(context.hotkeys)
        let settings = context.settings
        let keys = MediaSettingsKeys(settings)
        let panel = LyricsPanelHost(
            store: store, settings: settings, scheduler: context.scheduler, displays: lyricsPanelDisplays, present: presentLyricsPanel
        )
        lyricsPanel = panel
        panel.apply()
        context.run { [weak self] in
            let changes = Observations {
                (
                    settings.value(keys.showActivity), settings.value(keys.pauseGraceSeconds),
                    settings.value(keys.hiddenApps), settings.value(keys.realSpectrum), settings.value(keys.lyrics),
                    settings.value(keys.youtubeCaptions), settings.value(keys.lyricsUnderNotch), settings.value(keys.controlButtons),
                    settings.value(keys.karaoke)
                )
            }
            for await _ in changes { self?.settingsChanged() }
        }
        // Not in the loop above: moving the panel writes its frame, which must not make the module look at its activity again.
        context.run { [weak self] in
            let changes = Observations {
                (
                    settings.value(keys.lyricsPanel), settings.value(keys.lyricsPanelFontSize),
                    settings.value(keys.lyricsPanelOpacity), settings.value(keys.lyricsPanelClickThrough)
                )
            }
            for await _ in changes { self?.lyricsPanel?.apply() }
        }
        let store = store
        context.run { [weak self] in
            for await _ in Observations({ store.spectrumViewCount }) { self?.updateSpectrum() }
        }
        let account = appleAccount
        context.run { [weak self] in
            for await _ in Observations({ account.status }) { self?.appleStatusChanged() }
        }
        let source = makeSource(context.scheduler)
        self.source = source
        store.setCanLike(source.canLike)
        source.start(
            onLine: { [weak self] line in self?.receive(line) },
            onFailure: { [weak self] reason in self?.sourceFailed(reason) }
        )
    }

    public func stop() async {
        lyricsPanel?.close()
        lyricsPanel = nil
        source?.stop()
        source = nil
        store.setCanLike(false)
        pendingSeek = nil
        volume.stopWatching()
        spectrumFeed?.shutDown()
        spectrumFeed = nil
        lyricsTask?.cancel()
        lyricsTask = nil
        lyricsTrack = nil
        shownCaptions = nil
        #if DEBUG
        appleDebugTrigger?.stop()
        appleDebugTrigger = nil
        #endif
        lyricsService?.shutDown()
        lyricsService = nil
        youtubeCaptionsEnabled = false
        stopYouTubeBridge()
        signIn.close()
        context = nil
        cancelDeadline()
        policy = ActivityPolicy()
        publishedTrack = nil
        publishedStrip = false
        resetStripHold()
        lockScreenOffered = false
        store.reset()
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Media", systemImage: "music.note", preferredHeight: MediaTabView.preferredHeight,
            content: AnyView(MediaTabView(store: store, actions: actions, volume: volume))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        let keys = MediaSettingsKeys(environment.settings)
        return AnyView(MediaSettingsView(
            showActivity: environment.settings.binding(keys.showActivity),
            pauseGraceSeconds: environment.settings.binding(keys.pauseGraceSeconds),
            hiddenApps: environment.settings.binding(keys.hiddenApps),
            realSpectrum: environment.settings.binding(keys.realSpectrum),
            lyrics: environment.settings.binding(keys.lyrics),
            youtubeCaptions: environment.settings.binding(keys.youtubeCaptions),
            lyricsUnderNotch: environment.settings.binding(keys.lyricsUnderNotch),
            controlButtons: environment.settings.binding(keys.controlButtons),
            karaoke: environment.settings.binding(keys.karaoke),
            lyricsPanel: environment.settings.binding(keys.lyricsPanel),
            lyricsPanelFontSize: environment.settings.binding(keys.lyricsPanelFontSize),
            lyricsPanelOpacity: environment.settings.binding(keys.lyricsPanelOpacity),
            lyricsPanelClickThrough: environment.settings.binding(keys.lyricsPanelClickThrough),
            youtubeBridge: youtubeBridgeModel(for: environment),
            store: store,
            appleAccount: appleAccount,
            connectAppleMusic: { [weak self] in self?.connectAppleMusic() },
            disconnectAppleMusic: { [weak self] in Task { await self?.disconnectAppleMusic() } }
        ))
    }

    /// Installing the bridge turns `youtubeCaptions` on, since the captions come over a socket that is open only while it is.
    func youtubeBridgeModel(for environment: ModuleSettingsEnvironment) -> YouTubeBridgeModel {
        let settings = environment.settings
        let key = MediaSettingsKeys(settings).youtubeCaptions
        youtubeBridge.configure(
            setup: youtubeSetup ?? .system(storageDirectory: environment.storage.directory),
            didInstall: { settings.set(true, for: key) }
        )
        return youtubeBridge
    }

    /// Opens the sign-in window; the account is connected once the window has found the tokens. The page is only how
    /// they are found: when the window is gone (signed in, failed, or given up) the tokens are in the Keychain or
    /// never will be, so nothing of the web session stays behind, where the Settings rows offer no way to clear it.
    func connectAppleMusic() {
        signIn.open(
            connect: { [appleClient] credentials in await appleClient.connect(credentials) },
            closed: { [signIn] in await signIn.removeWebsiteData() }
        )
    }

    /// Forgets the sign-in: the tokens in the Keychain and everything the sign-in window's web view stored.
    func disconnectAppleMusic() async {
        signIn.close()
        appleAccount.disconnect()
        await signIn.removeWebsiteData()
    }

    var actions: MediaActions {
        MediaActions(
            send: { [weak self] command in self?.send(command) },
            seek: { [weak self] seconds in self?.seek(toSeconds: seconds) },
            press: { [weak self] button in self?.press(button) },
            toggleLyricsPanel: { [weak self] in self?.lyricsPanel?.toggle() }
        )
    }

    /// Next and previous of a video that plays in Chrome go to the extension, which presses the player's own button, when it
    /// has a live session for that video: Chrome ignores MediaRemote's next and previous there. Whatever else is sent
    /// goes to MediaRemote, as does a press the extension does not take (see `sendToExtension`).
    func send(_ command: MediaCommand) {
        if let action = command.youTubeCommand, skipRoute() == .bridge {
            sendToExtension(command, as: action)
            return
        }
        source?.send(command)
    }

    /// Where Next and Previous go for what plays now.
    func skipRoute(at now: Date = Date()) -> SkipRoute {
        SkipRoute.decide(for: store.state, in: captionStore, now: now, after: bridgedSkip)
    }

    /// The hosts connected to the socket (for tests).
    var youtubeServerConnectionCount: Int { youtubeServer?.connectionCount ?? 0 }

    /// Writes the command to the host and waits `SkipRoute.answerTimeout` for the extension to answer it (it does, with a
    /// diagnostic, whether or not it could do it). Nothing answers when the host or the extension is of a version that does not
    /// know commands, which an app update can leave behind; that press goes to MediaRemote instead. So does a press the
    /// extension's service worker could not hand to a tab, since nothing was done. Any other answer, "unavailable" included,
    /// ends it: nothing else is tried.
    private func sendToExtension(_ command: MediaCommand, as action: YouTubeCommand) {
        guard let youtubeServer, youtubeServer.send(action) else {
            fallBackToMediaRemote(command, reason: "no-host")
            return
        }
        youtubeLog("command sent action=\(action.rawValue)")
        // The state can be empty between two videos, when the player is the one of the press before.
        bridgedSkip = SkipRoute.BridgedSkip(at: Date(), player: store.state.playerBundleIdentifier ?? bridgedSkip?.player)
        guard let context else { return }
        unansweredSkipCount += 1
        let id = unansweredSkipCount
        let timer = context.scheduler.schedule(after: SkipRoute.answerTimeout) { [weak self] in self?.skipUnanswered(id) }
        unansweredSkips.append(UnansweredSkip(id: id, command: command, action: action, timer: timer))
    }

    private func skipUnanswered(_ id: Int) {
        guard let index = unansweredSkips.firstIndex(where: { $0.id == id }) else { return }
        let skip = unansweredSkips.remove(at: index)
        fallBackToMediaRemote(skip.command, reason: "no-answer")
    }

    /// MediaRemote does what the extension did not, so no title change of the extension's is expected any more.
    private func fallBackToMediaRemote(_ command: MediaCommand, reason: String) {
        bridgedSkip = nil
        youtubeLog("skip fallback=mediaremote reason=\(reason)")
        source?.send(command)
    }

    /// The extension answered a command: the oldest press waiting for that answer is done. A worker's answer says that the
    /// command was not delivered, so that press goes to MediaRemote, which cannot double a skip nothing performed.
    private func commandAnswered(_ answer: YouTubeDiag.CommandAnswer) {
        let index = unansweredSkips.firstIndex { skip in
            if case .content(let action, _) = answer { skip.action == action } else { true }
        }
        guard let index else { return }
        let skip = unansweredSkips.remove(at: index)
        skip.timer.cancel()
        if case .worker = answer { fallBackToMediaRemote(skip.command, reason: "worker") }
    }

    private func dropUnansweredSkips() {
        for skip in unansweredSkips { skip.timer.cancel() }
        unansweredSkips = []
        bridgedSkip = nil
    }

    func seek(toSeconds seconds: Double, at now: Date = Date()) {
        pendingSeek = PendingSeek(seconds: seconds, anchor: store.state.elapsedAnchor, date: now)
        source?.seek(toSeconds: seconds)
    }

    /// A button beside play and pause: what it does depends on what the player reports (see `MediaControlButton`), and a
    /// button that cannot be used does nothing. Next and previous go through `send`, so they take the same route as the hotkeys.
    func press(_ button: MediaControlButton, at now: Date = Date()) {
        // The volume slider is the row's own: it has no effect on the player and is never open from here.
        let waiting = pendingSeek.flatMap { $0.isPending(for: store.state, at: now) ? $0.seconds : nil }
        let context = store.controlContext(hasVolume: volume.isAvailable, volumeIsOpen: false, pendingSeek: waiting)
        switch button.effect(in: context, at: now) {
        case .command(let command): send(command)
        case .seek(let seconds): seek(toSeconds: seconds, at: now)
        case .shuffle(let mode): source?.setShuffle(mode)
        case .repeatMode(let mode): source?.setRepeat(mode)
        case .toggleLyrics:
            store.toggleLyricsHidden()
            refreshActivity()
        case nil: break
        }
    }

    private func registerHotkeys(_ hotkeys: ModuleHotkeys) {
        // No defaults: the keyboard's media keys already do this; these are for users who want other keys.
        hotkeys.register("mediaPlayPause", title: "Phát/dừng nhạc") { [weak self] in self?.send(.togglePlayPause) }
        hotkeys.register("mediaNext", title: "Bài sau") { [weak self] in self?.send(.nextTrack) }
        hotkeys.register("mediaPrevious", title: "Bài trước") { [weak self] in self?.send(.previousTrack) }
        hotkeys.register("lyricsPanel", title: "Bật/tắt bảng lời nổi") { [weak self] in self?.lyricsPanel?.toggle() }
    }

    private func receive(_ line: String) {
        let now = Date()
        guard store.apply(line: line, receivedAt: now) else { return }
        evaluate(at: now)
    }

    private func sourceFailed(_ reason: String) {
        context?.logger.error("Now playing stopped: \(reason, privacy: .public)")
        // Commands would only start perl processes that fail like the stream did; a restart makes a new source.
        source = nil
        store.fail(message: Self.blockedMessage)
        policy = ActivityPolicy(pauseGrace: policy.pauseGrace, hiddenBundleIDs: policy.hiddenBundleIDs)
        cancelDeadline()
        refreshActivity()
        updateSpectrum()
        refreshLyrics()
    }

    private func settingsChanged() {
        guard let context else { return }
        applySettings(context.settings)
        evaluate(at: Date())
    }

    private func applySettings(_ settings: ModuleSettings) {
        let keys = MediaSettingsKeys(settings)
        showActivity = settings.value(keys.showActivity)
        policy.pauseGrace = TimeInterval(settings.value(keys.pauseGraceSeconds))
        policy.hiddenBundleIDs = Set(settings.value(keys.hiddenApps))
        realSpectrum = settings.value(keys.realSpectrum)
        lyricsEnabled = settings.value(keys.lyrics)
        lyricsUnderNotch = settings.value(keys.lyricsUnderNotch)
        youtubeCaptionsEnabled = settings.value(keys.youtubeCaptions)
        store.setControlLayout(settings.value(keys.controlButtons))
        store.setKaraokeEnabled(settings.value(keys.karaoke))
        store.setLyricsOn(lyricsEnabled || youtubeCaptionsEnabled)
        updateYouTubeBridge()
    }

    private func evaluate(at now: Date) {
        policy.update(store.state, at: now)
        scheduleDeadline(from: now)
        // The lyrics first: the activity's strip depends on which track's lyrics are in the store.
        refreshLyrics()
        refreshActivity()
        updateSpectrum()
    }

    /// Connecting changes what can be found for the track playing now, so it is looked up again. Losing the sign-in does
    /// not: lyrics already shown stay, and the service stops asking Apple on its own.
    private func appleStatusChanged() {
        let isConnected = appleAccount.status.isConnected
        defer { appleWasConnected = isConnected }
        guard isConnected, !appleWasConnected else { return }
        lyricsTrack = nil
        refreshLyrics()
    }

    /// Asks for lyrics when another track starts while the setting is on; drops them when the setting turns off,
    /// the track has no key (an advertisement, no length) or nothing plays. Position and play-state updates leave
    /// the key as it is, so they never fetch.
    private func refreshLyrics() {
        if let captions = matchedCaptions() {
            showCaptions(captions)
            return
        }
        if shownCaptions != nil {
            // What was fetched for the track was replaced by the captions, so the lookup starts again (from the cache if it can).
            shownCaptions = nil
            lyricsTrack = nil
            show(lyrics: nil)
        }
        let track = lyricsEnabled ? TrackKey(store.state) : nil
        guard track != lyricsTrack else { return }
        lyricsTask?.cancel()
        lyricsTask = nil
        lyricsTrack = track
        lyricsEpoch += 1
        // The lookup is under way before the activity looks at the lyrics, so a strip held for them knows they are coming.
        if let track { fetchLyrics(for: track, mayRetry: true) }
        show(lyrics: nil)
    }

    /// Hands the lyrics to the store and the activity gets its say: its strip exists only while there are synced lyrics
    /// (or is held for a moment while they are on their way).
    private func show(lyrics: [LyricLine]?) {
        store.showLyrics(lyrics)
        refreshActivity()
    }

    private func fetchLyrics(for track: TrackKey, mayRetry: Bool) {
        guard let lyricsService else { return }
        lyricsTask = Task { [weak self] in
            let result = await lyricsService.lyrics(for: track)
            self?.receiveLyrics(result, for: track, mayRetry: mayRetry)
        }
    }

    private func receiveLyrics(_ result: LyricsResult, for track: TrackKey, mayRetry: Bool) {
        // The track may have changed while the answer was on its way.
        guard track == lyricsTrack else { return }
        // The lookup is over: nothing is pending any more, which lets a strip held for it go.
        lyricsTask = nil
        switch result {
        case .synced(let lines):
            show(lyrics: lines)
        case .unavailable(let reason):
            context?.logger.info("Lyrics unavailable: \(reason, privacy: .public)")
            refreshActivity()
            // A rate limit is no verdict on the track: ask once more when lrclib is open again.
            guard mayRetry, let lyricsService, lyricsService.isCoolingDown else { return }
            let epoch = lyricsEpoch
            lyricsService.afterCooldown { [weak self] in
                guard let self, lyricsEpoch == epoch else { return }
                fetchLyrics(for: track, mayRetry: false)
            }
        case .plain:
            store.showUnsyncedLyrics()
            refreshActivity()
        case .instrumental, .notFound:
            refreshActivity()
        }
    }

    // MARK: YouTube captions

    private static let driftLogInterval: TimeInterval = 10

    /// Listens for the Chrome helper only while the setting is on.
    private func updateYouTubeBridge() {
        guard let context else { return }
        guard youtubeCaptionsEnabled else {
            stopYouTubeBridge()
            return
        }
        guard youtubeServer == nil, !youtubeListenFailed else { return }
        let path = youtubeSocketPath ?? YouTubeSocket.path(inStorageDirectory: context.storage.directory)
        let server = YouTubeBridgeServer(socketPath: path, log: youtubeLog) { [weak self] message in self?.receiveYouTube(message) }
        do {
            try server.start()
            youtubeServer = server
            youtubeBridge.listenFailed = false
        } catch {
            youtubeListenFailed = true
            youtubeBridge.listenFailed = true
            context.logger.error("Cannot listen for YouTube captions: \(String(describing: error), privacy: .public)")
        }
    }

    /// Closes the socket and forgets everything the extension sent. Runs with every change of a setting, so it assigns
    /// only what is not already so: the Settings rows watch these.
    private func stopYouTubeBridge() {
        youtubeServer?.stop()
        youtubeServer = nil
        dropUnansweredSkips()
        youtubeListenFailed = false
        if youtubeBridge.listenFailed { youtubeBridge.listenFailed = false }
        if youtubeBridge.lastPageMessageAt != nil { youtubeBridge.lastPageMessageAt = nil }
        if youtubeBridge.accessWithheld { youtubeBridge.accessWithheld = false }
        captionStore.removeAll()
        loggedMatchDecision = nil
        lastDriftLoggedAt = nil
    }

    /// What the helper passed on. Ignored while the setting is off, as a message still on its way when it was switched
    /// off would be.
    func receiveYouTube(_ message: YouTubeMessage, at now: Date = Date()) {
        guard youtubeCaptionsEnabled else { return }
        captionStore.apply(message, at: now)
        if message.isFromPage {
            youtubeBridge.lastPageMessageAt = now
            // The page is sending, so Chrome lets the extension read YouTube, whatever was reported before: the notice
            // would otherwise stay when Chrome gives the access without telling the extension.
            if youtubeBridge.accessWithheld { youtubeBridge.accessWithheld = false }
        }
        // A diagnostic decides nothing about lyrics; the service worker's says whether Chrome lets the extension read YouTube.
        if case .diag(let diag) = message {
            if let answer = diag.commandAnswer { commandAnswered(answer) }
            if let access = diag.siteAccess, youtubeBridge.accessWithheld != (access == .withheld) {
                youtubeBridge.accessWithheld = access == .withheld
            }
            return
        }
        refreshLyrics()
        logDrift(of: message, at: now)
    }

    /// The captions for the track playing now, nil while the setting is off or nothing fits. A decision is logged
    /// when it changes, with the rule that failed and never a title.
    private func matchedCaptions() -> YouTubeCaptionStore.Track? {
        guard youtubeCaptionsEnabled else { return nil }
        let decision = YouTubeCaptionMatcher.decision(for: store.state, in: captionStore, now: Date(), keeping: shownCaptions?.videoID)
        let line: String
        switch decision {
        case .matched: line = "match matched"
        case .notMatched(let reason): line = "match not-matched reason=\(reason.rawValue)"
        }
        if line != loggedMatchDecision {
            loggedMatchDecision = line
            youtubeLog(line)
        }
        return decision.track
    }

    /// How far the extension's clock is from the notch's, when a playback of the video whose captions are shown arrives:
    /// the video's time minus the position the system's now-playing clock gives at that moment (positive: the video is
    /// ahead of the notch). It tells whether the clock or the lyric source is off. At most one line every 10 s.
    private func logDrift(of message: YouTubeMessage, at now: Date) {
        guard case .playback(let playback) = message, playback.videoID == shownCaptions?.videoID,
              let position = store.position(at: now) else { return }
        if let last = lastDriftLoggedAt, now.timeIntervalSince(last) < Self.driftLogInterval { return }
        lastDriftLoggedAt = now
        youtubeLog("playback " + String(format: "drift=%+.2fs", playback.time - position))
    }

    /// The captions win over lyrics from the web: a lookup still going is stopped, and one that was shown is replaced.
    private func showCaptions(_ captions: YouTubeCaptionStore.Track) {
        if lyricsTrack != nil {
            lyricsTask?.cancel()
            lyricsTask = nil
            lyricsTrack = nil
            lyricsEpoch += 1
        }
        guard shownCaptions?.videoID != captions.videoID || shownCaptions?.revision != captions.revision else { return }
        shownCaptions = (captions.videoID, captions.revision)
        show(lyrics: captions.lines)
    }

    /// The tap runs only while the setting is on, something plays and some bars are on screen.
    private func updateSpectrum() {
        spectrumFeed?.update(isEnabled: realSpectrum, isPlaying: store.state.isPlaying, isShown: store.spectrumViewCount > 0)
    }

    /// One timer for the policy's next deadline (end of the pause grace or of the track-change debounce).
    private func scheduleDeadline(from now: Date) {
        guard policy.nextDeadline != scheduledDeadline else { return }
        cancelDeadline()
        guard let deadline = policy.nextDeadline, let context else { return }
        scheduledDeadline = deadline
        // Whole milliseconds, so a 5 s grace is exactly 5 s rather than a hair over it after floating-point math.
        let delay = Duration.milliseconds(Int64((max(deadline.timeIntervalSince(now), 0) * 1000).rounded()))
        deadlineTimer = context.scheduler.schedule(after: delay) { [weak self] in self?.deadlineReached(deadline) }
    }

    private func deadlineReached(_ deadline: Date) {
        deadlineTimer = nil
        scheduledDeadline = nil
        // The timer may fire a little early after rounding; the deadline itself is when the policy expects the tick.
        let now = max(Date(), deadline)
        policy.tick(at: now)
        scheduleDeadline(from: now)
        refreshActivity()
    }

    private func cancelDeadline() {
        deadlineTimer?.cancel()
        deadlineTimer = nil
        scheduledDeadline = nil
    }

    /// On offer while the policy shows playback, whatever the live activity setting says: the lock screen module
    /// has its own switch for Media.
    private func refreshLockScreen(_ context: ModuleContext) {
        guard policy.visible != lockScreenOffered else { return }
        lockScreenOffered = policy.visible
        if lockScreenOffered {
            context.lockScreen.set(AnyView(NowPlayingLockScreenView(store: store)), priority: .normal)
        } else {
            context.lockScreen.clear()
        }
    }

    /// Lyrics for the current track may still arrive: a lookup is out, the next track has not shown up yet, or captions
    /// from the Chrome extension may still come.
    private var lyricsArePending: Bool {
        lyricsTask != nil || !store.state.isActive || (youtubeCaptionsEnabled && shownCaptions == nil)
    }

    /// Whether the activity carries the strip: the setting is on and the track plays with synced lyrics, from whichever
    /// source (a paused track has no line being sung). Once up it also stays through a track change (up to 3 s, while
    /// the new lyrics are looked up) and a stall of playback (up to 1 s), so the notch does not collapse and grow again.
    private func updateStripHold() -> Bool {
        stripHold.update(
            LyricStripHold.Inputs(
                enabled: lyricsUnderNotch && !store.lyricsHidden, playing: store.state.isPlaying,
                hasLyrics: store.syncedLyrics?.isEmpty == false, lyricsPending: lyricsArePending
            ),
            at: Date()
        )
        scheduleStripHold()
        return stripHold.isShown
    }

    /// One timer for the end of the hold, like the policy's deadline.
    private func scheduleStripHold() {
        guard stripHold.nextDeadline != scheduledStripDeadline else { return }
        cancelStripHold()
        guard let deadline = stripHold.nextDeadline, let context else { return }
        scheduledStripDeadline = deadline
        let delay = Duration.milliseconds(Int64((max(deadline.timeIntervalSince(Date()), 0) * 1000).rounded()))
        stripHoldTimer = context.scheduler.schedule(after: delay) { [weak self] in self?.stripHoldEnded(at: deadline) }
    }

    private func stripHoldEnded(at deadline: Date) {
        stripHoldTimer = nil
        scheduledStripDeadline = nil
        stripHold.tick(at: max(Date(), deadline))
        refreshActivity()
    }

    private func cancelStripHold() {
        stripHoldTimer?.cancel()
        stripHoldTimer = nil
        scheduledStripDeadline = nil
    }

    private func resetStripHold() {
        stripHold = LyricStripHold()
        cancelStripHold()
    }

    /// Sets the activity when it becomes visible, another track starts or its strip comes or goes; clears it when it
    /// hides; nothing else, so frequent position updates neither redraw nor reorder it.
    private func refreshActivity() {
        guard let context else { return }
        refreshLockScreen(context)
        guard showActivity, policy.visible else {
            if publishedTrack != nil {
                context.activities.clear(id: Self.activityID)
                publishedTrack = nil
                publishedStrip = false
            }
            resetStripHold()
            return
        }
        let track = store.state.trackIdentity
        // Before the guard below: the hold starts at the track change, while the state is still empty.
        let strip = updateStripHold()
        // While a track change is debounced the state is briefly empty: an activity already up keeps showing
        // the last track (the store's snapshot), and none is published until a track is there to show.
        guard store.state.isActive, publishedTrack == nil || track != publishedTrack || strip != publishedStrip else { return }
        context.activities.set(LiveActivity(
            id: Self.activityID,
            priority: .normal,
            leading: AnyView(NowPlayingActivityArtwork(store: store)),
            trailing: AnyView(NowPlayingBars(store: store)),
            bottom: strip ? AnyView(NowPlayingLyricStrip(store: store)) : nil,
            bottomHeight: strip ? NowPlayingLyricStrip.height : 0
        ))
        publishedTrack = track
        publishedStrip = strip
    }
}
