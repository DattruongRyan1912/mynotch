import Foundation

/// Extrapolates the playback position between adapter updates, which arrive only when something changes.
nonisolated enum PlaybackClock {
    /// Seconds into the track at `date`, or nil when the player reported no elapsed time.
    /// Never negative, and never past the duration when it is known.
    static func position(_ state: NowPlayingState, at date: Date) -> Double? {
        guard let anchor = state.elapsedAnchor else { return nil }
        let advance = state.isPlaying ? date.timeIntervalSince(anchor.timestamp) * anchor.rate : 0
        return min(max(anchor.elapsedSeconds + advance, 0), state.durationSeconds ?? .infinity)
    }
}
