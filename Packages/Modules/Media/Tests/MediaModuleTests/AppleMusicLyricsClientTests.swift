import Foundation
import Testing
@testable import MediaModule

/// Apple Music web API answers, shaped like the real ones, with fake tokens and placeholder words.
enum AppleReplies {
    static let developerToken = "dev-token-fake"
    static let userToken = "user-token-fake"

    /// A JWT-shaped string with a fake signature, for the developer token the refresh looks for.
    static func jwt(header: String, payload: String = #"{"iss":"FAKE"}"#) -> String {
        func base64URL(_ text: String) -> String {
            Data(text.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return [header, payload, "fake-signature"].map(base64URL).joined(separator: ".")
    }

    /// ES256 as Apple signs developer tokens, with the header keys in the web player's order (it starts "eyJ0").
    static let freshToken = jwt(header: #"{"typ":"JWT","alg":"ES256","kid":"FAKEKID1"}"#)
    static let otherToken = jwt(header: #"{"alg":"ES256","kid":"FAKEKID2","typ":"JWT"}"#)

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

    /// What `ttml(timing: "Line", count:, tag:)` parses to, or with `words: true` what `timing: "Word"` does: each line has the
    /// two words of its two spans, the first up to the second's begin and the second for a second.
    static func lines(count: Int = 4, tag: String = "line", words: Bool = false) -> [LyricLine] {
        (0..<count).map { index in
            let time = Double(index + 1)
            guard words else { return LyricLine(time: time, text: "\(tag) \(index + 1)") }
            return LyricLine(time: time, words: [
                LyricWord(text: "\(tag) ", begin: time, end: time), LyricWord(text: "\(index + 1)", begin: time, end: time + 1),
            ])
        }
    }

    /// `data[0].attributes.ttml`, as the web API sends it.
    static func lyrics(ttml: String, type: String = "syllable-lyrics") -> HTTPReply {
        let object: [String: Any] = ["data": [["id": "1856960468", "type": type, "attributes": ["ttml": ttml, "playParams": ["id": "1856960468", "kind": "lyrics"]]]]]
        return HTTPReply(status: 200, body: try! JSONSerialization.data(withJSONObject: object))
    }

    /// The answer to a request with `extend=ttmlLocalizations`: `attributes.ttmlLocalizations` next to (or instead of)
    /// `attributes.ttml`. Either is left out when nil; `localizations` can be any JSON value.
    static func lyrics(ttml: String?, localizations: Any?) -> HTTPReply {
        var attributes: [String: Any] = ["playParams": ["id": "1856960468", "kind": "lyrics"]]
        if let ttml { attributes["ttml"] = ttml }
        if let localizations { attributes["ttmlLocalizations"] = localizations }
        let object: [String: Any] = ["data": [["id": "1856960468", "type": "syllable-lyrics", "attributes": attributes]]]
        return HTTPReply(status: 200, body: try! JSONSerialization.data(withJSONObject: object))
    }

    /// A TTML document the way the localizations carry it: the lyrics in the body, and translations and
    /// transliterations of them in the head (which the parser must leave alone).
    static func localizedTTML(count: Int = 4, tag: String = "local") -> String {
        let head = #"<head><metadata><iTunesMetadata xmlns="http://music.apple.com/lyric-ttml-internal"><translations><translation type="subtitle" xml:lang="en"><text for="L1">translated words</text></translation></translations><transliterations><transliteration xml:lang="vi-Latn"><text for="L1"><span>romanised words</span></text></transliteration></transliterations></iTunesMetadata></metadata></head>"#
        return ttml(timing: "Word", count: count, tag: tag).replacingOccurrences(of: "<body>", with: "\(head)<body>")
    }

    static let empty = HTTPReply(status: 200, body: Data(#"{"data":[]}"#.utf8))

    /// `GET /v1/catalog/{storefront}/songs/{id}`: the song's entry; a flag that is nil is left out, like a flag Apple omits.
    static func catalog(hasLyrics: Bool? = true, hasTimeSyncedLyrics: Bool? = true) -> HTTPReply {
        var attributes: [String: Any] = ["name": "Song", "artistName": "Artist"]
        if let hasLyrics { attributes["hasLyrics"] = hasLyrics }
        if let hasTimeSyncedLyrics { attributes["hasTimeSyncedLyrics"] = hasTimeSyncedLyrics }
        let object: [String: Any] = ["data": [["id": "1856960468", "type": "songs", "attributes": attributes]]]
        return HTTPReply(status: 200, body: try! JSONSerialization.data(withJSONObject: object))
    }

    /// The catalog entry of a song without lyrics.
    static let catalogWithoutLyrics = catalog(hasLyrics: false, hasTimeSyncedLyrics: false)
    /// A catalog entry that does not say either way.
    static let catalogWithoutVerdict = catalog(hasLyrics: nil, hasTimeSyncedLyrics: nil)

    /// What Apple answers a lyrics request with when it does not take the user token, as seen on a real machine.
    static let noRelatedResources = HTTPReply(
        status: 404,
        body: Data(#"{"errors":[{"id":"FAKE","title":"No related resources","detail":"No related resources for the request","status":"404","code":"40400"}]}"#.utf8)
    )
    static let notFound = HTTPReply(status: 404, body: Data(#"{"errors":[{"status":"404","code":"40400"}]}"#.utf8))
    static let rejected = HTTPReply(status: 401, body: Data(#"{"errors":[{"status":"401","code":"40100"}]}"#.utf8))
    static let forbidden = HTTPReply(status: 403, body: Data(#"{"errors":[{"status":"403","code":"40300"}]}"#.utf8))

    /// `GET /v1/me/storefront`: `data[0].id` and, when given, `attributes.defaultLanguageTag`.
    static func storefront(_ id: String = "vn", language: String? = nil) -> HTTPReply {
        var attributes: [String: Any] = ["name": "Fake"]
        if let language { attributes["defaultLanguageTag"] = language }
        let object: [String: Any] = ["data": [["id": id, "type": "storefronts", "attributes": attributes]]]
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
    let log = FakeAppleMusicLog()
    let account: AppleMusicAccount
    let client: AppleMusicLyricsClient

    init() {
        account = AppleMusicAccount(tokens: tokens)
        account.load()
        client = AppleMusicLyricsClient(client: http, account: account, log: log)
    }

    func ask(_ id: String = "1856960468") async -> LyricsResult {
        await client.lyrics(forSongID: id, pace: { true })
    }

    static let storefrontPath = "/v1/me/storefront"

    /// "host/path" of every request sent so far.
    var calls: [String] { http.requests.map { "\($0.url!.host()!)\($0.url!.path())" } }

    /// The requests of the lookup itself: the first lookup of a run also asks for the account's storefront, which most
    /// tests are not about.
    var lookupRequests: [URLRequest] { http.requests.filter { $0.url!.path() != Self.storefrontPath } }
    var lookupCalls: [String] { lookupRequests.map { "\($0.url!.host()!)\($0.url!.path())" } }

    func header(_ name: String, of request: URLRequest) -> String? { request.value(forHTTPHeaderField: name) }

    func queryValue(_ name: String, of request: URLRequest) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    static let api = "amp-api.music.apple.com/v1/catalog/vn/songs/1856960468"
    static let storefrontCall = "amp-api.music.apple.com/v1/me/storefront"
    /// The parameters a lyrics request carries when the account's language is not known: brackets percent-encoded.
    static let query = "l%5Blyrics%5D=en-US&extend=ttmlLocalizations&l%5Bscript%5D=en-Latn"

    /// Each of Apple's endpoints answers on its own; the account is in `vn` and the catalog says the song has lyrics
    /// unless told otherwise.
    func route(
        storefront: HTTPReply = AppleReplies.storefront("vn"), catalog: HTTPReply = AppleReplies.catalog(),
        syllable: HTTPReply = AppleReplies.notFound, lyrics: HTTPReply = AppleReplies.notFound
    ) {
        http.handler = { request in
            let path = request.url!.path()
            if path == Self.storefrontPath { return storefront }
            if path.hasSuffix("/syllable-lyrics") { return syllable }
            if path.hasSuffix("/lyrics") { return lyrics }
            return catalog
        }
    }

    var found: HTTPReply { AppleReplies.lyrics(ttml: AppleReplies.ttml()) }

    // MARK: request

    @Test func theCatalogIsAskedFirstWithNoParameters() async throws {
        route(syllable: found)
        #expect(await ask() == .synced(AppleReplies.lines()))
        let request = try #require(lookupRequests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://amp-api.music.apple.com/v1/catalog/vn/songs/1856960468")
        #expect(header("Authorization", of: request) == "Bearer dev-token-fake")
        #expect(header("Media-User-Token", of: request) == "user-token-fake")
        #expect(header("Origin", of: request) == "https://music.apple.com")
        #expect(header("Referer", of: request) == "https://music.apple.com/")
        #expect(header("User-Agent", of: request) == nil)
        #expect(request.timeoutInterval == AppleMusicLyricsClient.requestTimeout)
    }

    @Test func aLyricsRequestCarriesTheLyricParametersWithTheirBracketsEncoded() async throws {
        route(syllable: AppleReplies.lyrics(ttml: AppleReplies.ttml(timing: "Word")))
        #expect(await ask() == .synced(AppleReplies.lines(tag: "line", words: true)))
        #expect(lookupCalls == [Self.api, "\(Self.api)/syllable-lyrics"])
        let request = try #require(lookupRequests.last)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://amp-api.music.apple.com/v1/catalog/vn/songs/1856960468/syllable-lyrics?\(Self.query)")
        #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == [
            URLQueryItem(name: "l[lyrics]", value: "en-US"), URLQueryItem(name: "extend", value: "ttmlLocalizations"), URLQueryItem(name: "l[script]", value: "en-Latn"),
        ])
        #expect(header("Authorization", of: request) == "Bearer dev-token-fake")
        #expect(header("Media-User-Token", of: request) == "user-token-fake")
        #expect(header("Origin", of: request) == "https://music.apple.com")
        #expect(header("Referer", of: request) == "https://music.apple.com/")
        #expect(request.timeoutInterval == AppleMusicLyricsClient.requestTimeout)
    }

    @Test func theLyricsEndpointCarriesThemToo() async throws {
        route(lyrics: found)
        #expect(await ask() == .synced(AppleReplies.lines()))
        #expect(lookupCalls == [Self.api, "\(Self.api)/syllable-lyrics", "\(Self.api)/lyrics"])
        for request in lookupRequests.suffix(2) {
            #expect(request.url?.query?.contains("l%5Blyrics%5D=en-US&extend=ttmlLocalizations&l%5Bscript%5D=en-Latn") == true)
        }
        #expect(lookupRequests.first?.url?.query == nil)
    }

    @Test func theStorefrontIsAskedWithTheTokensAndNoParameters() async throws {
        route(syllable: found)
        _ = await ask()
        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://amp-api.music.apple.com/v1/me/storefront")
        #expect(header("Authorization", of: request) == "Bearer dev-token-fake")
        #expect(header("Media-User-Token", of: request) == "user-token-fake")
        #expect(header("Origin", of: request) == "https://music.apple.com")
        #expect(header("Referer", of: request) == "https://music.apple.com/")
    }

    @Test func aSongIdThatIsNotDigitsIsNeverAsked() async {
        for id in ["", "12/../3", "12a", "1 2", "١٢٣"] {
            #expect(await ask(id) == .notFound, "\(id)")
        }
        #expect(http.requests.isEmpty)
    }

    // MARK: the language

    @Test(arguments: [
        ("vi", "vi-Latn"), ("en-US", "en-Latn"), ("fr-FR", "fr-Latn"), ("pt-BR", "pt-Latn"), ("ja", "ja-Jpan"), ("ko-KR", "ko-Kore"),
        ("th", "th-Thai"), ("ru", "ru-Cyrl"), ("zh-Hans-CN", "zh-Hans"), ("zh-Hant-TW", "zh-Hant"), ("zh-TW", "zh-Hant"), ("zh-CN", "zh-Hans"),
    ])
    func theLanguageAndScriptComeFromTheStorefrontsDefaultLanguage(language: String, script: String) async throws {
        route(storefront: AppleReplies.storefront("vn", language: language), syllable: found)
        _ = await ask()
        let request = try #require(lookupRequests.last)
        #expect(request.url?.query == "l%5Blyrics%5D=\(language)&extend=ttmlLocalizations&l%5Bscript%5D=\(script)")
    }

    @Test func withoutALanguageItIsEnglish() async throws {
        route(storefront: AppleReplies.storefront("vn", language: nil), syllable: found)
        _ = await ask()
        #expect(try #require(lookupRequests.last).url?.query == Self.query)
    }

    @Test(arguments: ["", "en US", "../x", "en_US", "e", "english-language-tag-too-long", "en-US&x=1"])
    func aLanguageThatIsNotATagIsIgnored(language: String) async throws {
        route(storefront: AppleReplies.storefront("vn", language: language), syllable: found)
        _ = await ask()
        #expect(try #require(lookupRequests.last).url?.query == Self.query)
    }

    @Test func aLanguageWhoseScriptIsUnknownLeavesTheScriptOut() async throws {
        route(storefront: AppleReplies.storefront("vn", language: "xx"), syllable: found)
        _ = await ask()
        #expect(try #require(lookupRequests.last).url?.query == "l%5Blyrics%5D=xx&extend=ttmlLocalizations")
    }

    @Test func scriptsOfLanguages() {
        #expect(AppleMusicLyricsClient.scriptTag(forLanguage: "vi") == "vi-Latn")
        #expect(AppleMusicLyricsClient.scriptTag(forLanguage: "en-US") == "en-Latn")
        #expect(AppleMusicLyricsClient.scriptTag(forLanguage: "ja-JP") == "ja-Jpan")
        #expect(AppleMusicLyricsClient.scriptTag(forLanguage: "sr-Latn-RS") == "sr-Latn")
        #expect(AppleMusicLyricsClient.scriptTag(forLanguage: "sr-Cyrl") == "sr-Cyrl")
        #expect(AppleMusicLyricsClient.scriptTag(forLanguage: "zh-HK") == "zh-Hant")
        #expect(AppleMusicLyricsClient.scriptTag(forLanguage: "xx") == nil)
    }

    // MARK: the account's storefront

    @Test func theAccountStorefrontIsAskedOncePerRun() async {
        route(syllable: found)
        _ = await ask()
        #expect(calls.first == Self.storefrontCall)
        #expect(calls.filter { $0 == Self.storefrontCall }.count == 1)
        _ = await ask("42")
        _ = await ask()
        #expect(calls.filter { $0 == Self.storefrontCall }.count == 1)
    }

    @Test func aDifferentStorefrontIsStoredAndUsed() async throws {
        let store = FakeTokenStore.connected(storefront: "us")
        let account = AppleMusicAccount(tokens: store)
        account.load()
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        route(storefront: AppleReplies.storefront("vn"), syllable: found)
        #expect(await client.lyrics(forSongID: "1856960468", pace: { true }) == .synced(AppleReplies.lines()))
        #expect(store.values[.storefront] == "vn")
        #expect(account.status == .connected(storefront: "vn"))
        // The catalog and the lyrics are asked in the account's store.
        #expect(calls == [Self.storefrontCall, Self.api, "\(Self.api)/syllable-lyrics"])
        #expect(log.messages(at: .default).contains("Apple Music account storefront: id=vn stored=us language=- changed=true"))
    }

    @Test func aRefreshedStorefrontStaysInUseForTheRunWhenTheKeychainRefusesIt() async {
        let store = FakeTokenStore.connected(storefront: "us")
        let account = AppleMusicAccount(tokens: store)
        account.load()
        let log = FakeAppleMusicLog()
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        store.failsToSave = true
        route(storefront: AppleReplies.storefront("vn", language: "vi"), syllable: found)
        #expect(await client.lyrics(forSongID: "1856960468", pace: { true }) == .synced(AppleReplies.lines()))
        #expect(await client.lyrics(forSongID: "42", pace: { true }) == .synced(AppleReplies.lines()))
        #expect(await client.lyrics(forSongID: "7", pace: { true }) == .synced(AppleReplies.lines()))
        // Every lookup is in the account's store, not the stale one the Keychain still holds, and the answer is not asked for again.
        let paths = http.requests.map { $0.url!.path() }.filter { $0.contains("/catalog/") }
        #expect(paths.count == 6)
        #expect(paths.allSatisfy { $0.hasPrefix("/v1/catalog/vn/") })
        #expect(http.requests.filter { $0.url!.path() == Self.storefrontPath }.count == 1)
        #expect(http.requests.last?.url?.query == "l%5Blyrics%5D=vi&extend=ttmlLocalizations&l%5Bscript%5D=vi-Latn")
        #expect(store.values[.storefront] == "us")
        // The failure is logged, once, with no secret.
        let errors = log.messages(at: .error)
        #expect(errors == ["Apple Music could not keep the account storefront in the Keychain: it is used for this run only"])
    }

    @Test func aStorefrontTheKeychainTookIsNotReportedAsAFailure() async {
        route(storefront: AppleReplies.storefront("us"), syllable: found)
        let other = FakeTokenStore.connected(storefront: "vn")
        let account = AppleMusicAccount(tokens: other)
        account.load()
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        _ = await client.lyrics(forSongID: "1856960468", pace: { true })
        #expect(other.values[.storefront] == "us")
        #expect(log.messages(at: .error).isEmpty)
    }

    @Test func theSameStorefrontIsNotStoredAgain() async {
        route(storefront: AppleReplies.storefront("vn", language: "vi"), syllable: found)
        _ = await ask()
        #expect(tokens.saveCount == 0)
        #expect(log.messages(at: .default).contains("Apple Music account storefront: id=vn stored=vn language=vi changed=false"))
    }

    @Test(arguments: ["", "../x", "usa", "u1", "143441"])
    func aStorefrontThatIsNotACountryCodeIsIgnored(id: String) async {
        route(storefront: AppleReplies.storefront(id), syllable: found)
        #expect(await ask() == .synced(AppleReplies.lines()))
        #expect(tokens.values[.storefront] == "vn")
        #expect(lookupCalls.first == Self.api)
    }

    @Test func anAnswerWithoutAnEntryKeepsTheStoredStorefront() async {
        route(storefront: AppleReplies.empty, syllable: found)
        #expect(await ask() == .synced(AppleReplies.lines()))
        #expect(tokens.values[.storefront] == "vn")
    }

    @Test func aStorefrontThatIsRefusedNeedsASignInLikeARefusedLyricsRequest() async {
        // 403 40300 is Apple's answer to a user token it does not accept; for lyrics it answers 404, so this is the one signal.
        route(storefront: AppleReplies.forbidden, syllable: found)
        let result = await ask()
        #expect(result == .unavailable("Apple Music sign-in expired"))
        #expect(account.status == .needsReauth)
        #expect(!client.isAvailable)
        // Nothing of the lookup itself was asked (the developer token was renewed once, which is all a refusal allows).
        #expect(lookupRequests.allSatisfy { $0.url!.host() == "music.apple.com" })
        #expect(log.messages(at: .default).contains { $0.hasPrefix(#"Apple Music storefront: status=403 error="-" code=40300 storefront=vn"#) })
        let before = http.requests.count
        #expect(await ask("42").isUnavailable)
        #expect(http.requests.count == before)
    }

    @Test func aStorefrontRefusedTwiceByAnExpiredDeveloperTokenNeedsASignInToo() async {
        http.handler = { request in
            switch request.url!.host() {
            case "music.apple.com": request.url!.path() == "/" ? AppleReplies.page : AppleReplies.bundle(containing: [AppleReplies.freshToken])
            default: AppleReplies.rejected
            }
        }
        #expect(await ask() == .unavailable("Apple Music sign-in expired"))
        #expect(calls == [Self.storefrontCall, "music.apple.com/", "music.apple.com/assets/index-a1b2c3.js", Self.storefrontCall])
        #expect(account.status == .needsReauth)
    }

    @Test func aStorefrontRefusalWhoseRenewalCouldNotReachTheWebPageIsNoReasonToSignInAgain() async {
        http.handler = { request in
            if request.url!.host() == "music.apple.com" { throw URLError(.notConnectedToInternet) }
            return AppleReplies.forbidden
        }
        #expect(await ask().isUnavailable)
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test func aRefusalAtConnectIsLeftToTheLogAndTheStoredStorefrontIsKept() async {
        let store = FakeTokenStore()
        let account = AppleMusicAccount(tokens: store)
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        http.reply(AppleReplies.forbidden)
        #expect(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "us")))
        #expect(account.status == .connected(storefront: "us"))
        #expect(log.messages(at: .default).contains { $0.hasPrefix("Apple Music storefront: status=403") })
    }

    @Test(arguments: [500, 503, 429])
    func aStorefrontThatCouldNotBeReadIsAskedAgainAtTheNextLookup(status: Int) async {
        route(storefront: HTTPReply(status: status), syllable: found)
        #expect(await ask() == .synced(AppleReplies.lines()))
        route(storefront: AppleReplies.storefront("us"), syllable: found)
        _ = await ask("42")
        #expect(calls.filter { $0 == Self.storefrontCall }.count == 2)
        #expect(tokens.values[.storefront] == "us")
    }

    @Test func aStorefrontThatNeverGotAnAnswerIsAskedAgainAtTheNextLookup() async {
        http.handler = { request in
            if request.url!.path() == Self.storefrontPath { throw URLError(.timedOut) }
            return request.url!.path().hasSuffix("/syllable-lyrics") ? AppleReplies.lyrics(ttml: AppleReplies.ttml()) : AppleReplies.catalog()
        }
        #expect(await ask() == .synced(AppleReplies.lines()))
        _ = await ask("42")
        #expect(calls.filter { $0 == Self.storefrontCall }.count == 2)
        #expect(log.messages(at: .default).contains("Apple Music storefront: failed=Request failed (NSURLErrorDomain -1001) storefront=vn userToken=attached length=15"))
    }

    @Test func theStorefrontStepIsLoggedAtNoticeLevelWithItsStatusAndTheIdItReturned() async {
        route(storefront: AppleReplies.storefront("vn", language: "vi"), syllable: found)
        _ = await ask()
        let notice = log.messages(at: .default)
        #expect(notice.contains("Apple Music storefront: status=200 storefront=vn userToken=attached length=15"))
        #expect(notice.contains("Apple Music account storefront: id=vn stored=vn language=vi changed=false"))
    }

    // MARK: a new sign-in starts the run over

    @Test func connectingAgainForgetsWhatTheRunLearnedAboutTheOldAccount() async throws {
        let store = FakeTokenStore()
        let client = await clientAfterConnecting(page: "us", account: "vn", store: store)
        // A probe finds that the MusicKit storefront works for the old account, and that variant is remembered.
        http.handler = { request in
            let path = request.url!.path()
            if path == Self.storefrontPath { return AppleReplies.storefront("vn") }
            if path.hasSuffix("/lyrics") || path.hasSuffix("/syllable-lyrics") {
                return path.contains("/catalog/us/") && request.url!.query != nil ? AppleReplies.lyrics(ttml: AppleReplies.ttml()) : AppleReplies.noRelatedResources
            }
            return AppleReplies.catalog()
        }
        #expect(await client.lyrics(forSongID: "1856960468", pace: { true }) == .synced(AppleReplies.lines()))
        http.forgetRequests()

        // The user signs in again, as a Thai account.
        http.reply(AppleReplies.storefront("th", language: "th"))
        #expect(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "th")))
        http.forgetRequests()
        route(storefront: AppleReplies.storefront("th", language: "th"), syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        #expect(await client.lyrics(forSongID: "1856960468", pace: { true }) == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        try #require(http.requests.count == 4)
        // The new account's store and language, with the parameters, and the probe runs again.
        #expect(http.requests.map { $0.url!.path() } == [
            "/v1/catalog/th/songs/1856960468", "/v1/catalog/th/songs/1856960468/syllable-lyrics",
            "/v1/catalog/th/songs/1856960468/lyrics", "/v1/catalog/th/songs/1856960468/lyrics",
        ])
        #expect(http.requests[1].url?.query == "l%5Blyrics%5D=th&extend=ttmlLocalizations&l%5Bscript%5D=th-Thai")
        #expect(http.requests[3].url?.query == nil)
        #expect(store.values[.storefront] == "th")
    }

    @Test func theStorefrontIsAskedAgainAfterANewSignIn() async {
        let store = FakeTokenStore()
        let client = await clientAfterConnecting(page: "us", account: "vn", store: store)
        route(storefront: AppleReplies.storefront("vn"), syllable: found)
        _ = await client.lyrics(forSongID: "1856960468", pace: { true })
        #expect(!calls.contains(Self.storefrontCall))
        // A sign-in whose storefront request failed leaves the next lookup to ask.
        http.forgetRequests()
        http.reply(HTTPReply(status: 503))
        #expect(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "vn")))
        route(storefront: AppleReplies.storefront("vn"), syllable: found)
        _ = await client.lyrics(forSongID: "1856960468", pace: { true })
        #expect(calls.filter { $0 == Self.storefrontCall }.count == 2)
    }

    // MARK: the catalog

    @Test(arguments: [(false, false), (false, nil), (nil, false)] as [(Bool?, Bool?)])
    func aSongTheCatalogSaysHasNoLyricsIsNotFoundWithoutAskingForThem(hasLyrics: Bool?, synced: Bool?) async {
        route(catalog: AppleReplies.catalog(hasLyrics: hasLyrics, hasTimeSyncedLyrics: synced), syllable: found, lyrics: found)
        #expect(await ask() == .notFound)
        #expect(lookupCalls == [Self.api])
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test(arguments: [(true, true), (true, false), (false, true), (true, nil), (nil, true)] as [(Bool?, Bool?)])
    func aSongTheCatalogListsLyricsForIsAskedForThem(hasLyrics: Bool?, synced: Bool?) async {
        route(catalog: AppleReplies.catalog(hasLyrics: hasLyrics, hasTimeSyncedLyrics: synced), syllable: found)
        #expect(await ask() == .synced(AppleReplies.lines()))
        #expect(lookupCalls == [Self.api, "\(Self.api)/syllable-lyrics"])
    }

    @Test func aSongNotInTheCatalogIsNotFound() async {
        for reply in [AppleReplies.notFound, AppleReplies.empty, HTTPReply(status: 410)] {
            route(catalog: reply)
            #expect(await ask() == .notFound)
        }
        #expect(lookupRequests.count == 3)
    }

    @Test func withoutAVerdictFromTheCatalogNoLyricsIsWhatAppleSaid() async {
        route(catalog: AppleReplies.catalogWithoutVerdict)
        #expect(await ask() == .notFound)
        #expect(lookupCalls == [Self.api, "\(Self.api)/syllable-lyrics", "\(Self.api)/lyrics"])
        #expect(account.status == .connected(storefront: "vn"))
    }

    // MARK: answers

    @Test func lineSyncedLyricsFromTheSyllableEndpoint() async {
        route(syllable: AppleReplies.lyrics(ttml: AppleReplies.ttml(timing: "Line", count: 5, tag: "la")))
        #expect(await ask() == .synced(AppleReplies.lines(count: 5, tag: "la")))
    }

    @Test func plainLyricsAreAnAnswerToo() async {
        route(syllable: AppleReplies.lyrics(ttml: AppleReplies.ttml(timing: "None", count: 2, tag: "words")))
        #expect(await ask() == .plain("words 1\nwords 2"))
        #expect(lookupRequests.count == 2)
    }

    @Test func a404FallsBackToTheLyricsEndpoint() async throws {
        route(lyrics: AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 6, tag: "plain"), type: "lyrics"))
        #expect(await ask() == .synced(AppleReplies.lines(count: 6, tag: "plain")))
        #expect(lookupCalls == [Self.api, "\(Self.api)/syllable-lyrics", "\(Self.api)/lyrics"])
        let last = try #require(http.requests.last)
        #expect(header("Authorization", of: last) == "Bearer dev-token-fake")
        #expect(header("Media-User-Token", of: last) == "user-token-fake")
        #expect(header("Origin", of: last) == "https://music.apple.com")
        #expect(header("Referer", of: last) == "https://music.apple.com/")
    }

    @Test func noTTMLFallsBackToTheLyricsEndpointToo() async {
        for first in [AppleReplies.empty, AppleReplies.lyrics(ttml: ""), AppleReplies.lyrics(ttml: "<tt><unclosed>"), HTTPReply(status: 200, body: Data(#"{"data":[{"attributes":{}}]}"#.utf8))] {
            route(syllable: first, lyrics: AppleReplies.lyrics(ttml: AppleReplies.ttml(), type: "lyrics"))
            #expect(await ask() == .synced(AppleReplies.lines()))
        }
        #expect(lookupRequests.count == 12)
    }

    // MARK: ttmlLocalizations

    @Test func theLogSaysWhichAttributeSuppliedTheLyrics() async {
        route(syllable: AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 3, tag: "plainttml"), localizations: AppleReplies.localizedTTML(count: 5, tag: "local")))
        _ = await ask()
        #expect(log.messages(at: .default).contains("Apple Music syllable-lyrics: lyrics from ttmlLocalizations"))

        route(syllable: AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 3, tag: "plainttml"), localizations: nil))
        _ = await ask("42")
        #expect(log.messages(at: .default).contains("Apple Music syllable-lyrics: lyrics from ttml"))

        route(syllable: AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 3, tag: "plainttml"), localizations: "<tt><unclosed>"))
        _ = await ask("7")
        #expect(log.messages(at: .default).filter { $0 == "Apple Music syllable-lyrics: lyrics from ttml" }.count == 2)
        // Nothing of the lyrics themselves.
        #expect(log.messages.allSatisfy { !$0.contains("plainttml") && !$0.contains("local 1") })
    }

    @Test func theLocalizationsAreReadBeforeTheTTML() async {
        route(syllable: AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 3, tag: "plainttml"), localizations: AppleReplies.localizedTTML(count: 5, tag: "local")))
        #expect(await ask() == .synced(AppleReplies.lines(count: 5, tag: "local", words: true)))
        #expect(lookupRequests.count == 2)
    }

    @Test func theLocalizationsAloneAreEnough() async {
        route(syllable: AppleReplies.lyrics(ttml: nil, localizations: AppleReplies.localizedTTML(count: 4, tag: "local")))
        #expect(await ask() == .synced(AppleReplies.lines(count: 4, tag: "local", words: true)))
    }

    @Test func theTranslationsInTheHeadAreNotLyrics() async {
        route(syllable: AppleReplies.lyrics(ttml: nil, localizations: AppleReplies.localizedTTML(count: 4, tag: "local")))
        let result = await ask()
        guard case .synced(let lines) = result else { Issue.record("not synced: \(result)"); return }
        #expect(lines.allSatisfy { $0.text.hasPrefix("local ") })
        #expect(!lines.contains { $0.text.contains("translated") || $0.text.contains("romanised") })
    }

    @Test(arguments: [Optional("<tt><unclosed>"), "", "   ", "<html>not ttml</html>"])
    func localizationsThatAreNoLyricsFallBackToTheTTML(localizations: String?) async {
        route(syllable: AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 3, tag: "plainttml"), localizations: localizations))
        #expect(await ask() == .synced(AppleReplies.lines(count: 3, tag: "plainttml")))
        #expect(lookupRequests.count == 2)
    }

    @Test func localizationsOfAnotherTypeAreIgnored() async {
        for localizations in [["x": 1], [1, 2], 5, true] as [Any] {
            route(syllable: AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 3, tag: "plainttml"), localizations: localizations))
            #expect(await ask() == .synced(AppleReplies.lines(count: 3, tag: "plainttml")))
        }
    }

    // MARK: failures

    @Test(arguments: [408, 429, 500, 502, 503])
    func otherStatusesAreUnavailableAndNothingMoreIsAsked(status: Int) async {
        http.reply(HTTPReply(status: status, body: Data("busy".utf8), retryAfter: "30"))
        let result = await ask()
        #expect(result.isUnavailable)
        #expect(lookupRequests.count == 1)
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test(arguments: [408, 429, 500, 503])
    func theSameFromALyricsEndpointIsUnavailableAndNoProbeFollows(status: Int) async {
        route(syllable: HTTPReply(status: status))
        #expect(await ask().isUnavailable)
        #expect(lookupCalls == [Self.api, "\(Self.api)/syllable-lyrics"])
    }

    @Test(arguments: [400, 405, 410, 422, 451])
    func otherClientErrorsAreNoLyricsRatherThanTrouble(status: Int) async {
        // An answer like this every time must not cost a full lookup at each replay: it is "not found", which is cached.
        route(catalog: AppleReplies.catalogWithoutVerdict, syllable: HTTPReply(status: status, body: Data("no".utf8)), lyrics: HTTPReply(status: status, body: Data("no".utf8)))
        #expect(await ask() == .notFound)
        #expect(lookupCalls == [Self.api, "\(Self.api)/syllable-lyrics", "\(Self.api)/lyrics"])
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test func aFailureOnTheSecondEndpointIsUnavailable() async {
        route(lyrics: HTTPReply(status: 503))
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

    // MARK: lyrics listed but not returned

    @Test func lyricsTheCatalogListsButTheEndpointsDoNotGiveAreNotNotFound() async {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        let result = await ask()
        #expect(result == .unavailable("Apple Music did not return the lyrics it lists"))
        #expect(result == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test func emptyAnswersForListedLyricsCountAsNotReturned() async {
        route(syllable: AppleReplies.empty, lyrics: AppleReplies.lyrics(ttml: ""))
        #expect(await ask() == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
    }

    @Test func theMismatchIsLoggedAsAnError() async {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        _ = await ask()
        let errors = log.messages(at: .error)
        #expect(errors.contains { $0.contains("lists lyrics") && $0.contains("storefront=200 catalog-song=200 syllable-lyrics=404 lyrics=404") && $0.contains("storefront=vn") && $0.contains("userToken=attached length=15") })
    }

    // MARK: the probe

    /// A client that has just connected: the page (MusicKit) said `page`, the account says `accountStorefront`, which is stored.
    func clientAfterConnecting(page: String, account accountStorefront: String, store: FakeTokenStore = FakeTokenStore()) async -> AppleMusicLyricsClient {
        let account = AppleMusicAccount(tokens: store)
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        http.reply(AppleReplies.storefront(accountStorefront))
        _ = await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: page))
        http.forgetRequests()
        return client
    }

    @Test func theProbeAsksTheLyricsEndpointWithTheMusicKitStorefrontAndWithoutParameters() async throws {
        let client = await clientAfterConnecting(page: "us", account: "vn")
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        #expect(await client.lyrics(forSongID: "1856960468", pace: { true }) == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        // The catalog and both endpoints (in the account's vn); then the probe: its first variant (the account's storefront with
        // the parameters) is what the lookup asked already, so the MusicKit one (us) and the bare one (vn) follow.
        #expect(calls == [
            "amp-api.music.apple.com/v1/catalog/vn/songs/1856960468",
            "amp-api.music.apple.com/v1/catalog/vn/songs/1856960468/syllable-lyrics",
            "amp-api.music.apple.com/v1/catalog/vn/songs/1856960468/lyrics",
            "amp-api.music.apple.com/v1/catalog/us/songs/1856960468/lyrics",
            "amp-api.music.apple.com/v1/catalog/vn/songs/1856960468/lyrics",
        ])
        try #require(http.requests.count == 5)
        let musicKit = http.requests[3]
        #expect(musicKit.url?.absoluteString == "https://amp-api.music.apple.com/v1/catalog/us/songs/1856960468/lyrics?\(Self.query)")
        let bare = http.requests[4]
        #expect(bare.url?.absoluteString == "https://amp-api.music.apple.com/v1/catalog/vn/songs/1856960468/lyrics")
        for request in http.requests.suffix(2) {
            #expect(header("Authorization", of: request) == "Bearer dev-token-fake")
            #expect(header("Media-User-Token", of: request) == "user-token-fake")
            #expect(header("Origin", of: request) == "https://music.apple.com")
            #expect(header("Referer", of: request) == "https://music.apple.com/")
        }
    }

