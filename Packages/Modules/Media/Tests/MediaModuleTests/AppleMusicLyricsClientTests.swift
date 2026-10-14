import Foundation
import Testing
@testable import MediaModule

/// Apple Music web API answers, shaped like the real ones, with fake tokens and placeholder words.
enum AppleReplies {
    static let developerToken = "dev-token-fake"
    static let userToken = "user-token-fake"
    static let freshToken = "eyJhZmFrZS1oZWFkZXI.ZmFrZS1wYXlsb2Fk.ZmFrZS1zaWduYXR1cmU"
    static let otherToken = "eyJhb3RoZXItaGVhZGVy.b3RoZXItcGF5bG9hZA.b3RoZXItc2ln"

    /// A TTML document of `count` lines reading "<tag> 1", "<tag> 2", ... one second apart.
    static func ttml(timing: String = "Line", count: Int = 4, tag: String = "line") -> String {
        let lines = (0..<count).map { index in
            let text = "\(tag) \(index + 1)"
            let begin = String(format: "%d.000", index + 1)
            return timing == "Word"
                ? #"<p begin="\#(begin)"><span begin="\#(begin)">\#(tag)</span> <span begin="\#(begin)">\#(index + 1)</span></p>"#
                : timing == "None" ? "<p>\(text)</p>" : #"<p begin="\#(begin)">\#(text)</p>"#
        }
        return #"<tt xmlns="http://www.w3.org/ns/ttml" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" itunes:timing="\#(timing)"><body><div>\#(lines.joined())</div></body></tt>"#
    }

    /// What `ttml(timing: "Line" or "Word", count:, tag:)` parses to.
    static func lines(count: Int = 4, tag: String = "line") -> [LyricLine] {
        (0..<count).map { LyricLine(time: Double($0 + 1), text: "\(tag) \($0 + 1)") }
    }

    /// `data[0].attributes.ttml`, as the web API sends it.
    static func lyrics(ttml: String, type: String = "syllable-lyrics") -> HTTPReply {
        let object: [String: Any] = ["data": [["id": "1856960468", "type": type, "attributes": ["ttml": ttml, "playParams": ["id": "1856960468", "kind": "lyrics"]]]]]
        return HTTPReply(status: 200, body: try! JSONSerialization.data(withJSONObject: object))
    }

