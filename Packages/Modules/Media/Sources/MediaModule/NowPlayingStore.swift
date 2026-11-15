import AppKit
import MyNotchCore
import Observation

/// What the media views show: the reduced adapter state plus the decoded artwork and the playing app.
/// Views read it directly, so the live activity is published once per track instead of on every update.
@Observable
final class NowPlayingStore {
    private(set) var state = NowPlayingState.empty
    private(set) var artworkImage: NSImage?
    private(set) var appName: String?
    private(set) var appIcon: NSImage?
    /// Set when the source gave up; the tab shows it instead of the player.
    private(set) var failureMessage: String?

    // What the closed-notch activity shows: the current track, or the last active one while the state is empty.
    // A track change empties the state for up to 300 ms while the activity stays up; it must not flash the
    // placeholder or stop the bars meanwhile. Separate properties, so the bars observe only `activityIsPlaying`.
    private(set) var activityArtwork: NSImage?
    private(set) var activityAppIcon: NSImage?
    private(set) var activityIsPlaying = false

    /// Levels from the system audio tap (0…1, low to high) while it runs; nil keeps the bars' made-up motion. Not observable: the
    /// bars follow it through `observeSpectrum`, so a set of levels every 33 ms never invalidates a SwiftUI view.
    @ObservationIgnored private(set) var spectrumBands: [Float]?
    @ObservationIgnored private var spectrumObservers: [Int: @MainActor ([Float]?) -> Void] = [:]
    @ObservationIgnored private var nextSpectrumObserverID = 0
    /// The tap has heard only silence while music played: the Settings rows explain how to grant the permission.
    private(set) var spectrumPermissionLikelyDenied = false
    /// Bars on screen right now (beside the notch, in the tab, one per screen); the tap only runs while there are some.
    private(set) var spectrumViewCount = 0

    /// Synced lyrics of the current track; nil while there are none (lyrics off, still fetching, no entry, unsynced).
    private(set) var syncedLyrics: [LyricLine]?
    /// lrclib has the words of the current track but no timing: the lyric row says so instead of following along.
    private(set) var lyricsAreUnsynced = false
    /// Some line of the synced lyrics has the timing of its words (Apple Music's syllable lyrics, enhanced LRC).
    private(set) var lyricsHaveWordTiming = false
    /// The user wants the sung part of a line filled word by word ("Tô theo từng chữ"); the setting's value, set by the module.
    private(set) var karaokeEnabled = true
    /// The floating lyrics panel is up; set by the module from its setting, which the Media tab's button flips.
    private(set) var lyricsPanelShown = false
    /// A lyrics source (lrclib and Apple, or YouTube captions) is turned on. The lyric row then keeps its place under
    /// the controls while there is nothing to show in it yet, so the player does not move as lyrics come and go.
    private(set) var lyricsAreOn = false
    /// The user hid the lyrics with the row's button: neither the row nor the strip under the notch shows them, until it is
    /// pressed again. For as long as the app runs; it is no setting.
    private(set) var lyricsHidden = false

    /// The colours of the current cover, once they are worked out; nil while they are not, and for a track with no cover. They are
    /// the tint, and change once per track, so views may read them.
    private(set) var tint: ArtworkPalette?
    /// "Màu theo ảnh bìa": the player's progress bar, glow and (in the cover's mode) the bars use `tint`; the setting's value.
    private(set) var tintEnabled = true
    private(set) var spectrumMode = SpectrumColorMode.artwork
    private(set) var spectrumGradientStart = SpectrumColorMode.defaultStart
    private(set) var spectrumGradientEnd = SpectrumColorMode.defaultEnd

    /// The buttons beside play and pause; the setting's value, set by the module.
    private(set) var controlLayout = MediaControlLayout.standard
    /// The source can send a like; set by the module from the source it runs.
    private(set) var canLike = false

    @ObservationIgnored private var reducer = NowPlayingReducer()
    @ObservationIgnored private let lookUpApp: @MainActor (String) -> PlayerApp?
    /// What moves every bars view of this store; made as the first one is.
    @ObservationIgnored private(set) lazy var barsHub = SpectrumBarsHub(store: self, scheduler: barsScheduler, now: barsClock)
    @ObservationIgnored private let barsScheduler: any Scheduler
    @ObservationIgnored private let barsClock: () -> Date
    /// Which source the cover came from and its revision there; the image is decoded only when either changes. A revision counts
    /// per source (the adapter's, an app's), so the same number from another source is another image.
    @ObservationIgnored private var artworkStamp: ArtworkStamp?
    /// Bundle IDs `appName`/`appIcon` were looked up for, so position updates skip the lookup.
    @ObservationIgnored private var appBundleIDs: [String] = []

    /// `scheduler` and `now` are the clock of the bars' driver, which tests move by hand.
    init(
        lookUpApp: @escaping @MainActor (String) -> PlayerApp? = PlayerApp.installed,
        scheduler: any Scheduler = TaskScheduler(), now: @escaping () -> Date = Date.init
    ) {
        self.lookUpApp = lookUpApp
        barsScheduler = scheduler
        barsClock = now
    }

