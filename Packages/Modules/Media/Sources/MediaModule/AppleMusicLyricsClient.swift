import Foundation
import os

/// Asks Apple Music's web API for the lyrics of a catalog song with the user's own sign-in (unofficial: the API the
/// music.apple.com player uses, which Apple may change). Sends requests through the injected `HTTPClient`; the
/// caller decides when each one may go out.
///
/// The catalog is asked first whether the song has lyrics at all: Apple answers a lyrics request it does not accept the
/// user's token for with 404 "No related resources", the same as for a song without lyrics. A song that lists lyrics
/// but gets none is therefore not "not found": it is `.unavailable`, so nothing is remembered, and once per run a
/// few variants of the request are tried to find out why (the one that works is used from then on).
///
/// A rejected developer token is refreshed once without the user, from the web player's own script; rejected again,
/// the account needs a sign-in and Apple is left alone until then. Every step is logged (see `AppleMusicLog`); nothing
/// here puts a token into an answer, a message or the log.
final class AppleMusicLyricsClient {
    static let apiBase = "https://amp-api.music.apple.com/v1"
    static let webURL = URL(string: "https://music.apple.com/")!
    static let requestTimeout: TimeInterval = 10
    static let storefrontProblem = "Không lấy được quốc gia (storefront) của tài khoản Apple Music."
    /// The answer for a song the catalog lists lyrics for and the lyrics endpoints do not give.
    static let missingLyricsReason = "Apple Music did not return the lyrics it lists"
    static let stoppedReason = "Lookup stopped"
    /// What the web player's browser sends; the probe tries it in place of the app's own.
    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    private static let scriptPattern = try! NSRegularExpression(pattern: #"/assets/index[A-Za-z0-9._~-]*\.js"#)
    /// Any JWT: its header can start with `eyJ` and any character (the web player's starts `eyJ0`).
    private static let tokenPattern = try! NSRegularExpression(pattern: #"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#)

    private let client: any HTTPClient
    private let log: any AppleMusicLog
    let account: AppleMusicAccount
    /// The variant of the request that was found to work; used for every later request of the run.
    private var workingVariant: Variant?
    private var hasProbed = false

    init(client: any HTTPClient, account: AppleMusicAccount, log: any AppleMusicLog = OSAppleMusicLog()) {
        self.client = client
        self.account = account
        self.log = log
    }

    /// Whether Apple may be asked: the account is connected and does not need a sign-in.
    var isAvailable: Bool { account.status.isConnected }

    private enum Step: String {
        case catalogSong = "catalog-song"
        case syllableLyrics = "syllable-lyrics"
        case lyrics
    }

    /// How a request differs from the plain one, for the probe.
    private struct Variant {
        var name: String
        var userAgent: String?
        var language: String?
        var decodesUserToken = false

        var details: String {
            "\(name) (userAgent=\(userAgent == nil ? "default" : "Safari") language=\(language ?? "-") decodedUserToken=\(decodesUserToken))"
        }
    }

    private enum Answer {
        case found(LyricsResult)
        /// The catalog entry of the song; nil where it does not say.
        case listing(hasLyrics: Bool?, hasTimeSyncedLyrics: Bool?)
        case notFound
        /// 401 or 403: the tokens are not accepted.
        case rejected
        case unavailable(String)
    }

    private enum Fetched {
        case reply(HTTPReply)
        case failed(String)
    }

    private enum Refresh {
        case token(String)
        /// The page answered, but holds no script or no token: only a sign-in can renew the token now.
        case missing
        case failed(String)
    }

    /// `.synced` or `.plain` lyrics, `.notFound` when Apple has none, `.unavailable` for anything else: not connected, a
    /// rate limit, a failing server, a lost connection, a stopped lookup, a sign-in that needs renewing, or lyrics the
    /// catalog lists and the endpoints do not give.
    ///
    /// - Parameter pace: awaited before every request, true to send it; false stops the lookup.
    func lyrics(forSongID id: String, pace: () async -> Bool) async -> LyricsResult {
        // The id goes into a path: only a catalog song id (digits) is asked about.
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { return .notFound }
        guard isAvailable, let stored = account.credentials, let storefront = stored.storefront else {
            return .unavailable("Apple Music is not connected")
        }
        var credentials = stored
        var hasRefreshed = false
        var steps: [String] = []

        func attempt(_ step: Step, _ parse: (HTTPReply) -> Answer) async -> Answer {
            let request = makeRequest(step, id: id, storefront: storefront, credentials: credentials, variant: workingVariant)
            switch await fetch(request, step: step.rawValue, storefront: storefront, pace: pace) {
            case .reply(let reply):
                steps.append("\(step.rawValue)=\(reply.status)")
                return parse(reply)
            case .failed(let reason):
                steps.append("\(step.rawValue)=failed")
                return .unavailable(reason)
            }
        }

        /// A rejected developer token is renewed once per lookup and the request sent again.
        func ask(_ step: Step, _ parse: (HTTPReply) -> Answer) async -> Answer {
            let answer = await attempt(step, parse)
            guard case .rejected = answer, !hasRefreshed else { return answer }
            hasRefreshed = true
            switch await freshDeveloperToken(pace) {
            case .token(let token):
                credentials.developerToken = token
                account.replaceDeveloperToken(token)
                return await attempt(step, parse)
            case .missing:
                return .rejected
            case .failed(let reason):
                return .unavailable(reason)
            }
        }

        var isListed: Bool?
        switch await ask(.catalogSong, Self.catalogAnswer) {
        case .listing(let hasLyrics, let hasTimeSyncedLyrics):
            if hasLyrics != nil || hasTimeSyncedLyrics != nil { isListed = hasLyrics == true || hasTimeSyncedLyrics == true }
            // The catalog answers the same whether or not the sign-in is accepted: this is a verdict on the song.
            if isListed == false { return .notFound }
        case .notFound, .found:
            return .notFound
        case .rejected:
            return signInExpired()
        case .unavailable(let reason):
            return .unavailable(reason)
        }
        // Word-by-word lyrics first, the line-synced ones when there are none.
        for step in [Step.syllableLyrics, .lyrics] {
            switch await ask(step, Self.lyricsAnswer) {
            case .found(let result): return result
            case .notFound, .listing: continue
            case .rejected: return signInExpired()
            case .unavailable(let reason): return .unavailable(reason)
            }
        }
        // Without a verdict from the catalog, no lyrics is what Apple said.
        guard isListed == true else { return .notFound }
        return await lyricsAreMissing(id: id, storefront: storefront, credentials: credentials, steps: steps, pace: pace)
    }

    /// The store of the account, nil when Apple does not say.
    func storefront(for credentials: AppleMusicCredentials) async -> String? {
        let url = URL(string: "\(Self.apiBase)/me/storefront")!
        guard case .reply(let reply) = await fetch(authorised(url, credentials, variant: nil), step: "storefront", storefront: credentials.storefront, pace: { true }),
              reply.status == 200, let envelope = try? JSONDecoder().decode(Envelope.self, from: reply.body) else { return nil }
        return AppleMusicSessionReader.storefront(envelope.data?.first?.id)
    }

    /// Stores a sign-in the window found, fetching the storefront first when the page did not give it. False (with the
    /// reason in `account.problem`) when that fails or the Keychain refuses; nothing is stored then.
    func connect(_ credentials: AppleMusicCredentials) async -> Bool {
        var credentials = credentials
        if credentials.storefront == nil { credentials.storefront = await storefront(for: credentials) }
        guard credentials.storefront != nil else {
            account.problem = Self.storefrontProblem
            return false
        }
        return account.connect(credentials)
    }

    private func signInExpired() -> LyricsResult {
        account.markNeedsReauth()
        return .unavailable("Apple Music sign-in expired")
    }

    // MARK: lyrics the catalog lists

    /// The catalog lists lyrics and the endpoints gave none: logged as an error, and the first time in a run the lyrics
    /// endpoint is asked again with variants of the request, to see which difference Apple minds. A variant that
    /// returns lyrics is the answer and is used for the rest of the run. At most three extra requests, paced like the others.
    private func lyricsAreMissing(
        id: String, storefront: String, credentials: AppleMusicCredentials, steps: [String], pace: () async -> Bool
    ) async -> LyricsResult {
        write(.error, "Apple Music lists lyrics for the song but returned none: \(steps.joined(separator: " ")) storefront=\(storefront) userToken=\(Self.describe(userToken: credentials.userToken))")
        guard !hasProbed else { return .unavailable(Self.missingLyricsReason) }
        hasProbed = true
        var variants = [
            Variant(name: "safari-user-agent", userAgent: Self.safariUserAgent),
            Variant(name: "safari-user-agent+language", userAgent: Self.safariUserAgent, language: Self.language(ofStorefront: storefront)),
        ]
        if credentials.userToken.contains("%") { variants.append(Variant(name: "decoded-user-token", decodesUserToken: true)) }
        var results: [String] = []
        for variant in variants {
            let request = makeRequest(.lyrics, id: id, storefront: storefront, credentials: credentials, variant: variant)
            switch await fetch(request, step: "lyrics-probe(\(variant.name))", storefront: storefront, pace: pace) {
            case .failed(let reason):
                results.append("\(variant.name)=failed")
                if reason == Self.stoppedReason { return .unavailable(reason) }
            case .reply(let reply):
                results.append("\(variant.name)=\(reply.status)")
                if case .found(let lyrics) = Self.lyricsAnswer(reply) {
                    workingVariant = variant
                    // The default (notice) level, which the log keeps on disk: the line that says what the fix is must survive.
                    write(.default, "Apple lyrics variant that works: \(variant.details)")
                    return lyrics
                }
            }
        }
        write(.error, "Apple Music lyrics probe: no variant returned the lyrics: \(results.joined(separator: " "))")
        return .unavailable(Self.missingLyricsReason)
    }

    /// The language the web player asks in for a storefront: the account's own is not kept, so Vietnam is Vietnamese
    /// and every other store English.
    private static func language(ofStorefront storefront: String) -> String {
        storefront == "vn" ? "vi" : "en-US"
    }

    // MARK: requests

    private func makeRequest(_ step: Step, id: String, storefront: String, credentials: AppleMusicCredentials, variant: Variant?) -> URLRequest {
        var path = "\(Self.apiBase)/catalog/\(storefront)/songs/\(id)"
        if step != .catalogSong { path += "/\(step.rawValue)" }
        var components = URLComponents(string: path)!
        if let language = variant?.language { components.queryItems = [URLQueryItem(name: "l", value: language)] }
        return authorised(components.url!, credentials, variant: variant)
    }

    private func authorised(_ url: URL, _ credentials: AppleMusicCredentials, variant: Variant?) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        let userToken = variant?.decodesUserToken == true ? credentials.userToken.removingPercentEncoding ?? credentials.userToken : credentials.userToken
        request.setValue("Bearer \(credentials.developerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(userToken, forHTTPHeaderField: "Media-User-Token")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        if let userAgent = variant?.userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        return request
    }

    /// Sends the request once `pace` allows and logs how it went. Only the domain and code of an error, never its text:
    /// that can hold the URL, and a message must hold no secret.
    private func fetch(_ request: URLRequest, step: String, storefront: String?, pace: () async -> Bool) async -> Fetched {
        guard await pace() else { return .failed(Self.stoppedReason) }
        do {
            let reply = try await client.send(request)
            record(step, of: request, storefront: storefront, outcome: "status=\(reply.status)\(Self.errorSummary(of: reply, hiding: Self.secrets(of: request)))")
            return .reply(reply)
        } catch {
            let nsError = error as NSError
            let reason = "Request failed (\(nsError.domain) \(nsError.code))"
            record(step, of: request, storefront: storefront, outcome: "failed=\(reason)")
            return .failed(reason)
        }
    }

    // MARK: answers

    private static func answer(for reply: HTTPReply, ok: (Data) -> Answer) -> Answer {
        switch reply.status {
        case 200:
            return ok(reply.body)
        case 404:
            return .notFound
        case 401, 403:
            return .rejected
        case 400..<500 where reply.status != 408 && reply.status != 429:
            // Apple has no lyrics to give for this song (an id that is no catalog song, say): remembered like a 404, not
            // retried at every replay. A timeout or a rate limit says nothing about the song.
            return .notFound
        default:
            return .unavailable("HTTP \(reply.status)")
        }
    }

    private static func lyricsAnswer(_ reply: HTTPReply) -> Answer {
        answer(for: reply) { body in
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return .unavailable("Unreadable answer") }
            // No TTML, or TTML that is no lyrics: the same as nothing there.
            guard let ttml = envelope.data?.first?.attributes?.ttml, let lyrics = TTMLLyricsParser.parse(ttml) else { return .notFound }
            return .found(lyrics)
        }
    }

    private static func catalogAnswer(_ reply: HTTPReply) -> Answer {
        answer(for: reply) { body in
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return .unavailable("Unreadable answer") }
            // No entry: the storefront has no such song.
            guard let song = envelope.data?.first else { return .notFound }
            return .listing(hasLyrics: song.attributes?.hasLyrics, hasTimeSyncedLyrics: song.attributes?.hasTimeSyncedLyrics)
        }
    }