    @Test func eachVariantIsLoggedAtNoticeLevelWithItsStatusAndCode() async {
        let client = await clientAfterConnecting(page: "us", account: "vn")
        route(syllable: AppleReplies.noRelatedResources, lyrics: HTTPReply(status: 404, body: Data(#"{"errors":[{"title":"No related resources","code":"40403"}]}"#.utf8)))
        _ = await client.lyrics(forSongID: "1856960468", pace: { true })
        let notice = log.messages(at: .default)
        #expect(notice.contains("Apple Music lyrics-probe(params+account-storefront): skipped, the same as the normal request"))
        #expect(notice.contains(#"Apple Music lyrics-probe(params+musickit-storefront): status=404 error="No related resources" code=40403 storefront=us userToken=attached length=15 query=\#(Self.query)"#))
        #expect(notice.contains(#"Apple Music lyrics-probe(no-params+account-storefront): status=404 error="No related resources" code=40403 storefront=vn userToken=attached length=15"#))
        #expect(log.messages(at: .error).contains { $0.contains("probe") && $0.contains("params+account-storefront=skipped params+musickit-storefront=404 no-params+account-storefront=404") })
    }

    @Test func withoutADifferentMusicKitStorefrontOnlyTheBareVariantIsTried() async throws {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        #expect(await ask() == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        #expect(lookupCalls == [Self.api, "\(Self.api)/syllable-lyrics", "\(Self.api)/lyrics", "\(Self.api)/lyrics"])
        #expect(try #require(lookupRequests.last).url?.query == nil)
        #expect(log.messages(at: .default).contains("Apple Music lyrics-probe(params+musickit-storefront): skipped, no other storefront is known"))
    }

    @Test func theProbeRunsOncePerRun() async {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        #expect(await ask() == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        let first = lookupRequests.count
        #expect(first == 4)
        #expect(await ask() == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        #expect(await ask("42") == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        // Only the catalog and the two endpoints each time.
        #expect(lookupRequests.count == first + 6)
    }

    @Test func aStorefrontThatCouldNotBeAskedLeavesOnlyTheBareVariantAgainstTheStoredOne() async {
        route(storefront: HTTPReply(status: 503), syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        #expect(await ask() == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        #expect(log.messages(at: .default).contains("Apple Music lyrics-probe(params+account-storefront): skipped, the account's storefront is not known"))
        #expect(lookupRequests.count == 4)
        #expect(lookupRequests.last?.url?.query == nil)
    }

    @Test func theMusicKitStorefrontThatWorksIsTheAnswerAndIsUsedFromThenOn() async throws {
        let store = FakeTokenStore()
        let client = await clientAfterConnecting(page: "us", account: "vn", store: store)
        http.handler = { request in
            let path = request.url!.path()
            if path == Self.storefrontPath { return AppleReplies.storefront("vn") }
            if path.hasSuffix("/lyrics") || path.hasSuffix("/syllable-lyrics") {
                return path.contains("/catalog/us/") && request.url!.query != nil ? AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 5, tag: "apple")) : AppleReplies.noRelatedResources
            }
            return AppleReplies.catalog()
        }
        #expect(await client.lyrics(forSongID: "1856960468", pace: { true }) == .synced(AppleReplies.lines(count: 5, tag: "apple")))
        #expect(http.requests.count == 4)
        #expect(log.messages(at: .default).contains { $0.hasPrefix("Apple lyrics variant that works: params+musickit-storefront") && $0.contains("storefront=us") && $0.hasSuffix("source=ttml") })

        // The next song is asked the way that works, in the MusicKit storefront, with the parameters.
        #expect(await client.lyrics(forSongID: "42", pace: { true }) == .synced(AppleReplies.lines(count: 5, tag: "apple")))
        let next = http.requests.dropFirst(4)
        #expect(next.map { $0.url!.path() } == ["/v1/catalog/us/songs/42", "/v1/catalog/us/songs/42/syllable-lyrics"])
        #expect(next.last?.url?.query == Self.query)
        // What is stored stays the account's storefront.
        #expect(store.values[.storefront] == "vn")
    }

    @Test func requestsWithoutParametersThatWorkAreUsedFromThenOn() async throws {
        http.handler = { request in
            let path = request.url!.path()
            if path == Self.storefrontPath { return AppleReplies.storefront("vn") }
            if path.hasSuffix("/lyrics") || path.hasSuffix("/syllable-lyrics") {
                return request.url!.query == nil ? AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 5, tag: "bare")) : AppleReplies.noRelatedResources
            }
            return AppleReplies.catalog()
        }
        #expect(await ask() == .synced(AppleReplies.lines(count: 5, tag: "bare")))
        #expect(lookupRequests.count == 4)
        #expect(log.messages(at: .default).contains { $0.hasPrefix("Apple lyrics variant that works: no-params+account-storefront") })
        #expect(await ask("42") == .synced(AppleReplies.lines(count: 5, tag: "bare")))
        let next = lookupRequests.dropFirst(4)
        #expect(next.map { $0.url!.path() } == ["/v1/catalog/vn/songs/42", "/v1/catalog/vn/songs/42/syllable-lyrics"])
        #expect(next.allSatisfy { $0.url?.query == nil })
    }

