import Foundation

/// What the tab's progress bar shows at one moment. Pure, so the drag and seek handling is testable without views.
nonisolated struct PlaybackProgress: Equatable, Sendable {
    var elapsed: Double?
    var duration: Double?

    init(elapsed: Double?, duration: Double?) {
        self.elapsed = elapsed
        self.duration = duration
    }

    /// The drag in progress if any, else a seek the player has not confirmed yet, else the playback clock.
    init(state: NowPlayingState, at date: Date, dragFraction: Double? = nil, pendingSeek: PendingSeek? = nil) {
        duration = state.durationSeconds
        if let dragFraction, let duration {
            elapsed = min(max(dragFraction, 0), 1) * duration
        } else if let pendingSeek, pendingSeek.isPending(for: state, at: date) {
            elapsed = pendingSeek.seconds
        } else {
            elapsed = PlaybackClock.position(state, at: date)
        }
    }

    /// 0…1 along the bar; 0 while the length or position is unknown (e.g. a live stream).
    var fraction: Double {
        guard let elapsed, let duration, duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    /// The position a drag to `fraction` asks for; nil when the track has no known length to seek in.
    func seconds(atFraction fraction: Double) -> Double? {
        duration.map { min(max(fraction, 0), 1) * $0 }
    }

    var elapsedText: String { elapsed.map(Self.format) ?? "--:--" }

    /// Empty while the length is unknown, so live streams show only the elapsed time.
    var remainingText: String {
        guard let duration else { return "" }
        return "-" + Self.format(duration - (elapsed ?? 0))
    }

    /// `m:ss`, or `h:mm:ss` from one hour.
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let total = Int(max(seconds, 0).rounded(.down))
        let (hours, minutes, rest) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

/// A seek sent to the player. The adapter reports the new position a moment later; until then the bar stays
/// where the user let go instead of snapping back to the old position.
nonisolated struct PendingSeek: Equatable, Sendable {
    /// Players that never confirm a seek fall back to the clock after this long.
    static let timeout: TimeInterval = 2

    var seconds: Double
    /// The player's position report when the seek was sent; a new report means it answered.
    var anchor: PlaybackAnchor?
    var date: Date

    func isPending(for state: NowPlayingState, at date: Date) -> Bool {
        state.elapsedAnchor == anchor && date < self.date + Self.timeout
    }
}
