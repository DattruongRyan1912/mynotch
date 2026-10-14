import Foundation

/// Asks Apple Music's web API for the lyrics of a catalog song with the user's own sign-in (unofficial: the API the
/// music.apple.com player uses, which Apple may change). Sends requests through the injected `HTTPClient`; the
/// caller decides when each one may go out.
///
/// A rejected developer token is refreshed once without the user, from the web player's own script; rejected again,
/// the account needs a sign-in and Apple is left alone until then. Nothing here puts a token into an answer or a message.
final class AppleMusicLyricsClient {
    static let apiBase = "https://amp-api.music.apple.com/v1"
    static let webURL = URL(string: "https://music.apple.com/")!
    static let requestTimeout: TimeInterval = 10
    static let storefrontProblem = "Không lấy được quốc gia (storefront) của tài khoản Apple Music."
    /// Word-by-word lyrics first, the line-synced ones when there are none.
    private static let endpoints = ["syllable-lyrics", "lyrics"]
    private static let scriptPattern = try! NSRegularExpression(pattern: #"/assets/index[A-Za-z0-9._~-]*\.js"#)
    private static let tokenPattern = try! NSRegularExpression(pattern: #"eyJh[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#)

    private let client: any HTTPClient
    let account: AppleMusicAccount

    init(client: any HTTPClient, account: AppleMusicAccount) {
        self.client = client
        self.account = account
    }

    /// Whether Apple may be asked: the account is connected and does not need a sign-in.
    var isAvailable: Bool { account.status.isConnected }

    private enum Answer {
        case found(LyricsResult)
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
    /// rate limit, a failing server, a lost connection, a stopped lookup or a sign-in that needs renewing.
    ///
    /// - Parameter pace: awaited before every request, true to send it; false stops the lookup.
    func lyrics(forSongID id: String, pace: () async -> Bool) async -> LyricsResult {
        // The id goes into a path: only a catalog song id (digits) is asked about.
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { return .notFound }
        guard isAvailable, var credentials = account.credentials, let storefront = credentials.storefront else {
            return .unavailable("Apple Music is not connected")
        }
        var hasRefreshed = false
        for endpoint in Self.endpoints {
            let url = URL(string: "\(Self.apiBase)/catalog/\(storefront)/songs/\(id)/\(endpoint)")!
            var answer = await ask(url, credentials, pace)
            if case .rejected = answer {
                guard !hasRefreshed else { return signInExpired() }
                hasRefreshed = true
                switch await freshDeveloperToken(pace) {
                case .token(let token):
                    credentials.developerToken = token
                    account.replaceDeveloperToken(token)
                    answer = await ask(url, credentials, pace)
                case .missing:
                    return signInExpired()
                case .failed(let reason):
                    return .unavailable(reason)
                }
            }
            switch answer {
            case .found(let result): return result
            case .notFound: continue
            case .rejected: return signInExpired()
            case .unavailable(let reason): return .unavailable(reason)
            }
        }
        return .notFound
    }

    /// The store of the account, nil when Apple does not say.
    func storefront(for credentials: AppleMusicCredentials) async -> String? {
        let url = URL(string: "\(Self.apiBase)/me/storefront")!
        guard case .reply(let reply) = await fetch(authorised(url, credentials), pace: { true }), reply.status == 200,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: reply.body) else { return nil }
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

    // MARK: requests

    private func ask(_ url: URL, _ credentials: AppleMusicCredentials, _ pace: () async -> Bool) async -> Answer {
        switch await fetch(authorised(url, credentials), pace: pace) {
        case .reply(let reply): Self.answer(for: reply)
        case .failed(let reason): .unavailable(reason)
        }
    }

    /// Only the domain and code of an error, never its text: that can hold the URL, and a message must hold no secret.
    private func fetch(_ request: URLRequest, pace: () async -> Bool) async -> Fetched {
        guard await pace() else { return .failed("Lookup stopped") }
        do {
            return .reply(try await client.send(request))
        } catch {
            let nsError = error as NSError
            return .failed("Request failed (\(nsError.domain) \(nsError.code))")
        }
    }

    private func authorised(_ url: URL, _ credentials: AppleMusicCredentials) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.setValue("Bearer \(credentials.developerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.userToken, forHTTPHeaderField: "Media-User-Token")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        return request
    }

    private static func answer(for reply: HTTPReply) -> Answer {
        switch reply.status {
        case 200:
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: reply.body) else { return .unavailable("Unreadable answer") }
            // No TTML, or TTML that is no lyrics: the same as nothing there.
            guard let ttml = envelope.data?.first?.attributes?.ttml, let lyrics = TTMLLyricsParser.parse(ttml) else { return .notFound }
            return .found(lyrics)
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

    private nonisolated struct Envelope: Decodable {
        struct Item: Decodable {
            struct Attributes: Decodable { var ttml: String? }
            var id: String?
            var attributes: Attributes?
        }
        var data: [Item]?
    }

    // MARK: developer token

    /// The token in the web player's own script, found through its page, as a browser would: no credentials go to either
    /// request, and the script is always fetched from music.apple.com whatever the page says.
    private func freshDeveloperToken(_ pace: () async -> Bool) async -> Refresh {
        guard case .reply(let page) = await fetch(URLRequest(url: Self.webURL, timeoutInterval: Self.requestTimeout), pace: pace) else {
            return .failed("Token refresh failed")
        }
        guard page.status == 200 else { return .failed("Token refresh failed (HTTP \(page.status))") }
        guard let path = Self.firstMatch(of: Self.scriptPattern, in: page.body),
              let scriptURL = URL(string: path, relativeTo: Self.webURL)?.absoluteURL else { return .missing }
        guard case .reply(let script) = await fetch(URLRequest(url: scriptURL, timeoutInterval: Self.requestTimeout), pace: pace) else {
            return .failed("Token refresh failed")
        }
        guard script.status == 200 else { return .failed("Token refresh failed (HTTP \(script.status))") }
        guard let token = Self.firstMatch(of: Self.tokenPattern, in: script.body) else { return .missing }
        return .token(token)
    }

    private static func firstMatch(of regex: NSRegularExpression, in data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        guard let range = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)).flatMap({ Range($0.range, in: text) }) else { return nil }
        return String(text[range])
    }
}
