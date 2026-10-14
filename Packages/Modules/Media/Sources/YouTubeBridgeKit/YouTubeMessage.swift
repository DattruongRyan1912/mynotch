import Foundation

/// A message of the Chrome extension's protocol (version 1), checked and cleaned. The host and the app both use
/// `decode`, so neither trusts the other's checking: anything that is not exactly what the protocol allows is nil.
public enum YouTubeMessage: Equatable, Sendable {
    case captions(YouTubeCaptions)
    case playback(YouTubePlayback)
    case clear(videoID: String)
    /// The extension reporting on itself, for the logs; not part of the captions flow.
    case diag(YouTubeDiag)

    /// Why a message was refused. Fixed words, so a log line holds nothing of the message.
    public enum Rejection: String, Error, Equatable, Sendable {
        /// Not a JSON object with an integer `v` and a string `type`.
        case malformed
        case unsupportedVersion = "unsupported-version"
        case unknownType = "unknown-type"
        case invalidCaptions = "invalid-captions"
        case invalidPlayback = "invalid-playback"
        case invalidClear = "invalid-clear"
        case invalidDiag = "invalid-diag"
    }

    public static let version = 1
    /// Caption events past this many make the whole message invalid; the extension never sends more.
    public static let maxEvents = 5_000
    /// Longer event text is cut.
    public static let maxTextLength = 500
    public static let maxTitleLength = 300
    public static let maxRate = 16.0
    static let maxLanguageLength = 35

    /// The video the message is about; a diagnostic is about none.
    public var videoID: String? {
        switch self {
        case .captions(let captions): captions.videoID
        case .playback(let playback): playback.videoID
        case .clear(let videoID): videoID
        case .diag: nil
        }
    }

    /// The protocol's word for the type, which is also what the logs count by.
    public var typeName: String {
        switch self {
        case .captions: "captions"
        case .playback: "playback"
        case .clear: "clear"
        case .diag: "diag"
        }
    }

    /// nil unless `data` is one JSON object of a known type with every field of the right type and in range.
    public static func decode(_ data: Data) -> YouTubeMessage? {
        try? check(data).get()
    }

    /// `decode` with the reason when there is none.
    public static func check(_ data: Data) -> Result<YouTubeMessage, Rejection> {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { return .failure(.malformed) }
        guard envelope.v == version else { return .failure(.unsupportedVersion) }
        let message: YouTubeMessage?
        let rejection: Rejection
        switch envelope.type {
        case "captions":
            message = (try? decoder.decode(CaptionsFields.self, from: data)).flatMap(captions)
            rejection = .invalidCaptions
        case "playback":
            message = (try? decoder.decode(PlaybackFields.self, from: data)).flatMap(playback)
            rejection = .invalidPlayback
        case "clear":
            message = (try? decoder.decode(ClearFields.self, from: data)).flatMap { isVideoID($0.videoId) ? .clear(videoID: $0.videoId) : nil }
            rejection = .invalidClear
        case "diag":
            message = (try? decoder.decode(DiagFields.self, from: data)).flatMap(diag)
            rejection = .invalidDiag
        default:
            return .failure(.unknownType)
        }
        return message.map { .success($0) } ?? .failure(rejection)
    }

    // MARK: fields

    private struct Envelope: Decodable {
        var v: Int
        var type: String
    }

    private struct CaptionsFields: Decodable {
        var videoId: String
        var lang: String
        var kind: String
        var events: [EventFields]
    }

    private struct EventFields: Decodable {
        var t: Double
        var d: Double
        var text: String
    }

    private struct PlaybackFields: Decodable {
        var videoId: String
        var title: String
        var time: Double
        var playing: Bool
        var rate: Double
    }

    private struct ClearFields: Decodable {
        var videoId: String
    }

    private struct DiagFields: Decodable {
        var origin: String
        var event: String

        enum CodingKeys: String, CodingKey {
            case origin = "where"
            case event
        }
    }

    // MARK: checking

    private static func captions(_ fields: CaptionsFields) -> YouTubeMessage? {
        guard isVideoID(fields.videoId), fields.lang.count <= maxLanguageLength,
              let kind = YouTubeCaptions.Kind(rawValue: fields.kind),
              (1...maxEvents).contains(fields.events.count),
              fields.events.allSatisfy({ $0.t >= 0 && $0.d >= 0 })
        else { return nil }
        var events = fields.events.compactMap { event -> CaptionEvent? in
            let text = normalised(event.text, limit: maxTextLength)
            return text.isEmpty ? nil : CaptionEvent(time: event.t, duration: event.d, text: text)
        }
        guard !events.isEmpty else { return nil }
        // Sorted for the lyric lookup, which needs the order; an extension that keeps its promise changes nothing.
        if zip(events, events.dropFirst()).contains(where: { $0.time > $1.time }) {
            events = events.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element)
        }
        return .captions(YouTubeCaptions(videoID: fields.videoId, language: fields.lang, kind: kind, events: events))
    }

    private static func playback(_ fields: PlaybackFields) -> YouTubeMessage? {
        let title = normalised(fields.title, limit: maxTitleLength)
        guard isVideoID(fields.videoId), !title.isEmpty, fields.time >= 0, fields.rate > 0, fields.rate <= maxRate else { return nil }
        return .playback(YouTubePlayback(videoID: fields.videoId, title: title, time: fields.time, isPlaying: fields.playing, rate: fields.rate))
    }

    private static func diag(_ fields: DiagFields) -> YouTubeMessage? {
        guard let origin = YouTubeDiag.Origin(rawValue: fields.origin), YouTubeDiag.isAllowed(fields.event, from: origin) else { return nil }
        return .diag(YouTubeDiag(origin: origin, event: fields.event))
    }

    /// Eleven letters, digits, dashes or underscores: what a YouTube video id is made of.
    static func isVideoID(_ text: String) -> Bool {
        text.utf8.count == 11 && text.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45 || byte == 95
        }
    }

    /// Runs of whitespace (newlines included) become one space, the ends are trimmed, and the rest is cut at `limit`.
    private static func normalised(_ text: String, limit: Int) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces)
    }
}

/// One caption line: shown `time` seconds into the video for `duration` seconds (0 when the source gave none).
public struct CaptionEvent: Equatable, Sendable {
    public var time: Double
    public var duration: Double
    public var text: String

    public init(time: Double, duration: Double, text: String) {
        self.time = time
        self.duration = duration
        self.text = text
    }
}

/// The caption track the player loaded for one video, events sorted by time.
public struct YouTubeCaptions: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case standard
        /// Generated by speech recognition.
        case asr
    }

    public var videoID: String
    /// Informational only: when the user picked auto-translate, the extension reports the language of the text.
    public var language: String
    public var kind: Kind
    public var events: [CaptionEvent]

    public init(videoID: String, language: String, kind: Kind, events: [CaptionEvent]) {
        self.videoID = videoID
        self.language = language
        self.kind = kind
        self.events = events
    }
}

/// What the page's video is doing, without the position's clock: the app follows the system's now-playing clock.
public struct YouTubePlayback: Equatable, Sendable {
    public var videoID: String
    /// The video's title as the page shows it, without the " - YouTube" suffix.
    public var title: String
    public var time: Double
    public var isPlaying: Bool
    public var rate: Double

    public init(videoID: String, title: String, time: Double, isPlaying: Bool, rate: Double) {
        self.videoID = videoID
        self.title = title
        self.time = time
        self.isPlaying = isPlaying
        self.rate = rate
    }
}
