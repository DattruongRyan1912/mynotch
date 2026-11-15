import Foundation

/// A day's rates against the dollar.
struct ExchangeRates: Codable, Equatable {
    var base = "USD"
    var rates: [String: Double]
    /// The day the source says the rates are from.
    var rateDate: Date
    /// When this Mac got them, which is what the 24 hours of the cache count from.
    var fetchedAt: Date

    /// `amount` of `from` in `to`; nil for a currency the source has no rate for.
    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let source = rates[from], let target = rates[to], source > 0, target > 0 else { return nil }
        return amount / source * target
    }
}

nonisolated struct HTTPReply: Sendable {
    var status: Int
    var body = Data()
}

/// How the rates are fetched. A protocol so tests use a fake and never reach the network.
protocol RatesHTTPClient {
    /// Any HTTP status is a reply; only failing to get one (offline, timeout, cancelled) throws.
    func get(_ url: URL) async throws -> HTTPReply
}

/// The real thing: a private URLSession with no cache and no cookies, since nothing of a rates request is worth keeping.
struct URLSessionRatesClient: RatesHTTPClient {
    private static let privateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    var session: URLSession = URLSessionRatesClient.privateSession

    func get(_ url: URL) async throws -> HTTPReply {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return HTTPReply(status: http.statusCode, body: data)
    }
}

/// The day's rates: fetched once a day at most, kept on disk, and only when asked for, which only happens while the
/// setting "Quy đổi tiền tệ" is on.
///
/// The source is the free, key-less endpoint of Exchange Rate API (open.er-api.com), which updates once a day and
/// asks not to be called more than that. The ECB's daily file is smaller but has no dong.
final class ExchangeRateService {
    static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!
    /// Rates are good for a day.
    static let lifetime: TimeInterval = 24 * 3600
    /// After a failure, the next try waits, so a dead connection is not asked again at every keystroke.
    static let retryDelay: TimeInterval = 5 * 60
    /// After "too many requests" it waits longer: the source lifts that block after 20 minutes.
    static let blockedDelay: TimeInterval = 30 * 60

    private let client: any RatesHTTPClient
    private let cacheFile: URL
    private let now: () -> Date
    private var cached: ExchangeRates?
    private var loadedFromDisk = false
    private var lastFailure: Date?
    private var retryDelay = ExchangeRateService.retryDelay
    private var fetching: Task<ExchangeRates?, Never>?

    init(client: any RatesHTTPClient, cacheFile: URL, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.cacheFile = cacheFile
        self.now = now
    }

    /// The rates of the last 24 hours, fetched when none are that fresh. When the fetch fails, older ones are better
    /// than none (their date is shown); nil when there are none at all. Asked twice at once, it fetches once.
    func rates() async -> ExchangeRates? {
        loadFromDisk()
        if let cached, isFresh(cached) { return cached }
        if let fetching { return await fetching.value }
        if let lastFailure, now().timeIntervalSince(lastFailure) < retryDelay { return cached }
        let task = Task { await fetch() }
        fetching = task
        let result = await task.value
        fetching = nil
        return result
    }

    private func isFresh(_ rates: ExchangeRates) -> Bool {
        let age = now().timeIntervalSince(rates.fetchedAt)
        return age >= 0 && age < Self.lifetime
    }

    private func fetch() async -> ExchangeRates? {
        let reply = try? await client.get(Self.endpoint)
        guard let reply, reply.status == 200, let fresh = Self.decode(reply.body, fetchedAt: now()) else {
            lastFailure = now()
            retryDelay = reply?.status == 429 ? Self.blockedDelay : Self.retryDelay
            return cached
        }
        lastFailure = nil
        cached = fresh
        save(fresh)
        return fresh
    }

    private struct Reply: Decodable {
        var result: String
        var baseCode: String
        var timeLastUpdateUnix: Double
        var rates: [String: Double]
    }

    static func decode(_ body: Data, fetchedAt: Date) -> ExchangeRates? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let reply = try? decoder.decode(Reply.self, from: body), reply.result == "success", reply.baseCode == "USD",
              reply.rates["USD"] == 1, reply.rates.values.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return ExchangeRates(rates: reply.rates, rateDate: Date(timeIntervalSince1970: reply.timeLastUpdateUnix), fetchedAt: fetchedAt)
    }

    private func loadFromDisk() {
        guard !loadedFromDisk else { return }
        loadedFromDisk = true
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        cached = (try? Data(contentsOf: cacheFile)).flatMap { try? decoder.decode(ExchangeRates.self, from: $0) }
    }

    /// A cache that cannot be written only costs the next launch a fetch.
    private func save(_ rates: ExchangeRates) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(rates) else { return }
        try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheFile, options: .atomic)
    }
}
