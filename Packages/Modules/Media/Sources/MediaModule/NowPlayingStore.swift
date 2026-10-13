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
        if failureMessage != nil { failureMessage = nil }
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
