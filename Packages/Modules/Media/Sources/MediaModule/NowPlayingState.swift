import Foundation

/// What the system reports as now playing, reduced from the adapter's JSON payloads.
nonisolated struct NowPlayingState: Equatable, Sendable {
    var bundleIdentifier: String?
    /// The app that owns `bundleIdentifier` when a helper process plays (e.g. a browser's media helper).
    var parentApplicationBundleIdentifier: String?
    var title: String?
    var artist: String?
    var album: String?
    var durationSeconds: Double?
    /// Elapsed time sampled by the player; the current position is extrapolated from it by `PlaybackClock`.
    var elapsedAnchor: PlaybackAnchor?
    var isPlaying = false
    var artwork: ArtworkData?
    var uniqueIdentifier: String?
    var contentItemIdentifier: String?
    var isAdvertisement = false

    static let empty = NowPlayingState()

    /// A player is reporting a track; the adapter treats media without a title as invalid.
    var isActive: Bool { !(bundleIdentifier ?? "").isEmpty && !(title ?? "").isEmpty }

    /// Changes only when another track starts, so views re-publish once per track instead of on every update.
    var trackIdentity: TrackIdentity {
        TrackIdentity(
            bundleIdentifier: bundleIdentifier, parentApplicationBundleIdentifier: parentApplicationBundleIdentifier,
            title: title, artist: artist, album: album,
            uniqueIdentifier: uniqueIdentifier, contentItemIdentifier: contentItemIdentifier
        )
    }
}

nonisolated struct TrackIdentity: Hashable, Sendable {
    var bundleIdentifier: String?
    var parentApplicationBundleIdentifier: String?
    var title: String?
    var artist: String?
    var album: String?
    var uniqueIdentifier: String?
    var contentItemIdentifier: String?
}

/// Playback position `elapsedSeconds` at `timestamp`, advancing at `rate` (0 while paused).
nonisolated struct PlaybackAnchor: Equatable, Sendable {
    var elapsedSeconds: Double
    var timestamp: Date
    var rate: Double
}

/// Raw cover image bytes; `revision` changes whenever the bytes do, so the image is decoded once per change.
nonisolated struct ArtworkData: Equatable, Sendable {
    var data: Data
    var mimeType: String?
    var revision: Int
}
