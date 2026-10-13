import Foundation
@testable import MediaModule

/// Stands in for URLSession, so no test ever reaches lrclib.net: tests set what comes back and read the requests.
final class FakeHTTPClient: HTTPClient {
    private(set) var requests: [URLRequest] = []
    private(set) var activeCount = 0
    private(set) var maxActiveCount = 0
    /// What each request gets; until a test sets it, every request fails like a dead connection.
    var handler: (URLRequest) async throws -> HTTPReply = { _ in throw URLError(.notConnectedToInternet) }

    func send(_ request: URLRequest) async throws -> HTTPReply {
        requests.append(request)
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
        defer { activeCount -= 1 }
        return try await handler(request)
    }

    /// Every request gets `reply`.
    func reply(_ reply: HTTPReply) {
        handler = { _ in reply }
    }
}

/// lrclib `GET /api/get` answers, shaped like the real ones (id, names, duration and the three lyrics fields).
enum LrclibReplies {
    static let lrc = "[00:01.00] First\n[00:05.00] Second"
    static let firstTwoLines = [LyricLine(time: 1, text: "First"), LyricLine(time: 5, text: "Second")]

    static func found(synced: String? = lrc, plain: String? = "First\nSecond", instrumental: Bool = false) -> HTTPReply {
        var object: [String: Any] = [
            "id": 3396226, "trackName": "Song", "artistName": "Artist", "albumName": "Album",
            "duration": 200.0, "instrumental": instrumental,
        ]
        object["plainLyrics"] = plain ?? NSNull()
        object["syncedLyrics"] = synced ?? NSNull()
        return HTTPReply(status: 200, body: try! JSONSerialization.data(withJSONObject: object))
    }

    static let instrumental = found(synced: nil, plain: nil, instrumental: true)

    static let notFound = HTTPReply(
        status: 404,
        body: Data(#"{"code":404,"name":"TrackNotFound","message":"Failed to find specified track"}"#.utf8)
    )

    /// 429 and 503 bodies are not always JSON.
    static func busy(status: Int = 429, retryAfter: String? = "120") -> HTTPReply {
        HTTPReply(status: status, body: Data("Too Many Requests".utf8), retryAfter: retryAfter)
    }
}

/// Holds requests inside the fake client until the test lets them go, so tests can overlap calls.
final class Gate {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var isWaiting: Bool { !continuations.isEmpty }

    func wait() async {
        await withCheckedContinuation { continuations.append($0) }
    }

    /// Releases everything waiting now.
    func open() {
        let waiting = continuations
        continuations = []
        waiting.forEach { $0.resume() }
    }
}
