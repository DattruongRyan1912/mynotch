import Foundation

/// The subtitle line the app wants drawn over a tab's film, in the page itself: the extension draws it on the player (in its frame,
/// over the video, inside the fullscreen player too), so it goes with the tab when the user changes tab or app. It travels like
/// `TabCommand`. `{"v":1,"type":"subtitle","tab":5,"text":"Hello","until":2.5,"gap":0.08,"scale":1}`.
///
/// `text` is the line ("" takes it away), which the page shows as text only; `until` is how many seconds it stays unless a newer one
/// comes, so a line is never left on the film by an app that went away; `gap` and `scale` are where and how large the user put the
/// floating subtitles (a share of the video's height from its bottom, and a factor of the size). Every hop checks it again.
public struct TabSubtitle: Equatable, Sendable, Codable {
    public var tab: Int
    public var text: String
    public var until: Double
    public var gap: Double
    public var scale: Double

    public static let untilRange = 0.0...30.0
    public static let gapRange = 0.0...0.6
    public static let scaleRange = 0.5...2.5

    public init(tab: Int, text: String, until: Double, gap: Double, scale: Double) {
        self.tab = tab
        self.text = DisplayText.clean(text, limit: YouTubeMessage.maxTextLength)
        self.until = Self.clamped(until, to: Self.untilRange)
        self.gap = Self.clamped(gap, to: Self.gapRange)
        self.scale = Self.clamped(scale, to: Self.scaleRange)
    }

    /// The one JSON form of the line; the numbers rounded to the millisecond.
    public var json: Data {
        let fields = Fields(
            v: YouTubeMessage.version, type: "subtitle", tab: tab, text: text,
            until: Self.rounded(until), gap: Self.rounded(gap), scale: Self.rounded(scale)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Plain strings and numbers always encode.
        return try! encoder.encode(fields)
    }

    /// The line as the app sends it to the host: a 4-byte big-endian length, then the JSON. nil only for a line too long for a frame,
    /// which `maxTextLength` rules out.
    public var frame: Data? {
        AppFrame.encode(json)
    }

    /// The line `data` says, or nil unless it is one JSON object with exactly its fields, each of its type and in range.
    public static func decode(_ data: Data) -> TabSubtitle? {
        let decoder = JSONDecoder()
        guard let fields = try? decoder.decode(Fields.self, from: data),
              fields.v == YouTubeMessage.version, fields.type == "subtitle",
              (0...BrowserTab.maxTabID).contains(fields.tab),
              fields.text.count <= YouTubeMessage.maxTextLength,
              untilRange.contains(fields.until), gapRange.contains(fields.gap), scaleRange.contains(fields.scale),
              // Closed: no other field, whatever it holds.
              let keys = try? decoder.decode([String: Anything].self, from: data), keys.count == 7
        else { return nil }
        return TabSubtitle(tab: fields.tab, text: fields.text, until: fields.until, gap: fields.gap, scale: fields.scale)
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    private struct Fields: Codable {
        var v: Int
        var type: String
        var tab: Int
        var text: String
        var until: Double
        var gap: Double
        var scale: Double
    }

    private struct Anything: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
