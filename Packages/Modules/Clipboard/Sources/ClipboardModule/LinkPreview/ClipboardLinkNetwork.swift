import Darwin
import Foundation

/// The real transport: single GETs through an ephemeral `URLSession` that keeps nothing. No cookie is sent, taken or stored, nothing is
/// cached, no credential is stored or offered (a page that asks for a password is not read), a redirect is not followed here (the fetcher
/// follows and checks each one), and the body is read from the stream only as far as the request allows.
nonisolated final class ClipboardLinkNetwork: ClipboardLinkTransport {
    /// A plain, common browser string, the same for everybody: a site is not told which app or version asked.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    static let timeout: TimeInterval = 5
    /// How much of a page is checked for the end of its head at a time.
    private static let headCheckInterval = 4_096

    /// Every setting that keeps something is turned off, one by one: `.ephemeral` alone still keeps cookies and a cache in memory.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return configuration
    }

    private let session: URLSession
    /// The time between two bytes that a request waits; the fetcher's own limits are on the whole.
    let timeout: TimeInterval

    /// `adjust` and `timeout` are for tests, which add a stand-in protocol so no request leaves the process and give it the time a busy
    /// machine may take.
    init(timeout: TimeInterval = ClipboardLinkNetwork.timeout, adjusting adjust: (URLSessionConfiguration) -> Void = { _ in }) {
        let configuration = Self.configuration()
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        adjust(configuration)
        session = URLSession(configuration: configuration)
        self.timeout = timeout
    }

    func get(_ request: ClipboardLinkRequest) async throws -> ClipboardLinkResponse {
        var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        urlRequest.httpMethod = "GET"
        urlRequest.httpShouldHandleCookies = false
        urlRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue(request.kind == .page ? "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1" : "image/*;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")
        urlRequest.setValue("vi,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (stream, response) = try await session.bytes(for: urlRequest, delegate: Delegate())
        defer { stream.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let answer = ClipboardLinkResponse(
            status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type"),
            location: http.value(forHTTPHeaderField: "Location"), body: Data(), wasCut: false
        )
        // A picture that says it is too large is not read at all.
        if request.kind == .image, http.expectedContentLength > Int64(request.byteLimit) {
            var cut = answer
            cut.wasCut = true
            return cut
        }
        var body = Data()
        var sinceCheck = 0
        var wasCut = false
        for try await byte in stream {
            if body.count >= request.byteLimit {
                wasCut = true
                break
            }
            body.append(byte)
            sinceCheck += 1
            if request.kind == .page, sinceCheck >= Self.headCheckInterval {
                sinceCheck = 0
                // The head is all that is read of a page, so the rest is not downloaded.
                if ClipboardLinkBytes.hasEndOfHead(body.suffix(Self.headCheckInterval + 8)) {
                    wasCut = true
                    break
                }
            }
        }
        var full = answer
        full.body = body
        full.wasCut = wasCut
        return full
    }

    func addresses(for host: String) async -> [String] {
        await ClipboardLinkResolver.addresses(for: host)
    }

    /// Takes no redirect (the 3xx answer is returned as it is) and answers no challenge that asks for a secret.
    private nonisolated final class Delegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }

        /// The server's certificate is checked by the system as usual; a password, a client certificate or a negotiated login is
        /// not given, whatever the keychain holds.
        func urlSession(
            _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                completionHandler(.performDefaultHandling, nil)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}

/// Asks the system what a name resolves to, off the main actor and on a thread that is not one of the cooperative pool's, since the
/// call cannot be cancelled and can take as long as the DNS servers do. A cancelled wait is answered at once.
nonisolated enum ClipboardLinkResolver {
    static func addresses(for host: String) async -> [String] {
        let box = Answer()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.wait(continuation)
                DispatchQueue.global(qos: .utility).async { box.finish(lookup(host)) }
            }
        } onCancel: {
            box.finish([])
        }
    }

    private static func lookup(_ host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &found) == 0, let first = found else { return [] }
        defer { freeaddrinfo(first) }
        var addresses: [String] = []
        var next: UnsafeMutablePointer<addrinfo>? = first
        while let info = next {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let text = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if !addresses.contains(text) { addresses.append(text) }
            }
            next = info.pointee.ai_next
        }
        return addresses
    }

    /// The answer, given once: by the lookup or by a cancellation, whichever is first.
    private nonisolated final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[String], Never>?
        private var result: [String]?

        func wait(_ continuation: CheckedContinuation<[String], Never>) {
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }

        func finish(_ addresses: [String]) {
            lock.lock()
            guard result == nil else {
                lock.unlock()
                return
            }
            result = addresses
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(returning: addresses)
        }
    }
}
