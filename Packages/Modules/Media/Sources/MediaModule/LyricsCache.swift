import Foundation

/// Lyrics already fetched: one JSON file per track in `directory`, named by `TrackKey.cacheKey`, so a track is
/// asked for once. Holds results only, never the track's name. Entries are a few KB, so reads and writes stay
/// on the caller's actor.
nonisolated struct LyricsCache: Sendable {
    let directory: URL

    /// nil when the track is not cached, or the file cannot be read as a result (the next fetch replaces it).
    func load(_ track: TrackKey) -> LyricsResult? {
        guard let data = try? Data(contentsOf: url(for: track)),
              let result = try? JSONDecoder().decode(LyricsResult.self, from: data) else { return nil }
        if case .unavailable = result { return nil }
        return result
    }

    /// Keeps found and not-found answers. `.unavailable` is trouble of the moment, not an answer. Best effort:
    /// a cache that cannot be written only costs another request.
    func store(_ result: LyricsResult, for track: TrackKey) {
        if case .unavailable = result { return }
        guard let data = try? JSONEncoder().encode(result) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(for: track), options: .atomic)
    }

    private func url(for track: TrackKey) -> URL {
        directory.appending(path: "\(track.cacheKey).json")
    }
}