    /// Folds one adapter line in; false when the line was ignored and nothing changed.
    @discardableResult
    func apply(line: String, receivedAt: Date) -> Bool {
        guard reducer.apply(line: line, receivedAt: receivedAt) == .applied else { return false }
        update(reducer.state, source: "adapter")
        return true
    }

    /// Shows what a source reports, when the module works out the sources itself and this store only shows one of them: the primary
    /// source of the notch, or the one the player shows. `source` names where the state, and the revision of its cover, come from.
    /// False when the state is the one already shown.
    @discardableResult
    func show(_ newState: NowPlayingState, source: String) -> Bool {
        let changed = newState != state
        update(newState, source: source)
        if failureMessage != nil { failureMessage = nil }
        return changed
    }

    /// Seconds into the track at `date`, extrapolated between adapter updates.
    func position(at date: Date) -> Double? {
        PlaybackClock.position(state, at: date)
    }

    /// Forgets playback after the source gave up; no lines follow, so the old track would be stale.
    func fail(message: String) {
        reset()
        failureMessage = message
    }

    /// Back to nothing playing, for a fresh start of the source.
    func reset() {
        reducer = NowPlayingReducer()
        update(.empty, source: "adapter")
        showInActivity(artwork: nil, icon: nil, isPlaying: false)
        showLyrics(nil)
        showTint(nil)
        if failureMessage != nil { failureMessage = nil }
    }

    /// What the player's views tint with: `tint` while the setting is on.
    var activeTint: ArtworkPalette? { tintEnabled ? tint : nil }

    /// The colour of each bar by the user's choice, nil while the bars should keep their own colour. Not observable, like
    /// `spectrumBands`: the bars are layers that read it as they are made and follow it through `observeSpectrumColors`. SwiftUI
    /// evaluates a representable's `makeNSView` with its reads tracked, so an observable value read there would make the whole
    /// notch lay out again at every new cover.
    @ObservationIgnored private(set) var spectrumColors: [SRGBColor]?
    @ObservationIgnored private var spectrumColorObservers: [Int: @MainActor ([SRGBColor]?) -> Void] = [:]

    func showTint(_ palette: ArtworkPalette?) {
        guard palette != tint else { return }
        tint = palette
        refreshSpectrumColors()
    }

    func setTintEnabled(_ isEnabled: Bool) {
        guard isEnabled != tintEnabled else { return }
        tintEnabled = isEnabled
        refreshSpectrumColors()
    }

    func setSpectrumColors(mode: SpectrumColorMode, start: SRGBColor, end: SRGBColor) {
        if mode != spectrumMode { spectrumMode = mode }
        if start != spectrumGradientStart { spectrumGradientStart = start }
        if end != spectrumGradientEnd { spectrumGradientEnd = end }
        refreshSpectrumColors()
    }

    /// Calls `observer` with every change of `spectrumColors`, until the returned closure is called.
    func observeSpectrumColors(_ observer: @escaping @MainActor ([SRGBColor]?) -> Void) -> () -> Void {
        let id = nextSpectrumObserverID
        nextSpectrumObserverID += 1
        spectrumColorObservers[id] = observer
        return { [weak self] in self?.spectrumColorObservers[id] = nil }
    }

    private func refreshSpectrumColors() {
        let colors = spectrumMode.colors(count: NowPlayingBars.barCount, tint: activeTint, start: spectrumGradientStart, end: spectrumGradientEnd)
        guard colors != spectrumColors else { return }
        spectrumColors = colors
        for observer in spectrumColorObservers.values { observer(colors) }
    }

    /// Assigns only real changes: the bars redraw for every assignment, about 30 times a second.
    func showSpectrum(_ bands: [Float]?) {
        guard bands != spectrumBands else { return }
        spectrumBands = bands
        for observer in spectrumObservers.values { observer(bands) }
    }

    /// Calls `observer` with every change of `spectrumBands`, until the returned closure is called.
    func observeSpectrum(_ observer: @escaping @MainActor ([Float]?) -> Void) -> () -> Void {
        let id = nextSpectrumObserverID
        nextSpectrumObserverID += 1
        spectrumObservers[id] = observer
        return { [weak self] in self?.spectrumObservers[id] = nil }
    }

    func setSpectrumPermissionLikelyDenied(_ likelyDenied: Bool) {
        if likelyDenied != spectrumPermissionLikelyDenied { spectrumPermissionLikelyDenied = likelyDenied }
    }

    /// Assigns only a real change, so the lyric row is redrawn only for new lyrics.
    func showLyrics(_ lines: [LyricLine]?) {
        if lines != syncedLyrics { syncedLyrics = lines }
        let hasWords = lines?.contains { $0.words != nil } ?? false
        if hasWords != lyricsHaveWordTiming { lyricsHaveWordTiming = hasWords }
        if lyricsAreUnsynced { lyricsAreUnsynced = false }
    }

