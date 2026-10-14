import Foundation
import MyNotchTestSupport
import Testing
@testable import MediaModule

/// The Apple Music step in front of the lrclib chain. Fake HTTP and a fake token store: no network, no Keychain.
@Suite final class LyricsServiceAppleTests {
    let root = ScratchFolders.shared.reserve("LyricsServiceApple")
    let http = FakeHTTPClient()
    let scheduler = ManualScheduler()
    let tokens: FakeTokenStore
    let account: AppleMusicAccount

    init() {
        tokens = FakeTokenStore.connected()
        account = AppleMusicAccount(tokens: tokens)
        account.load()
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var cacheDirectory: URL { root.appending(path: "lyrics", directoryHint: .isDirectory) }

    func makeService() -> LyricsService {
        LyricsService(
            client: http, cacheDirectory: cacheDirectory, scheduler: scheduler, appVersion: "1.2",
            apple: AppleMusicLyricsClient(client: http, account: account)
        )
    }

    /// A track as the Music app reports it, unless said otherwise.
    func track(
        _ title: String = "Song", id: String? = "1856960468", bundle: String = "com.apple.Music", album: String? = "Album"
    ) -> TrackKey {
        let state = NowPlayingState(
            bundleIdentifier: bundle, title: title, artist: "Artist", album: album, durationSeconds: 200, uniqueIdentifier: id
        )
        return TrackKey(state)!
    }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    /// Runs one lookup to its end, moving time past the spacing between its requests.
    func lookup(_ service: LyricsService, _ track: TrackKey) async -> LyricsResult {
        var result: LyricsResult?
        let task = Task { result = await service.lyrics(for: track) }
        for _ in 0..<12 where result == nil {
            await settle { result != nil }
            scheduler.advance(by: LyricsService.minimumSpacing)
        }
        // A lookup that does not end is a failure, not a test that waits for ever.
        if result == nil { task.cancel() }
        await task.value
        #expect(result != nil, "the lookup did not finish")
        return result ?? .unavailable("did not finish")
    }

    /// Apple's two endpoints and lrclib answer separately; lrclib's searches find nothing unless `search` says so.
    func route(
        syllable: HTTPReply = AppleReplies.notFound, plain: HTTPReply = AppleReplies.notFound,
        lrclib: HTTPReply = LrclibReplies.notFound, search: HTTPReply = LrclibReplies.results([])
    ) {
        http.handler = { request in
            let url = request.url!
            switch url.host() {
            case "amp-api.music.apple.com": return url.path().hasSuffix("/syllable-lyrics") ? syllable : plain
            default: return url.path() == "/api/search" ? search : lrclib
            }
        }
    }

    /// "host path" of every request.
    var calls: [String] { http.requests.map { "\($0.url!.host()!)\($0.url!.path())" } }

    static let apple = "amp-api.music.apple.com"
    static let appleLines = AppleReplies.lines(count: 5, tag: "apple")
    static let appleSyllable = AppleReplies.lyrics(ttml: AppleReplies.ttml(timing: "Word", count: 5, tag: "apple"))
    var appleFound: HTTPReply { AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 5, tag: "apple")) }

    // MARK: the chain

    @Test func appleLyricsAreTheAnswerAndLrclibIsNotAsked() async {
        route(syllable: appleFound, lrclib: LrclibReplies.found())
        #expect(await lookup(makeService(), track()) == .synced(Self.appleLines))
        #expect(calls == ["\(Self.apple)/v1/catalog/vn/songs/1856960468/syllable-lyrics"])
    }

    @Test func syllableTimedLyricsAreTheAnswerToo() async {
        route(syllable: Self.appleSyllable, lrclib: LrclibReplies.found())
        let result = await lookup(makeService(), track())
        guard case .synced(let lines) = result else { Issue.record("not synced: \(result)"); return }
        #expect(lines.count == 5)
        #expect(http.requests.count == 1)
    }

    @Test func plainLyricsFromAppleAreAnAnswerToo() async {
        route(syllable: AppleReplies.lyrics(ttml: AppleReplies.ttml(timing: "None", count: 2, tag: "words")), lrclib: LrclibReplies.found())
        #expect(await lookup(makeService(), track()) == .plain("words 1\nwords 2"))
        #expect(http.requests.count == 1)
    }

    @Test func whenAppleHasNothingTheLrclibChainRunsAsItAlwaysDid() async {
        route(lrclib: LrclibReplies.found())
        #expect(await lookup(makeService(), track()) == .synced(LrclibReplies.syncedLines))
        #expect(calls == [
            "\(Self.apple)/v1/catalog/vn/songs/1856960468/syllable-lyrics",
            "\(Self.apple)/v1/catalog/vn/songs/1856960468/lyrics",
            "lrclib.net/api/get",
        ])
    }

    @Test func theWholeLrclibChainFollowsWhenNobodyHasIt() async {
        route()
        #expect(await lookup(makeService(), track()) == .notFound)
        #expect(http.requests.count == 6)
        #expect(calls.suffix(4) == ["lrclib.net/api/get", "lrclib.net/api/get", "lrclib.net/api/search", "lrclib.net/api/search"])
    }

    @Test func appleFoundOnTheLyricsEndpointEndsTheChainThere() async {
        route(plain: AppleReplies.lyrics(ttml: AppleReplies.ttml(count: 5, tag: "apple"), type: "lyrics"), lrclib: LrclibReplies.found())
        #expect(await lookup(makeService(), track()) == .synced(Self.appleLines))
        #expect(http.requests.count == 2)
    }

    @Test func aMixInTheTitleStillKeepsMusicTracksOutOfEveryLookup() async {
        route(syllable: appleFound)
        var state = NowPlayingState(bundleIdentifier: "com.apple.Music", title: "Best Mix 2024", artist: "Artist", album: "Album", durationSeconds: 420)
        state.uniqueIdentifier = "1856960468"
        #expect(await lookup(makeService(), TrackKey(state)!) == .notFound)
        #expect(http.requests.isEmpty)
    }

    // MARK: who is asked

    @Test(arguments: ["com.spotify.client", "com.google.Chrome", "com.apple.Safari", "tv.plex.player", "com.apple.Music.helper"])
    func onlyTheMusicAppIsAskedAboutAtApple(bundle: String) async {
        route(lrclib: LrclibReplies.found())
        #expect(await lookup(makeService(), track(id: "1856960468", bundle: bundle)) == .synced(LrclibReplies.syncedLines))
        #expect(http.requests.allSatisfy { $0.url!.host() == "lrclib.net" })
    }

    @Test(arguments: [nil, "", "ABC123", "12-34", "1219::1227", "-5", "1.5"] as [String?])
    func aMusicTrackWithoutANumericCatalogIdIsLrclibOnly(id: String?) async {
        route(lrclib: LrclibReplies.found())
        #expect(await lookup(makeService(), track(id: id)) == .synced(LrclibReplies.syncedLines))
        #expect(http.requests.allSatisfy { $0.url!.host() == "lrclib.net" })
    }

    @Test func withoutAnAccountAppleIsNotAsked() async {
        let account = AppleMusicAccount(tokens: FakeTokenStore())
        account.load()
        let service = LyricsService(
            client: http, cacheDirectory: cacheDirectory, scheduler: scheduler, appVersion: "1.2",
            apple: AppleMusicLyricsClient(client: http, account: account)
        )
        route(lrclib: LrclibReplies.found())
        #expect(await lookup(service, track()) == .synced(LrclibReplies.syncedLines))
        #expect(http.requests.allSatisfy { $0.url!.host() == "lrclib.net" })
    }

    @Test func withoutAnAppleClientAtAllAppleIsNotAsked() async {
        route(lrclib: LrclibReplies.found())
        let service = LyricsService(client: http, cacheDirectory: cacheDirectory, scheduler: scheduler, appVersion: "1.2")
        #expect(await lookup(service, track()) == .synced(LrclibReplies.syncedLines))
        #expect(http.requests.allSatisfy { $0.url!.host() == "lrclib.net" })
    }

    @Test func whenASignInIsNeededAppleIsNotAsked() async {
        account.markNeedsReauth()
        route(lrclib: LrclibReplies.found())
        #expect(await lookup(makeService(), track()) == .synced(LrclibReplies.syncedLines))
        #expect(http.requests.allSatisfy { $0.url!.host() == "lrclib.net" })
    }

    // MARK: failures

    @Test func aFailureAtAppleStillRunsLrclib() async {
        route(syllable: HTTPReply(status: 503), lrclib: LrclibReplies.found())
        #expect(await lookup(makeService(), track()) == .synced(LrclibReplies.syncedLines))
        #expect(calls == ["\(Self.apple)/v1/catalog/vn/songs/1856960468/syllable-lyrics", "lrclib.net/api/get"])
    }

    @Test(arguments: [429, 500, 503])
    func nothingFoundAnywhereAfterAppleFailedIsNotRememberedAsNotFound(status: Int) async {
        route(syllable: HTTPReply(status: status))
        let service = makeService()
        let result = await lookup(service, track())
        #expect(result.reason == "Apple Music: HTTP \(status)")
        #expect(http.requests.count == 5)
        let cached = (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path())) ?? []
        #expect(cached.isEmpty)

        // The next ask goes to Apple again, and this time Apple has it.
        route(syllable: appleFound)
        #expect(await lookup(service, track()) == .synced(Self.appleLines))
        #expect(http.requests.count == 6)
    }

    @Test func aClientErrorFromAppleIsNoTroubleAndTheNotFoundIsRemembered() async {
        route(syllable: HTTPReply(status: 410), plain: HTTPReply(status: 410))
        let service = makeService()
        #expect(await lookup(service, track()) == .notFound)
        let asked = http.requests.count
        scheduler.advance(by: .seconds(1))
        #expect(await lookup(service, track()) == .notFound)
        #expect(http.requests.count == asked)
    }

    @Test func aNetworkFailureAtAppleStillRunsLrclib() async {
        http.handler = { request in
            if request.url!.host() == "amp-api.music.apple.com" { throw URLError(.notConnectedToInternet) }
            return LrclibReplies.found()
        }
        #expect(await lookup(makeService(), track()) == .synced(LrclibReplies.syncedLines))
    }

    @Test func aFoundAnswerWhileAppleWasDownIsStillCached() async {
        route(syllable: HTTPReply(status: 500), lrclib: LrclibReplies.found())
        let service = makeService()
        _ = await lookup(service, track())
        let asked = http.requests.count
        scheduler.advance(by: .seconds(1))
        #expect(await lookup(service, track()) == .synced(LrclibReplies.syncedLines))
        #expect(http.requests.count == asked)
    }

    @Test func rejectedTwiceFallsBackToLrclibAndLeavesAppleAlone() async {
        http.handler = { request in
            switch request.url!.host() {
            case "amp-api.music.apple.com": AppleReplies.rejected
            case "music.apple.com": request.url!.path() == "/" ? AppleReplies.page : AppleReplies.bundle(containing: [AppleReplies.freshToken])
            default: LrclibReplies.found()
            }
        }
        let service = makeService()
        #expect(await lookup(service, track()) == .synced(LrclibReplies.syncedLines))
        #expect(account.status == .needsReauth)
        #expect(account.status.text == "Cần đăng nhập lại")
        #expect(calls.last == "lrclib.net/api/get")

        let asked = http.requests.count
        scheduler.advance(by: .seconds(1))
        #expect(await lookup(service, track("Another")) == .synced(LrclibReplies.syncedLines))
        #expect(http.requests.dropFirst(asked).allSatisfy { $0.url!.host() == "lrclib.net" })
    }

    // MARK: cache

    @Test func appleAnswersAreCachedAcrossARestart() async {
        route(syllable: appleFound)
        _ = await lookup(makeService(), track())
        scheduler.advance(by: .seconds(1))
        #expect(await lookup(makeService(), track()) == .synced(Self.appleLines))
        #expect(http.requests.count == 1)
    }

    @Test func connectingMakesAnEarlierNotFoundIrrelevant() async {
        let loggedOut = AppleMusicAccount(tokens: FakeTokenStore())
        loggedOut.load()
        route()
        let before = LyricsService(
            client: http, cacheDirectory: cacheDirectory, scheduler: scheduler, appVersion: "1.2",
            apple: AppleMusicLyricsClient(client: http, account: loggedOut)
        )
        #expect(await lookup(before, track()) == .notFound)
        #expect(http.requests.count == 4)
        // Asked again: the answer is cached, for lrclib only.
        scheduler.advance(by: .seconds(1))
        #expect(await lookup(before, track()) == .notFound)
        #expect(http.requests.count == 4)

        // Connected: the same track, in the same cache, goes to Apple.
        route(syllable: appleFound)
        scheduler.advance(by: .seconds(1))
        #expect(await lookup(makeService(), track()) == .synced(Self.appleLines))
        #expect(http.requests.count == 5)
        #expect(calls.last?.hasPrefix(Self.apple) == true)
    }

    @Test func disconnectingBringsTheLrclibAnswerBack() async {
        route()
        let service = makeService()
        _ = await lookup(service, track())
        let asked = http.requests.count
        account.disconnect()
        scheduler.advance(by: .seconds(1))
        // The answer above was cached under the key that says Apple was asked, so a lookup without Apple starts over.
        route(lrclib: LrclibReplies.found())
        #expect(await lookup(service, track()) == .synced(LrclibReplies.syncedLines))
        #expect(http.requests.count > asked)
        #expect(http.requests.dropFirst(asked).allSatisfy { $0.url!.host() == "lrclib.net" })
    }

    // MARK: sequencing

    @Test func everyRequestWaitsForTheSpacingAfterTheLast() async {
        route(lrclib: LrclibReplies.found())
        let service = makeService()
        let task = Task { await service.lyrics(for: track()) }
        await settle { http.requests.count == 1 }
        // Apple's first request goes out at once; nothing follows before the spacing is over.
        scheduler.advance(by: .milliseconds(299))
        await settle { http.requests.count > 1 }
        #expect(http.requests.count == 1)
        scheduler.advance(by: .milliseconds(1))
        await settle { http.requests.count == 2 }
        #expect(http.requests.count == 2)
        scheduler.advance(by: .milliseconds(299))
        await settle { http.requests.count > 2 }
        #expect(http.requests.count == 2)
        scheduler.advance(by: .milliseconds(1))
        #expect(await task.value == .synced(LrclibReplies.syncedLines))
        #expect(http.requests.count == 3)
        #expect(http.maxActiveCount == 1)
    }

    @Test func theTokenRefreshIsPacedLikeEveryOtherRequest() async {
        http.handler = { request in
            switch request.url!.host() {
            case "amp-api.music.apple.com":
                request.value(forHTTPHeaderField: "Authorization") == "Bearer \(AppleReplies.freshToken)" ? self.appleFound : AppleReplies.rejected
            case "music.apple.com":
                request.url!.path() == "/" ? AppleReplies.page : AppleReplies.bundle(containing: [AppleReplies.freshToken])
            default: LrclibReplies.found()
            }
        }
        let service = makeService()
        let task = Task { await service.lyrics(for: track()) }
        for expected in 1...4 {
            await settle { http.requests.count == expected }
            #expect(http.requests.count == expected)
            await settle { http.requests.count > expected }
            #expect(http.requests.count == expected)
            scheduler.advance(by: LyricsService.minimumSpacing)
        }
        #expect(await task.value == .synced(Self.appleLines))
        #expect(http.requests.count == 4)
        #expect(http.maxActiveCount == 1)
    }

    @Test func aLookupCancelledBetweenAppleStepsSendsNothingMore() async {
        route(lrclib: LrclibReplies.found())
        let service = makeService()
        let task = Task { await service.lyrics(for: track()) }
        await settle { http.requests.count == 1 }
        task.cancel()
        // No time passes: the lookup ends at once instead of waiting out the spacing.
        #expect(await task.value.reason == "Lookup cancelled")
        #expect(http.requests.count == 1)
    }

    @Test func shuttingDownBetweenAppleStepsSendsNothingMore() async {
        route(lrclib: LrclibReplies.found())
        let service = makeService()
        let task = Task { await service.lyrics(for: track()) }
        await settle { http.requests.count == 1 }
        service.shutDown()
        #expect(await task.value.isUnavailable)
        #expect(http.requests.count == 1)
    }

    @Test func aCancelledLookupPassesTheTurnOn() async {
        route(lrclib: LrclibReplies.found())
        let service = makeService()
        let first = Task { await service.lyrics(for: track("A")) }
        await settle { http.requests.count == 1 }
        let second = Task { await service.lyrics(for: track("B", id: nil)) }
        await settle { service.queuedCount == 1 }
        first.cancel()
        _ = await first.value
        scheduler.advance(by: LyricsService.minimumSpacing)
        #expect(await second.value == .synced(LrclibReplies.syncedLines))
        #expect(http.maxActiveCount == 1)
    }
}