    @Test func aProbeThatFailsOnTheWireIsLoggedAndTheNextVariantTried() async {
        let client = await clientAfterConnecting(page: "us", account: "vn")
        http.handler = { request in
            let path = request.url!.path()
            if path == Self.storefrontPath { return AppleReplies.storefront("vn") }
            if path.contains("/catalog/us/") { throw URLError(.timedOut) }
            if path.hasSuffix("/syllable-lyrics") || path.hasSuffix("/lyrics") { return AppleReplies.noRelatedResources }
            return AppleReplies.catalog()
        }
        #expect(await client.lyrics(forSongID: "1856960468", pace: { true }) == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        #expect(http.requests.count == 5)
        #expect(log.messages(at: .default).contains { $0.contains("lyrics-probe(params+musickit-storefront): failed=Request failed (NSURLErrorDomain -1001)") })
    }

    @Test func theProbeStopsWhenTheLookupDoes() async {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        var paced = 0
        // The storefront, the catalog and both endpoints; the probe's request is not allowed.
        let result = await client.lyrics(forSongID: "1856960468", pace: { paced += 1; return paced <= 4 })
        #expect(result == .unavailable(AppleMusicLyricsClient.stoppedReason))
        #expect(http.requests.count == 4)
    }

    @Test func aProbeThatWasCutShortIsNotSpent() async {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        var paced = 0
        _ = await client.lyrics(forSongID: "1856960468", pace: { paced += 1; return paced <= 4 })
        #expect(http.requests.count == 4)
        // The next mismatch probes: the catalog, both endpoints, and the bare variant.
        #expect(await ask() == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        #expect(http.requests.count == 8)
        #expect(lookupRequests.last?.url?.query == nil)
        // And that one is the run's probe.
        #expect(await ask() == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        #expect(http.requests.count == 11)
    }

