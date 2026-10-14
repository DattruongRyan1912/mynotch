import Foundation
import MyNotchCore

/// Looks lyrics up on lrclib.net, and for a track of the Music app on Apple Music first, when the user has connected
/// their account. Opt-in: a request sends the track's name, artist, album and length off the Mac.
///
/// One request at a time, each at least `minimumSpacing` after the previous one (whichever server it goes to), and none
/// while lrclib has asked for quiet. Answers are cached on disk, so a track is asked for once; "not found" is asked
/// again after a week.
final class LyricsService {
    static let minimumSpacing: Duration = .milliseconds(300)
    static let endpoint = URL(string: "https://lrclib.net/api/get")!
    static let searchEndpoint = URL(string: "https://lrclib.net/api/search")!
    /// How far a search result's length may be from the track's and still count as the same recording.
    static let durationTolerance = 3.0
    /// Synced lyrics of fewer lines are a stub (lrclib has records with a single line): kept only as a last resort.
    static let minSyncedLines = 4
    static let requestTimeout: TimeInterval = 10
    /// How long to stay quiet after a 429 or 503 without a usable `Retry-After`.
    static let defaultCooldownSeconds = 60
    /// Whatever `Retry-After` says, the cooldown stays within this, so a bad header cannot end lyrics for the session.
    static let cooldownSecondsRange = 1...3600

    private let client: any HTTPClient
    private let apple: AppleMusicLyricsClient?
    private let cache: LyricsCache
    private let scheduler: any Scheduler
    private let userAgent: String
    /// A call holds the turn from its start until the spacing after its answer has passed.
    private var isBusy = false
    private var waiters: [(id: Int, continuation: CheckedContinuation<Bool, Never>)] = []
    private var nextWaiterID = 0
    private var spacingTimer: ScheduledAction?
    /// A chain waiting out the spacing between two of its requests.
    private var stepContinuation: CheckedContinuation<Void, Never>?
    /// Set while lrclib's `Retry-After` runs.
    private var cooldownTimer: ScheduledAction?
    private var cooldownWaiters: [@MainActor () -> Void] = []
    private var isShutDown = false
    /// Whether the lookup in progress has sent a request yet; the next one waits out the spacing only if it has.
    private var hasSentRequest = false

    /// Calls waiting for their turn (for tests).
    var queuedCount: Int { waiters.count }

    /// True while lrclib's `Retry-After` runs: new lookups answer `.unavailable` without a request.
    var isCoolingDown: Bool { cooldownTimer != nil }

    /// Runs `action` once the current cooldown ends (a second rate limit extends it); dropped on shut down.
    func afterCooldown(_ action: @escaping @MainActor () -> Void) {
        cooldownWaiters.append(action)
    }

    /// - Parameters:
    ///   - appVersion: the app's `CFBundleShortVersionString`, for the User-Agent lrclib asks clients to send.
    ///   - apple: asked first for the Music app's tracks while its account is connected; nil never asks Apple.
    init(
        client: any HTTPClient,
        cacheDirectory: URL,
        scheduler: any Scheduler,
        appVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        apple: AppleMusicLyricsClient? = nil
    ) {
        self.client = client
        self.apple = apple
        cache = LyricsCache(directory: cacheDirectory)
        self.scheduler = scheduler
        userAgent = "MyNotch/\(appVersion ?? "dev") (personal)"
    }

