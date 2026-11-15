/// What the lyrics service found for one track.
nonisolated enum LyricsResult: Equatable, Codable, Sendable {
    case synced([LyricLine])
    /// Lyrics without timestamps.
    case plain(String)
    case instrumental
    /// lrclib has no entry for the track.
    case notFound
    /// Nothing is known: offline, rate limited, an unreadable answer or a stopped service. Never cached, so the
    /// next ask tries again. The reason is for the log and holds no track data.
    case unavailable(String)
}
