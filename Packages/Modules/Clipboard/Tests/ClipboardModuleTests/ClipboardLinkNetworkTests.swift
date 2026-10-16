import Foundation
import Testing
@testable import ClipboardModule

/// Answers requests from a table, inside the process: the session under test is the real one, with this added as its protocol, so no
/// request leaves the machine. Each test uses addresses of its own, since the table is shared.
nonisolated final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        /// A redirect the way a server's own answer arrives at the session: through the protocol client.
        var redirectsTo: URL?
        var chunk = 16_384
    }

    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]
    nonisolated(unsafe) private static var log: [URLRequest] = []
    private static let lock = NSLock()

    static func set(_ url: String, _ stub: Stub) {
        lock.lock()
        defer { lock.unlock() }
        stubs[url] = stub
    }

    static func requests(for url: String) -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return log.filter { $0.url?.absoluteString == url }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lock.lock()
        Self.log.append(request)
        let stub = request.url.flatMap { Self.stubs[$0.absoluteString] }
        Self.lock.unlock()
        guard let url = request.url, let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        if let target = stub.redirectsTo {
            // The session asks its delegate. A built-in protocol then delivers the 3xx answer as the final one when the delegate says no;
            // this stand-in does the same by hand, and a session that followed would show up as a request for the target.
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        var offset = 0
        while offset < stub.body.count {
            let end = min(offset + stub.chunk, stub.body.count)
            client?.urlProtocol(self, didLoad: stub.body[offset..<end])
            offset = end
        }
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// The real transport, with nothing behind it: what it sends, what it refuses to keep, and how much of an answer it reads.
/// Nonisolated for the same reason as the fetcher's tests: a session's time limit is real time, and the main actor may be busy with
/// another test.
@Suite nonisolated struct ClipboardLinkNetworkTests {
    /// A long limit, so that the time a busy machine takes is not what a test is about; the brief's five seconds is checked on its own.
    let network = ClipboardLinkNetwork(timeout: 1_200, adjusting: { $0.protocolClasses = [StubURLProtocol.self] })

    func page(_ url: String, limit: Int = 512 * 1024) -> ClipboardLinkRequest {
        ClipboardLinkRequest(url: URL(string: url)!, kind: .page, byteLimit: limit)
    }

    func image(_ url: String, limit: Int = 2 * 1024 * 1024) -> ClipboardLinkRequest {
        ClipboardLinkRequest(url: URL(string: url)!, kind: .image, byteLimit: limit)
    }

    // MARK: Configuration

    /// `.ephemeral` alone still keeps cookies and a cache in memory, so each of them is turned off on its own.
    @Test func theSessionKeepsNothing() {
        let configuration = ClipboardLinkNetwork.configuration()
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.urlCache == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(configuration.timeoutIntervalForRequest == 5)
        #expect(configuration.timeoutIntervalForResource == 5)
        #expect(configuration.waitsForConnectivity == false)
        #expect(configuration.tlsMinimumSupportedProtocolVersion == .TLSv12)
        // No disk: an ephemeral configuration has no identifier a background session would need.
        #expect(configuration.identifier == nil)
        #expect(configuration.sharedContainerIdentifier == nil)
    }

    @Test func theTimeLimitIsFiveSeconds() {
        #expect(ClipboardLinkNetwork.timeout == 5)
        #expect(ClipboardLinkNetwork().timeout == 5)
    }

    // MARK: What is sent

    @Test func aPlainGetWithAPlainUserAgent() async throws {
        let url = "https://sent.example.org/page"
        StubURLProtocol.set(url, .init(body: Data("<head></head>".utf8)))
        _ = try await network.get(page(url))
        let sent = try #require(StubURLProtocol.requests(for: url).first)
        #expect(sent.httpMethod == "GET")
        #expect(sent.httpBody == nil)
        #expect(sent.value(forHTTPHeaderField: "User-Agent") == ClipboardLinkNetwork.userAgent)
        #expect(ClipboardLinkNetwork.userAgent.hasPrefix("Mozilla/5.0 (Macintosh"))
        #expect(!ClipboardLinkNetwork.userAgent.localizedCaseInsensitiveContains("MyNotch"))
        #expect(sent.value(forHTTPHeaderField: "Accept")?.hasPrefix("text/html") == true)
        #expect(sent.timeoutInterval == network.timeout)
        #expect(sent.httpShouldHandleCookies == false)
        #expect(sent.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(sent.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent.value(forHTTPHeaderField: "Referer") == nil)
    }

    @Test func aPictureAsksForAPicture() async throws {
        let url = "https://sent.example.org/picture.png"
        StubURLProtocol.set(url, .init(headers: ["Content-Type": "image/png"], body: TestPictures.png(width: 8, height: 8)))
        _ = try await network.get(image(url))
        let sent = try #require(StubURLProtocol.requests(for: url).first)
        #expect(sent.value(forHTTPHeaderField: "Accept")?.hasPrefix("image/") == true)
    }

    @Test func noCookieIsKeptOrSent() async throws {
        let first = "https://cookies.example.org/set", second = "https://cookies.example.org/next"
        StubURLProtocol.set(first, .init(headers: ["Set-Cookie": "session=abc; Path=/"], body: Data("<head></head>".utf8)))
        StubURLProtocol.set(second, .init(body: Data("<head></head>".utf8)))
        _ = try await network.get(page(first))
        _ = try await network.get(page(second))
        #expect(StubURLProtocol.requests(for: second).first?.value(forHTTPHeaderField: "Cookie") == nil)
    }

    // MARK: What comes back

    @Test func theStatusAndTheHeadersComeBack() async throws {
        let url = "https://answer.example.org/a"
        StubURLProtocol.set(url, .init(status: 203, headers: ["Content-Type": "text/html; charset=utf-8"], body: Data("<head><title>x</title></head>".utf8)))
        let answer = try await network.get(page(url))
        #expect(answer.status == 203)
        #expect(answer.contentType == "text/html; charset=utf-8")
        #expect(String(decoding: answer.body, as: UTF8.self) == "<head><title>x</title></head>")
        #expect(!answer.wasCut)
        StubURLProtocol.set("https://answer.example.org/missing", .init(status: 404))
        #expect(try await network.get(page("https://answer.example.org/missing")).status == 404)
    }

    /// The fetcher follows redirects, one at a time and with a check on each; the session follows none.
    @Test func aRedirectIsReturnedNotFollowed() async throws {
        let from = "https://redirect.example.org/from", target = "https://redirect.example.org/target"
        StubURLProtocol.set(from, .init(status: 302, headers: ["Location": target], redirectsTo: URL(string: target)))
        StubURLProtocol.set(target, .init(body: Data("<head><title>không được tới</title></head>".utf8)))
        let answer = try await network.get(page(from))
        #expect(answer.status == 302)
        #expect(answer.location == target)
        #expect(StubURLProtocol.requests(for: target).isEmpty)
    }

    // MARK: How much is read

    @Test func aPageIsReadOnlyUpToTheLimit() async throws {
        let url = "https://caps.example.org/page"
        StubURLProtocol.set(url, .init(headers: ["Content-Type": "text/html"], body: Data(repeating: UInt8(ascii: "a"), count: 20_000)))
        let answer = try await network.get(page(url, limit: 5_000))
        #expect(answer.body.count == 5_000)
        #expect(answer.wasCut)
        let whole = try await network.get(page(url, limit: 20_000))
        #expect(whole.body.count == 20_000)
        #expect(!whole.wasCut)
    }

    @Test func theRestOfAPageIsNotReadOnceItsHeadHasEnded() async throws {
        let url = "https://caps.example.org/head"
        let head = "<html><head><title>Đầu trang</title></head><body>"
        StubURLProtocol.set(url, .init(body: Data((head + String(repeating: "x", count: 300_000)).utf8)))
        let answer = try await network.get(page(url))
        #expect(answer.wasCut)
        #expect(answer.body.count < 20_000)
        #expect(String(decoding: answer.body, as: UTF8.self).contains("Đầu trang"))
    }

    @Test func aPictureOverTheLimitIsCutAndSaidSo() async throws {
        let url = "https://caps.example.org/big.png"
        StubURLProtocol.set(url, .init(headers: ["Content-Type": "image/png"], body: Data(repeating: 7, count: 30_000)))
        let answer = try await network.get(image(url, limit: 10_000))
        #expect(answer.body.count == 10_000)
        #expect(answer.wasCut)
    }

    @Test func aPictureThatSaysItIsTooLargeIsNotReadAtAll() async throws {
        let url = "https://caps.example.org/huge.png"
        StubURLProtocol.set(url, .init(headers: ["Content-Type": "image/png", "Content-Length": "5000000"], body: Data(repeating: 7, count: 30_000)))
        let answer = try await network.get(image(url, limit: 2_000_000))
        #expect(answer.body.isEmpty)
        #expect(answer.wasCut)
    }

    // MARK: Resolving

    /// Name resolution of a name the machine knows by itself: nothing leaves it.
    @Test func theResolverAnswersWithAddressesAsText() async {
        let addresses = await ClipboardLinkResolver.addresses(for: "localhost")
        #expect(addresses.contains("127.0.0.1") || addresses.contains("::1"))
        #expect(addresses.allSatisfy(ClipboardLinkGuard.isForbidden(address:)))
        #expect(await ClipboardLinkResolver.addresses(for: "127.0.0.1") == ["127.0.0.1"])
    }
}