    static let empty = HTTPReply(status: 200, body: Data(#"{"data":[]}"#.utf8))
    static let notFound = HTTPReply(status: 404, body: Data(#"{"errors":[{"status":"404","code":"40400"}]}"#.utf8))
    static let rejected = HTTPReply(status: 401, body: Data(#"{"errors":[{"status":"401","code":"40100"}]}"#.utf8))
    static let forbidden = HTTPReply(status: 403, body: Data(#"{"errors":[{"status":"403","code":"40300"}]}"#.utf8))

    static func storefront(_ id: String = "vn") -> HTTPReply {
        let object: [String: Any] = ["data": [["id": id, "type": "storefronts", "attributes": ["name": "Fake"]]]]
        return HTTPReply(status: 200, body: try! JSONSerialization.data(withJSONObject: object))
    }

    static let page = HTTPReply(status: 200, body: Data("""
    <!doctype html><html><head><link rel="stylesheet" href="/assets/index-d4e5f6.css">
    <script type="module" crossorigin src="/assets/index-a1b2c3.js"></script></head><body></body></html>
    """.utf8))

    static func bundle(containing tokens: [String]) -> HTTPReply {
        let body = #"var a="eyJzdHJpbmc";var b="x.y";"# + tokens.map { #"var t="\#($0)";"# }.joined() + "var c=1;"
        return HTTPReply(status: 200, body: Data(body.utf8))
    }
}

@Suite struct AppleMusicLyricsClientTests {
    let tokens = FakeTokenStore.connected()
    let http = FakeHTTPClient()
    let account: AppleMusicAccount
    let client: AppleMusicLyricsClient

    init() {
        account = AppleMusicAccount(tokens: tokens)
        account.load()
        client = AppleMusicLyricsClient(client: http, account: account)
    }

    func ask(_ id: String = "1856960468") async -> LyricsResult {
        await client.lyrics(forSongID: id, pace: { true })
    }

    /// "host/path" of every request sent so far.
    var calls: [String] { http.requests.map { "\($0.url!.host()!)\($0.url!.path())" } }

    func header(_ name: String, of request: URLRequest) -> String? { request.value(forHTTPHeaderField: name) }

    static let api = "amp-api.music.apple.com/v1/catalog/vn/songs/1856960468"

    // MARK: request

    @Test func askingForSyllableLyricsShapesTheRequest() async throws {
        http.reply(AppleReplies.lyrics(ttml: AppleReplies.ttml(timing: "Word")))
        #expect(await ask() == .synced(AppleReplies.lines(tag: "line")))
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://amp-api.music.apple.com/v1/catalog/vn/songs/1856960468/syllable-lyrics")
        #expect(header("Authorization", of: request) == "Bearer dev-token-fake")
        #expect(header("Media-User-Token", of: request) == "user-token-fake")
        #expect(header("Origin", of: request) == "https://music.apple.com")
        #expect(header("Referer", of: request) == "https://music.apple.com/")
        #expect(request.timeoutInterval == AppleMusicLyricsClient.requestTimeout)
    }

    @Test func theStorefrontOfTheAccountIsInThePath() async {
        let other = FakeTokenStore.connected(storefront: "us")
        let account = AppleMusicAccount(tokens: other)
        account.load()
        let client = AppleMusicLyricsClient(client: http, account: account)
        http.reply(AppleReplies.lyrics(ttml: AppleReplies.ttml()))
        _ = await client.lyrics(forSongID: "42", pace: { true })
        #expect(calls == ["amp-api.music.apple.com/v1/catalog/us/songs/42/syllable-lyrics"])
    }

    @Test func aSongIdThatIsNotDigitsIsNeverAsked() async {
        for id in ["", "12/../3", "12a", "1 2", "١٢٣"] {
            #expect(await ask(id) == .notFound, "\(id)")
        }
        #expect(http.requests.isEmpty)
    }

    // MARK: answers

    @Test func lineSyncedLyricsFromTheSyllableEndpoint() async {
        http.reply(AppleReplies.lyrics(ttml: AppleReplies.ttml(timing: "Line", count: 5, tag: "la")))
        #expect(await ask() == .synced(AppleReplies.lines(count: 5, tag: "la")))
    }

    @Test func plainLyricsAreAnAnswerToo() async {
        http.reply(AppleReplies.lyrics(ttml: AppleReplies.ttml(timing: "None", count: 2, tag: "words")))
        #expect(await ask() == .plain("words 1\nwords 2"))
        #expect(http.requests.count == 1)
    }

    @Test func a404FallsBackToTheLyricsEndpoint() async throws {
        http.handler = { request in
            request.url!.path().hasSuffix("/syllable-lyrics") ? AppleReplies.notFound : AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 6, tag: "plain"), type: "lyrics")
        }
        #expect(await ask() == .synced(AppleReplies.lines(count: 6, tag: "plain")))
        #expect(calls == ["\(Self.api)/syllable-lyrics", "\(Self.api)/lyrics"])
        let second = try #require(http.requests.last)
        #expect(header("Authorization", of: second) == "Bearer dev-token-fake")
        #expect(header("Media-User-Token", of: second) == "user-token-fake")
        #expect(header("Origin", of: second) == "https://music.apple.com")
        #expect(header("Referer", of: second) == "https://music.apple.com/")
    }

    @Test func noTTMLFallsBackToTheLyricsEndpointToo() async {
        for first in [AppleReplies.empty, AppleReplies.lyrics(ttml: ""), AppleReplies.lyrics(ttml: "<tt><unclosed>"), HTTPReply(status: 200, body: Data(#"{"data":[{"attributes":{}}]}"#.utf8))] {
            http.handler = { request in
                request.url!.path().hasSuffix("/syllable-lyrics") ? first : AppleReplies.lyrics(ttml: AppleReplies.ttml(), type: "lyrics")
            }
            #expect(await ask() == .synced(AppleReplies.lines()))
        }
        #expect(http.requests.count == 8)
    }

    @Test func notFoundOnBothEndpointsIsNotFound() async {
        http.reply(AppleReplies.notFound)
        #expect(await ask() == .notFound)
        #expect(calls == ["\(Self.api)/syllable-lyrics", "\(Self.api)/lyrics"])
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test func emptyOnBothEndpointsIsNotFound() async {
        http.reply(AppleReplies.empty)
        #expect(await ask() == .notFound)
        #expect(http.requests.count == 2)
    }

    // MARK: failures

    @Test(arguments: [429, 500, 502, 503, 400])
    func otherStatusesAreUnavailableAndNothingMoreIsAsked(status: Int) async {
        http.reply(HTTPReply(status: status, body: Data("busy".utf8), retryAfter: "30"))
        let result = await ask()
        #expect(result.isUnavailable)
        #expect(http.requests.count == 1)
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test func aFailureOnTheSecondEndpointIsUnavailable() async {
        http.handler = { request in
            request.url!.path().hasSuffix("/syllable-lyrics") ? AppleReplies.notFound : HTTPReply(status: 503)
        }
        #expect(await ask().isUnavailable)
    }

    @Test func aDeadConnectionIsUnavailable() async {
        http.handler = { _ in throw URLError(.notConnectedToInternet) }
        #expect(await ask().isUnavailable)
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test func anUnreadableAnswerIsUnavailable() async {
        http.reply(HTTPReply(status: 200, body: Data("<html>captive portal</html>".utf8)))
        #expect(await ask().isUnavailable)
    }

    // MARK: sign-in rejected

    /// 401 for the stored developer token, the lyrics for the fresh one: what Apple does after the old one expired.
    func expiredToken(bundle: HTTPReply = AppleReplies.bundle(containing: [AppleReplies.freshToken])) {
        http.handler = { request in
            switch request.url!.host() {
            case "music.apple.com":
                return request.url!.path() == "/" ? AppleReplies.page : bundle
            default:
                let isFresh = request.value(forHTTPHeaderField: "Authorization") == "Bearer \(AppleReplies.freshToken)"
                return isFresh ? AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 5, tag: "fresh")) : AppleReplies.rejected
            }
        }
    }

    @Test func aRejectedTokenIsRefreshedAndTheRequestRetriedOnce() async throws {
        expiredToken()
        #expect(await ask() == .synced(AppleReplies.lines(count: 5, tag: "fresh")))
        #expect(calls == [
            "\(Self.api)/syllable-lyrics", "music.apple.com/", "music.apple.com/assets/index-a1b2c3.js", "\(Self.api)/syllable-lyrics",
        ])
        #expect(header("Authorization", of: http.requests[0]) == "Bearer dev-token-fake")
        #expect(header("Authorization", of: http.requests[3]) == "Bearer \(AppleReplies.freshToken)")
        #expect(header("Media-User-Token", of: http.requests[3]) == "user-token-fake")
        #expect(account.credentials?.developerToken == AppleReplies.freshToken)
        #expect(tokens.values[.developerToken] == AppleReplies.freshToken)
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test func theRefreshSendsNoCredentialsToTheWebPageOrItsScript() async {
        expiredToken()
        _ = await ask()
        for request in http.requests where request.url!.host() == "music.apple.com" {
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Media-User-Token") == nil)
            #expect(request.httpMethod == "GET")
        }
    }

    @Test func aForbiddenAnswerIsHandledLikeARejectedOne() async {
        http.handler = { request in
            switch request.url!.host() {
            case "music.apple.com": return request.url!.path() == "/" ? AppleReplies.page : AppleReplies.bundle(containing: [AppleReplies.freshToken])
            default: return request.value(forHTTPHeaderField: "Authorization") == "Bearer \(AppleReplies.freshToken)" ? AppleReplies.lyrics(ttml: AppleReplies.ttml()) : AppleReplies.forbidden
            }
        }
        #expect(await ask() == .synced(AppleReplies.lines()))
        #expect(http.requests.count == 4)
    }

    @Test func theFirstTokenInTheScriptIsTheOne() async {
        expiredToken(bundle: AppleReplies.bundle(containing: [AppleReplies.freshToken, AppleReplies.otherToken]))
        _ = await ask()
        #expect(account.credentials?.developerToken == AppleReplies.freshToken)
    }

    @Test func rejectedTwiceNeedsASignInAndNothingMoreIsAsked() async {
        http.handler = { request in
            switch request.url!.host() {
            case "music.apple.com": request.url!.path() == "/" ? AppleReplies.page : AppleReplies.bundle(containing: [AppleReplies.freshToken])
            default: AppleReplies.rejected
            }
        }
        let result = await ask()
        #expect(result.isUnavailable)
        #expect(calls == ["\(Self.api)/syllable-lyrics", "music.apple.com/", "music.apple.com/assets/index-a1b2c3.js", "\(Self.api)/syllable-lyrics"])
        #expect(account.status == .needsReauth)
        #expect(!client.isAvailable)

        // Until the user signs in again Apple is left alone.
        let before = http.requests.count
        #expect(await ask().isUnavailable)
        #expect(await ask("42").isUnavailable)
        #expect(http.requests.count == before)
    }

    @Test func theRefreshHappensOncePerLookup() async {
        http.handler = { request in
            switch request.url!.host() {
            case "music.apple.com":
                return request.url!.path() == "/" ? AppleReplies.page : AppleReplies.bundle(containing: [AppleReplies.freshToken])
            default:
                // The fresh token is fine for the first endpoint (nothing there), the second endpoint rejects everything.
                let isSyllable = request.url!.path().hasSuffix("/syllable-lyrics")
                return isSyllable && request.value(forHTTPHeaderField: "Authorization") == "Bearer \(AppleReplies.freshToken)" ? AppleReplies.notFound : AppleReplies.rejected
            }
        }
        #expect(await ask().isUnavailable)
        #expect(calls.filter { $0 == "music.apple.com/" }.count == 1)
        #expect(account.status == .needsReauth)
    }

    @Test func aPageWithoutAScriptNeedsASignIn() async {
        http.handler = { request in request.url!.host() == "music.apple.com" ? HTTPReply(status: 200, body: Data("<html><body>no scripts</body></html>".utf8)) : AppleReplies.rejected }
        #expect(await ask().isUnavailable)
        #expect(calls == ["\(Self.api)/syllable-lyrics", "music.apple.com/"])
        #expect(account.status == .needsReauth)
    }

    @Test func aScriptWithoutATokenNeedsASignIn() async {
        expiredToken(bundle: AppleReplies.bundle(containing: []))
        #expect(await ask().isUnavailable)
        #expect(account.status == .needsReauth)
        #expect(tokens.values[.developerToken] == "dev-token-fake")
    }

    @Test(arguments: ["https://evil.example/assets/index-x.js", "//evil.example/assets/index-x.js"])
    func theScriptIsAlwaysFetchedFromMusicAppleCom(source: String) async {
        http.handler = { request in
            switch request.url!.host() {
            case "music.apple.com": request.url!.path() == "/" ? HTTPReply(status: 200, body: Data(#"<script src="\#(source)"></script>"#.utf8)) : AppleReplies.bundle(containing: [AppleReplies.freshToken])
            default: AppleReplies.rejected
            }
        }
        _ = await ask()
        #expect(Set(http.requests.map { $0.url!.host()! }).isSubset(of: ["amp-api.music.apple.com", "music.apple.com"]))
    }

    @Test func aRefreshThatFailsToConnectIsUnavailableAndKeepsTheSignIn() async {
        for failure in [HTTPReply(status: 503), HTTPReply(status: 404)] {
            http.handler = { request in request.url!.host() == "music.apple.com" ? failure : AppleReplies.rejected }
            #expect(await ask().isUnavailable)
            #expect(account.status == .connected(storefront: "vn"))
        }
        http.handler = { request in if request.url!.host() == "music.apple.com" { throw URLError(.timedOut) } else { return AppleReplies.rejected } }
        #expect(await ask().isUnavailable)
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test func aScriptThatFailsToDownloadIsUnavailableAndKeepsTheSignIn() async {
        http.handler = { request in
            switch request.url!.host() {
            case "music.apple.com": request.url!.path() == "/" ? AppleReplies.page : HTTPReply(status: 500)
            default: AppleReplies.rejected
            }
        }
        #expect(await ask().isUnavailable)
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test func notBeingConnectedSendsNothing() async {
        let account = AppleMusicAccount(tokens: FakeTokenStore())
        account.load()
        let client = AppleMusicLyricsClient(client: http, account: account)
        #expect(!client.isAvailable)
        #expect(await client.lyrics(forSongID: "42", pace: { true }).isUnavailable)
        #expect(http.requests.isEmpty)
    }

    // MARK: pacing

    @Test func everyRequestWaitsItsTurnFirst() async {
        expiredToken()
        var paced = 0
        _ = await client.lyrics(forSongID: "1856960468", pace: { paced += 1; return true })
        #expect(paced == 4)
        #expect(http.requests.count == 4)
    }

    @Test func aStoppedLookupSendsNothingFurther() async {
        http.reply(AppleReplies.notFound)
        var paced = 0
        let result = await client.lyrics(forSongID: "1856960468", pace: { paced += 1; return paced < 2 })
        #expect(result.isUnavailable)
        #expect(http.requests.count == 1)
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test func aLookupStoppedBeforeItsFirstRequestSendsNothing() async {
        let result = await client.lyrics(forSongID: "1856960468", pace: { false })
        #expect(result.isUnavailable)
        #expect(http.requests.isEmpty)
    }

    // MARK: secrets stay out of what is reported

    @Test func noTokenEverAppearsInAnAnswerOrItsDescription() async {
        let secrets = ["dev-token-fake", "user-token-fake", AppleReplies.freshToken]
        let leaky = NSError(domain: "FakeDomain", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "failed with Bearer dev-token-fake and user-token-fake",
            NSURLErrorFailingURLErrorKey: URL(string: "https://amp-api.music.apple.com/v1/catalog/vn/songs/1?token=dev-token-fake")!,
        ])
        let scenarios: [(URLRequest) async throws -> HTTPReply] = [
            { _ in throw leaky },
            { _ in throw URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "user-token-fake"]) },
            { _ in HTTPReply(status: 500, body: Data("dev-token-fake user-token-fake".utf8)) },
            { _ in HTTPReply(status: 429, body: Data("user-token-fake".utf8), retryAfter: "dev-token-fake") },
            { _ in HTTPReply(status: 200, body: Data("dev-token-fake".utf8)) },
            { _ in AppleReplies.rejected },
            { request in if request.url!.host() == "music.apple.com" { throw leaky } else { return AppleReplies.rejected } },
        ]
        for scenario in scenarios {
            let account = AppleMusicAccount(tokens: FakeTokenStore.connected())
            account.load()
            http.handler = scenario
            let client = AppleMusicLyricsClient(client: http, account: account)
            let result = await client.lyrics(forSongID: "1856960468", pace: { true })
            let text = String(describing: result) + String(describing: account.status) + (account.problem ?? "") + account.status.text
            for secret in secrets { #expect(!text.contains(secret)) }
            if case .unavailable(let reason) = result { #expect(!reason.isEmpty) }
        }
    }

    // MARK: storefront

    @Test func theStorefrontIsAskedWithTheTokens() async throws {
        http.reply(AppleReplies.storefront("us"))
        let credentials = AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: nil)
        #expect(await client.storefront(for: credentials) == "us")
        let request = try #require(http.requests.first)
        #expect(request.url?.absoluteString == "https://amp-api.music.apple.com/v1/me/storefront")
        #expect(request.httpMethod == "GET")
        #expect(header("Authorization", of: request) == "Bearer dev-token-fake")
        #expect(header("Media-User-Token", of: request) == "user-token-fake")
        #expect(header("Origin", of: request) == "https://music.apple.com")
        #expect(header("Referer", of: request) == "https://music.apple.com/")
    }

    @Test func anUnusableStorefrontAnswerIsNil() async {
        let credentials = AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: nil)
        for reply in [AppleReplies.rejected, HTTPReply(status: 500), AppleReplies.empty, AppleReplies.storefront("../x"), AppleReplies.storefront(""), HTTPReply(status: 200, body: Data("nope".utf8))] {
            http.reply(reply)
            #expect(await client.storefront(for: credentials) == nil)
        }
        http.handler = { _ in throw URLError(.notConnectedToInternet) }
        #expect(await client.storefront(for: credentials) == nil)
    }

    // MARK: connecting

    @Test func connectingWithAStorefrontJustSavesIt() async {
        let account = AppleMusicAccount(tokens: FakeTokenStore())
        let client = AppleMusicLyricsClient(client: http, account: account)
        #expect(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "vn")))
        #expect(account.status == .connected(storefront: "vn"))
        #expect(http.requests.isEmpty)
    }

    @Test func connectingWithoutAStorefrontFetchesItFirst() async {
        let store = FakeTokenStore()
        let account = AppleMusicAccount(tokens: store)
        let client = AppleMusicLyricsClient(client: http, account: account)
        http.reply(AppleReplies.storefront("th"))
        #expect(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: nil)))
        #expect(account.status == .connected(storefront: "th"))
        #expect(store.values[.storefront] == "th")
        #expect(calls == ["amp-api.music.apple.com/v1/me/storefront"])
    }

    @Test func connectingWithoutAStorefrontThatCannotBeFetchedSavesNothing() async {
        let store = FakeTokenStore()
        let account = AppleMusicAccount(tokens: store)
        let client = AppleMusicLyricsClient(client: http, account: account)
        http.reply(AppleReplies.rejected)
        #expect(!(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: nil))))
        #expect(account.status == .notConnected)
        #expect(store.values.isEmpty)
        #expect(account.problem == AppleMusicLyricsClient.storefrontProblem)
    }

    @Test func connectingWhenTheKeychainFailsSaysSo() async {
        let store = FakeTokenStore()
        store.failsToSave = true
        let account = AppleMusicAccount(tokens: store)
        let client = AppleMusicLyricsClient(client: http, account: account)
        #expect(!(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "vn"))))
        #expect(account.problem == AppleMusicAccount.keychainProblem)
    }
}
