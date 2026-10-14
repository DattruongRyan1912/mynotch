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

    init(_ settings: ModuleSettings) {
        showActivity = settings.key("showActivity", default: true)
        pauseGraceSeconds = settings.key("pauseGraceSeconds", default: 5, clampedTo: Self.pauseGraceRange)
        hiddenApps = settings.key("hiddenApps", default: [])
        realSpectrum = settings.key("realSpectrum", default: false)
        lyrics = settings.key("lyrics", default: false)
        youtubeCaptions = settings.key("youtubeCaptions", default: false)
    }
}

/// What the tab's controls do, without handing the views the module or the source.
struct MediaActions {
    var send: (MediaCommand) -> Void
    var seek: (Double) -> Void
}

/// Now playing from any app: a live activity while music plays and a "Media" tab with the player controls.
public final class MediaModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "media",
        displayName: "Media",
        systemImage: "music.note",
        defaultEnabled: true,
        order: 200
    )

    static let activityID = "nowPlaying"
    static let blockedMessage = "Không đọc được thông tin phát nhạc (macOS đã chặn adapter)"

    let store: NowPlayingStore
    /// nil when the app was built without the adapter; `start` then reports the module unavailable.
    private let makeSource: ((any Scheduler) -> any NowPlayingSource)?
    private let spectrum: any SpectrumSource
    private let lyricsClient: any HTTPClient
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
    /// Whether the lock screen view is on offer; its view reads `store`, so it is set once and cleared once.
    private var lockScreenOffered = false
    private var deadlineTimer: ScheduledAction?
    private var scheduledDeadline: Date?

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
                signIn: AppleMusicLoginWindow()
            )
        } else {
            self.init(
                makeSource: nil, spectrum: spectrum, lyricsClient: URLSessionHTTPClient(),
                tokens: KeychainTokenStore(), signIn: AppleMusicLoginWindow()
            )
        }
    }

    /// For tests: lines come from `source` instead of perl, levels from `spectrum` instead of a system audio tap,
    /// lyrics from `lyricsClient` instead of lrclib.net and Apple, the sign-in from `tokens` instead of the Keychain,
    /// the sign-in window is `signIn`. No defaults for those, so no test reaches the network or the Keychain by accident.
    convenience init(
        source: any NowPlayingSource,
        spectrum: any SpectrumSource,
        lyricsClient: any HTTPClient,
        tokens: any TokenStore,
        signIn: any AppleMusicSignIn,
        lookUpApp: @escaping @MainActor (String) -> PlayerApp? = PlayerApp.installed,
        youtubeSocketPath: String? = nil,
        youtubeSetup: YouTubeBridgeSetup? = nil,
        youtubeLog: YouTubeBridgeLog = .silent
    ) {
        self.init(
            makeSource: { _ in source }, spectrum: spectrum, lyricsClient: lyricsClient,
            tokens: tokens, signIn: signIn, lookUpApp: lookUpApp, youtubeSocketPath: youtubeSocketPath, youtubeSetup: youtubeSetup,
            youtubeLog: youtubeLog
        )
    }

    private init(
        makeSource: ((any Scheduler) -> any NowPlayingSource)?,
        spectrum: any SpectrumSource,
        lyricsClient: any HTTPClient,
        tokens: any TokenStore,
        signIn: any AppleMusicSignIn,
        lookUpApp: @escaping @MainActor (String) -> PlayerApp? = PlayerApp.installed,
        youtubeSocketPath: String? = nil,
        youtubeSetup: YouTubeBridgeSetup? = nil,
        youtubeLog: YouTubeBridgeLog = .system
    ) {
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
        context.run { [weak self] in
            let changes = Observations {
                (
                    settings.value(keys.showActivity), settings.value(keys.pauseGraceSeconds),
                    settings.value(keys.hiddenApps), settings.value(keys.realSpectrum), settings.value(keys.lyrics),
                    settings.value(keys.youtubeCaptions)
                )
            }
            for await _ in changes { self?.settingsChanged() }
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
        source.start(
            onLine: { [weak self] line in self?.receive(line) },
            onFailure: { [weak self] reason in self?.sourceFailed(reason) }
        )
    }

    public func stop() async {
        source?.stop()
        source = nil
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
        lockScreenOffered = false
        store.reset()
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Media", systemImage: "music.note", preferredHeight: 150,
            content: AnyView(MediaTabView(store: store, actions: actions))
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
            seek: { [weak self] seconds in self?.seek(toSeconds: seconds) }
        )
    }

    func send(_ command: MediaCommand) {
        source?.send(command)
    }

    func seek(toSeconds seconds: Double) {
        source?.seek(toSeconds: seconds)
    }

    private func registerHotkeys(_ hotkeys: ModuleHotkeys) {
        // No defaults: the keyboard's media keys already do this; these are for users who want other keys.
        hotkeys.register("mediaPlayPause", title: "Phát/dừng nhạc") { [weak self] in self?.send(.togglePlayPause) }
        hotkeys.register("mediaNext", title: "Bài sau") { [weak self] in self?.send(.nextTrack) }
        hotkeys.register("mediaPrevious", title: "Bài trước") { [weak self] in self?.send(.previousTrack) }
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
        youtubeCaptionsEnabled = settings.value(keys.youtubeCaptions)
        updateYouTubeBridge()
    }

    private func evaluate(at now: Date) {
        policy.update(store.state, at: now)
        scheduleDeadline(from: now)
        refreshActivity()
        updateSpectrum()
        refreshLyrics()
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
            store.showLyrics(nil)
        }
        let track = lyricsEnabled ? TrackKey(store.state) : nil
        guard track != lyricsTrack else { return }
        lyricsTask?.cancel()
        lyricsTask = nil
        lyricsTrack = track
        lyricsEpoch += 1
        store.showLyrics(nil)
        guard let track else { return }
        fetchLyrics(for: track, mayRetry: true)
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
        switch result {
        case .synced(let lines):
            store.showLyrics(lines)
        case .unavailable(let reason):
            context?.logger.info("Lyrics unavailable: \(reason, privacy: .public)")
            // A rate limit is no verdict on the track: ask once more when lrclib is open again.
            guard mayRetry, let lyricsService, lyricsService.isCoolingDown else { return }
            let epoch = lyricsEpoch
            lyricsService.afterCooldown { [weak self] in
                guard let self, lyricsEpoch == epoch else { return }
                fetchLyrics(for: track, mayRetry: false)
            }
        case .plain:
            store.showUnsyncedLyrics()
        case .instrumental, .notFound:
            break
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
        youtubeListenFailed = false
        if youtubeBridge.listenFailed { youtubeBridge.listenFailed = false }
        if youtubeBridge.lastMessageAt != nil { youtubeBridge.lastMessageAt = nil }
        captionStore.removeAll()
        loggedMatchDecision = nil
        lastDriftLoggedAt = nil
    }

    /// What the helper passed on. Ignored while the setting is off, as a message still on its way when it was switched
    /// off would be.
    func receiveYouTube(_ message: YouTubeMessage, at now: Date = Date()) {
        guard youtubeCaptionsEnabled else { return }
        captionStore.apply(message, at: now)
        youtubeBridge.lastMessageAt = now
        // A diagnostic only shows that the extension is there.
        if case .diag = message { return }
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
        store.showLyrics(captions.lines)
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

    /// Sets the activity when it becomes visible or another track starts, clears it when it hides; nothing else,
    /// so frequent position updates neither redraw nor reorder it.
    private func refreshActivity() {
        guard let context else { return }
        refreshLockScreen(context)
        guard showActivity, policy.visible else {
            if publishedTrack != nil {
                context.activities.clear(id: Self.activityID)
                publishedTrack = nil
            }
            return
        }
        let track = store.state.trackIdentity
        // While a track change is debounced the state is briefly empty: an activity already up keeps showing
        // the last track (the store's snapshot), and none is published until a track is there to show.
        guard store.state.isActive, publishedTrack == nil || track != publishedTrack else { return }
        context.activities.set(LiveActivity(
            id: Self.activityID,
            priority: .normal,
            leading: AnyView(NowPlayingActivityArtwork(store: store)),
            trailing: AnyView(NowPlayingBars(store: store))
        ))
        publishedTrack = track
    }
}
