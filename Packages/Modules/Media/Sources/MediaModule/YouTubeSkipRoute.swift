import Foundation
import YouTubeBridgeKit

/// Where Next and Previous go for what plays now.
///
/// YouTube clears the Media Session handlers for the next and previous track, so Chrome ignores MediaRemote's next and
/// previous for a video while play, pause and seek still work. The extension can press the player's own buttons instead,
/// when it has a live session for the video the system is playing.
nonisolated enum SkipRoute: Equatable {
    /// The usual way: the command goes to the system's now-playing source.
    case mediaRemote
    /// The command goes to the Chrome extension, which presses the player's button.
    case bridge
    /// Chrome plays and the extension that could skip is not talking: neither route would do anything.
    case unavailable

    /// The extension counts as live while the page has said anything (a playback, captions or the content script's
    /// heartbeat) this recently. The page sends a playback every 5 s while it plays and a heartbeat every 30 s whatever it
    /// does, but a tab that has been in the background for minutes may be let run only about once a minute.
    static let liveWindow: TimeInterval = 75

    /// The route for the track `state` describes, given what the extension has sent.
    ///
    /// The extension is for Chrome, so Chrome with no live session is the only case that has no route; any other source,
    /// another browser included, keeps MediaRemote (which may well work for it) and its buttons stay what they were.
    static func decide(for state: NowPlayingState, in store: YouTubeCaptionStore, now: Date) -> SkipRoute {
        guard state.isFromBrowser else { return .mediaRemote }
        if hasLiveSession(for: state, in: store, now: now) { return .bridge }
        return state.isFromChrome ? .unavailable : .mediaRemote
    }

    private static func hasLiveSession(for state: NowPlayingState, in store: YouTubeCaptionStore, now: Date) -> Bool {
        guard case .success = YouTubeCaptionMatcher.playback(for: state, in: store), let heard = store.lastPageMessageAt else { return false }
        return now.timeIntervalSince(heard) <= liveWindow
    }
}

nonisolated extension NowPlayingState {
    /// Chrome plays this, or one of its helper processes does.
    var isFromChrome: Bool {
        [bundleIdentifier, parentApplicationBundleIdentifier].compactMap { $0 }.contains { $0.hasPrefix("com.google.Chrome") }
    }
}

nonisolated extension MediaCommand {
    /// What the extension is asked instead of MediaRemote: only next and previous have such a command.
    var youTubeCommand: YouTubeCommand? {
        switch self {
        case .nextTrack: .next
        case .previousTrack: .previous
        case .play, .pause, .togglePlayPause: nil
        }
    }
}
