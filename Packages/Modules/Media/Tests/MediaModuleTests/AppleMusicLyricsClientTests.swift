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

    /// "host/path" of every request sent so far.
    var calls: [String] { http.requests.map { "\($0.url!.host()!)\($0.url!.path())" } }

    func header(_ name: String, of request: URLRequest) -> String? { request.value(forHTTPHeaderField: name) }

    func queryValue(_ name: String, of request: URLRequest) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    static let api = "amp-api.music.apple.com/v1/catalog/vn/songs/1856960468"

    /// Each of Apple's three endpoints answers on its own; the catalog says the song has lyrics unless told otherwise.
    func route(catalog: HTTPReply = AppleReplies.catalog(), syllable: HTTPReply = AppleReplies.notFound, lyrics: HTTPReply = AppleReplies.notFound) {
        http.handler = { request in
            let path = request.url!.path()
            if path.hasSuffix("/syllable-lyrics") { return syllable }
            if path.hasSuffix("/lyrics") { return lyrics }
            return catalog
        }
    }

    var found: HTTPReply { AppleReplies.lyrics(ttml: AppleReplies.ttml()) }

    // MARK: request

    @Test func theCatalogIsAskedFirstWithTheSameHeaders() async throws {
        route(syllable: found)
        #expect(await ask() == .synced(AppleReplies.lines()))
        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://amp-api.music.apple.com/v1/catalog/vn/songs/1856960468")
        #expect(header("Authorization", of: request) == "Bearer dev-token-fake")
        #expect(header("Media-User-Token", of: request) == "user-token-fake")
        #expect(header("Origin", of: request) == "https://music.apple.com")
        #expect(header("Referer", of: request) == "https://music.apple.com/")
        #expect(header("User-Agent", of: request) == nil)
        #expect(request.timeoutInterval == AppleMusicLyricsClient.requestTimeout)
    }

    @Test func askingForSyllableLyricsShapesTheRequest() async throws {
        route(syllable: AppleReplies.lyrics(ttml: AppleReplies.ttml(timing: "Word")))
        #expect(await ask() == .synced(AppleReplies.lines(tag: "line")))
        #expect(calls == ["\(Self.api)", "\(Self.api)/syllable-lyrics"])
        let request = try #require(http.requests.last)
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
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        http.reply(found)
        _ = await client.lyrics(forSongID: "42", pace: { true })
        #expect(calls == ["amp-api.music.apple.com/v1/catalog/us/songs/42", "amp-api.music.apple.com/v1/catalog/us/songs/42/syllable-lyrics"])
    }

    @Test func aSongIdThatIsNotDigitsIsNeverAsked() async {
        for id in ["", "12/../3", "12a", "1 2", "١٢٣"] {
            #expect(await ask(id) == .notFound, "\(id)")
        }
        #expect(http.requests.isEmpty)
    }

    // MARK: the catalog

    @Test(arguments: [(false, false), (false, nil), (nil, false)] as [(Bool?, Bool?)])
    func aSongTheCatalogSaysHasNoLyricsIsNotFoundWithoutAskingForThem(hasLyrics: Bool?, synced: Bool?) async {
        route(catalog: AppleReplies.catalog(hasLyrics: hasLyrics, hasTimeSyncedLyrics: synced), syllable: found, lyrics: found)
        #expect(await ask() == .notFound)
        #expect(calls == [Self.api])
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test(arguments: [(true, true), (true, false), (false, true), (true, nil), (nil, true)] as [(Bool?, Bool?)])
    func aSongTheCatalogListsLyricsForIsAskedForThem(hasLyrics: Bool?, synced: Bool?) async {
        route(catalog: AppleReplies.catalog(hasLyrics: hasLyrics, hasTimeSyncedLyrics: synced), syllable: found)
        #expect(await ask() == .synced(AppleReplies.lines()))
        #expect(calls == [Self.api, "\(Self.api)/syllable-lyrics"])
    }

    @Test func aSongNotInTheCatalogIsNotFound() async {
        for reply in [AppleReplies.notFound, AppleReplies.empty, HTTPReply(status: 410)] {
            http.reply(reply)
            #expect(await ask() == .notFound)
        }
        #expect(http.requests.count == 3)
    }

    @Test func withoutAVerdictFromTheCatalogNoLyricsIsWhatApplesaid() async {
        route(catalog: AppleReplies.catalogWithoutVerdict)
        #expect(await ask() == .notFound)
        #expect(calls == [Self.api, "\(Self.api)/syllable-lyrics", "\(Self.api)/lyrics"])
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test func withoutAnyEntryAtAllTheCatalogAnswerIsNotFound() async {
        http.reply(AppleReplies.empty)
        #expect(await ask() == .notFound)
        #expect(http.requests.count == 1)
    }

    // MARK: answers

    @Test func lineSyncedLyricsFromTheSyllableEndpoint() async {
        route(syllable: AppleReplies.lyrics(ttml: AppleReplies.ttml(timing: "Line", count: 5, tag: "la")))
        #expect(await ask() == .synced(AppleReplies.lines(count: 5, tag: "la")))
    }

    @Test func plainLyricsAreAnAnswerToo() async {
        route(syllable: AppleReplies.lyrics(ttml: AppleReplies.ttml(timing: "None", count: 2, tag: "words")))
        #expect(await ask() == .plain("words 1\nwords 2"))
        #expect(http.requests.count == 2)
    }

    @Test func a404FallsBackToTheLyricsEndpoint() async throws {
        route(lyrics: AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 6, tag: "plain"), type: "lyrics"))
        #expect(await ask() == .synced(AppleReplies.lines(count: 6, tag: "plain")))
        #expect(calls == [Self.api, "\(Self.api)/syllable-lyrics", "\(Self.api)/lyrics"])
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
        #expect(http.requests.count == 12)
    }

    // MARK: failures

    @Test(arguments: [408, 429, 500, 502, 503])
    func otherStatusesAreUnavailableAndNothingMoreIsAsked(status: Int) async {
        http.reply(HTTPReply(status: status, body: Data("busy".utf8), retryAfter: "30"))
        let result = await ask()
        #expect(result.isUnavailable)
        #expect(http.requests.count == 1)
        #expect(account.status == .connected(storefront: "vn"))
    }

    @Test(arguments: [408, 429, 500, 503])
    func theSameFromALyricsEndpointIsUnavailableAndNoProbeFollows(status: Int) async {
        route(syllable: HTTPReply(status: status))
        #expect(await ask().isUnavailable)
        #expect(calls == [Self.api, "\(Self.api)/syllable-lyrics"])
    }

    @Test(arguments: [400, 405, 410, 422, 451])
    func otherClientErrorsAreNoLyricsRatherThanTrouble(status: Int) async {
        // An answer like this every time must not cost a full lookup at each replay: it is "not found", which is cached.
        route(catalog: AppleReplies.catalogWithoutVerdict, syllable: HTTPReply(status: status, body: Data("no".utf8)), lyrics: HTTPReply(status: status, body: Data("no".utf8)))
        #expect(await ask() == .notFound)
        #expect(calls == [Self.api, "\(Self.api)/syllable-lyrics", "\(Self.api)/lyrics"])
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
        #expect(errors.contains { $0.contains("lists lyrics") && $0.contains("catalog-song=200 syllable-lyrics=404 lyrics=404") && $0.contains("storefront=vn") && $0.contains("userToken=attached length=15") })
    }

    // MARK: the probe

    func probeCalls() -> [URLRequest] { Array(http.requests.dropFirst(3)) }

    @Test func theProbeTriesTheLyricsEndpointWithASafariUserAgentAndThenItsLanguage() async throws {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        #expect(await ask() == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        // catalog, syllable, lyrics, then at most three more; this token has no "%", so two.
        #expect(calls == [Self.api, "\(Self.api)/syllable-lyrics", "\(Self.api)/lyrics", "\(Self.api)/lyrics", "\(Self.api)/lyrics"])
        try #require(http.requests.count == 5)
        for request in http.requests.prefix(3) { #expect(header("User-Agent", of: request) == nil) }
        let (plain, withLanguage) = (probeCalls()[0], probeCalls()[1])
        #expect(header("User-Agent", of: plain) == AppleMusicLyricsClient.safariUserAgent)
        #expect(header("User-Agent", of: plain) == "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15")
        #expect(queryValue("l", of: plain) == nil)
        #expect(plain.url?.absoluteString == "https://amp-api.music.apple.com/v1/catalog/vn/songs/1856960468/lyrics")
        #expect(header("User-Agent", of: withLanguage) == AppleMusicLyricsClient.safariUserAgent)
        #expect(queryValue("l", of: withLanguage) == "vi")
        for request in probeCalls() {
            #expect(header("Authorization", of: request) == "Bearer dev-token-fake")
            #expect(header("Media-User-Token", of: request) == "user-token-fake")
            #expect(header("Origin", of: request) == "https://music.apple.com")
            #expect(header("Referer", of: request) == "https://music.apple.com/")
        }
    }

    @Test func otherStoresAskInEnglish() async throws {
        let account = AppleMusicAccount(tokens: FakeTokenStore.connected(storefront: "us"))
        account.load()
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        _ = await client.lyrics(forSongID: "1856960468", pace: { true })
        try #require(http.requests.count == 5)
        #expect(queryValue("l", of: http.requests[4]) == "en-US")
    }

    @Test func aTokenWithAPercentSignIsAlsoTriedDecoded() async throws {
        let store = FakeTokenStore.connected()
        store.signIn()
        _ = store.save("user%2Ftoken%3Dfake", for: .mediaUserToken)
        let account = AppleMusicAccount(tokens: store)
        account.load()
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        #expect(await client.lyrics(forSongID: "1856960468", pace: { true }) == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        try #require(http.requests.count == 6)
        let decoded = http.requests[5]
        #expect(header("Media-User-Token", of: decoded) == "user/token=fake")
        #expect(header("User-Agent", of: decoded) == nil)
        #expect(queryValue("l", of: decoded) == nil)
        // The first requests and the first two probes send the token as it is stored.
        for index in [0, 1, 2, 3, 4] { #expect(header("Media-User-Token", of: http.requests[index]) == "user%2Ftoken%3Dfake") }
        // What is stored is not changed by the probe.
        #expect(store.values[.mediaUserToken] == "user%2Ftoken%3Dfake")
    }

    @Test func theProbeRunsOncePerRun() async {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        #expect(await ask() == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        let first = http.requests.count
        #expect(first == 5)
        #expect(await ask() == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        #expect(await ask("42") == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        // Only the catalog and the two endpoints each time.
        #expect(http.requests.count == first + 6)
        #expect(http.requests.dropFirst(first).allSatisfy { header("User-Agent", of: $0) == nil })
    }

    @Test func aVariantThatWorksIsTheAnswerAndIsUsedFromThenOn() async throws {
        http.handler = { [self] request in
            let path = request.url!.path()
            if path.hasSuffix("/syllable-lyrics") || path.hasSuffix("/lyrics") {
                return header("User-Agent", of: request) == AppleMusicLyricsClient.safariUserAgent ? AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 5, tag: "apple")) : AppleReplies.noRelatedResources
            }
            return AppleReplies.catalog()
        }
        #expect(await ask() == .synced(AppleReplies.lines(count: 5, tag: "apple")))
        #expect(http.requests.count == 4)
        #expect(log.messages(at: .default).contains { $0.hasPrefix("Apple lyrics variant that works: safari-user-agent") })

        // The next song asks the way that works: no probe is needed.
        #expect(await ask("42") == .synced(AppleReplies.lines(count: 5, tag: "apple")))
        let next = http.requests.dropFirst(4)
        #expect(next.map { "\($0.url!.path())" } == ["/v1/catalog/vn/songs/42", "/v1/catalog/vn/songs/42/syllable-lyrics"])
        #expect(next.allSatisfy { header("User-Agent", of: $0) == AppleMusicLyricsClient.safariUserAgent })
        #expect(next.allSatisfy { queryValue("l", of: $0) == nil })
    }

    @Test func aVariantWithTheLanguageIsUsedWithItsLanguage() async {
        http.handler = { [self] request in
            let path = request.url!.path()
            if path.hasSuffix("/syllable-lyrics") || path.hasSuffix("/lyrics") {
                return queryValue("l", of: request) == "vi" ? AppleReplies.lyrics(ttml: AppleReplies.ttml()) : AppleReplies.noRelatedResources
            }
            return AppleReplies.catalog()
        }
        #expect(await ask() == .synced(AppleReplies.lines()))
        #expect(http.requests.count == 5)
        #expect(log.messages(at: .default).contains { $0.hasPrefix("Apple lyrics variant that works: safari-user-agent+language") && $0.contains("language=vi") })
        #expect(await ask("42") == .synced(AppleReplies.lines()))
        let next = http.requests.dropFirst(5)
        #expect(next.allSatisfy { header("User-Agent", of: $0) == AppleMusicLyricsClient.safariUserAgent && queryValue("l", of: $0) == "vi" })
    }

    @Test func aDecodedTokenThatWorksIsUsedFromThenOnWithoutChangingTheStore() async {
        let store = FakeTokenStore.connected()
        _ = store.save("user%2Ftoken%3Dfake", for: .mediaUserToken)
        let account = AppleMusicAccount(tokens: store)
        account.load()
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        http.handler = { [self] request in
            let path = request.url!.path()
            if path.hasSuffix("/syllable-lyrics") || path.hasSuffix("/lyrics") {
                return header("Media-User-Token", of: request) == "user/token=fake" ? AppleReplies.lyrics(ttml: AppleReplies.ttml()) : AppleReplies.noRelatedResources
            }
            return AppleReplies.catalog()
        }
        #expect(await client.lyrics(forSongID: "1856960468", pace: { true }) == .synced(AppleReplies.lines()))
        #expect(http.requests.count == 6)
        #expect(log.messages(at: .default).contains { $0.hasPrefix("Apple lyrics variant that works: decoded-user-token") })
        #expect(await client.lyrics(forSongID: "42", pace: { true }) == .synced(AppleReplies.lines()))
        #expect(http.requests.dropFirst(6).allSatisfy { header("Media-User-Token", of: $0) == "user/token=fake" })
        #expect(store.values[.mediaUserToken] == "user%2Ftoken%3Dfake")
    }

    @Test func aProbeThatFailsOnTheWireIsLoggedAndTheNextVariantTried() async {
        http.handler = { [self] request in
            if header("User-Agent", of: request) != nil && queryValue("l", of: request) == nil { throw URLError(.timedOut) }
            let path = request.url!.path()
            if path.hasSuffix("/syllable-lyrics") || path.hasSuffix("/lyrics") { return AppleReplies.noRelatedResources }
            return AppleReplies.catalog()
        }
        #expect(await ask() == .unavailable(AppleMusicLyricsClient.missingLyricsReason))
        #expect(http.requests.count == 5)
        #expect(log.messages.contains { $0.contains("lyrics-probe(safari-user-agent): failed=Request failed (NSURLErrorDomain -1001)") })
    }

    @Test func theProbeStopsWhenTheLookupDoes() async {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        var paced = 0
        let result = await client.lyrics(forSongID: "1856960468", pace: { paced += 1; return paced <= 4 })
        #expect(result == .unavailable(AppleMusicLyricsClient.stoppedReason))
        #expect(http.requests.count == 4)
    }

    // MARK: log

    @Test func everyStepIsLoggedWithItsStatusAndAppleSError() async {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        _ = await ask()
        let steps = log.messages(at: .info)
        #expect(steps.contains("Apple Music catalog-song: status=200 storefront=vn userToken=attached length=15 userAgent=system default"))
        #expect(steps.contains(#"Apple Music syllable-lyrics: status=404 error="No related resources" code=40400 storefront=vn userToken=attached length=15 userAgent=system default"#))
        #expect(steps.contains(#"Apple Music lyrics: status=404 error="No related resources" code=40400 storefront=vn userToken=attached length=15 userAgent=system default"#))
        let userAgent = AppleMusicLyricsClient.safariUserAgent
        #expect(steps.contains(#"Apple Music lyrics-probe(safari-user-agent): status=404 error="No related resources" code=40400 storefront=vn userToken=attached length=15 userAgent=\#(userAgent)"#))
        #expect(steps.contains { $0.hasPrefix("Apple Music lyrics-probe(safari-user-agent+language): status=404") })
        #expect(log.messages(at: .error).contains { $0.contains("probe") && $0.contains("safari-user-agent=404 safari-user-agent+language=404") })
    }

    @Test func aStepThatNeverGotAnAnswerIsLogged() async {
        http.handler = { _ in throw URLError(.notConnectedToInternet) }
        _ = await ask()
        #expect(log.messages(at: .info) == ["Apple Music catalog-song: failed=Request failed (NSURLErrorDomain -1009) storefront=vn userToken=attached length=15 userAgent=system default"])
    }

    @Test func theRefreshAndTheStorefrontAreLoggedToo() async {
        http.handler = { request in
            switch request.url!.host() {
            case "music.apple.com": request.url!.path() == "/" ? AppleReplies.page : AppleReplies.bundle(containing: [AppleReplies.freshToken])
            default: request.value(forHTTPHeaderField: "Authorization") == "Bearer \(AppleReplies.freshToken)" ? AppleReplies.catalogWithoutLyrics : AppleReplies.rejected
            }
        }
        #expect(await ask() == .notFound)
        let steps = log.messages(at: .info)
        #expect(steps.contains { $0.hasPrefix("Apple Music catalog-song: status=401") && $0.contains(#"code=40100"#) })
        #expect(steps.contains("Apple Music token-refresh(page): status=200 storefront=- userToken=none userAgent=system default"))
        #expect(steps.contains("Apple Music token-refresh(script): status=200 storefront=- userToken=none userAgent=system default"))
        http.reply(AppleReplies.storefront("vn"))
        _ = await client.storefront(for: AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: nil))
        #expect(log.messages(at: .info).contains("Apple Music storefront: status=200 storefront=- userToken=attached length=15 userAgent=system default"))
    }

    @Test func noLogLineEverHoldsASecretOrALyric() async {
        let echoing = HTTPReply(status: 404, body: Data(#"{"errors":[{"title":"Bad Bearer dev-token-fake / user-token-fake and user%2Ftoken%3Dfake and user/token=fake","code":"user-token-fake"}]}"#.utf8))
        let leaky = NSError(domain: "FakeDomain", code: 7, userInfo: [NSLocalizedDescriptionKey: "Bearer dev-token-fake user-token-fake user%2Ftoken%3Dfake"])
        let scenarios: [(URLRequest) async throws -> HTTPReply] = [
            { _ in echoing },
            { request in request.url!.path().hasSuffix("/lyrics") ? echoing : AppleReplies.catalog() },
            { request in
                let path = request.url!.path()
                if path.hasSuffix("/syllable-lyrics") || path.hasSuffix("/lyrics") {
                    // The decoded token is the one that works: its lyrics must not reach the log either.
                    return ["user/token=fake", "user-token-fake"].contains(request.value(forHTTPHeaderField: "Media-User-Token") ?? "") && request.value(forHTTPHeaderField: "Media-User-Token") != "user%2Ftoken%3Dfake"
                        ? AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 3, tag: "secretlyric")) : echoing
                }
                return AppleReplies.catalog()
            },
            { _ in throw leaky },
            { request in if request.url!.host() == "music.apple.com" { throw leaky } else { return AppleReplies.rejected } },
            { _ in HTTPReply(status: 500, body: Data("dev-token-fake user-token-fake user%2Ftoken%3Dfake".utf8)) },
        ]
        // A user token as stored, and one that is percent-encoded (which makes the probe try it decoded too).
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
                _ = await client.storefront(for: AppleMusicCredentials(developerToken: "dev-token-fake", userToken: storedUserToken, storefront: nil))
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
        let line = log.messages(at: .info).first ?? ""
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
                return request.url!.path().hasSuffix("/syllable-lyrics") ? AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 5, tag: "fresh")) : AppleReplies.catalog()
            }
        }
    }

    @Test func aRejectedTokenIsRefreshedAndTheRequestRetriedOnce() async throws {
        expiredToken()
        #expect(await ask() == .synced(AppleReplies.lines(count: 5, tag: "fresh")))
        #expect(calls == [
            Self.api, "music.apple.com/", "music.apple.com/assets/index-a1b2c3.js", Self.api, "\(Self.api)/syllable-lyrics",
        ])
        try #require(http.requests.count == 5)
        #expect(header("Authorization", of: http.requests[0]) == "Bearer dev-token-fake")
        #expect(header("Authorization", of: http.requests[3]) == "Bearer \(AppleReplies.freshToken)")
        #expect(header("Authorization", of: http.requests[4]) == "Bearer \(AppleReplies.freshToken)")
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
                return request.url!.path().hasSuffix("/syllable-lyrics") ? AppleReplies.lyrics(ttml: AppleReplies.ttml()) : AppleReplies.catalog()
            }
        }
        #expect(await ask() == .synced(AppleReplies.lines()))
        #expect(http.requests.count == 5)
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
        #expect(calls == [Self.api, "music.apple.com/", "music.apple.com/assets/index-a1b2c3.js", Self.api])
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
                // The fresh token is fine for the catalog and the first endpoint (nothing there), the second endpoint rejects everything.
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(AppleReplies.freshToken)" else { return AppleReplies.rejected }
                let path = request.url!.path()
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
        #expect(calls == [Self.api, "music.apple.com/"])
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
        #expect(paced == 5)
        #expect(http.requests.count == 5)
    }

    @Test func theProbeRequestsWaitTheirTurnToo() async {
        route(syllable: AppleReplies.noRelatedResources, lyrics: AppleReplies.noRelatedResources)
        var paced = 0
        _ = await client.lyrics(forSongID: "1856960468", pace: { paced += 1; return true })
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
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        #expect(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "vn")))
        #expect(account.status == .connected(storefront: "vn"))
        #expect(http.requests.isEmpty)
    }

    @Test func connectingWithoutAStorefrontFetchesItFirst() async {
        let store = FakeTokenStore()
        let account = AppleMusicAccount(tokens: store)
        let client = AppleMusicLyricsClient(client: http, account: account, log: log)
        http.reply(AppleReplies.storefront("th"))
        #expect(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: nil)))
        #expect(account.status == .connected(storefront: "th"))
        #expect(store.values[.storefront] == "th")
        #expect(calls == ["amp-api.music.apple.com/v1/me/storefront"])
    }

    @Test func connectingWithoutAStorefrontThatCannotBeFetchedSavesNothing() async {
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
        #expect(!(await client.connect(AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "vn"))))
        #expect(account.problem == AppleMusicAccount.keychainProblem)
    }
}
