import Foundation
import YouTubeBridgeKit

/// What a player app says of itself: from the notification it posts when something changes, or from a read by Apple Events.
nonisolated struct AppPlayerSnapshot: Equatable, Sendable {
    var isPlaying: Bool
    var title: String
    var artist: String?
    var album: String?
    var durationSeconds: Double?
    /// Where the player is, in seconds, when it said so; the notification of Music does not.
    var positionSeconds: Double?
    /// What tells one track from another for the app (its own id), when it says; the cover is looked up again only when it changes.
    var trackID: String?
    /// Where the cover is, for an app that gives an address (Spotify).
    var artworkURL: URL?
    /// The cover itself, when it has been read or fetched.
    var artwork: Data?

    init(
        isPlaying: Bool, title: String, artist: String? = nil, album: String? = nil, durationSeconds: Double? = nil,
        positionSeconds: Double? = nil, trackID: String? = nil, artworkURL: URL? = nil, artwork: Data? = nil
    ) {
        self.isPlaying = isPlaying
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.positionSeconds = positionSeconds
        self.trackID = trackID
        self.artworkURL = artworkURL
        self.artwork = artwork
    }

    /// The same track as `other`: by the id when both have one, else by the words.
    func isSameTrack(as other: AppPlayerSnapshot) -> Bool {
        if let trackID, let otherID = other.trackID { return trackID == otherID }
        return title == other.title && artist == other.artist && album == other.album
    }
}

/// The players MyNotch reads and controls itself, besides what the system says of them.
nonisolated enum KnownPlayer: CaseIterable, Sendable {
    case music
    case spotify

    var bundleID: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// What the user calls it, for the hint in Settings.
    var name: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    /// The distributed notification the player posts when its state or its track changes. It carries the track, and needs no
    /// permission to receive, so the source can be listed before the user has let MyNotch control the app.
    var notificationName: String {
        switch self {
        case .music: "com.apple.Music.playerInfo"
        case .spotify: "com.spotify.client.PlaybackStateChanged"
        }
    }

    static func player(forBundleID bundleID: String) -> KnownPlayer? {
        allCases.first { $0.bundleID == bundleID }
    }

    /// What the notification says: the track and whether it plays, or that nothing is loaded. nil for a payload that is neither.
    func event(fromNotification userInfo: [AnyHashable: Any]) -> PlayerNotification? {
        guard let state = (userInfo["Player State"] as? String)?.lowercased() else { return nil }
        guard state == "playing" || state == "paused" else { return .stopped }
        let title = Self.text(userInfo["Name"], limit: DisplayLimits.title) ?? ""
        guard !title.isEmpty else { return .stopped }
        let duration: Double?
        switch self {
        case .music: duration = Self.number(userInfo["Total Time"]).map { $0 / 1000 }
        case .spotify: duration = Self.number(userInfo["Duration"]).map { $0 / 1000 }
        }
        let identifier = switch self {
        case .music: Self.text(userInfo["Persistent ID"], limit: 100)
        case .spotify: Self.text(userInfo["Track ID"], limit: 100)
        }
        return .track(AppPlayerSnapshot(
            isPlaying: state == "playing", title: title, artist: Self.text(userInfo["Artist"], limit: DisplayLimits.name),
            album: Self.text(userInfo["Album"], limit: DisplayLimits.name),
            durationSeconds: duration.flatMap { $0 > 0 ? $0 : nil },
            positionSeconds: self == .spotify ? Self.number(userInfo["Playback Position"]).flatMap { $0 >= 0 ? $0 : nil } : nil,
            trackID: identifier
        ))
    }

    /// Non-empty text of at most `limit` characters and without control characters (any process can post these notifications), whatever
    /// type the app put it in (an id may be a number).
    static func text(_ value: Any?, limit: Int) -> String? {
        let text: String? = switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
        let cleaned = text.map { DisplayText.clean($0, limit: limit) }
        return cleaned?.isEmpty == false ? cleaned : nil
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }
}

/// How much text of a title, an artist or an album is kept: the extension's limits.
nonisolated enum DisplayLimits {
    static let title = 300
    static let name = 200
}

nonisolated enum PlayerNotification: Equatable, Sendable {
    case track(AppPlayerSnapshot)
    case stopped
}

/// What the module knows of one app, put together from its notifications and its reads: the latest snapshot, where the player was
/// then, and the cover.
nonisolated struct AppPlayerSession: Equatable, Sendable {
    var snapshot: AppPlayerSnapshot
    /// Where the player was and when, with the rate it moved at; nil while nothing says (Music's notification does not).
    var anchor: PlaybackAnchor?
    var artwork: ArtworkData?

    /// A session from a notification at `now`: the position the notification gives; else, for the track that was already there, the
    /// position the earlier session had got to by now (it moves on at the speed of the earlier anchor while it plays, and stops
    /// where it was when the notification says it paused); else none.
    init(notified snapshot: AppPlayerSnapshot, replacing previous: AppPlayerSession?, at now: Date, revision: () -> Int) {
        self.snapshot = snapshot
        let anchor: PlaybackAnchor?
        if let position = snapshot.positionSeconds {
            anchor = PlaybackAnchor(elapsedSeconds: position, timestamp: now, rate: snapshot.isPlaying ? 1 : 0)
        } else if let previous, previous.snapshot.isSameTrack(as: snapshot), let before = previous.anchor {
            let elapsed = before.elapsedSeconds + (previous.snapshot.isPlaying ? now.timeIntervalSince(before.timestamp) * before.rate : 0)
            anchor = PlaybackAnchor(elapsedSeconds: max(elapsed, 0), timestamp: now, rate: snapshot.isPlaying ? 1 : 0)
        } else {
            anchor = nil
        }
        self.anchor = anchor
        artwork = Self.artwork(of: snapshot, replacing: previous, revision: revision)
    }

    /// A session from a read of the player at `now`, which says where it is and, when the track is new, its cover.
    init(read snapshot: AppPlayerSnapshot, replacing previous: AppPlayerSession?, at now: Date, revision: () -> Int) {
        self.snapshot = snapshot
        anchor = snapshot.positionSeconds.map { PlaybackAnchor(elapsedSeconds: $0, timestamp: now, rate: snapshot.isPlaying ? 1 : 0) }
        artwork = Self.artwork(of: snapshot, replacing: previous, revision: revision)
    }

    /// The cover this session shows: what the snapshot carries, else the earlier session's when the track is the same, else none.
    private static func artwork(of snapshot: AppPlayerSnapshot, replacing previous: AppPlayerSession?, revision: () -> Int) -> ArtworkData? {
        if let data = snapshot.artwork {
            if let previous, previous.snapshot.isSameTrack(as: snapshot), previous.artwork?.data == data { return previous.artwork }
            return ArtworkData(data: data, mimeType: nil, revision: revision())
        }
        if let previous, previous.snapshot.isSameTrack(as: snapshot) { return previous.artwork }
        return nil
    }

    /// What the player shows for this app. The app is the player; its bundle id is its own.
    func state(bundleID: String) -> NowPlayingState {
        NowPlayingState(
            bundleIdentifier: bundleID, title: snapshot.title, artist: snapshot.artist, album: snapshot.album,
            durationSeconds: snapshot.durationSeconds, elapsedAnchor: anchor, isPlaying: snapshot.isPlaying, artwork: artwork
        )
    }
}
