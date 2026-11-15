import Foundation

/// What the app can ask of one tab that has media: play, pause, toggle, go to the next or the previous track, or seek. It
/// travels like `YouTubeCommand`, but names its tab: the app writes a frame on the connection of the Chrome that owns the tab,
/// the host writes the command to Chrome as a native message, the extension's service worker hands it to the tab, and the tab's
/// script does it to its player. `{"v":1,"type":"tabcommand","tab":5,"action":"seek","seconds":61.235}`.
///
/// A closed set: `v`, `type`, `tab`, `action` and, for a seek only, `seconds`; no field that could carry text. Every hop checks
/// it again with `decode` and passes on the command it checked, never the bytes it was given.
public struct TabCommand: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case play
        case pause
        case toggle
        case next
        case previous
        case seek(seconds: Double)
        case volume(volume: Double, muted: Bool = false)

        /// The protocol's word for it.
        public var word: String {
            switch self {
            case .play: "play"
            case .pause: "pause"
            case .toggle: "toggle"
            case .next: "next"
            case .previous: "previous"
            case .seek: "seek"
            case .volume: "volume"
            }
        }
    }

    public var tab: Int
    public var action: Action

    public init(tab: Int, action: Action) {
        self.tab = tab
        self.action = action
    }

    /// The one JSON form of the command. A seek's seconds are rounded to the millisecond, as the extension does.
    public var json: Data {
        let head = #"{"v":\#(YouTubeMessage.version),"type":"tabcommand","tab":\#(tab),"action":"\#(action.word)""#
        switch action {
        case .seek(let seconds):
            let rounded = (min(max(seconds, 0), BrowserTab.maxSeconds) * 1000).rounded() / 1000
            return Data((head + #","seconds":\#(String(format: "%.3f", rounded))}"#).utf8)
        case .volume(let volume, let muted):
            let rounded = (min(max(volume, 0), 2.0) * 1000).rounded() / 1000
            return Data((head + #","volume":\#(String(format: "%.3f", rounded)),"muted":\#(muted ? "true" : "false")}"#).utf8)
        default:
            return Data((head + "}").utf8)
        }
    }

    /// The command as the app sends it to the host: a 4-byte big-endian length, then the JSON.
    public var frame: Data {
        // A few dozen bytes always fit a frame.
        AppFrame.encode(json)!
    }

    /// The command that `data` says, or nil unless it is one JSON object with exactly the fields of a command: `v` (1), `type`
    /// ("tabcommand"), a tab id in range, one of the seven actions and, for a seek, `seconds` within range, or for volume, `volume` and optional `muted`.
    public static func decode(_ data: Data) -> TabCommand? {
        let decoder = JSONDecoder()
        guard let fields = try? decoder.decode(Fields.self, from: data),
              fields.v == YouTubeMessage.version, fields.type == "tabcommand",
              (0...BrowserTab.maxTabID).contains(fields.tab),
              // Closed: no other field, whatever it holds.
              let keys = try? decoder.decode([String: Anything].self, from: data)
        else { return nil }
        let action: Action
        switch fields.action {
        case "play": action = .play
        case "pause": action = .pause
        case "toggle": action = .toggle
        case "next": action = .next
        case "previous": action = .previous
        case "seek":
            guard let seconds = fields.seconds, seconds >= 0, seconds <= BrowserTab.maxSeconds, keys.count == 5 else { return nil }
            return TabCommand(tab: fields.tab, action: .seek(seconds: seconds))
        case "volume":
            guard let volume = fields.volume, volume >= 0, volume <= 2.0, (keys.count == 5 || keys.count == 6) else { return nil }
            return TabCommand(tab: fields.tab, action: .volume(volume: volume, muted: fields.muted ?? false))
        default: return nil
        }
        guard keys.count == 4 else { return nil }
        return TabCommand(tab: fields.tab, action: action)
    }

    private struct Fields: Decodable {
        var v: Int
        var type: String
        var tab: Int
        var action: String
        var seconds: Double?
        var volume: Double?
        var muted: Bool?
    }

    /// A value of any kind, which is only counted.
    private struct Anything: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
