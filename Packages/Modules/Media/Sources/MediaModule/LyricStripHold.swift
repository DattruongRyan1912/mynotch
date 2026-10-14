import Foundation

/// Decides when the lyric strip under the notch is on offer, so that a skip, a seek or a buffering stall does not
/// make the notch shrink and grow again: once up, the strip stays through a short gap in its own conditions.
///
/// Time is passed in so the type stays pure: the module schedules one timer for `nextDeadline` and calls `tick(at:)`
/// when it fires.
nonisolated struct LyricStripHold: Equatable, Sendable {
    /// How long the strip waits for the next track's lyrics before it goes away.
    static let trackChangeHold: TimeInterval = 3
    /// How long it waits through playback stopping for a moment (a seek, buffering) while the lyrics stay.
    static let stallHold: TimeInterval = 1

    struct Inputs: Equatable, Sendable {
        /// The user wants the strip.
        var enabled: Bool
        var playing: Bool
        /// Synced lyrics for the current track are there.
        var hasLyrics: Bool
        /// Lyrics for the current track may still arrive: a lookup is out, or the next track has not shown up yet.
        var lyricsPending: Bool
    }

    /// Whether the activity carries the strip.
    private(set) var isShown = false
    /// When the hold runs out; nil while the strip's conditions are met or nothing is held.
    private(set) var nextDeadline: Date?
    /// When the strip's conditions were first lost; the hold is measured from here, not from later updates.
    private var heldSince: Date?

    mutating func update(_ inputs: Inputs, at now: Date) {
        guard inputs.enabled else {
            release()
            return
        }
        if inputs.playing, inputs.hasLyrics {
            isShown = true
            heldSince = nil
            nextDeadline = nil
            return
        }
        guard isShown else { return }
        // Without lyrics there is only something to wait for while they may still come: a lookup that ended empty
        // releases the strip at once, so a track without lyrics collapses once.
        guard inputs.hasLyrics || inputs.lyricsPending else {
            release()
            return
        }
        let since = heldSince ?? now
        heldSince = since
        nextDeadline = since + (inputs.hasLyrics ? Self.stallHold : Self.trackChangeHold)
        tick(at: now)
    }

    mutating func tick(at now: Date) {
        if let deadline = nextDeadline, now >= deadline { release() }
    }

    private mutating func release() {
        isShown = false
        heldSince = nil
        nextDeadline = nil
    }
}