    /// Lines are filled word by word: the setting is on and the lyrics have the timing for it. Lines without word timing are
    /// shown as they always were, whatever this says.
    var karaokeIsActive: Bool { karaokeEnabled && lyricsHaveWordTiming }

    func setKaraokeEnabled(_ isEnabled: Bool) {
        if isEnabled != karaokeEnabled { karaokeEnabled = isEnabled }
    }

    func setLyricsPanelShown(_ isShown: Bool) {
        if isShown != lyricsPanelShown { lyricsPanelShown = isShown }
    }

    func showUnsyncedLyrics() {
        showLyrics(nil)
        lyricsAreUnsynced = true
    }

    func setLyricsOn(_ isOn: Bool) {
        if isOn != lyricsAreOn { lyricsAreOn = isOn }
    }

    func toggleLyricsHidden() {
        lyricsHidden.toggle()
    }

    func setLyricsHidden(_ hidden: Bool) {
        if lyricsHidden != hidden {
            lyricsHidden = hidden
        }
    }

    func setControlLayout(_ layout: MediaControlLayout) {
        if layout != controlLayout { controlLayout = layout }
    }

    func setCanLike(_ canLike: Bool) {
        if canLike != self.canLike { self.canLike = canLike }
    }

    /// What the buttons look at: the track, the lyrics and the source, and what only the row knows of the volume.
    func controlContext(hasVolume: Bool, volumeIsOpen: Bool, pendingSeek: Double? = nil) -> MediaControlContext {
        MediaControlContext(
            state: state, lyricsAreOn: lyricsAreOn, lyricsHidden: lyricsHidden, canLike: canLike,
            hasVolume: hasVolume, volumeIsOpen: volumeIsOpen, pendingSeek: pendingSeek
        )
    }

    /// What the lyric row under the controls holds now. Hidden lyrics leave the row empty but in its place, so the player does
    /// not move under the pointer when the button is pressed.
    var lyricRow: LyricRow {
        if !lyricsHidden {
            if syncedLyrics != nil { return .synced }
            if lyricsAreUnsynced { return .unsynced }
        }
        return lyricsAreOn ? .reserved : .absent
    }

    /// The lyric line being sung at `date`, by the playback clock; nil before the first line or without lyrics.
    func lyric(at date: Date) -> LyricLine? {
        guard let syncedLyrics, let position = position(at: date) else { return nil }
        return syncedLyrics.line(at: position)
    }

    /// The two lines of the strip under the notch at `date`; nil while the track has no synced lyrics.
    func lyricStrip(at date: Date) -> LyricStrip? {
        guard let syncedLyrics else { return nil }
        return LyricStrip(lines: syncedLyrics, position: position(at: date))
    }

    /// The panel's three lines at `date`; nil while the track has no synced lyrics.
    func lyricPanel(at date: Date) -> LyricPanelLines? {
        guard let syncedLyrics else { return nil }
        return LyricPanelLines(lines: syncedLyrics, position: position(at: date))
    }

    /// Called by each bars view as it appears and disappears.
    func spectrumViewAppeared() {
        spectrumViewCount += 1
    }

    func spectrumViewDisappeared() {
        spectrumViewCount = max(spectrumViewCount - 1, 0)
    }

    private func update(_ newState: NowPlayingState, source: String) {
        if newState != state { state = newState }
        let stamp = newState.artwork.map { ArtworkStamp(source: source, revision: $0.revision) }
        if stamp != artworkStamp {
            artworkStamp = stamp
            artworkImage = newState.artwork.flatMap { NSImage(data: $0.data) }
        }
        // A browser plays through a helper process; its parent is the app the user recognises.
        let bundleIDs = [newState.parentApplicationBundleIdentifier, newState.bundleIdentifier].compactMap { $0 }
        if bundleIDs != appBundleIDs {
            appBundleIDs = bundleIDs
            // A loop, not `lazy.compactMap(_:).first`, which runs the lookup twice for the match.
            var app: PlayerApp?
            for bundleID in bundleIDs where app == nil { app = lookUpApp(bundleID) }
            appName = app?.name
            appIcon = app?.icon
        }
        if newState.isActive { showInActivity(artwork: artworkImage, icon: appIcon, isPlaying: newState.isPlaying) }
    }

    /// Assigns only what changed, so the activity's views redraw only for their own value.
    private func showInActivity(artwork: NSImage?, icon: NSImage?, isPlaying: Bool) {
        if activityArtwork !== artwork { activityArtwork = artwork }
        if activityAppIcon !== icon { activityAppIcon = icon }
        if activityIsPlaying != isPlaying { activityIsPlaying = isPlaying }
    }
}

/// Where a cover came from and which of that source's it is.
private nonisolated struct ArtworkStamp: Equatable, Sendable {
    var source: String
    var revision: Int
}
