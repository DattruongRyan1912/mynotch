import Foundation
import MyNotchTestSupport
import Testing
@testable import TranslationModule

/// Stands in for the network: tests set what each request gets and read what was asked, so none reaches a server.
final class FakeRatesClient: RatesHTTPClient {
    private(set) var requests: [URL] = []
    /// What every request gets; until a test sets it, requests fail like a dead connection.
    var handler: (URL) async throws -> HTTPReply = { _ in throw URLError(.notConnectedToInternet) }

    func get(_ url: URL) async throws -> HTTPReply {
        requests.append(url)
        return try await handler(url)
    }

    func reply(_ reply: HTTPReply) {
        handler = { _ in reply }
    }
}

/// Answers shaped like open.er-api.com's.
nonisolated enum RatesReplies {
    static func success(_ rates: [String: Double] = ["USD": 1, "VND": 25_000, "EUR": 0.9, "JPY": 150], updated: Double = 1_760_400_151) -> HTTPReply {
        HTTPReply(status: 200, body: body(["result": "success", "base_code": "USD", "time_last_update_unix": updated, "rates": rates]))
    }

    static func body(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }
}

/// A clock the test moves.
final class TestClock {
    var now: Date
    init(_ iso: String = "2026-10-14T08:00:00Z") { now = utc(iso) }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@Suite struct ExchangeRateServiceTests {
    let client = FakeRatesClient()
    let clock = TestClock()
    let cacheFile = ScratchFolders.shared.reserve("rates").appending(path: "Caches/exchange-rates.json")

    func makeService() -> ExchangeRateService {
        ExchangeRateService(client: client, cacheFile: cacheFile) { [clock] in clock.now }
    }

    @Test func asksTheDailyEndpointOfExchangeRateAPI() async throws {
        client.reply(RatesReplies.success())
        _ = await makeService().rates()
        #expect(client.requests == [URL(string: "https://open.er-api.com/v6/latest/USD")!])
        #expect(client.requests.first?.scheme == "https")
    }

    @Test func fetchesNothingUntilAskedFor() {
        _ = makeService()
        #expect(client.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: cacheFile.path))
    }

    @Test func readsTheRatesAndTheirDate() async throws {
        client.reply(RatesReplies.success(["USD": 1, "VND": 25_500], updated: 1_760_400_151))
        let rates = try #require(await makeService().rates())
        #expect(rates.base == "USD")
        #expect(rates.rates == ["USD": 1, "VND": 25_500])
        #expect(rates.rateDate == Date(timeIntervalSince1970: 1_760_400_151))
        #expect(rates.fetchedAt == clock.now)
    }

    @Test func keepsTheRatesFor24HoursThenFetchesAgain() async throws {
        client.reply(RatesReplies.success())
        let service = makeService()
        _ = await service.rates()
        _ = await service.rates()
        clock.advance(24 * 3600 - 1)
        _ = await service.rates()
        #expect(client.requests.count == 1)
        clock.advance(1)
        client.reply(RatesReplies.success(["USD": 1, "VND": 26_000], updated: 1_760_486_551))
        let fresh = try #require(await service.rates())
        #expect(client.requests.count == 2)
        #expect(fresh.rates["VND"] == 26_000)
        _ = await service.rates()
        #expect(client.requests.count == 2)
    }

    @Test func keepsTheRatesOnDiskForTheNextLaunch() async throws {
        client.reply(RatesReplies.success())
        let first = try #require(await makeService().rates())
        #expect(FileManager.default.fileExists(atPath: cacheFile.path))
        client.handler = { _ in throw URLError(.notConnectedToInternet) }
        clock.advance(3600)
        let second = try #require(await makeService().rates())
        #expect(client.requests.count == 1)
        #expect(second.rates == first.rates)
        #expect(second.rateDate == first.rateDate)
    }

    @Test func aCacheOlderThan24HoursIsRefreshedAtLaunch() async throws {
        client.reply(RatesReplies.success())
        _ = await makeService().rates()
        clock.advance(25 * 3600)
        client.reply(RatesReplies.success(["USD": 1, "VND": 26_000]))
        let rates = try #require(await makeService().rates())
        #expect(client.requests.count == 2)
        #expect(rates.rates["VND"] == 26_000)
    }

    @Test func olderRatesBeatNoneWhenTheNetworkIsDown() async throws {
        client.reply(RatesReplies.success())
        let service = makeService()
        let old = try #require(await service.rates())
        clock.advance(30 * 3600)
        client.handler = { _ in throw URLError(.notConnectedToInternet) }
        let stale = try #require(await service.rates())
        #expect(client.requests.count == 2)
        // They keep their own date, so the card can say how old they are.
        #expect(stale.rateDate == old.rateDate)
        #expect(stale.fetchedAt == old.fetchedAt)
    }

    @Test func noRatesAtAllWhenThereWasNeverAnAnswer() async {
        #expect(await makeService().rates() == nil)
        #expect(!FileManager.default.fileExists(atPath: cacheFile.path))
    }

    @Test func afterAFailureItWaitsBeforeAskingAgain() async throws {
        let service = makeService()
        #expect(await service.rates() == nil)
        #expect(await service.rates() == nil)
        clock.advance(ExchangeRateService.retryDelay - 1)
        #expect(await service.rates() == nil)
        #expect(client.requests.count == 1)
        clock.advance(1)
        client.reply(RatesReplies.success())
        #expect(await service.rates() != nil)
        #expect(client.requests.count == 2)
    }

    @Test func afterTooManyRequestsItWaitsUntilTheSourceLiftsTheBlock() async throws {
        client.reply(HTTPReply(status: 429, body: Data("Too Many Requests".utf8)))
        let service = makeService()
        #expect(await service.rates() == nil)
        clock.advance(ExchangeRateService.retryDelay + 1)
        #expect(await service.rates() == nil)
        #expect(client.requests.count == 1)
        clock.advance(ExchangeRateService.blockedDelay)
        client.reply(RatesReplies.success())
        #expect(await service.rates() != nil)
        #expect(client.requests.count == 2)
        // An ordinary failure goes back to the short wait.
        clock.advance(ExchangeRateService.lifetime + 1)
        client.handler = { _ in throw URLError(.timedOut) }
        _ = await service.rates()
        clock.advance(ExchangeRateService.retryDelay)
        client.reply(RatesReplies.success())
        #expect(await service.rates() != nil)
        #expect(client.requests.count == 4)
    }

    @Test(arguments: [
        HTTPReply(status: 500, body: Data("oops".utf8)),
        HTTPReply(status: 429, body: Data("Too Many Requests".utf8)),
        HTTPReply(status: 404),
        HTTPReply(status: 200),
        HTTPReply(status: 200, body: Data("<html>captive portal</html>".utf8)),
        HTTPReply(status: 200, body: Data("[]".utf8)),
        RatesReplies.success([:]),
        RatesReplies.success(["VND": 25_000]),
        RatesReplies.success(["USD": 2, "VND": 25_000]),
        RatesReplies.success(["USD": 1, "VND": -5]),
        RatesReplies.success(["USD": 1, "VND": 0]),
        HTTPReply(status: 200, body: RatesReplies.body(["result": "error", "error-type": "unsupported-code"])),
        HTTPReply(status: 200, body: RatesReplies.body(["result": "success", "base_code": "EUR", "time_last_update_unix": 1, "rates": ["USD": 1]])),
        HTTPReply(status: 200, body: RatesReplies.body(["result": "success", "base_code": "USD", "rates": ["USD": 1]])),
    ])
    func refusesAnAnswerThatIsNotUsableRates(reply: HTTPReply) async {
        client.reply(reply)
        #expect(await makeService().rates() == nil)
        #expect(!FileManager.default.fileExists(atPath: cacheFile.path))
    }

    @Test func aBadAnswerNeverReplacesGoodRates() async throws {
        client.reply(RatesReplies.success())
        let service = makeService()
        let good = try #require(await service.rates())
        clock.advance(25 * 3600)
        client.reply(HTTPReply(status: 200, body: Data("garbage".utf8)))
        #expect(await service.rates() == good)
        let onDisk = try #require(await makeService().rates())
        #expect(onDisk.rates == good.rates)
    }

    @Test func aDamagedCacheFileIsIgnored() async throws {
        try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cacheFile)
        client.reply(RatesReplies.success())
        #expect(await makeService().rates() != nil)
        #expect(client.requests.count == 1)
    }

