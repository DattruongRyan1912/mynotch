import Foundation
import Testing
@testable import ClipboardModule

/// Links that are used once or carry a credential are never requested; ordinary articles, products and videos still are.
@Suite nonisolated struct ClipboardLinkSingleUseTests {
    /// The shapes the review found that the secret filter lets through, then more of each kind.
    static let singleUse = [
        // The review's examples.
        "https://example.com/auth/magic/0123456789abcdef0123456789abcdef",
        "https://example.com/verify-email?code=123456",
        "https://example.com/unsubscribe/abc123def456ghi789",
        "https://example.com/invite/3b18e512-dba7-4e4c-8300-dd08aeb37f8e",
        "https://example.com/login/callback?code=4/0AX4XfWh-abc&state=xyz",
        "https://storage.googleapis.com/bucket/report.pdf?X-Goog-Algorithm=GOOG4-RSA-SHA256&X-Goog-Signature=3f2a9c",
        "https://example.com/s/Kj8dN2pQ?u=1042&k=9f3a7c",
        "https://example.com/magic?link=eyJhbGciOi",
        // Parameter names, as whole words, however they are written.
        "https://example.com/download?token=abc", "https://example.com/cb?access_token=zyx", "https://example.com/cb?accessToken=zyx",
        "https://example.com/f?X-Amz-Signature=abcdef", "https://example.com/f?X-Amz-Credential=AKIA%2F2024", "https://example.com/f?sig=abc",
        "https://example.com/a?session_id=77", "https://example.com/a?sessionId=77", "https://example.com/a?key=AIza", "https://example.com/a?apikey=1",
        "https://example.com/a?code=123456", "https://example.com/a?otp=123456", "https://example.com/a?auth=1", "https://example.com/a?page=1&password=hunter2",
        "https://example.com/a?verification_code=1", "https://example.com/a?confirmation-token=1", "https://example.com/a?unsubscribe",
        "https://example.com/a?utm_source=mail&reset=1", "https://example.com/a?nonce=xyz", "https://example.com/a?ticket=ST-1",
        // A value that is a web token.
        "https://example.com/open?next=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc",
        // A fragment: parameters, or a route with parameters.
        "https://example.com/cb#access_token=abc&token_type=bearer", "https://example.com/#/auth/callback?code=x", "https://example.com/#/reset-password",
        // Steps of a flow, in the path.
        "https://example.com/reset-password", "https://example.com/account/confirm-subscription/", "https://example.com/Unsubscribe",
        "https://example.com/login", "https://example.com/oauth2/callback", "https://example.com/users/activate", "https://example.com/verify.html",
        // Shapes of a token in the path: a UUID, 40 hex, 32 hex, a base64url string, a document id.
        "https://example.com/files/3b18e512-dba7-4e4c-8300-dd08aeb37f8e", "https://github.com/apple/swift/commit/3b18e512dba79e4c8300dd08aeb37f8e728b8dad",
        "https://example.com/files/0123456789abcdef0123456789abcdef", "https://example.com/download/dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        "https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit",
        "https://example.com/documents/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit",
        // A parameter of a path segment.
        "https://example.com/app;jsessionid=ABCDEF123456/home",
        // Share and tracking links: one letter, then a code.
        "https://example.com/l/Ab3dE7gH", "https://example.com/c/ZxY123-abc",
    ]

    static let ordinary = [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "https://youtu.be/dQw4w9WgXcQ", "https://www.apple.com/iphone/",
        "https://en.wikipedia.org/wiki/Cascading_Style_Sheets", "https://vi.wikipedia.org/wiki/Th%C3%A0nh_ph%E1%BB%91_H%E1%BB%93_Ch%C3%AD_Minh",
        "https://www.nytimes.com/2024/05/12/technology/how-to-choose-a-laptop-for-college-students.html",
        "https://www.bbc.com/news/world-europe-68123456",
        "https://www.amazon.com/Apple-iPhone-15-Pro-Max-256GB-Natural-Titanium/dp/B0CHX1W1XY",
        "https://stackoverflow.com/questions/11227809/why-is-processing-a-sorted-array-faster-than-processing-an-unsorted-array",
        "https://github.com/apple/swift/blob/main/README.md", "https://news.ycombinator.com/item?id=39123456",
        "https://www.google.com/search?q=keyword+monkey&hl=vi&ei=abc", "https://medium.com/@user/how-to-do-something-cool-4f3a9c1b2d7e",
        "https://example.com/products?category=shoes&page=2&utm_source=newsletter&utm_medium=email",
        "https://www.reddit.com/r/swift/comments/abc123/question_about_concurrency/", "https://www.reddit.com/r/programming",
        "https://developer.apple.com/documentation/swiftui/view", "https://twitter.com/user/status/1234567890123456789",
        "https://example.com/blog/how-to-reset-your-router-when-the-wifi-stops-working", "https://example.com/#section-2",
        "https://example.com/page?keyword=swift&monkey=1", "https://example.com/shop/monkey-wrench-set", "https://example.com/author/jane-doe",
        "https://example.com/blog/10-ways-to-verify-a-claim-online", "https://example.com/docs/internationalization-and-localization-best-practices",
        "https://example.com/Blog/How-To-Build-A-React-App-From-Scratch", "https://example.com/",
    ]

    @Test func theTablesAreBigEnough() {
        #expect(Self.singleUse.count >= 20)
        #expect(Self.ordinary.count >= 20)
    }

    /// Every row is a real URL: a row that cannot be made into one would pass without testing anything, so it fails instead.
    @Test(arguments: singleUse)
    func aLinkUsedOnceIsRecognised(_ text: String) throws {
        let url = try #require(URL(string: text), "\(text) is not an address")
        #expect(ClipboardLinkGuard.looksSingleUse(url), "\(text)")
    }

    @Test(arguments: ordinary)
    func anOrdinaryLinkIsNot(_ text: String) throws {
        let url = try #require(URL(string: text), "\(text) is not an address")
        #expect(!ClipboardLinkGuard.looksSingleUse(url), "\(text)")
        // And nothing else about it stops it being read.
        #expect(ClipboardLinkGuard.allows(url), "\(text)")
    }

    @Test func parameterNamesAreWholeWords() {
        #expect(ClipboardLinkGuard.words(of: "X-Amz-Signature") == ["x", "amz", "signature"])
        #expect(ClipboardLinkGuard.words(of: "accessToken") == ["access", "token"])
        #expect(ClipboardLinkGuard.words(of: "access_token") == ["access", "token"])
        #expect(ClipboardLinkGuard.words(of: "keyword") == ["keyword"])
        #expect(ClipboardLinkGuard.words(of: "monkey") == ["monkey"])
        #expect(ClipboardLinkGuard.words(of: "") == [])
    }

    // MARK: The fetcher

    @Test(arguments: singleUse)
    func aLinkUsedOnceIsNeverRequested(_ text: String) async throws {
        let transport = FakeLinkTransport()
        let url = try #require(URL(string: text))
        let outcome = await ClipboardLinkFetcher(transport: transport, sleep: LinkTimers.never).fetch(url)
        #expect(outcome == .failed)
        #expect(transport.requests.isEmpty, "\(text)")
        #expect(transport.lookups.isEmpty, "\(text)")
    }

    @Test func aPageThatSendsTheRequestToALoginIsNotFollowed() async throws {
        let transport = FakeLinkTransport()
        let page = "https://www.example.com/members/offer"
        for target in [
            "https://www.example.com/login?next=/members/offer", "https://www.example.com/auth/callback?code=abc",
            "https://www.example.com/x/3b18e512-dba7-4e4c-8300-dd08aeb37f8e", "https://www.example.com/page?token=abc",
        ] {
            transport.set(page, .redirect(to: target))
            transport.set(target, .html("<head><title>Không được thấy</title></head>"))
            let outcome = await ClipboardLinkFetcher(transport: transport, sleep: LinkTimers.never).fetch(try #require(URL(string: page)))
            #expect(outcome == .failed, "\(target)")
            #expect(!transport.requestedURLs.contains(target), "\(target)")
        }
    }

    /// A picture is part of a page that was already read and is often signed, so it is not held to the rule for a page.
    @Test func aSignedPictureOfAnOrdinaryPageIsStillUsed() async throws {
        let transport = FakeLinkTransport()
        let picture = "https://cdn.example.com/p.png?Expires=1893456000&Signature=abc&Key-Pair-Id=K1"
        transport.set("https://www.example.com/post", .html("<head><title>Có ảnh</title><meta property=\"og:image\" content=\"\(picture)\"></head>"))
        transport.set(picture, .picture(TestPictures.png(width: 40, height: 40)))
        let outcome = await ClipboardLinkFetcher(transport: transport, sleep: LinkTimers.never).fetch(try #require(URL(string: "https://www.example.com/post")))
        guard case .read(_, let image?) = outcome else { Issue.record("expected a picture"); return }
        #expect(try #require(TestPictures.size(of: image)).width == 40)
    }
}

/// In the module: a link used once is never read, and shows as it always did.
@Suite final class ClipboardLinkSingleUseModuleTests {
    let fixture: OptionalFeaturesFixture

    init() {
        fixture = OptionalFeaturesFixture()
    }

    @Test func aLinkUsedOnceIsNeverRead() async throws {
        try fixture.setLinkPreviews(true)
        await fixture.start()
        for text in ClipboardLinkSingleUseTests.singleUse {
            guard ClipboardClassifier.link(text) != nil else { Issue.record("\(text) is not copied as a link"); continue }
            fixture.servePage(text)
            fixture.copy(text)
            let item = try fixture.item(text)
            fixture.module.requestLinkPreview(for: item)
            #expect(fixture.module.linkPreviewDisplay(for: item) == nil, "\(text)")
        }
        await fixture.waitForLinks()
        #expect(fixture.transport.requests.isEmpty)
        #expect(fixture.transport.lookups.isEmpty)
        #expect(fixture.module.linkPreviews.startedCount == 0)
    }

    @Test func anOrdinaryLinkIsRead() async throws {
        try fixture.setLinkPreviews(true)
        await fixture.start()
        let text = "https://www.example.com/blog/how-to-choose-a-laptop?utm_source=mail"
        fixture.servePage(text)
        fixture.copy(text)
        fixture.module.requestLinkPreview(for: try fixture.item(text))
        await fixture.waitForLinks()
        #expect(try fixture.item(text).linkPreview?.title == "Trang thử")
    }
}
