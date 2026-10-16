import Foundation

/// One tab of a browser, as the extension names it: Chrome's tab number and the connection (one per Chrome profile) it was
/// reported on, since two profiles may use the same tab numbers.
nonisolated struct TabRef: Hashable, Sendable {
    var connection: Int
    var tab: Int
}

/// Which source of sound something is: an app, or one tab of a browser. It stays the same for as long as the source lives, whoever
/// reports it: what the system says is playing is given the id of the app or tab that plays it.
nonisolated struct MediaSourceID: Hashable, Sendable {
    var rawValue: String

    /// An app by its bundle id; a browser the extension knows nothing about is an app too.
    static func app(_ bundleID: String) -> MediaSourceID { MediaSourceID(rawValue: "app:" + bundleID) }

    static func tab(_ ref: TabRef) -> MediaSourceID { MediaSourceID(rawValue: "tab:\(ref.connection):\(ref.tab)") }
}

/// A source that is live now, as the player shows it and as the chips list it.
nonisolated struct MediaSourceEntry: Equatable, Sendable, Identifiable {
    var id: MediaSourceID
    /// What the player shows: the system's own session when it is this source that the system plays (it has the position, the
    /// cover and the modes of the player), else what the source itself reported.
    var state: NowPlayingState
    /// The system's now-playing session is this source, so its controls are the system's: MediaRemote through the adapter, and for a
    /// YouTube video the extension's skip. Any other source is controlled through its own: Apple Events for an app, the extension
    /// for a tab.
    var isSystemBacked: Bool
    /// The app's bundle id (the player's: a browser's helper counts as the browser); nil for a tab.
    var app: String?
    var tab: TabRef?
    /// The host name of the page, for a tab.
    var site: String?
    /// The source may become the one the notch follows by itself (see `MediaSourceBook`). A page that only says it plays, with no element
    /// of ours and no sound Chrome hears, may not: it can be chosen, and pinned, but its word alone does not take the notch.
    var canLead = true

    var isPlaying: Bool { state.isPlaying }
}

nonisolated extension NowPlayingState {
    /// The same session with the cover of `other` when it has none: an app that tells its cover by Apple Events while the system's
    /// session for it carries none.
    func withArtwork(from other: NowPlayingState?) -> NowPlayingState {
        guard artwork == nil, let artwork = other?.artwork else { return self }
        var copy = self
        copy.artwork = artwork
        return copy
    }
}