    private nonisolated struct Envelope: Decodable {
        struct Item: Decodable {
            struct Attributes: Decodable {
                var ttml: String?
                var hasLyrics: Bool?
                var hasTimeSyncedLyrics: Bool?
            }
            var id: String?
            var attributes: Attributes?
        }
        var data: [Item]?
    }

    // MARK: log

    private func write(_ level: OSLogType, _ message: String) {
        log.write(message, level: level)
    }

    /// One line per request: what was asked, how Apple answered, and what was attached. Whether a user token went along
    /// and how long it is, never its value; the user agent as set, or the system's when the request sets none.
    private func record(_ step: String, of request: URLRequest, storefront: String?, outcome: String) {
        let userToken = request.value(forHTTPHeaderField: "Media-User-Token").map { Self.describe(userToken: $0) } ?? "none"
        let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? "system default"
        write(.info, "Apple Music \(step): \(outcome) storefront=\(storefront ?? "-") userToken=\(userToken) userAgent=\(userAgent)")
    }

    private static func describe(userToken: String) -> String {
        userToken.isEmpty ? "none" : "attached length=\(userToken.count)"
    }

    /// The values a request carries in its credential headers, in the forms Apple might echo them.
    private static func secrets(of request: URLRequest) -> [String] {
        var values: [String] = []
        if let authorization = request.value(forHTTPHeaderField: "Authorization") {
            values += [authorization, String(authorization.dropFirst("Bearer ".count))]
        }
        if let userToken = request.value(forHTTPHeaderField: "Media-User-Token") {
            values += [userToken, userToken.removingPercentEncoding ?? userToken, userToken.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? userToken]
        }
        return values.filter { !$0.isEmpty }
    }

