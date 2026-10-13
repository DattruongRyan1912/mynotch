import Foundation
import MyNotchCore

/// Looks lyrics up on lrclib.net. Opt-in: a request sends the track's name, artist, album and length off the Mac.
///
/// One request at a time, each at least `minimumSpacing` after the previous answer, and none while lrclib has
/// asked for quiet. Answers, including "not found", are cached on disk, so a track is asked for once.
final class LyricsService {
    static let minimumSpacing: Duration = .milliseconds(300)
    static let endpoint = URL(string: "https://lrclib.net/api/get")!
    static let requestTimeout: TimeInterval = 10
    /// How long to stay quiet after a 429 or 503 without a usable `Retry-After`.
    static let defaultCooldownSeconds = 60
    /// Whatever `Retry-After` says, the cooldown stays within this, so a bad header cannot end lyrics for the session.
    static let cooldownSecondsRange = 1...3600

    private let client: any HTTPClient
    private let cache: LyricsCache
    private let scheduler: any Scheduler
    private let userAgent: String
    /// A call holds the turn from its start until the spacing after its answer has passed.
    private var isBusy = false
    private var waiters: [(id: Int, continuation: CheckedContinuation<Bool, Never>)] = []
    private var nextWaiterID = 0
    private var spacingTimer: ScheduledAction?
    /// Set while lrclib's `Retry-After` runs.
    private var cooldownTimer: ScheduledAction?
    private var cooldownWaiters: [@MainActor () -> Void] = []
    private var isShutDown = false

    /// Calls waiting for their turn (for tests).
    var queuedCount: Int { waiters.count }

    /// True while lrclib's `Retry-After` runs: new lookups answer `.unavailable` without a request.
    var isCoolingDown: Bool { cooldownTimer != nil }

    /// Runs `action` once the current cooldown ends (a second rate limit extends it); dropped on shut down.
    func afterCooldown(_ action: @escaping @MainActor () -> Void) {
        cooldownWaiters.append(action)
    }

    /// - Parameter appVersion: the app's `CFBundleShortVersionString`, for the User-Agent lrclib asks clients to send.
    init(
        client: any HTTPClient,
        cacheDirectory: URL,
        scheduler: any Scheduler,
        appVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    ) {
        self.client = client
        cache = LyricsCache(directory: cacheDirectory)
        self.scheduler = scheduler
        userAgent = "MyNotch/\(appVersion ?? "dev") (personal)"
    }

    /// Never throws and never makes a request for a cached track. A rate-limited request is not retried: the
    /// answer is `.unavailable` and the next uncached track waits out the cooldown, which is the retry.
    /// Cancelling the caller cancels the request in flight; a cancelled call still waiting its turn sends nothing.
    func lyrics(for track: TrackKey) async -> LyricsResult {
        if let cached = cache.load(track) { return cached }
        guard await takeTurn() else {
            return .unavailable(Task.isCancelled ? "Lookup cancelled" : "Lyrics service stopped")
        }
        guard !Task.isCancelled else {
            passTurn()
            return .unavailable("Lookup cancelled")
        }
        guard cooldownTimer == nil else {
            passTurn()
            return .unavailable("Waiting out a rate limit")
        }
        let result = await request(track)
        // The gap counts from the answer, however long the request took.
        spacingTimer = scheduler.schedule(after: Self.minimumSpacing) { [weak self] in self?.passTurn() }
        cache.store(result, for: track)
        return result
    }

    /// Ends the service with its module: calls still waiting come back `.unavailable` and nothing is sent again.
    func shutDown() {
        isShutDown = true
        spacingTimer?.cancel()
        spacingTimer = nil
        cooldownTimer?.cancel()
        cooldownTimer = nil
        cooldownWaiters = []
        isBusy = false
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.continuation.resume(returning: false) }
    }

    // MARK: request

    private func request(_ track: TrackKey) async -> LyricsResult {
        let reply: HTTPReply
        do {
            reply = try await client.send(makeRequest(for: track))
        } catch {
            // The domain and code only: an error's text can carry the URL, and with it the track.
            let nsError = error as NSError
            return .unavailable("Request failed (\(nsError.domain) \(nsError.code))")
        }
        switch reply.status {
        case 200:
            return Self.result(from: reply.body) ?? .unavailable("Unreadable answer")
        case 404:
            return .notFound
        case 429, 503:
            startCooldown(seconds: Self.cooldownSeconds(retryAfter: reply.retryAfter))
            return .unavailable("Rate limited (HTTP \(reply.status))")
        default:
            return .unavailable("HTTP \(reply.status)")
        }
    }

    private func makeRequest(for track: TrackKey) -> URLRequest {
        var items = [("track_name", track.title), ("artist_name", track.artist)]
        // An empty album would be matched literally.
        if !track.album.isEmpty { items.append(("album_name", track.album)) }
        items.append(("duration", String(track.durationSeconds)))
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = items.map { "\($0)=\(Self.escape($1))" }.joined(separator: "&")
        var request = URLRequest(url: components.url!, timeoutInterval: Self.requestTimeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Everything but unreserved characters is escaped, so "&", "+" and "=" in a name cannot change the query.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// The lrclib track entry as a result: synced lyrics when they parse, else plain ones, else nothing.
    private static func result(from body: Data) -> LyricsResult? {
        guard let entry = try? JSONDecoder().decode(Entry.self, from: body) else { return nil }
        if entry.instrumental == true { return .instrumental }
        let synced = LRCParser.parse(entry.syncedLyrics ?? "")
        if !synced.isEmpty { return .synced(synced) }
        let plain = (entry.plainLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? .notFound : .plain(plain)
    }

    private nonisolated struct Entry: Decodable {
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    // MARK: rate limit

    /// `Retry-After` in seconds (the only form lrclib sends), within `cooldownSecondsRange`.
    private static func cooldownSeconds(retryAfter: String?) -> Int {
        let seconds = retryAfter.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? defaultCooldownSeconds
        return min(max(seconds, cooldownSecondsRange.lowerBound), cooldownSecondsRange.upperBound)
    }

    private func startCooldown(seconds: Int) {
        cooldownTimer?.cancel()
        cooldownTimer = scheduler.schedule(after: .seconds(seconds)) { [weak self] in
            guard let self else { return }
            cooldownTimer = nil
            let ending = cooldownWaiters
            cooldownWaiters = []
            for action in ending { action() }
        }
    }

    // MARK: turns

    /// False when the service was shut down before or while waiting.
    private func takeTurn() async -> Bool {
        if isShutDown { return false }
        guard isBusy else {
            isBusy = true
            return true
        }
        let id = nextWaiterID
        nextWaiterID += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { waiters.append((id, $0)) }
        } onCancel: {
            // Back on the main actor, after the continuation is queued even when the task was cancelled already.
            Task { @MainActor [weak self] in self?.leaveQueue(id) }
        }
    }

    /// A cancelled call stops waiting; it never had the turn, so there is none to pass on.
    private func leaveQueue(_ id: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    /// Hands the turn to the longest waiting call, or frees it.
    private func passTurn() {
        spacingTimer = nil
        guard !isShutDown else { return }
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }
}
