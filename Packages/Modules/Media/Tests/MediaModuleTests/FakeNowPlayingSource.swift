import Foundation
@testable import MediaModule

/// Stands in for `AdapterProcess`: tests push adapter lines and failures, and read back the commands.
final class FakeNowPlayingSource: NowPlayingSource {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var sent: [MediaCommand] = []
    private(set) var seeks: [Double] = []
    private var onLine: (@MainActor (String) -> Void)?
    private var onFailure: (@MainActor (String) -> Void)?

    var isStarted: Bool { onLine != nil }

    func start(onLine: @escaping @MainActor (String) -> Void, onFailure: @escaping @MainActor (String) -> Void) {
        startCount += 1
        self.onLine = onLine
        self.onFailure = onFailure
    }

    func stop() {
        stopCount += 1
        onLine = nil
        onFailure = nil
    }

    func send(_ command: MediaCommand) { sent.append(command) }
    func seek(toSeconds seconds: Double) { seeks.append(seconds) }

    func emit(_ line: String) { onLine?(line) }

    func fail(_ reason: String) {
        let onFailure = onFailure
        stop()
        onFailure?(reason)
    }
}

/// Adapter `stream --micros` lines (README `get` and `stream`), built with JSONSerialization so values are escaped.
enum AdapterLines {
    static let empty = #"{"type":"data","diff":false,"payload":{}}"#

    static func track(
        _ title: String = "Song",
        artist: String = "Artist",
        album: String? = nil,
        playing: Bool = true,
        bundle: String = "com.example.Player",
        parent: String? = nil,
        elapsed: Double = 30,
        duration: Double = 200,
        artworkBase64: String? = nil,
        isAdvertisement: Bool = false
    ) -> String {
        var payload: [String: Any] = [
            "bundleIdentifier": bundle, "title": title, "artist": artist, "playing": playing,
            "durationMicros": Int(duration * 1_000_000), "elapsedTimeMicros": Int(elapsed * 1_000_000),
            "timestampEpochMicros": Int(Date().timeIntervalSince1970 * 1_000_000), "playbackRate": 1,
        ]
        payload["parentApplicationBundleIdentifier"] = parent
        payload["album"] = album
        if isAdvertisement { payload["isAdvertisement"] = true }
        if let artworkBase64 {
            payload["artworkData"] = artworkBase64
            payload["artworkMimeType"] = "image/png"
        }
        return line(diff: false, payload)
    }

    static func diff(_ payload: [String: Any]) -> String { line(diff: true, payload) }

    static func playing(_ playing: Bool) -> String { diff(["playing": playing]) }

    static func position(_ elapsed: Double) -> String {
        diff([
            "elapsedTimeMicros": Int(elapsed * 1_000_000),
            "timestampEpochMicros": Int(Date().timeIntervalSince1970 * 1_000_000),
        ])
    }

    private static func line(diff: Bool, _ payload: [String: Any]) -> String {
        let object: [String: Any] = ["type": "data", "diff": diff, "payload": payload]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
