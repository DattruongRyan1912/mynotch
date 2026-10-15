import AppKit
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
    /// A lyrics source (lrclib and Apple, or YouTube captions) is turned on. The lyric row then keeps its place under
    /// the controls while there is nothing to show in it yet, so the player does not move as lyrics come and go.
    private(set) var lyricsAreOn = false
    /// The user hid the lyrics with the row's button: neither the row nor the strip under the notch shows them, until it is
    /// pressed again. For as long as the app runs; it is no setting.
    private(set) var lyricsHidden = false

    /// The buttons beside play and pause; the setting's value, set by the module.
    private(set) var controlLayout = MediaControlLayout.standard
    /// The source can send a like; set by the module from the source it runs.
    private(set) var canLike = false

    @ObservationIgnored private var reducer = NowPlayingReducer()
    @ObservationIgnored private let lookUpApp: @MainActor (String) -> PlayerApp?
    /// Revision of `artworkImage`'s bytes; the image is decoded only when it changes.
    @ObservationIgnored private var artworkRevision: Int?
    /// Bundle IDs `appName`/`appIcon` were looked up for, so position updates skip the lookup.
    @ObservationIgnored private var appBundleIDs: [String] = []

    init(lookUpApp: @escaping @MainActor (String) -> PlayerApp? = PlayerApp.installed) {
        self.lookUpApp = lookUpApp
    }

    /// Folds one adapter line in; false when the line was ignored and nothing changed.
    @discardableResult
    func apply(line: String, receivedAt: Date) -> Bool {
        guard reducer.apply(line: line, receivedAt: receivedAt) == .applied else { return false }
        update(reducer.state)
        return true
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
        update(.empty)
        showInActivity(artwork: nil, icon: nil, isPlaying: false)
        showLyrics(nil)
        if failureMessage != nil { failureMessage = nil }
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
        if lyricsAreUnsynced { lyricsAreUnsynced = false }
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

    /// Called by each bars view as it appears and disappears.
    func spectrumViewAppeared() {
        spectrumViewCount += 1
    }

    func spectrumViewDisappeared() {
        spectrumViewCount = max(spectrumViewCount - 1, 0)
    }

    private func update(_ newState: NowPlayingState) {
        if newState != state { state = newState }
        if newState.artwork?.revision != artworkRevision {
            artworkRevision = newState.artwork?.revision
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
