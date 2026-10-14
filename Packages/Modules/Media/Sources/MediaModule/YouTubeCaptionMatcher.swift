import Foundation

/// Decides whether the captions the extension sent belong to what the system says is playing.
nonisolated enum YouTubeCaptionMatcher {
    /// How old the page's latest playback message may be. The page sends one every 5 s while it plays.
    static let maxPlaybackAge: TimeInterval = 10

    /// The captions for the track playing now, or nil. A match needs a browser as the source, a playback message that
    /// is at most `maxPlaybackAge` old and says the video plays, and a title equal to the now-playing one once
    /// normalised; the captions are those of the playback's video.
    ///
    /// Those conditions decide when captions start to be used. A video whose captions are being shown (`videoID`) keeps
    /// them while the title and the source still fit, whether it is paused or the page has gone quiet: they end with a `clear`,
    /// another video, another title or the setting, not with a pause that the lyric row would only answer with a flicker.
    static func track(
        for state: NowPlayingState, in store: YouTubeCaptionStore, now: Date, keeping videoID: String?
    ) -> YouTubeCaptionStore.Track? {
        guard state.isFromBrowser, let title = state.title, let received = store.playback,
              normalised(received.message.title) == normalised(title),
              let track = store.track(forVideo: received.message.videoID)
        else { return nil }
        if track.videoID == videoID { return track }
        guard received.message.isPlaying, now.timeIntervalSince(received.arrivedAt) <= maxPlaybackAge else { return nil }
        return track
    }

    /// Composed (NFC), case-folded, runs of whitespace collapsed to one space.
    static func normalised(_ title: String) -> String {
        title.precomposedStringWithCanonicalMapping
            .folding(options: .caseInsensitive, locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