    // MARK: log

    @Test func everyStepIsLoggedAtNoticeLevelWithItsStatusAndAppleSError() async {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        _ = await ask()
        let steps = log.messages(at: .default)
        #expect(steps.contains("Apple Music storefront: status=200 storefront=vn userToken=attached length=15"))
        #expect(steps.contains("Apple Music catalog-song: status=200 storefront=vn userToken=attached length=15"))
        #expect(steps.contains(#"Apple Music syllable-lyrics: status=404 error="No related resources" code=40400 storefront=vn userToken=attached length=15 query=\#(Self.query)"#))
        #expect(steps.contains(#"Apple Music lyrics: status=404 error="No related resources" code=40400 storefront=vn userToken=attached length=15 query=\#(Self.query)"#))
        #expect(steps.contains { $0.hasPrefix(#"Apple Music lyrics-probe(no-params+account-storefront): status=404"#) })
        #expect(log.messages(at: .info).isEmpty)
    }

    @Test func noUserAgentIsLoggedWhereNoneIsSet() async {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        _ = await ask()
        #expect(!log.messages.isEmpty)
        #expect(log.messages.allSatisfy { !$0.contains("userAgent") })
    }

    @Test func aStepThatNeverGotAnAnswerIsLogged() async {
        http.handler = { _ in throw URLError(.notConnectedToInternet) }
        _ = await ask()
        #expect(log.messages(at: .default) == [
            "Apple Music storefront: failed=Request failed (NSURLErrorDomain -1009) storefront=vn userToken=attached length=15",
            "Apple Music catalog-song: failed=Request failed (NSURLErrorDomain -1009) storefront=vn userToken=attached length=15",
        ])
    }

    @Test func theRefreshIsLoggedToo() async {
        http.handler = { request in
            switch request.url!.host() {
            case "music.apple.com": request.url!.path() == "/" ? AppleReplies.page : AppleReplies.bundle(containing: [AppleReplies.freshToken])
            default: request.value(forHTTPHeaderField: "Authorization") == "Bearer \(AppleReplies.freshToken)" ? (request.url!.path() == Self.storefrontPath ? AppleReplies.storefront("vn") : AppleReplies.catalogWithoutLyrics) : AppleReplies.rejected
            }
        }
        #expect(await ask() == .notFound)
        let steps = log.messages(at: .default)
        #expect(steps.contains { $0.hasPrefix("Apple Music storefront: status=401") && $0.contains("code=40100") })
        #expect(steps.contains("Apple Music token-refresh(page): status=200 storefront=- userToken=none"))
        #expect(steps.contains("Apple Music token-refresh(script): status=200 storefront=- userToken=none"))
    }

    @Test func noLogLineEverHoldsASecretOrALyric() async {
        let echoing = HTTPReply(status: 404, body: Data(#"{"errors":[{"title":"Bad Bearer dev-token-fake / user-token-fake and user%2Ftoken%3Dfake and user/token=fake","code":"user-token-fake"}]}"#.utf8))
        let leaky = NSError(domain: "FakeDomain", code: 7, userInfo: [NSLocalizedDescriptionKey: "Bearer dev-token-fake user-token-fake user%2Ftoken%3Dfake"])
        let scenarios: [(URLRequest) async throws -> HTTPReply] = [
            { _ in echoing },
            { request in request.url!.path().hasSuffix("/lyrics") ? echoing : AppleReplies.catalog() },
            { request in
                let path = request.url!.path()
                if path.hasSuffix("/syllable-lyrics") || path.hasSuffix("/lyrics") { return request.url!.query == nil ? AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 3, tag: "secretlyric")) : echoing }
                return path == Self.storefrontPath ? echoing : AppleReplies.catalog()
            },
            { _ in throw leaky },
            { request in if request.url!.host() == "music.apple.com" { throw leaky } else { return AppleReplies.rejected } },
            { _ in HTTPReply(status: 500, body: Data("dev-token-fake user-token-fake user%2Ftoken%3Dfake".utf8)) },
        ]
        // A user token as stored, and one that is percent-encoded.
        for storedUserToken in ["user-token-fake", "user%2Ftoken%3Dfake"] {
            let secrets = ["dev-token-fake", storedUserToken, storedUserToken.removingPercentEncoding!, "Bearer", AppleReplies.freshToken, "secretlyric", "<tt"]
            for scenario in scenarios {
                let store = FakeTokenStore.connected()
                _ = store.save(storedUserToken, for: .mediaUserToken)
                let account = AppleMusicAccount(tokens: store)
                account.load()
                let log = FakeAppleMusicLog()
                http.handler = scenario
                let client = AppleMusicLyricsClient(client: http, account: account, log: log)
                _ = await client.lyrics(forSongID: "1856960468", pace: { true })
                _ = await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: storedUserToken, storefront: "us"))
                #expect(!log.messages.isEmpty)
                for message in log.messages {
                    for secret in secrets { #expect(!message.contains(secret), "\(message)") }
                    #expect(!message.contains("\n"))
                }
            }
        }
    }

    @Test func anErrorTitleIsKeptShort() async {
        let long = String(repeating: "x", count: 500)
        http.reply(HTTPReply(status: 404, body: Data(#"{"errors":[{"title":"\#(long)","code":404}]}"#.utf8)))
        _ = await ask()
        let line = log.messages(at: .default).first ?? ""
        #expect(line.contains("code=404"))
        #expect(line.count < 400)
    }

    // MARK: sign-in rejected

    /// 401 for the stored developer token, the answers for the fresh one: what Apple does after the old one expired.
    func expiredToken(bundle: HTTPReply = AppleReplies.bundle(containing: [AppleReplies.freshToken])) {
        http.handler = { request in
            switch request.url!.host() {
            case "music.apple.com":
                return request.url!.path() == "/" ? AppleReplies.page : bundle
            default:
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(AppleReplies.freshToken)" else { return AppleReplies.rejected }
                let path = request.url!.path()
                if path == Self.storefrontPath { return AppleReplies.storefront("vn") }
                return path.hasSuffix("/syllable-lyrics") ? AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 5, tag: "fresh")) : AppleReplies.catalog()
            }
        }
    }

    @Test func aRejectedTokenIsRefreshedAndTheRequestRetriedOnce() async throws {
        expiredToken()
        #expect(await ask() == .synced(AppleReplies.lines(count: 5, tag: "fresh")))
        #expect(calls == [
            Self.storefrontCall, "music.apple.com/", "music.apple.com/assets/index-a1b2c3.js", Self.storefrontCall, Self.api, "\(Self.api)/syllable-lyrics",
        ])
        try #require(http.requests.count == 6)
        #expect(header("Authorization", of: http.requests[0]) == "Bearer dev-token-fake")
        for index in 3...5 { #expect(header("Authorization", of: http.requests[index]) == "Bearer \(AppleReplies.freshToken)") }
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
            default:
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(AppleReplies.freshToken)" else { return AppleReplies.forbidden }
                let path = request.url!.path()
                if path == Self.storefrontPath { return AppleReplies.storefront("vn") }
                return path.hasSuffix("/syllable-lyrics") ? AppleReplies.lyrics(ttml: AppleReplies.ttml()) : AppleReplies.catalog()
            }
        }
        #expect(await ask() == .synced(AppleReplies.lines()))
        #expect(http.requests.count == 6)
    }

    @Test func theFirstTokenInTheScriptIsTheOne() async {
        expiredToken(bundle: AppleReplies.bundle(containing: [AppleReplies.freshToken, AppleReplies.otherToken]))
        _ = await ask()
        #expect(account.credentials?.developerToken == AppleReplies.freshToken)
    }

    @Test func theTokenIsTheFirstJWTWhoseHeaderSaysES256() async {
        let hs256 = AppleReplies.jwt(header: #"{"alg":"HS256","typ":"JWT"}"#)
        let notJSON = "eyJub3QtanNvbg.cGF5bG9hZA.c2ln"
        let noAlgorithm = AppleReplies.jwt(header: #"{"typ":"JWT"}"#)
        let notAnObject = AppleReplies.jwt(header: "[1,2]")
        expiredToken(bundle: AppleReplies.bundle(containing: [hs256, notJSON, noAlgorithm, notAnObject, AppleReplies.freshToken, AppleReplies.otherToken]))
        #expect(await ask() == .synced(AppleReplies.lines(count: 5, tag: "fresh")))
        #expect(account.credentials?.developerToken == AppleReplies.freshToken)
        // The token starts "eyJ0", which the brief's first pattern ("eyJh") never matched.
        #expect(AppleReplies.freshToken.hasPrefix("eyJ0"))
    }

    @Test func aScriptWhoseTokensAreNotES256NeedsASignIn() async {
        let hs256 = AppleReplies.jwt(header: #"{"alg":"HS256","typ":"JWT"}"#)
        expiredToken(bundle: AppleReplies.bundle(containing: [hs256, "eyJub3QtanNvbg.cGF5bG9hZA.c2ln"]))
        #expect(await ask().isUnavailable)
        #expect(account.status == .needsReauth)
        #expect(tokens.values[.developerToken] == "dev-token-fake")
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
        #expect(calls == [Self.storefrontCall, "music.apple.com/", "music.apple.com/assets/index-a1b2c3.js", Self.storefrontCall])
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
                // The fresh token is fine for the storefront, the catalog and the first endpoint (nothing there); the second
                // endpoint rejects everything.
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(AppleReplies.freshToken)" else { return AppleReplies.rejected }
                let path = request.url!.path()
                if path == Self.storefrontPath { return AppleReplies.storefront("vn") }
                if path.hasSuffix("/syllable-lyrics") { return AppleReplies.notFound }
                return path.hasSuffix("/lyrics") ? AppleReplies.rejected : AppleReplies.catalog()
            }
        }
        #expect(await ask().isUnavailable)
        #expect(calls.filter { $0 == "music.apple.com/" }.count == 1)
        #expect(account.status == .needsReauth)
    }

    @Test func aPageWithoutAScriptNeedsASignIn() async {
        http.handler = { request in request.url!.host() == "music.apple.com" ? HTTPReply(status: 200, body: Data("<html><body>no scripts</body></html>".utf8)) : AppleReplies.rejected }
        #expect(await ask().isUnavailable)
        #expect(calls == [Self.storefrontCall, "music.apple.com/"])
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
            let account = AppleMusicAccount(tokens: FakeTokenStore.connected())
            account.load()
            let client = AppleMusicLyricsClient(client: http, account: account, log: log)
            http.handler = { request in request.url!.host() == "music.apple.com" ? failure : AppleReplies.rejected }
            #expect(await client.lyrics(forSongID: "1856960468", pace: { true }).isUnavailable)
            #expect(account.status == .connected(storefront: "vn"))
        }
        let account = AppleMusicAccount(tokens: FakeTokenStore.connected())
        account.load()
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        http.handler = { request in if request.url!.host() == "music.apple.com" { throw URLError(.timedOut) } else { return AppleReplies.rejected } }
        #expect(await client.lyrics(forSongID: "1856960468", pace: { true }).isUnavailable)
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
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        #expect(!client.isAvailable)
        #expect(await client.lyrics(forSongID: "42", pace: { true }).isUnavailable)
        #expect(http.requests.isEmpty)
    }

    // MARK: pacing

    @Test func everyRequestWaitsItsTurnFirst() async {
        expiredToken()
        var paced = 0
        _ = await client.lyrics(forSongID: "1856960468", pace: { paced += 1; return true })
        #expect(paced == 6)
        #expect(http.requests.count == 6)
    }

    @Test func theStorefrontAndProbeRequestsWaitTheirTurnToo() async {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        var paced = 0
        _ = await client.lyrics(forSongID: "1856960468", pace: { paced += 1; return true })
        // The account's storefront, the catalog, both endpoints, and the one variant that is not skipped.
        #expect(paced == 5)
        #expect(http.requests.count == 5)
    }

    @Test func aStoppedLookupSendsNothingFurther() async {
        route()
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
            { request in request.url!.path().hasSuffix("lyrics") ? HTTPReply(status: 404, body: Data("dev-token-fake user-token-fake".utf8)) : AppleReplies.catalog() },
        ]
        for scenario in scenarios {
            let account = AppleMusicAccount(tokens: FakeTokenStore.connected())
            account.load()
            http.handler = scenario
            let client = AppleMusicLyricsClient(client: http, account: account, log: FakeAppleMusicLog())
            let result = await client.lyrics(forSongID: "1856960468", pace: { true })
            let text = String(describing: result) + String(describing: account.status) + (account.problem ?? "") + account.status.text
            for secret in secrets { #expect(!text.contains(secret)) }
            if case .unavailable(let reason) = result { #expect(!reason.isEmpty) }
        }
    }

    // MARK: storefront at connect

    @Test func theStorefrontAnswerCarriesTheIdAndTheDefaultLanguage() async {
        http.reply(AppleReplies.storefront("us", language: "en-US"))
        let credentials = AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: nil)
        let answer = await client.storefront(for: credentials)
        #expect(answer?.id == "us")
        #expect(answer?.language == "en-US")
        #expect(calls == [Self.storefrontCall])
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

    @Test func connectingStoresTheStorefrontTheAccountReportsNotThePagesOne() async {
        let store = FakeTokenStore()
        let account = AppleMusicAccount(tokens: store)
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        http.reply(AppleReplies.storefront("vn"))
        #expect(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "us")))
        #expect(account.status == .connected(storefront: "vn"))
        #expect(store.values[.storefront] == "vn")
        #expect(calls == [Self.storefrontCall])
        #expect(log.messages(at: .default).contains("Apple Music account storefront: id=vn stored=us language=- changed=true"))
    }

    @Test func connectingKeepsThePagesStorefrontWhenAppleDoesNotAnswer() async {
        for reply in [AppleReplies.forbidden, HTTPReply(status: 500), AppleReplies.empty, AppleReplies.storefront("../x")] {
            let store = FakeTokenStore()
            let account = AppleMusicAccount(tokens: store)
            let client = AppleMusicLyricsClient(client: http, account: account, log: log)
            http.reply(reply)
            #expect(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "us")))
            #expect(account.status == .connected(storefront: "us"))
        }
    }

    @Test func connectingWithoutAStorefrontFromThePageTakesTheAccountsOne() async {
        let store = FakeTokenStore()
        let account = AppleMusicAccount(tokens: store)
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        http.reply(AppleReplies.storefront("th"))
        #expect(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: nil)))
        #expect(account.status == .connected(storefront: "th"))
        #expect(store.values[.storefront] == "th")
    }

    @Test func connectingWithoutAnyStorefrontSavesNothing() async {
        let store = FakeTokenStore()
        let account = AppleMusicAccount(tokens: store)
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
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
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        http.reply(AppleReplies.storefront("vn"))
        #expect(!(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "vn"))))
        #expect(account.problem == AppleMusicAccount.keychainProblem)
    }

    @Test func connectingCountsAsTheStorefrontCheckOfTheRunAndKeepsTheLanguage() async throws {
        let store = FakeTokenStore()
        let account = AppleMusicAccount(tokens: store)
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        http.reply(AppleReplies.storefront("vn", language: "vi"))
        _ = await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "vn"))
        http.forgetRequests()
        route(storefront: AppleReplies.storefront("vn", language: "vi"), syllable: found)
        #expect(await client.lyrics(forSongID: "1856960468", pace: { true }) == .synced(AppleReplies.lines()))
        #expect(!calls.contains(Self.storefrontCall))
        #expect(try #require(http.requests.last).url?.query == "l%5Blyrics%5D=vi&extend=ttmlLocalizations&l%5Bscript%5D=vi-Latn")
    }
}
