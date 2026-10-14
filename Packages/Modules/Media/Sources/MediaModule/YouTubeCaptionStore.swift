import Foundation
import YouTubeBridgeKit

/// What the Chrome extension has sent, in memory only: the latest captions of a few videos, as lyric lines, and the
/// latest playback. Nothing here is written to disk or to the lyrics cache.
nonisolated struct YouTubeCaptionStore {
    /// Captions of this many videos are kept (a page can be left and come back to); the least recently received goes first.
    static let maxVideos = 3

    struct Track: Equatable, Sendable {
        var videoID: String
        var language: String
        var kind: YouTubeCaptions.Kind
        var lines: [LyricLine]
        /// Counts the captions received, so a video whose captions arrive again can be told from the lines already shown.
        var revision: Int
    }

    struct ReceivedPlayback: Equatable, Sendable {
        var message: YouTubePlayback
        /// When the app got it, which is what its age is measured from: the page's own clock is not trusted.
        var arrivedAt: Date
    }

    /// Least recently received first.
    private(set) var tracks: [Track] = []
    private(set) var playback: ReceivedPlayback?
    /// When the last message of any kind arrived.
    private(set) var lastMessageAt: Date?
    private var received = 0

    mutating func apply(_ message: YouTubeMessage, at now: Date) {
        lastMessageAt = now
        switch message {
        case .captions(let captions):
            received += 1
            tracks.removeAll { $0.videoID == captions.videoID }
            tracks.append(Track(
                videoID: captions.videoID, language: captions.language, kind: captions.kind,
                lines: YouTubeCaptionLyrics.lines(from: captions.events), revision: received
            ))
            if tracks.count > Self.maxVideos { tracks.removeFirst(tracks.count - Self.maxVideos) }
        case .playback(let playback):
            self.playback = ReceivedPlayback(message: playback, arrivedAt: now)
        case .clear(let videoID):
            tracks.removeAll { $0.videoID == videoID }
        case .diag:
            // Only proves the extension is there.
            break
        }
    }

    func track(forVideo videoID: String) -> Track? {
        tracks.first { $0.videoID == videoID }
    }

    mutating func removeAll() {
        self = YouTubeCaptionStore()
    }
}
