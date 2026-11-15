import Foundation

/// How requests reach an engine's service. A protocol so tests use a fake and never reach the network.
protocol HTTPTransport {
    /// Any HTTP status is a reply; only failing to get one (offline, timeout, cancelled) throws.
    func send(_ request: URLRequest) async throws -> HTTPReply
}

/// Never follows a redirect. URLSession drops `Authorization` when a redirect leaves the host but forwards every other
/// header, so a key in `X-goog-api-key` or `Ocp-Apim-Subscription-Key` would go along, and so would the text to translate.
/// The redirect itself comes back as the reply, which the engine reports.
private nonisolated final class RefusesRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// A private URLSession with no cache and no cookies: nothing of a translation request is worth keeping. A request ends
/// at its `timeoutInterval` at the latest, however slowly the server drips its answer, and refuses every redirect.
struct URLSessionTransport: HTTPTransport {
    private static let privateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // A backstop for the per-request limit below; the default is a week.
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }()

    var session: URLSession = URLSessionTransport.privateSession

    func send(_ request: URLRequest) async throws -> HTTPReply {
        let session = session
        let limit = request.timeoutInterval > 0 ? request.timeoutInterval : 60
        return try await withThrowingTaskGroup(of: HTTPReply.self) { group in
            group.addTask { try await Self.load(request, with: session) }
            group.addTask {
                try await Task.sleep(for: .seconds(limit))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.unknown) }
            return first
        }
    }

    private nonisolated static func load(_ request: URLRequest, with session: URLSession) async throws -> HTTPReply {
        let (data, response) = try await session.data(for: request, delegate: RefusesRedirects())
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return HTTPReply(status: http.statusCode, body: data)
    }
}
