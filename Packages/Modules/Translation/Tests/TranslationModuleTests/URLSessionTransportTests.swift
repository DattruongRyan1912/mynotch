import Foundation
import Testing
@testable import TranslationModule

/// Answers every request inside the process, so a test never reaches a server, and remembers what it was asked.
nonisolated final class TransportStubURLProtocol: URLProtocol {
    enum Step {
        case reply(status: Int, body: String)
        /// A redirect to `target` that carries every header of the request along, which is the worst case for a key.
        case redirect(status: Int, target: URL)
        /// A reply that never ends: one byte every 50 ms for at most `seconds`, so no idle timeout can fire.
        case drip(seconds: Double)
        case fail(URLError)
    }

    nonisolated(unsafe) static var answer: (@Sendable (URLRequest) -> Step)?
    nonisolated(unsafe) private static var seen: [URLRequest] = []
    private static let lock = NSLock()

    static var requests: [URLRequest] { lock.withLock { seen } }

    static func reset(_ answer: @escaping @Sendable (URLRequest) -> Step) {
        lock.withLock {
            seen = []
            Self.answer = answer
        }
    }

    private let stopped = NSLock()
    nonisolated(unsafe) private var isStopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.seen.append(request) }
        let url = request.url!
        switch Self.answer?(request) ?? .fail(URLError(.cannotConnectToHost)) {
        case .reply(let status, let body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let status, let target):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Location": target.absoluteString])!
            var next = URLRequest(url: target)
            next.httpMethod = request.httpMethod
            next.httpBody = request.httpBody ?? request.httpBodyStream.map { _ in Data() }
            next.allHTTPHeaderFields = request.allHTTPHeaderFields
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            // What the redirect itself answered, which is all that is left when the redirect is refused.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("moved".utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .drip(let seconds):
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            nonisolated(unsafe) let protocolInstance = self
            DispatchQueue.global().async {
                let me = protocolInstance
                let end = Date().addingTimeInterval(seconds)
                while Date() < end, !me.stopped.withLock({ me.isStopped }) {
                    me.client?.urlProtocol(me, didLoad: Data("x".utf8))
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if !me.stopped.withLock({ me.isStopped }) { me.client?.urlProtocolDidFinishLoading(me) }
            }
        case .fail(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        stopped.withLock { isStopped = true }
    }
}

/// The real transport, over a session that only the stub answers: nothing reaches a server.
@Suite(.serialized) struct URLSessionTransportTests {
    let service = URL(string: "https://translation.example.com/v2")!
    let elsewhere = URL(string: "https://elsewhere.example.net/collect")!

    func makeTransport() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransportStubURLProtocol.self]
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    func keyedRequest(timeout: TimeInterval = 20) -> URLRequest {
        var request = URLRequest(url: service)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("SECRET-KEY-0123456789", forHTTPHeaderField: "X-goog-api-key")
        request.setValue("SECRET-KEY-0123456789", forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.httpBody = Data(#"{"q":"my private text"}"#.utf8)
        return request
    }

    @Test func theDefaultSessionKeepsNoCacheAndNoCookiesAndCapsTheWholeRequest() {
        let configuration = URLSessionTransport().session.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(configuration.timeoutIntervalForResource == 120)
    }

    @Test func repliesWithStatusAndBody() async throws {
        TransportStubURLProtocol.reset { _ in .reply(status: 200, body: #"{"a":1}"#) }
        let reply = try await makeTransport().send(keyedRequest())
        #expect(reply.status == 200)
        #expect(String(decoding: reply.body, as: UTF8.self) == #"{"a":1}"#)
        #expect(TransportStubURLProtocol.requests.count == 1)
    }

    @Test func errorStatusesAreRepliesNotErrors() async throws {
        TransportStubURLProtocol.reset { _ in .reply(status: 429, body: "Too Many Requests") }
        #expect(try await makeTransport().send(keyedRequest()).status == 429)
    }

    @Test func transportFailuresThrow() async {
        TransportStubURLProtocol.reset { _ in .fail(URLError(.notConnectedToInternet)) }
        await #expect(throws: URLError.self) { try await makeTransport().send(keyedRequest()) }
    }

    /// URLSession drops `Authorization` on a redirect to another host but forwards every other header, and the body:
    /// a key in `X-goog-api-key` or `Ocp-Apim-Subscription-Key`, and the user's text, would go along.
    @Test(arguments: [301, 302, 303, 307, 308])
    func aRedirectIsNeverFollowed(_ status: Int) async throws {
        let target = elsewhere
        let home = service.host
        TransportStubURLProtocol.reset { request in
            request.url?.host == home ? .redirect(status: status, target: target) : .reply(status: 200, body: "stolen")
        }
        let reply = try await makeTransport().send(keyedRequest())
        #expect(reply.status == status)
        let requests = TransportStubURLProtocol.requests
        #expect(requests.map(\.url) == [service])
        let toElsewhere = requests.filter { $0.url?.host == elsewhere.host }
        #expect(toElsewhere.isEmpty)
        for request in toElsewhere {
            #expect(request.value(forHTTPHeaderField: "X-goog-api-key") == nil)
        }
    }

    @Test func aRedirectToAnotherPortOfTheSameHostIsNotFollowedEither() async throws {
        let target = URL(string: "https://translation.example.com:8443/v2")!
        let home = service
        TransportStubURLProtocol.reset { request in
            request.url == home ? .redirect(status: 307, target: target) : .reply(status: 200, body: "x")
        }
        _ = try await makeTransport().send(keyedRequest())
        #expect(TransportStubURLProtocol.requests.map(\.url) == [service])
    }

    @Test func aReplyThatNeverEndsIsCutAtTheRequestsTimeout() async {
        TransportStubURLProtocol.reset { _ in .drip(seconds: 10) }
        let started = Date()
        await #expect(throws: URLError.self) { try await makeTransport().send(keyedRequest(timeout: 0.3)) }
        #expect(Date().timeIntervalSince(started) < 8)
    }

    @Test func theTimeoutIsATimedOutError() async {
        TransportStubURLProtocol.reset { _ in .drip(seconds: 10) }
        do {
            _ = try await makeTransport().send(keyedRequest(timeout: 0.3))
            Issue.record("a reply that never ends was returned")
        } catch {
            #expect((error as? URLError)?.code == .timedOut)
        }
    }
}
