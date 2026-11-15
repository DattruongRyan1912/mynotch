import Foundation
import Testing
@testable import ClipboardModule

/// The fetcher with a fake transport: every way a page might send MyNotch somewhere it must not go, and what it keeps when it does not.
/// Nonisolated, like the code it tests: this suite is about time (a request that never answers, a total that runs out), and a test on the
/// main actor would be kept waiting by whatever else is holding it, such as the glass tests that draw views for seconds.
@Suite nonisolated struct ClipboardLinkFetcherTests {
    let transport = FakeLinkTransport()
    let page = "https://www.example.com/post"

    /// With limits that never run out unless a test says so.
    func fetcher(request: Duration = .seconds(5), total: Duration = .seconds(20), sleep: @escaping ClipboardLinkFetcher.Sleep = LinkTimers.never) -> ClipboardLinkFetcher {
        ClipboardLinkFetcher(transport: transport, requestTimeout: request, totalTimeout: total, sleep: sleep)
    }

    func fetch(_ url: String) async throws -> ClipboardLinkFetcher.Outcome {
        await fetcher().fetch(try #require(URL(string: url)))
    }

    func html(title: String = "Tiêu đề", head: String = "") -> ClipboardLinkResponse {
        .html("<html><head><title>\(title)</title>\(head)</head><body>nội dung</body></html>")
    }

    // MARK: What it keeps

    @Test func theTitleAndTheOpenGraphPicture() async throws {
        transport.set(page, html(title: "Bài &amp; viết", head: "<meta property=\"og:image\" content=\"https://cdn.example.com/p.png\">"))
        transport.set("https://cdn.example.com/p.png", .picture(TestPictures.png(width: 800, height: 400)))
        guard case .read(let title, let image?) = try await fetch(page) else { Issue.record("expected a read"); return }
        #expect(title == "Bài & viết")
        #expect(try #require(TestPictures.size(of: image)).width == 256)
        #expect(transport.requestedURLs == [page, "https://cdn.example.com/p.png"])
    }

    @Test func theCapsAreTheOnesTheBriefSets() async throws {
        transport.set(page, html(head: "<meta property=\"og:image\" content=\"https://cdn.example.com/p.png\">"))
        transport.set("https://cdn.example.com/p.png", .picture(TestPictures.png(width: 10, height: 10)))
        _ = try await fetch(page)
        let requests = transport.requests
        #expect(requests.map(\.kind) == [.page, .image])
        #expect(requests.map(\.byteLimit) == [512 * 1024, 2 * 1024 * 1024])
        #expect(ClipboardLinkFetcher.requestTimeout == .seconds(5))
        #expect(ClipboardLinkFetcher.redirectLimit == 3)
        #expect(ClipboardLinkImage.maxPixelSize == 256)
    }

    @Test func theFaviconIsTheFallbackWhenThereIsNoOpenGraphPicture() async throws {
        transport.set(page, html(head: "<link rel=\"icon\" href=\"/static/icon.png\">"))
        transport.set("https://www.example.com/static/icon.png", .picture(TestPictures.png(width: 64, height: 64)))
        guard case .read(_, let image?) = try await fetch(page) else { Issue.record("expected a picture"); return }
        #expect(try #require(TestPictures.size(of: image)).width == 64)
        #expect(transport.requestedURLs == [page, "https://www.example.com/static/icon.png"])
    }

    @Test func slashFaviconIcoIsTheLastResort() async throws {
        transport.set(page, html())
        transport.set("https://www.example.com/favicon.ico", .picture(TestPictures.png(width: 32, height: 32), type: "image/x-icon"))
        guard case .read(_, let image?) = try await fetch(page) else { Issue.record("expected a picture"); return }
        #expect(try #require(TestPictures.size(of: image)).width == 32)
        #expect(transport.requestedURLs.last == "https://www.example.com/favicon.ico")
    }

    @Test func aBrokenOpenGraphPictureFallsBackToTheFavicon() async throws {
        transport.set(page, html(head: "<meta property=\"og:image\" content=\"https://cdn.example.com/p.png\"><link rel=icon href=/i.png>"))
        transport.set("https://cdn.example.com/p.png", .status(404))
        transport.set("https://www.example.com/i.png", .picture(TestPictures.png(width: 48, height: 48)))
        guard case .read(_, let image?) = try await fetch(page) else { Issue.record("expected a picture"); return }
        #expect(try #require(TestPictures.size(of: image)).width == 48)
    }

    @Test func aPictureThatIsNotOneIsNotUsed() async throws {
        transport.set(page, html(head: "<meta property=\"og:image\" content=\"https://cdn.example.com/p.png\">"))
        let png = TestPictures.png(width: 40, height: 40)
        // The wrong kind of answer, an error, an empty body, text that is not a picture, a type that is not a picture's.
        for answer: ClipboardLinkResponse in [
            .html("<html>login</html>"), .status(500), .picture(Data()), .picture(Data("not a picture".utf8)),
            .picture(png, type: "text/html"), .picture(png, type: nil), .picture(png, type: "image/svg+xml"),
        ] {
            transport.set("https://cdn.example.com/p.png", answer)
            guard case .read(let title, let image) = try await fetch(page) else { Issue.record("expected a read"); return }
            #expect(title == "Tiêu đề")
            #expect(image == nil)
        }
    }

    /// The kind of a picture is what its bytes are, not what the server's header says: a TIFF sent as `image/png` is not used, and the
    /// next address gets its turn.
    @Test func aPictureOfAnotherKindIsNotUsedWhateverItsHeaderSays() async throws {
        transport.set(page, html(head: "<meta property=\"og:image\" content=\"https://cdn.example.com/p\"><link rel=icon href=/i.png>"))
        transport.set("https://www.example.com/i.png", .picture(TestPictures.png(width: 48, height: 48)))
        for other in [TestPictures.encoded([(64, 64)], as: .tiff), TestPictures.webp] {
            transport.set("https://cdn.example.com/p", .picture(other, type: "image/png"))
            guard case .read(_, let image?) = try await fetch(page) else { Issue.record("expected the icon"); return }
            // The icon, not the og:image.
            #expect(try #require(TestPictures.size(of: image)).width == 48)
        }
        transport.set(page, html(head: "<meta property=\"og:image\" content=\"https://cdn.example.com/p\">"))
        transport.set("https://www.example.com/favicon.ico", .status(404))
        guard case .read(_, let image) = try await fetch(page) else { Issue.record("expected a read"); return }
        #expect(image == nil)
    }

    @Test func aPictureOverTheLimitIsRefusedNotUsedInPart() async throws {
        transport.set(page, html(head: "<meta property=\"og:image\" content=\"https://cdn.example.com/p.png\">"))
        // Valid bytes, but the transport had more: they are a part of a picture and nothing is made of them.
        transport.set("https://cdn.example.com/p.png", .picture(TestPictures.png(width: 100, height: 100), cut: true))
        guard case .read(_, let image) = try await fetch(page) else { Issue.record("expected a read"); return }
        #expect(image == nil)
    }

    @Test func aPageCutAtTheLimitIsStillRead() async throws {
        transport.set(page, .html("<html><head><title>Đủ rồi</title></head><body>…", cut: true))
        guard case .read(let title, _) = try await fetch(page) else { Issue.record("expected a read"); return }
        #expect(title == "Đủ rồi")
    }

    @Test func atMostThreePicturesAreTried() async throws {
        transport.set(page, html(head: """
        <meta property="og:image" content="https://cdn.example.com/a.png">
        <link rel="apple-touch-icon" href="/b.png"><link rel="icon" href="/c.png"><link rel="icon" href="/d.png"><link rel="icon" href="/e.png">
        """))
        _ = try await fetch(page)
        #expect(transport.requests.filter { $0.kind == .image }.count == ClipboardLinkFetcher.pictureAttempts)
        #expect(transport.requestedURLs.dropFirst() == ["https://cdn.example.com/a.png", "https://www.example.com/b.png", "https://www.example.com/c.png"])
    }

    @Test func noPictureStillGivesTheTitle() async throws {
        transport.set(page, html())
        guard case .read(let title, let image) = try await fetch(page) else { Issue.record("expected a read"); return }
        #expect(title == "Tiêu đề")
        #expect(image == nil)
    }

    @Test func aPageThatIsNotHTMLHasNothingToRead() async throws {
        transport.set(page, .html("%PDF-1.7 <title>fake</title>", type: "application/pdf"))
        #expect(try await fetch(page) == .read(title: nil, image: nil))
        #expect(transport.requests.count == 1)
        // No header at all is taken for a page.
        transport.set("https://www.example.com/bare", .html("<head><title>Không header</title></head>", type: nil))
        guard case .read(let title, _) = try await fetch("https://www.example.com/bare") else { Issue.record("expected a read"); return }
        #expect(title == "Không header")
    }

    @Test(arguments: [301, 400, 401, 403, 404, 410, 429, 500, 503])
    func anErrorStatusIsAFailure(_ status: Int) async throws {
        transport.set(page, .html("<head><title>Lỗi</title></head>", status: status))
        #expect(try await fetch(page) == .failed)
    }

    // MARK: Addresses it will not open

    @Test(arguments: ClipboardLinkGuardTests.refused)
    func aRefusedAddressIsNeverOpenedOrLookedUp(_ address: String) async throws {
        let url = try #require(URL(string: address), "\(address) is not an address")
        let outcome = await fetcher().fetch(url)
        #expect(outcome == .failed)
        #expect(transport.requests.isEmpty, "\(address)")
        #expect(transport.lookups.isEmpty, "\(address)")
    }

    @Test(arguments: [
        "http://192.168.1.1/logo.png", "http://169.254.169.254/latest/meta-data/", "http://localhost/x.png", "http://127.0.0.1:8080/x.png",
        "http://[::1]/x.png", "http://router/x.png", "http://nas.local/x.png", "file:///etc/passwd", "https://user:pw@cdn.example.com/x.png",
        "http://2130706433/x.png",
    ])
    func aPageCannotPointItsPictureAtTheUsersNetwork(_ target: String) async throws {
        transport.set(page, html(head: "<meta property=\"og:image\" content=\"\(target)\"><link rel=icon href=\"\(target)\">"))
        transport.set("https://www.example.com/favicon.ico", .picture(TestPictures.png(width: 20, height: 20)))
        guard case .read(_, let image) = try await fetch(page) else { Issue.record("expected a read"); return }
        // The favicon at the page's own host is used instead; the private address never saw a request or a lookup.
        #expect(image != nil)
        #expect(!transport.requestedURLs.contains(target), "\(target)")
        #expect(transport.requestedURLs.allSatisfy { $0.hasPrefix("https://www.example.com/") })
    }

    // MARK: Names that lead to private addresses

    @Test func aNameThatResolvesToAPrivateAddressIsNotOpened() async throws {
        for address in ["127.0.0.1", "10.0.0.5", "192.168.0.10", "169.254.169.254", "::1", "fe80::1%en0", "fd00::1"] {
            transport.setHost("evil.example.org", resolvesTo: [address])
            #expect(try await fetch("https://evil.example.org/") == .failed, "\(address)")
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func oneBadAddressAmongGoodOnesIsEnough() async throws {
        transport.setHost("mixed.example.org", resolvesTo: ["93.184.216.34", "10.1.1.1"])
        #expect(try await fetch("https://mixed.example.org/") == .failed)
        #expect(transport.requests.isEmpty)
    }

    @Test func aNameThatDoesNotResolveIsNotOpened() async throws {
        transport.setHost("nowhere.example.org", resolvesTo: [])
        #expect(try await fetch("https://nowhere.example.org/") == .failed)
        #expect(transport.requests.isEmpty)
        #expect(transport.lookups == ["nowhere.example.org"])
    }

    @Test func anAddressNeedsNoLookup() async throws {
        transport.set("https://93.184.216.34/", html())
        _ = try await fetch("https://93.184.216.34/")
        #expect(transport.lookups.isEmpty)
        #expect(transport.requests.count == 2)
    }

    @Test func thePicturesHostIsLookedUpToo() async throws {
        transport.set(page, html(head: "<meta property=\"og:image\" content=\"https://cdn.rebind.example.org/p.png\">"))
        transport.setHost("cdn.rebind.example.org", resolvesTo: ["192.168.1.9"])
        transport.set("https://www.example.com/favicon.ico", .picture(TestPictures.png(width: 20, height: 20)))
        _ = try await fetch(page)
        #expect(!transport.requestedURLs.contains("https://cdn.rebind.example.org/p.png"))
        #expect(transport.lookups.contains("cdn.rebind.example.org"))
    }

    // MARK: Redirects

    @Test func aRedirectIsFollowedAndRelativeAddressesAreAgainstTheNewPlace() async throws {
        transport.set(page, .redirect(to: "https://example.net/moved"))
        transport.set("https://example.net/moved", html(title: "Chỗ mới", head: "<link rel=icon href=\"icon.png\">"))
        transport.set("https://example.net/icon.png", .picture(TestPictures.png(width: 30, height: 30)))
        guard case .read(let title, let image) = try await fetch(page) else { Issue.record("expected a read"); return }
        #expect(title == "Chỗ mới")
        #expect(image != nil)
        #expect(transport.requestedURLs == [page, "https://example.net/moved", "https://example.net/icon.png"])
    }

    @Test(arguments: [301, 302, 303, 307, 308])
    func everyKindOfRedirectIsFollowed(_ status: Int) async throws {
        transport.set(page, .redirect(to: "/next", status: status))
        transport.set("https://www.example.com/next", html(title: "Đến nơi"))
        guard case .read(let title, _) = try await fetch(page) else { Issue.record("expected a read"); return }
        #expect(title == "Đến nơi")
    }

    @Test func threeRedirectsAreFollowedAndAFourthIsNot() async throws {
        transport.set("https://a.example.org/", .redirect(to: "https://b.example.org/"))
        transport.set("https://b.example.org/", .redirect(to: "https://c.example.org/"))
        transport.set("https://c.example.org/", .redirect(to: "https://d.example.org/"))
        transport.set("https://d.example.org/", html(title: "Cuối"))
        guard case .read(let title, _) = try await fetch("https://a.example.org/") else { Issue.record("expected a read"); return }
        #expect(title == "Cuối")

        transport.set("https://d.example.org/", .redirect(to: "https://e.example.org/"))
        transport.set("https://e.example.org/", html(title: "Quá xa"))
        #expect(try await fetch("https://a.example.org/") == .failed)
        #expect(!transport.requestedURLs.contains("https://e.example.org/"))
    }

    @Test func aRedirectLoopEnds() async throws {
        transport.set("https://loop.example.org/", .redirect(to: "https://loop.example.org/"))
        #expect(try await fetch("https://loop.example.org/") == .failed)
        #expect(transport.requests.count == ClipboardLinkFetcher.redirectLimit + 1)
    }

    @Test(arguments: [
        "http://127.0.0.1/admin", "http://localhost:8080/", "http://10.0.0.1/", "http://192.168.1.1/", "http://169.254.169.254/latest/",
        "http://[::1]/", "http://[fd00::1]/", "http://router/", "http://printer.local/", "file:///etc/passwd", "ftp://example.com/x",
        "https://user:pass@example.org/", "http://2130706433/", "http://[::ffff:7f00:1]/",
    ])
    func aRedirectToAForbiddenPlaceIsRefused(_ target: String) async throws {
        transport.set(page, .redirect(to: target))
        transport.set(target, html(title: "Không được thấy"))
        #expect(try await fetch(page) == .failed)
        #expect(transport.requestedURLs == [page], "\(target)")
    }

    @Test func aRedirectToANameThatResolvesPrivatelyIsRefused() async throws {
        transport.set(page, .redirect(to: "https://internal-app.example.org/"))
        transport.setHost("internal-app.example.org", resolvesTo: ["10.20.30.40"])
        transport.set("https://internal-app.example.org/", html())
        #expect(try await fetch(page) == .failed)
        #expect(transport.requestedURLs == [page])
    }

    @Test func aRedirectWithNowhereToGoIsAFailure() async throws {
        transport.set(page, .redirect(to: nil))
        #expect(try await fetch(page) == .failed)
        transport.set(page, .redirect(to: "   "))
        #expect(try await fetch(page) == .failed)
    }

    @Test func aPicturesRedirectIsCheckedToo() async throws {
        transport.set(page, html(head: "<meta property=\"og:image\" content=\"https://cdn.example.com/p.png\">"))
        transport.set("https://cdn.example.com/p.png", .redirect(to: "http://192.168.1.1/p.png"))
        transport.set("https://www.example.com/favicon.ico", .picture(TestPictures.png(width: 20, height: 20)))
        guard case .read(_, let image) = try await fetch(page) else { Issue.record("expected a read"); return }
        #expect(image != nil)
        #expect(!transport.requestedURLs.contains("http://192.168.1.1/p.png"))
    }

    // MARK: Time

    /// What a time limit is for: work that never ends. The limit runs out once the work has begun to hang, whatever the machine is doing.
    @Test(.timeLimit(.minutes(5))) func aRequestThatNeverAnswersIsGivenUpOn() async throws {
        let hanging = LinkFlag()
        transport.setHandler { _ in
            hanging.raise()
            try await Task.sleep(for: .seconds(3600))
            return .html("")
        }
        let request = Duration.milliseconds(5)
        let fetcher = fetcher(request: request, sleep: LinkTimers.runningOut([request], after: hanging))
        let outcome = await fetcher.fetch(try #require(URL(string: page)))
        #expect(outcome == .failed)
        #expect(transport.requests.count == 1)
    }

    @Test(.timeLimit(.minutes(5))) func aLookupThatNeverAnswersIsGivenUpOn() async throws {
        let hanging = LinkFlag()
        transport.setLookupHandler { _ in
            hanging.raise()
            try? await Task.sleep(for: .seconds(3600))
            return []
        }
        let request = Duration.milliseconds(5)
        let fetcher = fetcher(request: request, sleep: LinkTimers.runningOut([request], after: hanging))
        let outcome = await fetcher.fetch(try #require(URL(string: page)))
        #expect(outcome == .failed)
        #expect(transport.requests.isEmpty)
    }

    /// Every request answers, none runs out of time, and the whole still does: a server that answers each just in time would never reach
    /// the limit of any one of them.
    @Test(.timeLimit(.minutes(5))) func theWholeHasATimeLimitToo() async throws {
        let hanging = LinkFlag()
        transport.setHandler { request in
            if request.kind == .page { return .html("<head><title>Đã có tiêu đề</title><link rel=icon href=/a.png><link rel=icon href=/b.png></head>") }
            // The first picture is the one the whole ends in.
            hanging.raise()
            try await Task.sleep(for: .seconds(3600))
            return .status(404)
        }
        let total = Duration.milliseconds(7)
        let fetcher = fetcher(request: .seconds(30), total: total, sleep: LinkTimers.runningOut([total], after: hanging))
        let outcome = await fetcher.fetch(try #require(URL(string: page)))
        #expect(outcome == .failed)
    }

    @Test(.timeLimit(.minutes(5))) func aCancelledFetchEndsAsAFailure() async throws {
        let started = LinkFlag()
        transport.setHandler { _ in
            started.raise()
            try await Task.sleep(for: .seconds(3600))
            return .html("")
        }
        let fetcher = fetcher()
        let url = try #require(URL(string: page))
        let task = Task { await fetcher.fetch(url) }
        while !started.isRaised { try await Task.sleep(for: .milliseconds(1)) }
        task.cancel()
        let outcome = await task.value
        #expect(outcome == .failed)
    }

    @Test func theDefaultLimitsAreTheBriefsAndTheyRunOutOnARealClock() async throws {
        let fetcher = ClipboardLinkFetcher(transport: transport)
        #expect(fetcher.requestTimeout == .seconds(5))
        #expect(fetcher.totalTimeout == .seconds(20))
        // The real clock ends a wait: a limit of a few milliseconds beside work that finishes first.
        let value = try await fetcher.within(.seconds(30)) { 7 }
        #expect(value == 7)
        await #expect(throws: ClipboardLinkFetcher.Failure.timedOut) {
            try await fetcher.within(.milliseconds(1)) {
                try await Task.sleep(for: .seconds(3600))
                return 1
            }
        }
    }

    @Test func aTransportThatThrowsIsAFailure() async throws {
        transport.setHandler { _ in throw URLError(.cannotConnectToHost) }
        #expect(try await fetch(page) == .failed)
    }
}
