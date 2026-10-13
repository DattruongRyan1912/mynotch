import CryptoKit
import Foundation

/// Which track lyrics are wanted for: what lrclib is asked and what the disk cache is keyed by.
/// Spelling differences that do not change the answer (padding, runs of spaces) and sub-second duration
/// jitter between players do not make a different key.
nonisolated struct TrackKey: Hashable, Sendable {
    /// lrclib matches the duration within 2 s; nothing longer than a day has lyrics worth fetching.
    static let durationRange = 1...86_400

    var artist: String
    var title: String
    var album: String
    var durationSeconds: Int
    /// The player is a web browser, so `title` is a video title and `artist` the channel.
    var isFromBrowser = false

    /// Browsers and their helper processes; a prefix also covers beta and canary builds.
    static let browserBundlePrefixes = [
        "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.microsoft.edgemac",
        "org.mozilla.firefox", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    /// What lrclib is asked: the artist and song cleaned from the video title when the source is a browser (split on
    /// the dash only without an album), or has no album and a title shaped "Artist - Song"; as reported otherwise.
    var lookupArtist: String { lookup.artist }
    var lookupTitle: String { lookup.title }

    private var lookup: (artist: String, title: String) {
        let dashed = VideoTitleParser.separators.contains { title.contains($0) }
        guard isFromBrowser || (album.isEmpty && dashed) else { return (artist, title) }
        // With an album the player has tagged the track itself, so a dash belongs to the title.
        return VideoTitleParser.parse(title: title, channel: artist, splitsOnDash: album.isEmpty)
    }

    /// True for what is no song: a mix, a playlist or something longer than 15 minutes. Never looked up.
    var isLongOrMix: Bool {
        VideoTitleParser.isLongOrMix(title: title, durationSeconds: durationSeconds)
    }

    /// nil without an artist, a title or a usable duration: lrclib cannot match those.
    init?(artist: String?, title: String?, album: String?, duration: Double, isFromBrowser: Bool = false) {
        let seconds = duration.rounded()
        guard seconds >= Double(Self.durationRange.lowerBound), seconds <= Double(Self.durationRange.upperBound) else { return nil }
        self.artist = Self.normalised(artist)
        self.title = Self.normalised(title)
        self.album = Self.normalised(album)
        durationSeconds = Int(seconds)
        self.isFromBrowser = isFromBrowser
        guard !self.artist.isEmpty, !self.title.isEmpty else { return nil }
    }

    /// nil for advertisements (their metadata is not a song) and for tracks that report no length.
    init?(_ state: NowPlayingState) {
        guard !state.isAdvertisement, let duration = state.durationSeconds else { return nil }
        let owners = [state.bundleIdentifier, state.parentApplicationBundleIdentifier].compactMap { $0 }
        let isBrowser = owners.contains { owner in Self.browserBundlePrefixes.contains { owner.hasPrefix($0) } }
        self.init(artist: state.artist, title: state.title, album: state.album, duration: duration, isFromBrowser: isBrowser)
    }

    /// Bumped when the lookup changes, so answers of an older lookup (all "not found" for videos) are asked again.
    static let cacheVersion = "v3"

    /// SHA-256 of the fields as hex, a file name that is safe whatever the track is called.
    var cacheKey: String {
        // The separator keeps ("ab", "c") apart from ("a", "bc").
        let text = [artist, title, album, String(durationSeconds), Self.cacheVersion].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalised(_ text: String?) -> String {
        // Composed, as lrclib stores Vietnamese: a player may report the decomposed form.
        (text ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ").precomposedStringWithCanonicalMapping
    }
}
