import Foundation
import YouTubeBridgeKit

/// Where Next and Previous go for what plays now.
///
/// YouTube clears the Media Session handlers for the next and previous track, so Chrome ignores MediaRemote's next and
/// previous for a video while play, pause and seek still work. The extension can press the player's own buttons instead,
/// when it has a live session for the video the system is playing. Anything else keeps MediaRemote: the app cannot tell
/// which site plays without a session, and Spotify Web or YouTube Music skip through MediaRemote today.
nonisolated enum SkipRoute: Equatable {
    /// The usual way: the command goes to the system's now-playing source.
    case mediaRemote
    /// The command goes to the Chrome extension, which presses the player's button.
    case bridge

    /// The extension counts as live while the page has said anything (a playback, captions or the content script's
    /// heartbeat) this recently. The page sends a playback every 5 s while it plays and a heartbeat every 30 s whatever it
    /// does, but a tab that has been in the background for minutes may be let run only about once a minute.
    static let liveWindow: TimeInterval = 75

    /// How long the app waits for the extension to answer a command before it uses MediaRemote for that press.
    static let answerTimeout: Duration = .seconds(1)

    /// How long after a skip the extension took the title of what plays may differ from the extension's. YouTube changes
    /// the page's title and Chrome's now-playing title one to three seconds after the click, each at its own moment.
    static let titleChangeWindow: TimeInterval = 5

    /// A next or previous that went to the extension: the title it will change is the skip's doing, not another video's.
    struct BridgedSkip: Equatable {
        var at: Date
        /// The app that played it (`NowPlayingState.playerBundleIdentifier`).
        var player: String?
    }

    /// The route for the track `state` describes, given what the extension has sent: the bridge for a live session that
    /// belongs to the track, MediaRemote otherwise. Right after a `skip` the extension took, the session also belongs to
    /// whatever the same player shows next, so a quick second press is not turned away by a title that is changing.
    static func decide(for state: NowPlayingState, in store: YouTubeCaptionStore, now: Date, after skip: BridgedSkip? = nil) -> SkipRoute {
        hasLiveSession(for: state, in: store, now: now, after: skip) ? .bridge : .mediaRemote
    }

    private static func hasLiveSession(for state: NowPlayingState, in store: YouTubeCaptionStore, now: Date, after skip: BridgedSkip?) -> Bool {
        guard let heard = store.lastPageMessageAt, now.timeIntervalSince(heard) <= liveWindow else { return false }
        if case .success = YouTubeCaptionMatcher.playback(for: state, in: store) { return true }
        // The title rule gives way to the player: the one that was skipped, or none for a moment between two videos.
        guard let skip, now.timeIntervalSince(skip.at) <= titleChangeWindow else { return false }
        return state.playerBundleIdentifier == nil || state.playerBundleIdentifier == skip.player
    }
}

nonisolated extension NowPlayingState {
    /// The app the user knows as the player: a browser's media helper counts as the browser.
    var playerBundleIdentifier: String? { parentApplicationBundleIdentifier ?? bundleIdentifier }
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