    /// ` error="<title>" code=<code>` of the first error in a failing answer (Apple's JSON:API errors), kept short, on one
    /// line and with anything that looks like one of the request's own secrets removed; empty for any other answer.
    private static func errorSummary(of reply: HTTPReply, hiding secrets: [String]) -> String {
        guard reply.status >= 400, reply.body.count < 65_536,
              let object = (try? JSONSerialization.jsonObject(with: reply.body)) as? [String: Any],
              let error = (object["errors"] as? [[String: Any]])?.first else { return "" }
        func clean(_ value: Any?) -> String? {
            guard let text = (value as? String) ?? (value as? Int).map(String.init) else { return nil }
            var cleaned = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            for secret in secrets { cleaned = cleaned.replacingOccurrences(of: secret, with: "<redacted>") }
            return String(cleaned.prefix(80))
        }
        return " error=\"\(clean(error["title"]) ?? "-")\" code=\(clean(error["code"]) ?? "-")"
    }

    // MARK: developer token

    /// The token in the web player's own script, found through its page, as a browser would: no credentials go to either
    /// request, and the script is always fetched from music.apple.com whatever the page says.
    private func freshDeveloperToken(_ pace: () async -> Bool) async -> Refresh {
        guard case .reply(let page) = await fetch(URLRequest(url: Self.webURL, timeoutInterval: Self.requestTimeout), step: "token-refresh(page)", storefront: nil, pace: pace) else {
            return .failed("Token refresh failed")
        }
        guard page.status == 200 else { return .failed("Token refresh failed (HTTP \(page.status))") }
        guard let path = Self.firstMatch(of: Self.scriptPattern, in: page.body),
              let scriptURL = URL(string: path, relativeTo: Self.webURL)?.absoluteURL else { return .missing }
        guard case .reply(let script) = await fetch(URLRequest(url: scriptURL, timeoutInterval: Self.requestTimeout), step: "token-refresh(script)", storefront: nil, pace: pace) else {
            return .failed("Token refresh failed")
        }
        guard script.status == 200 else { return .failed("Token refresh failed (HTTP \(script.status))") }
        guard let token = Self.developerToken(in: script.body) else { return .missing }
        return .token(token)
    }

    private static func firstMatch(of regex: NSRegularExpression, in data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        guard let range = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)).flatMap({ Range($0.range, in: text) }) else { return nil }
        return String(text[range])
    }

    /// The first JWT in the script whose header says ES256, which is how Apple signs developer tokens: scripts hold other
    /// text shaped like one.
    private static func developerToken(in data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        var token: String?
        tokenPattern.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, stop in
            guard let match, let range = Range(match.range, in: text), isES256(String(text[range])) else { return }
            token = String(text[range])
            stop.pointee = true
        }
        return token
    }

    private static func isES256(_ jwt: String) -> Bool {
        guard let header = jwt.split(separator: ".").first else { return false }
        var base64 = header.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return object["alg"] as? String == "ES256"
    }
}