    /// Never throws. Something that is no song (a mix, a playlist, an hour-long video), or a title with nothing left
    /// after cleaning, answers `.notFound` at once, uncached and without a request; neither does a cached track make one.
    ///
    /// A lookup is a chain of requests, each after the spacing: the exact match with the album, the exact match
    /// without it (an album spelled differently from lrclib's breaks the first), a search by name and artist, a
    /// free-text search. The first step with usable lyrics ends it: synced ones of at least `minSyncedLines`, or an
    /// instrumental. What is less (a stub, plain words) is kept as a fallback, the answer when no step does better.
    /// A rate limit or any other failure ends the chain as `.unavailable`, fallback or not.
    ///
    /// A track of the Music app with a catalog id is asked of Apple Music first, while the account is connected:
    /// synced or plain lyrics from there are the answer and lrclib is not asked. Nothing from Apple (not found, or it
    /// could not be asked) goes on to the chain above, which then runs as it always did; only an Apple failure with
    /// nothing found at lrclib either is `.unavailable` rather than `.notFound`, so the track is not written off.
    ///
    /// A rate-limited request is not retried: the answer is `.unavailable` and the next uncached track waits out
    /// the cooldown, which is the retry. Cancelling the caller cancels the request in flight; a cancelled call
    /// still waiting its turn, or its next step, sends nothing.
    func lyrics(for track: TrackKey) async -> LyricsResult {
        if track.isLongOrMix || track.lookupTitle.isEmpty { return .notFound }
        var track = track
        // The key says whether Apple is asked, so what was found without the account does not stand for a lookup with it.
        if apple?.isAvailable != true { track.appleCatalogID = nil }
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
        let result = await lookUp(track)
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
        endStepWait()
        isBusy = false
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.continuation.resume(returning: false) }
    }

    // MARK: request

    private struct Step {
        var endpoint: URL
        var items: [(String, String)]
        var isSearch: Bool { endpoint == LyricsService.searchEndpoint }
    }

    private enum Outcome {
        case body(Data)
        case notFound
        case failed(LyricsResult)
    }

    private func lookUp(_ track: TrackKey) async -> LyricsResult {
        hasSentRequest = false
        var appleFailure: String?
        if let id = track.appleCatalogID, let apple {
            let answer = await apple.lyrics(forSongID: id, pace: { [self] in await pace() == nil })
            switch answer {
            case .synced, .plain: return answer
            case .unavailable(let reason): appleFailure = reason
            default: break
            }
        }
        let result = await lookUpOnLrclib(track)
        // Nothing found while Apple could not be asked is no verdict on the track: it is not remembered.
        if let appleFailure, result == .notFound { return .unavailable("Apple Music: \(appleFailure)") }
        return result
    }

    private func lookUpOnLrclib(_ track: TrackKey) async -> LyricsResult {
        let artist = track.lookupArtist
        let title = track.lookupTitle
        let named = [("track_name", title), ("artist_name", artist)]
        var steps: [Step] = []
        // An empty album would be matched literally.
        if !track.album.isEmpty {
            steps.append(Step(endpoint: Self.endpoint, items: named + [("album_name", track.album), ("duration", String(track.durationSeconds))]))
        }
        steps.append(Step(endpoint: Self.endpoint, items: named + [("duration", String(track.durationSeconds))]))
        steps.append(Step(endpoint: Self.searchEndpoint, items: named))
        steps.append(Step(endpoint: Self.searchEndpoint, items: [("q", "\(artist) \(title)")]))

        let duration = Double(track.durationSeconds)
        var fallback: LyricsResult?
        for step in steps {
            if let reason = await pace() { return reason }
            switch await send(step) {
            case .failed(let result):
                return result
            case .notFound:
                continue
            case .body(let body):
                let answer = step.isSearch ? Self.bestMatch(in: body, duration: duration) : Self.result(from: body)
                switch answer {
                case .unavailable:
                    return answer
                case .notFound:
                    continue
                default:
                    if Self.isUsable(answer) { return answer }
                    fallback = Self.better(fallback, answer)
                }
            }
        }
        return fallback ?? .notFound
    }

    /// Called before every request of a lookup, Apple's and lrclib's: waits out the spacing since the previous one (the
    /// first waits for nothing). The reason to send nothing more instead, nil to go on.
    private func pace() async -> LyricsResult? {
        if let reason = reasonToStop { return reason }
        if hasSentRequest {
            await waitOutSpacing()
            if let reason = reasonToStop { return reason }
        }
        hasSentRequest = true
        return nil
    }

    /// Why the chain sends nothing more, nil to go on.
    private var reasonToStop: LyricsResult? {
        if isShutDown { return .unavailable("Lyrics service stopped") }
        if Task.isCancelled { return .unavailable("Lookup cancelled") }
        return nil
    }

    private func send(_ step: Step) async -> Outcome {
        let reply: HTTPReply
        do {
            reply = try await client.send(makeRequest(for: step))
        } catch {
            // The domain and code only: an error's text can carry the URL, and with it the track.
            let nsError = error as NSError
            return .failed(.unavailable("Request failed (\(nsError.domain) \(nsError.code))"))
        }
        switch reply.status {
        case 200:
            return .body(reply.body)
        case 404:
            return .notFound
        case 429, 503:
            startCooldown(seconds: Self.cooldownSeconds(retryAfter: reply.retryAfter))
            return .failed(.unavailable("Rate limited (HTTP \(reply.status))"))
        default:
            return .failed(.unavailable("HTTP \(reply.status)"))
        }
    }

    /// The gap between two requests of one chain, counted from the answer like the gap between lookups.
    private func waitOutSpacing() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                stepContinuation = continuation
                spacingTimer = scheduler.schedule(after: Self.minimumSpacing) { [weak self] in self?.endStepWait() }
            }
        } onCancel: {
            // Back on the main actor, after the continuation is stored even when the task was cancelled already.
            Task { @MainActor [weak self] in self?.endStepWait() }
        }
    }

    /// Ends the wait between two steps, if there is one. Without one it does nothing: a cancellation that arrives late
    /// must not cancel the timer that has since been set to hand the turn over.
    private func endStepWait() {
        guard let continuation = stepContinuation else { return }
        stepContinuation = nil
        spacingTimer?.cancel()
        spacingTimer = nil
        continuation.resume()
    }

    private func makeRequest(for step: Step) -> URLRequest {
        var components = URLComponents(url: step.endpoint, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = step.items.map { "\($0)=\(Self.escape($1))" }.joined(separator: "&")
        var request = URLRequest(url: components.url!, timeoutInterval: Self.requestTimeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Everything but unreserved characters is escaped, so "&", "+" and "=" in a name cannot change the query.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// The lrclib track entry as a result: instrumental, else synced lyrics when they parse, else plain ones, else
    /// `.notFound`; `.unavailable` when the body is no entry.
    private static func result(from body: Data) -> LyricsResult {
        guard let entry = try? JSONDecoder().decode(Entry.self, from: body) else { return .unavailable("Unreadable answer") }
        return entry.instrumental == true ? .instrumental : lyrics(of: entry) ?? .notFound
    }

    /// The lyrics of an entry: synced when they parse, else plain; nil without either.
    private static func lyrics(of entry: Entry) -> LyricsResult? {
        let synced = LRCParser.parse(entry.syncedLyrics ?? "")
        if !synced.isEmpty { return .synced(synced) }
        let plain = (entry.plainLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? nil : .plain(plain)
    }

    /// The lyrics worth showing as they are: an instrumental, or synced ones that are more than a stub.
    private static func isUsable(_ result: LyricsResult) -> Bool {
        switch result {
        case .synced(let lines): lines.count >= minSyncedLines
        case .instrumental: true
        case .plain, .notFound, .unavailable: false
        }
    }

    /// Synced lyrics rank by their lines, plain ones below them.
    private static func rank(_ result: LyricsResult) -> Int {
        if case .synced(let lines) = result { lines.count } else { 0 }
    }

    /// The better of two fallbacks; the older one when they rank the same.
    private static func better(_ old: LyricsResult?, _ new: LyricsResult) -> LyricsResult {
        guard let old else { return new }
        return rank(new) > rank(old) ? new : old
    }

    /// The search result closest in length (within `durationTolerance`; the one with more lines of two equally
    /// close) with usable synced lyrics, else the best fallback among the close ones; `.notFound` when none fits.
    private static func bestMatch(in body: Data, duration: Double) -> LyricsResult {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: body) else { return .unavailable("Unreadable answer") }
        let close = entries
            .filter { $0.instrumental != true }
            .compactMap { entry -> (result: LyricsResult, difference: Double)? in
                guard let length = entry.duration, abs(length - duration) <= durationTolerance, let result = lyrics(of: entry) else { return nil }
                return (result, abs(length - duration))
            }
            .sorted { ($0.difference, -rank($0.result)) < ($1.difference, -rank($1.result)) }
        if let usable = close.first(where: { isUsable($0.result) }) { return usable.result }
        return close.map(\.result).reduce(nil as LyricsResult?, better) ?? .notFound
    }

    private nonisolated struct Entry: Decodable {
        var duration: Double?
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
