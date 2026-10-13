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

/// The real thing: a URLSession (a private one unless a test hands in its own).
struct URLSessionHTTPClient: HTTPClient {
    /// In memory only, with no cache and no cookies: request URLs hold the track's name, and none of it may stay
    /// on disk or come back with a later request.
    private static let privateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }()

    var session: URLSession = URLSessionHTTPClient.privateSession

    func send(_ request: URLRequest) async throws -> HTTPReply {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return HTTPReply(status: http.statusCode, body: data, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
    }
}
