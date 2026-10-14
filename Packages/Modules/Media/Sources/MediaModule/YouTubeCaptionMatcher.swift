import Foundation

/// Decides whether the captions the extension sent belong to what the system says is playing.
nonisolated enum YouTubeCaptionMatcher {
    /// How old the page's latest playback message may be. The page sends one every 5 s while it plays.
    static let maxPlaybackAge: TimeInterval = 10

    /// Why captions are or are not used for the track playing now. The reasons are fixed words for the log, which
    /// must never hold a title.
    enum Reason: String, Equatable {
        case notBrowser = "not-browser"
        /// The system reports a track without a title.
        case noTitle = "no-title"
        /// The extension has sent no playback yet.
        case noPlayback = "no-playback"
        case titleMismatch = "title-mismatch"
        /// The playback's video has no captions (the viewer has not turned them on, or they have not arrived).
        case noCaptions = "no-captions"
        case paused
        case stalePlayback = "stale-playback"
    }

    enum Decision: Equatable {
        /// `isKept`: the captions were already being shown, so the playback conditions were not asked again.
        case matched(YouTubeCaptionStore.Track, isKept: Bool)
        case notMatched(Reason)

        var track: YouTubeCaptionStore.Track? {
            if case .matched(let track, _) = self { track } else { nil }
        }
    }

    /// The captions for the track playing now, or nil. See `decision`.
    static func track(
        for state: NowPlayingState, in store: YouTubeCaptionStore, now: Date, keeping videoID: String?
    ) -> YouTubeCaptionStore.Track? {
        decision(for: state, in: store, now: now, keeping: videoID).track
    }

    /// A match needs a browser as the source, a playback message that is at most `maxPlaybackAge` old and says the
    /// video plays, and a title equal to the now-playing one once normalised; the captions are those of the playback's
    /// video. When it fails, the first rule that did is the reason.
    ///
    /// Those conditions decide when captions start to be used. A video whose captions are being shown (`videoID`) keeps
    /// them while the title and the source still fit, whether it is paused or the page has gone quiet: they end with a `clear`,
    /// another video, another title or the setting, not with a pause that the lyric row would only answer with a flicker.
    static func decision(
        for state: NowPlayingState, in store: YouTubeCaptionStore, now: Date, keeping videoID: String?
    ) -> Decision {
        guard state.isFromBrowser else { return .notMatched(.notBrowser) }
        guard let title = state.title else { return .notMatched(.noTitle) }
        guard let received = store.playback else { return .notMatched(.noPlayback) }
        guard normalised(received.message.title) == normalised(title) else { return .notMatched(.titleMismatch) }
        guard let track = store.track(forVideo: received.message.videoID) else { return .notMatched(.noCaptions) }
        if track.videoID == videoID { return .matched(track, isKept: true) }
        guard received.message.isPlaying else { return .notMatched(.paused) }
        guard now.timeIntervalSince(received.arrivedAt) <= maxPlaybackAge else { return .notMatched(.stalePlayback) }
        return .matched(track, isKept: false)
    }

    /// Composed (NFC), case-folded, runs of whitespace collapsed to one space.
    static func normalised(_ title: String) -> String {
        title.precomposedStringWithCanonicalMapping
            .folding(options: .caseInsensitive, locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
