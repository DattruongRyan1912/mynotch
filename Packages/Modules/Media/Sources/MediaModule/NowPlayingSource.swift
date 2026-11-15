/// Where now-playing JSON lines come from and where playback commands go.
/// A protocol so tests (or an AppleScript fallback if Apple blocks the adapter) can replace `AdapterProcess`.
protocol NowPlayingSource: AnyObject {
    /// Delivers adapter `stream` lines on the main actor until `stop()`.
    /// `onFailure` means the source gave up; no lines follow it.
    func start(onLine: @escaping @MainActor (String) -> Void, onFailure: @escaping @MainActor (String) -> Void)
    func stop()
    func send(_ command: MediaCommand)
    func seek(toSeconds seconds: Double)
    func setShuffle(_ mode: ShuffleMode)
    func setRepeat(_ mode: RepeatMode)
    /// Whether `send(.likeTrack)` does anything. The vendored adapter's `send` accepts only the commands 0 to 13, which have
    /// no like (its source says so), so the real source is false until it is updated.
    var canLike: Bool { get }
}

/// MediaRemote command IDs accepted by the adapter's `send` (README "send COMMAND").
nonisolated enum MediaCommand: Int, Sendable {
    case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    /// MediaRemote's like (0x6A); the player toggles it.
    case likeTrack = 106
}
