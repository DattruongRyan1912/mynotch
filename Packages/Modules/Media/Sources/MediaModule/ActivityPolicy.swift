import Foundation

/// Decides when the now-playing live activity is visible, without flicker on pauses and track changes.
///
/// Time is passed in so the policy stays pure: the module schedules one timer for `nextDeadline`
/// and calls `tick(at:)` when it fires.
nonisolated struct ActivityPolicy: Equatable, Sendable {
    /// Track changes emit brief empty or paused states; hiding waits this long for the next track.
    static let hideDebounce: TimeInterval = 0.3

    /// How long a paused track stays visible.
    var pauseGrace: TimeInterval
    /// Apps whose playback never shows, matched against the bundle ID and the parent app's bundle ID.
    var hiddenBundleIDs: Set<String>
    private var phase = Phase.hidden

    private nonisolated enum Phase: Equatable, Sendable {
        case hidden, playing
        case paused(until: Date)
        case hiding(at: Date)
    }

    init(pauseGrace: TimeInterval = 5, hiddenBundleIDs: Set<String> = []) {
        self.pauseGrace = pauseGrace
        self.hiddenBundleIDs = hiddenBundleIDs
    }

    var visible: Bool { phase != .hidden }

    /// When `tick(at:)` must run next; nil while nothing is pending.
    var nextDeadline: Date? {
        switch phase {
        case .hidden, .playing: nil
        case .paused(let until): until
        case .hiding(let at): at
        }
    }

    mutating func update(_ state: NowPlayingState, at date: Date) {
        if isHiddenApp(state) {
            phase = .hidden
        } else if !state.isActive {
            switch phase {
            case .hidden, .hiding: break
            case .playing: phase = .hiding(at: date + Self.hideDebounce)
            case .paused(let until): phase = .hiding(at: min(until, date + Self.hideDebounce))
            }
        } else if state.isPlaying {
            phase = .playing
        } else {
            switch phase {
            case .hidden, .paused: break
            case .playing, .hiding: phase = .paused(until: date + pauseGrace)
            }
        }
        tick(at: date)
    }

    mutating func tick(at date: Date) {
        if let deadline = nextDeadline, date >= deadline { phase = .hidden }
    }

    private func isHiddenApp(_ state: NowPlayingState) -> Bool {
        [state.bundleIdentifier, state.parentApplicationBundleIdentifier].contains { $0.map(hiddenBundleIDs.contains) ?? false }
    }
}
