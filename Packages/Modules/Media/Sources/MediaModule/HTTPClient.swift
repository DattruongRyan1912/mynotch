import Foundation

/// A response reduced to what the lyrics service reads.
nonisolated struct HTTPReply: Sendable {
    var status: Int
    var body = Data()
    /// The raw `Retry-After` header; lrclib sends seconds.
    var retryAfter: String?
}

/// How the lyrics service reaches the network. A protocol so tests use a fake and never touch lrclib.net.
protocol HTTPClient {
    /// Any HTTP status is a reply; only failing to get one (offline, timeout, cancelled) throws.
    func send(_ request: URLRequest) async throws -> HTTPReply
}

/// The real thing: a URLSession (the shared one unless a test hands in its own).
struct URLSessionHTTPClient: HTTPClient {
    var session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> HTTPReply {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return HTTPReply(status: http.statusCode, body: data, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
    }
}
