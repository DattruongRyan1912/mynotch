import Foundation
import MyNotchTestSupport
import Testing
@testable import MediaModule

@Suite final class LyricsServiceTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "LyricsServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let client = FakeHTTPClient()
    let scheduler = ManualScheduler()

    deinit { try? FileManager.default.removeItem(at: root) }

    var cacheDirectory: URL { root.appending(path: "lyrics", directoryHint: .isDirectory) }

    func makeService(appVersion: String? = "1.2") -> LyricsService {
        LyricsService(client: client, cacheDirectory: cacheDirectory, scheduler: scheduler, appVersion: appVersion)
    }

    func key(_ title: String = "Song", duration: Double = 200) -> TrackKey {
        TrackKey(artist: "Artist", title: title, album: "Album", duration: duration)!
    }

    /// Lets tasks that were just started run until they park or finish.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func queryItems(of request: URLRequest) -> [URLQueryItem] {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    /// Runs one lookup to its end, moving time past the spacing between the steps of the chain.
    func lookup(_ service: LyricsService, _ track: TrackKey) async -> LyricsResult {
        var result: LyricsResult?
        let task = Task { result = await service.lyrics(for: track) }
        for _ in 0..<10 where result == nil {
            await settle { result != nil }
            scheduler.advance(by: LyricsService.minimumSpacing)
        }
        await task.value
        return result!
    }

    /// What each request of the chain asked, as "path name=value ...".
    var calls: [String] {
        client.requests.map { request in
            let url = request.url!
            let items = queryItems(of: request).map { "\($0.name)=\($0.value ?? "")" }
            return ([url.path()] + items).joined(separator: " ")
        }
    }

    // MARK: answers

    @Test func syncedLyricsAreParsed() async {
        client.reply(LrclibReplies.found())
        #expect(await makeService().lyrics(for: key()) == .synced(LrclibReplies.firstTwoLines))
    }

    @Test func plainLyricsWhenThereAreNoTimestamps() async {
        client.reply(LrclibReplies.found(synced: nil, plain: "La la\nLa"))
        #expect(await makeService().lyrics(for: key()) == .plain("La la\nLa"))
    }

    @Test func syncedLyricsWithoutUsableLinesFallBackToPlain() async {
        client.reply(LrclibReplies.found(synced: "[ar:Artist]\nnot lrc", plain: "La la"))
        #expect(await makeService().lyrics(for: key()) == .plain("La la"))
    }

    @Test func instrumentalTracks() async {
        client.reply(LrclibReplies.instrumental)
        #expect(await makeService().lyrics(for: key()) == .instrumental)
    }

    @Test func aFoundTrackWithoutAnyLyricsIsNotFound() async {
        client.reply(LrclibReplies.found(synced: "", plain: nil))
        #expect(await makeService().lyrics(for: key()) == .notFound)
    }

    @Test func status404IsNotFound() async {
        client.reply(LrclibReplies.notFound)
        #expect(await lookup(makeService(), key()) == .notFound)
    }

    @Test func otherFailuresAreUnavailableAndNotRemembered() async {
        let service = makeService()
        client.reply(HTTPReply(status: 500, body: Data("oops".utf8)))
        #expect(await service.lyrics(for: key()).isUnavailable)

        scheduler.advance(by: .seconds(1))
        client.reply(HTTPReply(status: 200, body: Data("<html>captive portal</html>".utf8)))
        #expect(await service.lyrics(for: key()).isUnavailable)

        scheduler.advance(by: .seconds(1))
        client.handler = { _ in throw URLError(.timedOut) }
        #expect(await service.lyrics(for: key()).isUnavailable)

        // None of them was cached, so the next ask goes to the server again.
        scheduler.advance(by: .seconds(1))
        client.reply(LrclibReplies.found())
        #expect(await service.lyrics(for: key()) == .synced(LrclibReplies.firstTwoLines))
        #expect(client.requests.count == 4)
    }

    @Test func unavailableReasonsNeverCarryTheTrack() async {
        let service = makeService()
        let secret = key("Secret Title")
        var reasons: [String] = []
        client.handler = { _ in throw URLError(.notConnectedToInternet, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://lrclib.net/api/get?track_name=Secret%20Title")!]) }
        reasons.append(await service.lyrics(for: secret).reason)
        client.reply(HTTPReply(status: 502, body: Data("Secret Title".utf8)))
        scheduler.advance(by: .seconds(1))
        reasons.append(await service.lyrics(for: secret).reason)
        client.reply(HTTPReply(status: 200, body: Data("Secret Title".utf8)))
        scheduler.advance(by: .seconds(1))
        reasons.append(await service.lyrics(for: secret).reason)
        #expect(reasons.allSatisfy { !$0.isEmpty && !$0.contains("Secret") })
    }

    // MARK: request

    @Test func requestShape() async throws {
        client.reply(LrclibReplies.notFound)
        _ = await lookup(makeService(), key())
        let request = try #require(client.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "MyNotch/1.2 (personal)")
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "lrclib.net")
        #expect(components.path == "/api/get")
        #expect(components.queryItems == [
            URLQueryItem(name: "track_name", value: "Song"),
            URLQueryItem(name: "artist_name", value: "Artist"),
            URLQueryItem(name: "album_name", value: "Album"),
            URLQueryItem(name: "duration", value: "200"),
        ])
    }

    @Test func userAgentWithoutAKnownVersion() async throws {
        client.reply(LrclibReplies.notFound)
        _ = await lookup(makeService(appVersion: nil), key())
        let request = try #require(client.requests.first)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "MyNotch/dev (personal)")
    }

    @Test func valuesAreEscapedSoTheyCannotChangeTheQuery() async throws {
        client.reply(LrclibReplies.notFound)
        let track = TrackKey(artist: "AC/DC & Sons+1", title: "Ünï = ?#", album: "100%", duration: 200)!
        _ = await lookup(makeService(), track)
        let request = try #require(client.requests.first)
        #expect(request.url!.absoluteString.contains("artist_name=AC%2FDC%20%26%20Sons%2B1&"))
        #expect(queryItems(of: request).map(\.value) == ["Ünï = ?#", "AC/DC & Sons+1", "100%", "200"])
    }

    @Test func anEmptyAlbumIsLeftOut() async throws {
        client.reply(LrclibReplies.notFound)
        _ = await lookup(makeService(), TrackKey(artist: "Artist", title: "Song", album: nil, duration: 200)!)
        let request = try #require(client.requests.first)
        #expect(queryItems(of: request).map(\.name) == ["track_name", "artist_name", "duration"])
    }

    // MARK: cache

    @Test func aRepeatedTrackComesFromTheCacheEvenAfterARestart() async {
        client.reply(LrclibReplies.found())
        let first = makeService()
        #expect(await first.lyrics(for: key()) == .synced(LrclibReplies.firstTwoLines))
        // The spacing is over, so a call that wrongly went to the network would show in the count, not hang.
        scheduler.advance(by: .seconds(1))
        #expect(await first.lyrics(for: key()) == .synced(LrclibReplies.firstTwoLines))
        #expect(await makeService().lyrics(for: key()) == .synced(LrclibReplies.firstTwoLines))
        #expect(client.requests.count == 1)
    }

    @Test func plainLyricsAreCachedToo() async {
        client.reply(LrclibReplies.found(synced: nil, plain: "La la"))
        let service = makeService()
        _ = await service.lyrics(for: key())
        scheduler.advance(by: .seconds(1))
        #expect(await service.lyrics(for: key()) == .plain("La la"))
        #expect(client.requests.count == 1)
    }

    @Test func negativeResultsAreCached() async {
        let service = makeService()
        client.reply(LrclibReplies.notFound)
        #expect(await lookup(service, key("Missing")) == .notFound)
        let asked = client.requests.count
        client.reply(LrclibReplies.instrumental)
        scheduler.advance(by: .seconds(1))
        #expect(await service.lyrics(for: key("Humming")) == .instrumental)
        #expect(client.requests.count == asked + 1)

        let restarted = makeService()
        #expect(await restarted.lyrics(for: key("Missing")) == .notFound)
        scheduler.advance(by: .seconds(1))
        #expect(await restarted.lyrics(for: key("Humming")) == .instrumental)
        #expect(client.requests.count == asked + 1)
    }

    @Test func entriesAreJSONFilesNamedByTheTrackHash() async throws {
        client.reply(LrclibReplies.found())
        let track = key()
        _ = await makeService().lyrics(for: track)
        let file = cacheDirectory.appending(path: "\(track.cacheKey).json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
        #expect(object is [String: Any])
        #expect(try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path()).count == 1)
    }

    @Test func tracksThatDifferInDurationAreCachedApart() async {
        let service = makeService()
        client.reply(LrclibReplies.found())
        _ = await service.lyrics(for: key(duration: 200))
        client.reply(LrclibReplies.notFound)
        scheduler.advance(by: .seconds(1))
        #expect(await lookup(service, key(duration: 260)) == .notFound)
        let asked = client.requests.count
        scheduler.advance(by: .seconds(1))
        #expect(await service.lyrics(for: key(duration: 200)) == .synced(LrclibReplies.firstTwoLines))
        #expect(client.requests.count == asked)
    }

    @Test func aDamagedEntryIsFetchedAgainAndReplaced() async throws {
        let track = key()
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let file = cacheDirectory.appending(path: "\(track.cacheKey).json")
        try Data("{ not json".utf8).write(to: file)
        client.reply(LrclibReplies.found())
        #expect(await makeService().lyrics(for: track) == .synced(LrclibReplies.firstTwoLines))
        #expect(await makeService().lyrics(for: track) == .synced(LrclibReplies.firstTwoLines))
        #expect(client.requests.count == 1)
    }

    // MARK: lookup chain

    /// Answers by path (and by whether the album or `q` is asked), so each step of the chain can differ.
    func route(
        getWithAlbum: HTTPReply = LrclibReplies.notFound, get: HTTPReply = LrclibReplies.notFound,
        search: HTTPReply = LrclibReplies.notFound, query: HTTPReply = LrclibReplies.notFound
    ) {
        client.handler = { [self] request in
            let names = queryItems(of: request).map(\.name)
            if request.url!.path() == "/api/get" { return names.contains("album_name") ? getWithAlbum : get }
            return names.contains("q") ? query : search
        }
    }

    @Test func theAlbumIsAskedFirstAndWithoutItOn404() async {
        route(get: LrclibReplies.found())
        let result = await lookup(makeService(), key())
        #expect(result == .synced(LrclibReplies.firstTwoLines))
        #expect(calls == [
            "/api/get track_name=Song artist_name=Artist album_name=Album duration=200",
            "/api/get track_name=Song artist_name=Artist duration=200",
        ])
    }

    @Test func aMatchOnTheAlbumEndsTheChain() async {
        route(getWithAlbum: LrclibReplies.found())
        #expect(await lookup(makeService(), key()) == .synced(LrclibReplies.firstTwoLines))
        #expect(client.requests.count == 1)
    }

    @Test func withoutAnAlbumTheChainStartsWithoutIt() async {
        route(get: LrclibReplies.found())
        let track = TrackKey(artist: "Artist", title: "Song", album: nil, duration: 200)!
        #expect(await lookup(makeService(), track) == .synced(LrclibReplies.firstTwoLines))
        #expect(calls == ["/api/get track_name=Song artist_name=Artist duration=200"])
    }

    @Test func searchIsNextAndTakesTheClosestDuration() async {
        let far = LrclibReplies.entry(duration: 203, synced: "[00:09.00] Far")
        let near = LrclibReplies.entry(duration: 199)
        let off = LrclibReplies.entry(duration: 230, synced: "[00:09.00] Off")
        route(search: LrclibReplies.results([far, off, near]))
        #expect(await lookup(makeService(), key()) == .synced(LrclibReplies.firstTwoLines))
        #expect(calls == [
            "/api/get track_name=Song artist_name=Artist album_name=Album duration=200",
            "/api/get track_name=Song artist_name=Artist duration=200",
            "/api/search track_name=Song artist_name=Artist",
        ])
    }

    @Test func searchPrefersSyncedOverACloserPlainMatch() async {
        let plainOnly = LrclibReplies.entry(duration: 200, synced: nil, plain: "Plain")
        let synced = LrclibReplies.entry(duration: 202)
        route(search: LrclibReplies.results([plainOnly, synced]))
        #expect(await lookup(makeService(), key()) == .synced(LrclibReplies.firstTwoLines))
    }

    @Test func searchFallsBackToPlainLyricsWithinThreeSeconds() async {
        let far = LrclibReplies.entry(duration: 240, synced: "[00:09.00] Far")
        let farther = LrclibReplies.entry(duration: 203, synced: nil, plain: "Third")
        let nearer = LrclibReplies.entry(duration: 201, synced: nil, plain: "Nearer")
        route(search: LrclibReplies.results([far, farther, nearer]))
        #expect(await lookup(makeService(), key()) == .plain("Nearer"))
    }

    @Test func aDurationOfExactlyThreeSecondsOffCountsAndFourDoesNot() async {
        route(search: LrclibReplies.results([LrclibReplies.entry(duration: 197)]))
        #expect(await lookup(makeService(), key()) == .synced(LrclibReplies.firstTwoLines))
        route(search: LrclibReplies.results([LrclibReplies.entry(duration: 204)]))
        #expect(await lookup(makeService(), key("Other")) == .notFound)
    }

    @Test func theFreeTextSearchIsTheLastStep() async {
        let far = LrclibReplies.entry(duration: 230, synced: "[00:09.00] Far")
        route(search: LrclibReplies.results([]), query: LrclibReplies.results([far, LrclibReplies.entry(duration: 200)]))
        #expect(await lookup(makeService(), key()) == .synced(LrclibReplies.firstTwoLines))
        #expect(calls.count == 4)
        #expect(calls.last == "/api/search q=Artist Song")
    }

    @Test func anUnusableSearchAnswerMovesOnToTheFreeTextSearch() async {
        let noLyrics = LrclibReplies.entry(duration: 200, synced: nil, plain: nil)
        route(search: LrclibReplies.results([noLyrics]), query: LrclibReplies.results([LrclibReplies.entry(duration: 201, synced: nil, plain: "Free")]))
        #expect(await lookup(makeService(), key()) == .plain("Free"))
    }

    @Test func whenNothingMatchesTheTrackIsNotFoundAndRemembered() async {
        route(search: LrclibReplies.results([]), query: LrclibReplies.results([]))
        let service = makeService()
        #expect(await lookup(service, key()) == .notFound)
        #expect(client.requests.count == 4)
        scheduler.advance(by: .seconds(1))
        #expect(await service.lyrics(for: key()) == .notFound)
        #expect(client.requests.count == 4)
    }

    @Test func everyStepWaitsOutTheSpacing() async {
        route(search: LrclibReplies.results([]), query: LrclibReplies.results([]))
        let service = makeService()
        var result: LyricsResult?
        let task = Task { result = await service.lyrics(for: key()) }
        await settle { client.requests.count == 2 }
        #expect(client.requests.count == 1)
        for step in 2...4 {
            scheduler.advance(by: .milliseconds(299))
            await settle { client.requests.count == step }
            #expect(client.requests.count == step - 1)
            scheduler.advance(by: .milliseconds(1))
            await settle { client.requests.count == step }
            #expect(client.requests.count == step)
        }
        await settle { result != nil }
        await task.value
        #expect(result == .notFound)
    }

    /// Answers 404 to every request of the chain before the one numbered `step` (from 0), which gets `reply`.
    func answer404UntilStep(_ step: Int, with reply: HTTPReply) {
        var index = 0
        client.handler = { _ in
            defer { index += 1 }
            return index == step ? reply : LrclibReplies.notFound
        }
    }

    @Test(arguments: [429, 503], [0, 1, 2, 3])
    func aRateLimitAtAnyStepEndsTheChainAndStartsTheCooldown(status: Int, step: Int) async {
        answer404UntilStep(step, with: LrclibReplies.busy(status: status, retryAfter: "30"))
        let service = makeService()
        #expect(await lookup(service, key()).isUnavailable)
        #expect(client.requests.count == step + 1)
        #expect(service.isCoolingDown)
        // Nothing goes out while lrclib asks for quiet, and the failed track is not remembered.
        #expect(await service.lyrics(for: key("Next")).isUnavailable)
        #expect(client.requests.count == step + 1)
        #expect(!FileManager.default.fileExists(atPath: cacheDirectory.path()))
        scheduler.advance(by: .seconds(30))
        route(getWithAlbum: LrclibReplies.found())
        #expect(await lookup(service, key()) == .synced(LrclibReplies.firstTwoLines))
    }

    @Test func aFailureInTheMiddleEndsTheChainWithoutCaching() async {
        route(get: HTTPReply(status: 500))
        let service = makeService()
        #expect(await lookup(service, key()).isUnavailable)
        #expect(client.requests.count == 2)
        #expect(!FileManager.default.fileExists(atPath: cacheDirectory.path()))
    }

    @Test func shuttingDownBetweenTwoStepsSendsNothingMore() async {
        route()
        let service = makeService()
        let task = Task { await service.lyrics(for: key()) }
        await settle { scheduler.pendingCount == 1 }
        #expect(client.requests.count == 1)
        service.shutDown()
        #expect(await task.value.isUnavailable)
        #expect(client.requests.count == 1)
    }

    @Test func cancellingBetweenTwoStepsSendsNothingMore() async {
        route()
        let service = makeService()
        let task = Task { await service.lyrics(for: key()) }
        await settle { scheduler.pendingCount == 1 }
        task.cancel()
        scheduler.advance(by: LyricsService.minimumSpacing)
        #expect(await task.value.reason == "Lookup cancelled")
        #expect(client.requests.count == 1)
        #expect(!FileManager.default.fileExists(atPath: cacheDirectory.path()))
    }

    @Test func aLookupCancelledWhileARequestIsOutDoesNotWaitForTheNextStep() async {
        let gate = Gate()
        client.handler = { [gate] _ in
            await gate.wait()
            return LrclibReplies.notFound
        }
        let service = makeService()
        var result: LyricsResult?
        let task = Task { result = await service.lyrics(for: key()) }
        await settle { gate.isWaiting }
        task.cancel()
        gate.open()
        await settle { result != nil }
        #expect(result?.reason == "Lookup cancelled")
        // Only so that a regression ends in a failed expectation rather than a call that waits for ever.
        scheduler.advance(by: .seconds(1))
        await task.value
        #expect(client.requests.count == 1)
    }

    @Test func aNotFoundAnswerIsAskedAgainAfterAWeek() async throws {
        route()
        let service = makeService()
        #expect(await lookup(service, key()) == .notFound)
        let asked = client.requests.count
        scheduler.advance(by: .seconds(1))
        #expect(await service.lyrics(for: key()) == .notFound)
        #expect(client.requests.count == asked)

        let file = cacheDirectory.appending(path: "\(key().cacheKey).json")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-8 * 86_400)], ofItemAtPath: file.path())
        route(getWithAlbum: LrclibReplies.found())
        #expect(await lookup(service, key()) == .synced(LrclibReplies.firstTwoLines))
        #expect(client.requests.count == asked + 1)
    }

    @Test func aBrowserTrackIsAskedByItsCleanedTitleAtEveryStep() async throws {
        route(search: LrclibReplies.results([]), query: LrclibReplies.results([]))
        let track = try #require(TrackKey(
            artist: "Rick Astley", title: "Rick Astley - Never Gonna Give You Up (Official Video)", album: nil, duration: 213,
            isFromBrowser: true
        ))
        #expect(await lookup(makeService(), track) == .notFound)
        #expect(calls == [
            "/api/get track_name=Never Gonna Give You Up artist_name=Rick Astley duration=213",
            "/api/search track_name=Never Gonna Give You Up artist_name=Rick Astley",
            "/api/search q=Rick Astley Never Gonna Give You Up",
        ])
        // The cache still goes by what the player reported.
        #expect(FileManager.default.fileExists(atPath: cacheDirectory.appending(path: "\(track.cacheKey).json").path()))
    }

    // MARK: long tracks

    @Test(arguments: [("Song", 901.0), ("Best Mix 2024", 200), ("Lofi 1 hour", 200), ("Nhạc 1 giờ", 200), ("Nonstop Remix", 200), ("Tuyển tập nhạc", 200), ("Playlist", 200)])
    func longTracksAndMixesNeverReachLrclib(title: String, duration: Double) async {
        client.reply(LrclibReplies.found())
        let service = makeService()
        let track = TrackKey(artist: "Artist", title: title, album: "Album", duration: duration)!
        #expect(await service.lyrics(for: track) == .notFound)
        #expect(client.requests.isEmpty)
        // Not cached, and it did not take the turn: the next track goes out at once.
        #expect(!FileManager.default.fileExists(atPath: cacheDirectory.path()))
        #expect(await service.lyrics(for: key()) == .synced(LrclibReplies.firstTwoLines))
    }

    // MARK: rate limits

    @Test(arguments: [(429, "120", 120), (503, "7", 7), (429, "0", 1), (429, "100000", 3600), (503, "soon", 60), (429, nil, 60)] as [(Int, String?, Int)])
    func rateLimitsAreWaitedOutWithoutRetrying(status: Int, retryAfter: String?, seconds: Int) async {
        let service = makeService()
        client.reply(LrclibReplies.busy(status: status, retryAfter: retryAfter))
        #expect(await service.lyrics(for: key("A")).isUnavailable)
        #expect(client.requests.count == 1)

        // Nothing is sent while the cooldown runs, however many tracks come.
        client.reply(LrclibReplies.found())
        scheduler.advance(by: .seconds(seconds) - .milliseconds(1))
        #expect(await service.lyrics(for: key("B")).isUnavailable)
        #expect(await service.lyrics(for: key("C")).isUnavailable)
        #expect(client.requests.count == 1)

        scheduler.advance(by: .milliseconds(1))
        #expect(await service.lyrics(for: key("B")) == .synced(LrclibReplies.firstTwoLines))
        #expect(client.requests.count == 2)
    }

    @Test func afterCooldownRunsWhenTheCooldownEnds() async {
        let service = makeService()
        var calls = 0
        #expect(!service.isCoolingDown)
        client.reply(LrclibReplies.busy(retryAfter: "10"))
        _ = await service.lyrics(for: key("A"))
        #expect(service.isCoolingDown)
        service.afterCooldown { calls += 1 }
        scheduler.advance(by: .seconds(10) - .milliseconds(1))
        #expect(calls == 0)
        scheduler.advance(by: .milliseconds(1))
        #expect(calls == 1)
        #expect(!service.isCoolingDown)
    }

    @Test func aSecondRateLimitStartsAnotherCooldown() async {
        let service = makeService()
        client.reply(LrclibReplies.busy(retryAfter: "10"))
        _ = await service.lyrics(for: key("A"))
        scheduler.advance(by: .seconds(10))
        client.reply(LrclibReplies.busy(retryAfter: "30"))
        _ = await service.lyrics(for: key("B"))
        scheduler.advance(by: .seconds(29))
        _ = await service.lyrics(for: key("C"))
        #expect(client.requests.count == 2)
        scheduler.advance(by: .seconds(1))
        _ = await service.lyrics(for: key("C"))
        #expect(client.requests.count == 3)
    }

    @Test func cachedTracksStillAnswerWhileCoolingDown() async {
        let service = makeService()
        client.reply(LrclibReplies.found())
        _ = await service.lyrics(for: key("Cached"))
        scheduler.advance(by: .seconds(1))
        client.reply(LrclibReplies.busy())
        _ = await service.lyrics(for: key("Other"))
        scheduler.advance(by: .seconds(1))
        #expect(await service.lyrics(for: key("Cached")) == .synced(LrclibReplies.firstTwoLines))
        #expect(client.requests.count == 2)
    }

    // MARK: sequencing

    @Test func requestsAreSpacedAtLeast300Milliseconds() async {
        let service = makeService()
        client.reply(LrclibReplies.found())
        // The first one goes out at once.
        _ = await service.lyrics(for: key("A"))
        #expect(client.requests.count == 1)

        let second = Task { await service.lyrics(for: key("B")) }
        await settle { service.queuedCount == 1 }
        #expect(service.queuedCount == 1)
        scheduler.advance(by: .milliseconds(299))
        await settle { client.requests.count == 2 }
        #expect(client.requests.count == 1)

        scheduler.advance(by: .milliseconds(1))
        #expect(await second.value == .synced(LrclibReplies.firstTwoLines))
        #expect(client.requests.count == 2)
    }

    @Test func theGapCountsFromTheAnswerNotFromTheRequest() async {
        let service = makeService()
        let gate = Gate()
        var isFirst = true
        client.handler = { [gate] _ in
            if isFirst {
                isFirst = false
                await gate.wait()
            }
            return LrclibReplies.found()
        }
        let first = Task { await service.lyrics(for: key("A")) }
        await settle { gate.isWaiting }
        let second = Task { await service.lyrics(for: key("B")) }
        await settle { service.queuedCount == 1 }

        // A slow answer: time passes while the request is out, and none of it counts as spacing.
        scheduler.advance(by: .seconds(5))
        gate.open()
        _ = await first.value
        scheduler.advance(by: .milliseconds(299))
        await settle { client.requests.count == 2 }
        #expect(client.requests.count == 1)
        scheduler.advance(by: .milliseconds(1))
        _ = await second.value
        #expect(client.requests.count == 2)
    }

    @Test func requestsNeverOverlapAndKeepTheirOrder() async {
        let service = makeService()
        let gate = Gate()
        client.handler = { [gate] _ in
            await gate.wait()
            return LrclibReplies.found()
        }
        let first = Task { await service.lyrics(for: key("A")) }
        let second = Task { await service.lyrics(for: key("B")) }
        let third = Task { await service.lyrics(for: key("C")) }
        await settle { gate.isWaiting && service.queuedCount == 2 }
        #expect(client.requests.count == 1)
        #expect(service.queuedCount == 2)

        gate.open()
        _ = await first.value
        scheduler.advance(by: .milliseconds(300))
        await settle { gate.isWaiting }
        #expect(client.requests.count == 2)
        gate.open()
        _ = await second.value
        scheduler.advance(by: .milliseconds(300))
        await settle { gate.isWaiting }
        gate.open()
        _ = await third.value

        #expect(client.maxActiveCount == 1)
        #expect(client.requests.compactMap { queryItems(of: $0).first?.value } == ["A", "B", "C"])
    }

    @Test func cachedAnswersDoNotWaitForTheSpacing() async {
        let service = makeService()
        client.reply(LrclibReplies.found())
        _ = await service.lyrics(for: key("A"))
        // The spacing timer is still pending, yet a cached track answers without queueing for it.
        let again = Task { await service.lyrics(for: key("A")) }
        await settle { service.queuedCount > 0 }
        #expect(service.queuedCount == 0)
        scheduler.advance(by: .seconds(1))
        #expect(await again.value == .synced(LrclibReplies.firstTwoLines))
        #expect(client.requests.count == 1)
    }

    @Test func aCancelledCallWaitingItsTurnSendsNothingAndPassesTheTurnOn() async {
        let service = makeService()
        client.reply(LrclibReplies.found())
        _ = await service.lyrics(for: key("A"))
        let cancelled = Task { await service.lyrics(for: key("B")) }
        let next = Task { await service.lyrics(for: key("C")) }
        await settle { service.queuedCount == 2 }
        cancelled.cancel()

        scheduler.advance(by: .milliseconds(300))
        #expect(await cancelled.value.isUnavailable)
        // C follows B at once: B sent nothing, so there is nothing to space from.
        await settle { client.requests.count == 2 }
        #expect(client.requests.compactMap { queryItems(of: $0).first?.value } == ["A", "C"])
        // Only so that a regression ends in a failed expectation rather than a call that waits for ever.
        scheduler.advance(by: .seconds(1))
        #expect(await next.value == .synced(LrclibReplies.firstTwoLines))
    }

    @Test func cancellingLeavesTheQueueAtOnce() async {
        let service = makeService()
        client.reply(LrclibReplies.found())
        _ = await service.lyrics(for: key("A"))
        let cancelled = Task { await service.lyrics(for: key("B")) }
        await settle { service.queuedCount == 1 }
        cancelled.cancel()
        // No time passes: the call is gone without waiting for its turn, and says it was cancelled.
        #expect(await cancelled.value.reason == "Lookup cancelled")
        #expect(service.queuedCount == 0)
        #expect(client.requests.count == 1)
    }

    @Test func shuttingDownReleasesWaitingCallsAndStopsFurtherRequests() async {
        let service = makeService()
        client.reply(LrclibReplies.found())
        _ = await service.lyrics(for: key("A"))
        let waiting = Task { await service.lyrics(for: key("B")) }
        await settle { service.queuedCount == 1 }

        service.shutDown()
        #expect(await waiting.value.isUnavailable)
        #expect(await service.lyrics(for: key("D")).isUnavailable)
        #expect(client.requests.count == 1)
        #expect(scheduler.pendingCount == 0)
    }
}

extension LyricsResult {
    var isUnavailable: Bool {
        if case .unavailable = self { true } else { false }
    }

    /// The reason of `.unavailable`; "" for every other result.
    var reason: String {
        if case .unavailable(let reason) = self { reason } else { "" }
    }
}