    @Test func ratesFromTheFutureAreNotTrusted() async throws {
        client.reply(RatesReplies.success())
        _ = await makeService().rates()
        clock.advance(-3600)
        _ = await makeService().rates()
        #expect(client.requests.count == 2)
    }

    @Test func askedTwiceAtOnceItFetchesOnce() async throws {
        let gate = Gate()
        client.handler = { _ in
            await gate.wait()
            return RatesReplies.success()
        }
        let service = makeService()
        async let first = service.rates()
        await eventually { gate.isWaiting }
        async let second = service.rates()
        await settle()
        gate.open()
        let results = await (first, second)
        #expect(client.requests.count == 1)
        #expect(results.0 != nil && results.0 == results.1)
    }

    @Test func aCancelledCallerDoesNotCancelTheFetchForTheOthers() async throws {
        let gate = Gate()
        client.handler = { _ in
            await gate.wait()
            return RatesReplies.success()
        }
        let service = makeService()
        let first = Task { await service.rates() }
        await eventually { gate.isWaiting }
        first.cancel()
        let second = Task { await service.rates() }
        await settle()
        gate.open()
        #expect(await second.value != nil)
        #expect(client.requests.count == 1)
    }

    @Test func theCacheFolderIsCreatedWhenSaving() async {
        client.reply(RatesReplies.success())
        #expect(!FileManager.default.fileExists(atPath: cacheFile.deletingLastPathComponent().path))
        _ = await makeService().rates()
        #expect(FileManager.default.fileExists(atPath: cacheFile.path))
    }
}

