import Foundation
import YouTubeBridgeKit
@testable import MediaModule

/// Protocol messages for tests, with placeholder words as captions: never real captions or lyrics.
enum YouTubeTestMessages {
    static let videoID = "abcdefghijk"
    static let title = "Sample video"

    static func captions(
        _ videoID: String = videoID, _ events: [CaptionEvent]? = nil, kind: YouTubeCaptions.Kind = .standard
    ) -> YouTubeMessage {
        .captions(YouTubeCaptions(
            videoID: videoID, language: "vi", kind: kind,
            events: events ?? [
                CaptionEvent(time: 2, duration: 2, text: "alpha"), CaptionEvent(time: 4, duration: 2, text: "beta"),
                CaptionEvent(time: 6, duration: 2, text: "gamma"),
            ]
        ))
    }

    /// What `captions` turns into once converted.
    static let lines = [
        LyricLine(time: 2, text: "alpha"), LyricLine(time: 4, text: "beta"), LyricLine(time: 6, text: "gamma"), LyricLine(time: 8, text: ""),
    ]

    static func playback(
        _ videoID: String = videoID, title: String = title, playing: Bool = true, time: Double = 3
    ) -> YouTubeMessage {
        .playback(YouTubePlayback(videoID: videoID, title: title, time: time, isPlaying: playing, rate: 1))
    }

    static func clear(_ videoID: String = videoID) -> YouTubeMessage {
        .clear(videoID: videoID)
    }

    /// A page with media: `tab` is Chrome's id for it.
    static func tab(
        _ tab: Int = 1, title: String = "Page song", site: String = "music.example.com", artist: String? = nil, playing: Bool = true,
        time: Double = 10, duration: Double? = 200
    ) -> YouTubeMessage {
        .tab(BrowserTab(tab: tab, site: site, title: title, artist: artist, isPlaying: playing, time: time, duration: duration))
    }

    static func diag(_ event: String = "sw-start v=0.1.1", from origin: YouTubeDiag.Origin = .sw) -> YouTubeMessage {
        .diag(YouTubeDiag(origin: origin, event: event))
    }

    /// The JSON the extension sends, for the tests that go through a socket.
    static func json(_ message: YouTubeMessage) -> Data {
        let object: [String: Any]
        switch message {
        case .captions(let captions):
            object = [
                "v": 1, "type": "captions", "videoId": captions.videoID, "lang": captions.language, "kind": captions.kind.rawValue,
                "events": captions.events.map { ["t": $0.time, "d": $0.duration, "text": $0.text] },
            ]
        case .playback(let playback):
            object = [
                "v": 1, "type": "playback", "videoId": playback.videoID, "title": playback.title, "time": playback.time,
                "playing": playback.isPlaying, "rate": playback.rate,
            ]
        case .clear(let videoID):
            object = ["v": 1, "type": "clear", "videoId": videoID]
        case .diag(let diag):
            object = ["v": 1, "type": "diag", "where": diag.origin.rawValue, "event": diag.event]
        case .tab(let tab):
            object = [
                "v": 1, "type": "tab", "tab": tab.tab, "site": tab.site, "title": tab.title, "artist": tab.artist ?? "",
                "album": tab.album ?? "", "state": tab.isPlaying ? "playing" : "paused", "time": tab.time,
                "duration": tab.duration ?? NSNull(), "rate": tab.rate, "live": tab.isLive,
            ]
        case .tabGone(let tab):
            object = ["v": 1, "type": "tabgone", "tab": tab]
        }
        return try! JSONSerialization.data(withJSONObject: object)
    }
}
