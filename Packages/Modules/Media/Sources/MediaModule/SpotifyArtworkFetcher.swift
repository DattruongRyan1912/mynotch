import Foundation

/// Fetches a cover from Spotify's own image service and from nothing else: over https, no cookies and no cache, and without leaving the
/// service by a redirect; it stops reading at `SpotifyArtwork.maxBytes` (and does not start when the service says more), and gives up
/// after a few seconds. What it returns is bytes for `NSImage(data:)`, and nil for anything else.
nonisolated final class SpotifyArtworkFetcher: NSObject, URLSessionTaskDelegate, Sendable {
    private let configuration: URLSessionConfiguration

    /// Tests give a configuration with their own `protocolClasses`: none reaches the network.
    init(configuration: URLSessionConfiguration = SpotifyArtworkFetcher.makeConfiguration()) {
        self.configuration = configuration
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // The idle timeout alone would let a service that drips bytes hold the fetch for ever.
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        return configuration
    }

    func fetch(_ url: URL) async -> Data? {
        guard SpotifyArtwork.isAllowed(url) else { return nil }
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (bytes, response) = try await session.bytes(from: url, delegate: self)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, SpotifyArtwork.isAllowed(http.url ?? url),
                  http.expectedContentLength <= Int64(SpotifyArtwork.maxBytes)
            else { return nil }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                // Counted as it arrives: a body is never held whole before it is judged.
                if data.count > SpotifyArtwork.maxBytes { return nil }
            }
            return data.isEmpty ? nil : data
        } catch {
            return nil
        }
    }

    /// A redirect that leaves the service is not followed (the answer that asked for it is then the final one, and is not a cover).
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(SpotifyArtwork.isAllowed) == true ? request : nil)
    }
}
