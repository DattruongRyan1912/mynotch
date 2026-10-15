import Foundation

/// What the sweep of a line needs of the player: where the playback clock is and how fast it runs. Equal clocks mean the same
/// timeline, so a view that is handed the same one again leaves its running animation alone.
nonisolated struct KaraokeClock: Equatable, Sendable {
    var anchor: PlaybackAnchor?
    var isPlaying: Bool
    var duration: Double?

    init(_ state: NowPlayingState) {
        anchor = state.elapsedAnchor
        isPlaying = state.isPlaying
        duration = state.durationSeconds
    }

    /// Seconds into the track at `date`, as `PlaybackClock` says; nil without an anchor.
    func position(at date: Date) -> Double? {
        PlaybackClock.position(NowPlayingState(durationSeconds: duration, elapsedAnchor: anchor, isPlaying: isPlaying), at: date)
    }

    /// Seconds of track per second of wall clock: the anchor's rate while playing, 0 otherwise.
    var rate: Double { isPlaying ? (anchor?.rate ?? 0) : 0 }
}