/// Holds requests inside the fake client until the test lets them go.
final class Gate {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var isWaiting: Bool { !continuations.isEmpty }

    func wait() async {
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        let waiting = continuations
        continuations = []
        waiting.forEach { $0.resume() }
    }
}

/// Answers every request inside the process, so a test never reaches a server.
nonisolated final class RatesStubURLProtocol: URLProtocol {
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

@Suite(.serialized) struct URLSessionRatesClientTests {
    func makeClient() -> URLSessionRatesClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RatesStubURLProtocol.self]
        return URLSessionRatesClient(session: URLSession(configuration: configuration))
    }

    @Test func theDefaultSessionKeepsNoCacheAndNoCookies() {
        let configuration = URLSessionRatesClient().session.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(configuration.timeoutIntervalForRequest == 10)
    }

    @Test func repliesWithStatusAndBody() async throws {
        nonisolated(unsafe) var asked: URL?
        RatesStubURLProtocol.answer = { request in
            asked = request.url
            return .success((HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"a":1}"#.utf8)))
        }
        let reply = try await makeClient().get(ExchangeRateService.endpoint)
        #expect(reply.status == 200)
        #expect(String(decoding: reply.body, as: UTF8.self) == #"{"a":1}"#)
        #expect(asked == ExchangeRateService.endpoint)
    }

    @Test func errorStatusesAreRepliesNotErrors() async throws {
        RatesStubURLProtocol.answer = { request in
            .success((HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, Data("Too Many Requests".utf8)))
        }
        #expect(try await makeClient().get(ExchangeRateService.endpoint).status == 429)
    }

    @Test func transportFailuresThrow() async {
        RatesStubURLProtocol.answer = { _ in .failure(URLError(.notConnectedToInternet)) }
        await #expect(throws: URLError.self) { try await makeClient().get(ExchangeRateService.endpoint) }
    }
}
