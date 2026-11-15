import Foundation

/// What the app can ask of the page in Chrome: go to the next video or the previous one. It travels the way the extension's
/// messages do, but backwards: the app writes a frame on the connection the host keeps, the host writes the command to Chrome
/// as a native message, the extension's service worker hands it to the tab that last sent playback, and the content script
/// clicks the player's own button. `{"v":1,"type":"command","action":"next"}`.
///
/// A closed set: two words and no field that could carry anything else. Every hop checks it again with `decode`, and the
/// host writes out the command it checked, never the bytes it was given.
public enum YouTubeCommand: String, CaseIterable, Sendable {
    case next
    case previous

    /// The longest frame the host accepts from the app. A command is a few dozen bytes; a frame of any other size is not one.
    public static let maxFrameLength = 256

    /// The one JSON form of the command.
    public var json: Data {
        Data(#"{"v":\#(YouTubeMessage.version),"type":"command","action":"\#(rawValue)"}"#.utf8)
    }

    /// The command as the app sends it to the host: a 4-byte big-endian length, then the JSON.
    public var frame: Data {
        // A few dozen bytes always fit a frame.
        AppFrame.encode(json)!
    }

    /// The command that `data` says, or nil unless it is one JSON object with exactly the three fields `v` (1), `type`
    /// ("command") and `action` (one of the two words).
    public static func decode(_ data: Data) -> YouTubeCommand? {
        let decoder = JSONDecoder()
        guard let fields = try? decoder.decode(Fields.self, from: data),
              fields.v == YouTubeMessage.version, fields.type == "command",
              // Closed: no other field, whatever it holds.
              let keys = try? decoder.decode([String: Anything].self, from: data), keys.count == 3
        else { return nil }
        return YouTubeCommand(rawValue: fields.action)
    }

    private struct Fields: Decodable {
        var v: Int
        var type: String
        var action: String
    }

    /// A value of any kind, which is only counted.
    private struct Anything: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
