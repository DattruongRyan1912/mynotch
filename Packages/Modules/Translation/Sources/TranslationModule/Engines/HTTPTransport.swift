import Foundation

/// How requests reach an engine's service. A protocol so tests use a fake and never reach the network.
protocol HTTPTransport {
    /// Any HTTP status is a reply; only failing to get one (offline, timeout, cancelled) throws.
    func send(_ request: URLRequest) async throws -> HTTPReply
}

/// A private URLSession with no cache and no cookies: nothing of a translation request is worth keeping.
struct URLSessionTransport: HTTPTransport {
    private static let privateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }()

    var session: URLSession = URLSessionTransport.privateSession

    func send(_ request: URLRequest) async throws -> HTTPReply {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return HTTPReply(status: http.statusCode, body: data)
    }
}
