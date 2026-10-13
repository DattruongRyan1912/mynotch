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

    /// nil without an artist, a title or a usable duration: lrclib cannot match those.
    init?(artist: String?, title: String?, album: String?, duration: Double) {
        let seconds = duration.rounded()
        guard seconds >= Double(Self.durationRange.lowerBound), seconds <= Double(Self.durationRange.upperBound) else { return nil }
        self.artist = Self.normalised(artist)
        self.title = Self.normalised(title)
        self.album = Self.normalised(album)
        durationSeconds = Int(seconds)
        guard !self.artist.isEmpty, !self.title.isEmpty else { return nil }
    }

    /// nil for advertisements (their metadata is not a song) and for tracks that report no length.
    init?(_ state: NowPlayingState) {
        guard !state.isAdvertisement, let duration = state.durationSeconds else { return nil }
        self.init(artist: state.artist, title: state.title, album: state.album, duration: duration)
    }

    /// SHA-256 of the fields as hex, a file name that is safe whatever the track is called.
    var cacheKey: String {
        // The separator keeps ("ab", "c") apart from ("a", "bc").
        let text = [artist, title, album, String(durationSeconds)].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalised(_ text: String?) -> String {
        (text ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
