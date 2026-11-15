import Foundation
import Testing
@testable import MediaModule

/// Answers the cover requests inside the process and writes down what was asked, so that no test reaches a server.
nonisolated final class ArtworkStubProtocol: URLProtocol {
    enum Answer {
        case body(Data, status: Int = 200, headers: [String: String] = [:])
        case redirect(to: String)
    }

    nonisolated(unsafe) static var answers: [String: Answer] = [:]
    nonisolated(unsafe) static var asked: [URL] = []
    private static let lock = NSLock()

    static func reset(_ answers: [String: Answer]) {
        lock.withLock {
            Self.answers = answers
            asked = []
        }
    }

    static var askedURLs: [URL] { lock.withLock { asked } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let answer: Answer? = Self.lock.withLock {
            Self.asked.append(url)
            return Self.answers[url.absoluteString]
        }
        switch answer {
        case .body(let data, let status, let headers)?:
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let target)?:
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": target])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: target)!), redirectResponse: response)
            // As the real stack does when a redirect is not followed: the answer that asked for it is the final one.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        }
    }

    override func stopLoading() {}
}

/// The only network MyNotch uses for the sources: Spotify's cover from its own image service, bounded in where it goes and how much it takes.
@Suite(.serialized) struct SpotifyArtworkFetcherTests {
    static let cover = "https://i.scdn.co/image/abc"

    func makeFetcher() -> SpotifyArtworkFetcher {
        let configuration = SpotifyArtworkFetcher.makeConfiguration()
        configuration.protocolClasses = [ArtworkStubProtocol.self]
        return SpotifyArtworkFetcher(configuration: configuration)
    }

    func fetch(_ url: String = Self.cover) async -> Data? {
        await makeFetcher().fetch(URL(string: url)!)
    }

    @Test func aCoverFromTheServiceIsReturnedAsItCame() async {
        ArtworkStubProtocol.reset([Self.cover: .body(Data([1, 2, 3, 4]))])
        #expect(await fetch() == Data([1, 2, 3, 4]))
        #expect(ArtworkStubProtocol.askedURLs.map(\.absoluteString) == [Self.cover])
    }

    @Test func anAddressOutsideTheServiceIsNotRequestedAtAll() async {
        ArtworkStubProtocol.reset(["http://i.scdn.co/image/abc": .body(Data([1])), "https://evil.example/x": .body(Data([1]))])
        #expect(await fetch("http://i.scdn.co/image/abc") == nil)
        #expect(await fetch("https://evil.example/x") == nil)
        #expect(ArtworkStubProtocol.askedURLs.isEmpty)
    }

    @Test func aRedirectThatLeavesTheServiceIsNotFollowed() async {
        ArtworkStubProtocol.reset([
            Self.cover: .redirect(to: "https://evil.example/steal"),
            "https://evil.example/steal": .body(Data([9, 9, 9])),
        ])
        #expect(await fetch() == nil)
        #expect(ArtworkStubProtocol.askedURLs.map(\.absoluteString) == [Self.cover], "the other address was never asked")
    }

    @Test func aRedirectToPlainHTTPOrAFileOrAnotherHostOfTheSameNameIsNotFollowedEither() async {
        for target in ["http://i.scdn.co/image/abc", "https://scdn.co.evil.example/x", "https://i.scdn.co@evil.example/x"] {
            ArtworkStubProtocol.reset([Self.cover: .redirect(to: target), target: .body(Data([9]))])
            #expect(await fetch() == nil, Comment(rawValue: target))
            #expect(ArtworkStubProtocol.askedURLs.map(\.absoluteString) == [Self.cover], Comment(rawValue: target))
        }
    }

    @Test func aRedirectWithinTheServiceIsFollowed() async {
        let other = "https://mosaic.scdn.co/640/abc"
        ArtworkStubProtocol.reset([Self.cover: .redirect(to: other), other: .body(Data([5, 6]))])
        #expect(await fetch() == Data([5, 6]))
        #expect(ArtworkStubProtocol.askedURLs.map(\.absoluteString) == [Self.cover, other])
    }

    @Test func aBodyBiggerThanTheLimitIsRefusedWhetherOrNotTheServiceSaidSoFirst() async {
        let big = Data(repeating: 7, count: SpotifyArtwork.maxBytes + 1)
        // It said so: not even started.
        ArtworkStubProtocol.reset([Self.cover: .body(big, headers: ["Content-Length": "\(big.count)"])])
        #expect(await fetch() == nil)
        // It said nothing (or lied): stopped as the bytes arrive.
        ArtworkStubProtocol.reset([Self.cover: .body(big)])
        #expect(await fetch() == nil)
        // Exactly the limit is a cover.
        let exact = Data(repeating: 7, count: SpotifyArtwork.maxBytes)
        ArtworkStubProtocol.reset([Self.cover: .body(exact)])
        #expect(await fetch() == exact)
    }

    @Test func anAnswerThatIsNotAFoundOrIsEmptyIsNoCover() async {
        for status in [204, 301, 403, 404, 500] {
            ArtworkStubProtocol.reset([Self.cover: .body(Data([1, 2]), status: status)])
            #expect(await fetch() == nil, Comment(rawValue: "\(status)"))
        }
        ArtworkStubProtocol.reset([Self.cover: .body(Data())])
        #expect(await fetch() == nil)
        ArtworkStubProtocol.reset([:])
        #expect(await fetch() == nil, "a connection that fails")
    }

    @Test func theSessionKeepsNoCookiesNoCacheAndGivesUpSoon() {
        let configuration = SpotifyArtworkFetcher.makeConfiguration()
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(configuration.timeoutIntervalForRequest <= 10)
        #expect(configuration.timeoutIntervalForResource <= 15, "a service that drips bytes does not hold the fetch for ever")
    }
}
