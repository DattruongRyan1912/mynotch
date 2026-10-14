import Foundation
import os

/// Asks Apple Music's web API for the lyrics of a catalog song with the user's own sign-in (unofficial: the API the
/// music.apple.com player uses, which Apple may change). Sends requests through the injected `HTTPClient`; the
/// caller decides when each one may go out.
///
/// The account's own storefront is asked once per run (`/v1/me/storefront`): MusicKit's `storefrontId` can say "us" for
/// an account whose lyrics are licensed in another country, and the lyrics are asked in the account's. The lyrics requests
/// carry the parameters the web player's current tools send (`l[lyrics]`, `extend=ttmlLocalizations`, `l[script]`).
///
/// The catalog is asked next whether the song has lyrics at all: Apple answers a lyrics request it will not serve with
/// 404 "No related resources", the same as for a song without lyrics. A song that lists lyrics but gets none is therefore
/// not "not found": it is `.unavailable`, so nothing is remembered, and once per run a few variants of the request are
/// tried to find out which difference Apple minds (the one that works is used from then on).
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
    /// The language lyrics are asked in when the storefront does not name one.
    static let defaultLanguage = "en-US"
    private static let scriptPattern = try! NSRegularExpression(pattern: #"/assets/index[A-Za-z0-9._~-]*\.js"#)
    /// Any JWT: its header can start with `eyJ` and any character (the web player's starts `eyJ0`).
    private static let tokenPattern = try! NSRegularExpression(pattern: #"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#)
    private static let languagePattern = try! NSRegularExpression(pattern: #"^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$"#)

    /// What `/v1/me/storefront` says about the account: its country and the language it uses by default.
    struct AccountStorefront: Equatable {
        var id: String
        /// `attributes.defaultLanguageTag`, when it is a language tag.
        var language: String?
    }

    private let client: any HTTPClient
    private let log: any AppleMusicLog
    let account: AppleMusicAccount
    /// What the account's storefront answered this run.
    private var accountStorefront: AccountStorefront?
    /// The storefront MusicKit gave when it is not the account's; tried by the probe.
    private var musicKitStorefront: String?
    private var hasCheckedStorefront = false
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
        case accountStorefront = "storefront"
        case catalogSong = "catalog-song"
        case syllableLyrics = "syllable-lyrics"
        case lyrics

        var isLyrics: Bool { self == .syllableLyrics || self == .lyrics }
    }

    /// How a lyrics request differs from the normal one (the account's storefront, with the lyric parameters).
    private struct Variant {
        var name: String
        var storefront: String?
        var usesLyricParameters: Bool

        var details: String { "\(name) (storefront=\(storefront ?? "-") lyricParameters=\(usesLyricParameters))" }
    }

    private enum Answer {
        case found(LyricsResult)
        /// The catalog entry of the song; nil where it does not say.
        case listing(hasLyrics: Bool?, hasTimeSyncedLyrics: Bool?)
        case account(AccountStorefront)
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
        guard isAvailable, let stored = account.credentials, var storefront = stored.storefront else {
            return .unavailable("Apple Music is not connected")
        }
        var credentials = stored
        var refresh: Refresh?
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

        /// A rejected developer token is renewed once per lookup and the request sent again. A renewal that failed (the
        /// page could not be reached) is no reason to say the sign-in is bad: the answer is unavailable, then and later.
        func ask(_ step: Step, _ parse: (HTTPReply) -> Answer) async -> Answer {
            let answer = await attempt(step, parse)
            guard case .rejected = answer else { return answer }
            if refresh == nil {
                refresh = await freshDeveloperToken(pace)
                if case .token(let token) = refresh {
                    credentials.developerToken = token
                    account.replaceDeveloperToken(token)
                    return await attempt(step, parse)
                }
            }
            switch refresh {
            case .failed(let reason): return .unavailable(reason)
            default: return .rejected
            }
        }

        if !hasCheckedStorefront {
            switch await ask(.accountStorefront, Self.accountStorefrontAnswer) {
            case .account(let answer):
                hasCheckedStorefront = true
                storefront = adopt(answer, stored: storefront)
            case .notFound, .rejected:
                // Nothing to learn from asking again; whether the sign-in is good is for the lyrics to say.
                hasCheckedStorefront = true
            default:
                break
            }
        }

        var isListed: Bool?
        switch await ask(.catalogSong, Self.catalogAnswer) {
        case .listing(let hasLyrics, let hasTimeSyncedLyrics):
            if hasLyrics != nil || hasTimeSyncedLyrics != nil { isListed = hasLyrics == true || hasTimeSyncedLyrics == true }
            // The catalog answers the same whether or not the sign-in is accepted: this is a verdict on the song.
            if isListed == false { return .notFound }
        case .notFound, .found, .account:
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
            case .notFound, .listing, .account: continue
            case .rejected: return signInExpired()
            case .unavailable(let reason): return .unavailable(reason)
            }
        }
        // Without a verdict from the catalog, no lyrics is what Apple said.
        guard isListed == true else { return .notFound }
        return await lyricsAreMissing(id: id, storefront: storefront, credentials: credentials, steps: steps, pace: pace)
    }

    /// The account's storefront and default language, from `/v1/me/storefront`; nil when Apple does not say. Asked with
    /// the tokens as they are, and not through a lookup: this is what `connect` uses.
    func storefront(for credentials: AppleMusicCredentials) async -> AccountStorefront? {
        let request = makeRequest(.accountStorefront, id: "", storefront: credentials.storefront ?? "", credentials: credentials, variant: nil)
        guard case .reply(let reply) = await fetch(request, step: Step.accountStorefront.rawValue, storefront: credentials.storefront, pace: { true }),
              case .account(let answer) = Self.accountStorefrontAnswer(reply) else { return nil }
        return answer
    }

    /// Stores a sign-in the window found. The storefront stored is the account's own (`/v1/me/storefront`), not MusicKit's
    /// from the page, which is kept for the probe; the page's is used when Apple does not answer. False (with the reason
    /// in `account.problem`) when there is none or the Keychain refuses; nothing is stored then.
    func connect(_ credentials: AppleMusicCredentials) async -> Bool {
        var credentials = credentials
        if let answer = await storefront(for: credentials) {
            hasCheckedStorefront = true
            credentials.storefront = adopt(answer, stored: credentials.storefront)
        }
        guard credentials.storefront != nil else {
            account.problem = Self.storefrontProblem
            return false
        }
        return account.connect(credentials)
    }

    /// Takes what the account's storefront said: remembers it and its language, keeps the one it replaces (MusicKit's) for
    /// the probe, stores the new one. Returns the storefront to use.
    private func adopt(_ answer: AccountStorefront, stored: String?) -> String {
        accountStorefront = answer
        let changed = stored != answer.id
        if let stored, changed {
            musicKitStorefront = stored
            account.replaceStorefront(answer.id)
        }
        write(.default, "Apple Music account storefront: id=\(answer.id) stored=\(stored ?? "-") language=\(answer.language ?? "-") changed=\(changed)")
        return answer.id
    }

    private func signInExpired() -> LyricsResult {
        account.markNeedsReauth()
        return .unavailable("Apple Music sign-in expired")
    }

    // MARK: lyrics the catalog lists

    /// The catalog lists lyrics and the endpoints gave none: logged as an error, and the first time in a run the lyrics
    /// endpoint is asked again with variants of the request, to see which difference Apple minds: (a) the lyric parameters
    /// with the account's storefront, (b) the same with the storefront MusicKit gave, (c) no parameters, the account's
    /// storefront. A variant the lookup has asked already is not asked twice (that is the normal request, (a) as a rule, and
    /// its answer is in the log). A variant that returns lyrics is the answer and is used for the rest of the run. At most
    /// three extra requests, paced like the others.
    private func lyricsAreMissing(
        id: String, storefront: String, credentials: AppleMusicCredentials, steps: [String], pace: () async -> Bool
    ) async -> LyricsResult {
        write(.error, "Apple Music lists lyrics for the song but returned none: \(steps.joined(separator: " ")) storefront=\(storefront) userToken=\(Self.describe(userToken: credentials.userToken))")
        guard !hasProbed else { return .unavailable(Self.missingLyricsReason) }
        hasProbed = true
        let variants = [
            Variant(name: "params+account-storefront", storefront: accountStorefront?.id, usesLyricParameters: true),
            Variant(name: "params+musickit-storefront", storefront: musicKitStorefront, usesLyricParameters: true),
            Variant(name: "no-params+account-storefront", storefront: accountStorefront?.id ?? storefront, usesLyricParameters: false),
        ]
        var results: [String] = []
        for variant in variants {
            let step = "lyrics-probe(\(variant.name))"
            guard let variantStorefront = variant.storefront else {
                let reason = variant.name.contains("musickit") ? "no other storefront is known" : "the account's storefront is not known"
                write(.default, "Apple Music \(step): skipped, \(reason)")
                results.append("\(variant.name)=skipped")
                continue
            }
            if variant.usesLyricParameters && variantStorefront == storefront {
                write(.default, "Apple Music \(step): skipped, the same as the normal request")
                results.append("\(variant.name)=skipped")
                continue
            }
            let request = makeRequest(.lyrics, id: id, storefront: storefront, credentials: credentials, variant: variant)
            switch await fetch(request, step: step, storefront: variantStorefront, pace: pace) {
            case .failed(let reason):
                results.append("\(variant.name)=failed")
                if reason == Self.stoppedReason { return .unavailable(reason) }
            case .reply(let reply):
                results.append("\(variant.name)=\(reply.status)")
                if case .found(let lyrics) = Self.lyricsAnswer(reply) {
                    workingVariant = variant
                    write(.default, "Apple lyrics variant that works: \(variant.details)")
                    return lyrics
                }
            }
        }
        write(.error, "Apple Music lyrics probe: no variant returned the lyrics: \(results.joined(separator: " "))")
        return .unavailable(Self.missingLyricsReason)
    }

    // MARK: requests

    /// `storefront` is the one the lookup uses; a variant can name another for the catalog and lyrics paths.
    private func makeRequest(_ step: Step, id: String, storefront: String, credentials: AppleMusicCredentials, variant: Variant?) -> URLRequest {
        let path: String
        switch step {
        case .accountStorefront: path = "\(Self.apiBase)/me/storefront"
        case .catalogSong: path = "\(Self.apiBase)/catalog/\(variant?.storefront ?? storefront)/songs/\(id)"
        case .syllableLyrics, .lyrics: path = "\(Self.apiBase)/catalog/\(variant?.storefront ?? storefront)/songs/\(id)/\(step.rawValue)"
        }
        var components = URLComponents(string: path)!
        if step.isLyrics, variant?.usesLyricParameters ?? true { components.percentEncodedQuery = lyricQuery }
        var request = URLRequest(url: components.url!, timeoutInterval: Self.requestTimeout)
        request.setValue("Bearer \(credentials.developerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.userToken, forHTTPHeaderField: "Media-User-Token")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        return request
    }

    /// What the web player's tools send with a lyrics request: the language to ask in, the localizations, and the script of
    /// the lyrics. Brackets are percent-encoded; the language is a validated tag, so nothing else needs it.
    private var lyricQuery: String {
        let language = accountStorefront?.language ?? Self.defaultLanguage
        var query = "l%5Blyrics%5D=\(language)&extend=ttmlLocalizations"
        if let script = Self.scriptTag(forLanguage: language) { query += "&l%5Bscript%5D=\(script)" }
        return query
    }

    /// The script of a language's lyrics as the `l[script]` parameter writes it ("vi-Latn", "ja-Jpan", "zh-Hans"); nil
    /// where the script is not known.
    static func scriptTag(forLanguage tag: String) -> String? {
        let parts = tag.split(separator: "-").map(String.init)
        guard let base = parts.first?.lowercased() else { return nil }
        if let script = parts.dropFirst().first(where: { $0.count == 4 && $0.allSatisfy(\.isLetter) }) { return "\(base)-\(script.capitalized)" }
        if base == "zh" { return parts.dropFirst().contains { ["TW", "HK", "MO"].contains($0.uppercased()) } ? "zh-Hant" : "zh-Hans" }
        if let script = nonLatinScripts[base] { return "\(base)-\(script)" }
        return latinLanguages.contains(base) ? "\(base)-Latn" : nil
    }

    private static let nonLatinScripts = [
        "ja": "Jpan", "ko": "Kore", "th": "Thai", "ar": "Arab", "he": "Hebr", "fa": "Arab", "ur": "Arab", "ru": "Cyrl", "uk": "Cyrl",
        "bg": "Cyrl", "el": "Grek", "hi": "Deva", "mr": "Deva", "bn": "Beng", "ta": "Taml", "te": "Telu", "kn": "Knda", "ml": "Mlym",
        "gu": "Gujr", "pa": "Guru",
    ]
    private static let latinLanguages: Set<String> = [
        "en", "vi", "fr", "de", "es", "pt", "it", "nl", "sv", "da", "no", "nb", "nn", "fi", "pl", "cs", "sk", "hu", "ro", "tr", "id",
        "ms", "tl", "fil", "ca", "hr", "sl", "et", "lv", "lt", "is", "sq",
    ]

    private static func validLanguageTag(_ text: String?) -> String? {
        guard let text, text.count <= 35,
              languagePattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else { return nil }
        return text
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

    /// The localizations first (the answer to `extend=ttmlLocalizations`), then the plain TTML: whichever holds lyrics.
    private static func lyricsAnswer(_ reply: HTTPReply) -> Answer {
        answer(for: reply) { body in
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return .unavailable("Unreadable answer") }
            // No TTML, or TTML that is no lyrics: the same as nothing there.
            let attributes = envelope.data?.first?.attributes
            for ttml in [attributes?.ttmlLocalizations, attributes?.ttml] {
                if let ttml, let lyrics = TTMLLyricsParser.parse(ttml) { return .found(lyrics) }
            }
            return .notFound
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

    private static func accountStorefrontAnswer(_ reply: HTTPReply) -> Answer {
        answer(for: reply) { body in
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return .unavailable("Unreadable answer") }
            guard let item = envelope.data?.first, let id = AppleMusicSessionReader.storefront(item.id) else { return .notFound }
            return .account(AccountStorefront(id: id, language: validLanguageTag(item.attributes?.defaultLanguageTag)))
        }
    }

    /// Apple's attributes are not ours to be strict about: a value of another type is the same as none.
    private nonisolated struct Envelope: Decodable {
        struct Item: Decodable {
            struct Attributes: Decodable {
                var ttml: String?
                var ttmlLocalizations: String?
                var hasLyrics: Bool?
                var hasTimeSyncedLyrics: Bool?
                var defaultLanguageTag: String?

                private enum CodingKeys: String, CodingKey { case ttml, ttmlLocalizations, hasLyrics, hasTimeSyncedLyrics, defaultLanguageTag }

                init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    ttml = try? container.decodeIfPresent(String.self, forKey: .ttml)
                    ttmlLocalizations = try? container.decodeIfPresent(String.self, forKey: .ttmlLocalizations)
                    hasLyrics = try? container.decodeIfPresent(Bool.self, forKey: .hasLyrics)
                    hasTimeSyncedLyrics = try? container.decodeIfPresent(Bool.self, forKey: .hasTimeSyncedLyrics)
                    defaultLanguageTag = try? container.decodeIfPresent(String.self, forKey: .defaultLanguageTag)
                }
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

    /// One line per request, at the default (notice) level that the log keeps on disk: what was asked, how Apple answered,
    /// and what was attached. Whether a user token went along and how long it is, never its value; the user agent as set,
    /// or the system's when the request sets none; the lyric parameters, which hold no secret.
    private func record(_ step: String, of request: URLRequest, storefront: String?, outcome: String) {
        let userToken = request.value(forHTTPHeaderField: "Media-User-Token").map { Self.describe(userToken: $0) } ?? "none"
        let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? "system default"
        let query = request.url?.query.map { " query=\($0)" } ?? ""
        write(.default, "Apple Music \(step): \(outcome) storefront=\(storefront ?? "-") userToken=\(userToken) userAgent=\(userAgent)\(query)")
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
