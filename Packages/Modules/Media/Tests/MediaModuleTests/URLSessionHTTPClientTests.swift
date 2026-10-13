import Foundation
import Testing
@testable import MediaModule

/// Answers every request inside the process, so a test never reaches a server.
nonisolated final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var answer: ((URLRequest) -> Result<(HTTPURLResponse, Data), URLError>)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Self.answer?(request) ?? .failure(URLError(.cannotConnectToHost)) {
        case .success(let (response, data)):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct URLSessionHTTPClientTests {
    let request = URLRequest(url: URL(string: "https://lrclib.test/api/get")!)

    func makeClient() -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionHTTPClient(session: URLSession(configuration: configuration))
    }

    func answer(status: Int, headers: [String: String] = [:], body: String = "") {
        StubURLProtocol.answer = { request in
            .success((HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, Data(body.utf8)))
        }
    }

    @Test func repliesWithStatusAndBody() async throws {
        answer(status: 200, body: #"{"id":1}"#)
        let reply = try await makeClient().send(request)
        #expect(reply.status == 200)
        #expect(String(decoding: reply.body, as: UTF8.self) == #"{"id":1}"#)
        #expect(reply.retryAfter == nil)
    }

    @Test func errorStatusesAreRepliesNotErrors() async throws {
        answer(status: 404, body: #"{"code":404}"#)
        #expect(try await makeClient().send(request).status == 404)
    }

    @Test func readsRetryAfterWhateverTheHeaderCase() async throws {
        answer(status: 429, headers: ["retry-after": "42"], body: "Too Many Requests")
        let reply = try await makeClient().send(request)
        #expect(reply.status == 429)
        #expect(reply.retryAfter == "42")
    }

    @Test func transportFailuresThrow() async {
        StubURLProtocol.answer = { _ in .failure(URLError(.notConnectedToInternet)) }
        await #expect(throws: URLError.self) { try await makeClient().send(request) }
    }
}
