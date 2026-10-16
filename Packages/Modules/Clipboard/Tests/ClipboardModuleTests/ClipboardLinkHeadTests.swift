import Foundation
import Testing
@testable import ClipboardModule

/// What is taken from the head of a page, and what is not.
@Suite struct ClipboardLinkHeadTests {
    let page = URL(string: "https://www.example.com/articles/one?x=1")!

    func parse(_ html: String, type: String? = "text/html; charset=utf-8") -> ClipboardLinkHead {
        ClipboardLinkHead.parse(Data(html.utf8), contentType: type, pageURL: page)
    }

    // MARK: Title

    @Test func theTitleOfThePage() {
        #expect(parse("<html><head><title>Xin chào</title></head><body></body></html>").title == "Xin chào")
        #expect(parse("<HTML><HEAD><TITLE lang=vi>Chào</TITLE></HEAD>").title == "Chào")
        #expect(parse("<head>\n  <title>\n    Hai dòng\n    chữ\n  </title>\n</head>").title == "Hai dòng chữ")
    }

    @Test func theTitleIsMadePlain() {
        #expect(parse("<head><title>Tom &amp; Jerry&#7; &lt;3</title></head>").title == "Tom & Jerry <3")
    }

    @Test func theFirstTitleWins() {
        #expect(parse("<head><title>Một</title><title>Hai</title></head>").title == "Một")
    }

    @Test func openGraphTitleIsTheFallback() {
        #expect(parse("<head><meta property=\"og:title\" content=\"Từ OG\"></head>").title == "Từ OG")
        #expect(parse("<head><meta property=\"og:title\" content=\"Từ OG\"><title>Thật</title></head>").title == "Thật")
        #expect(parse("<head><title>   </title><meta property=\"og:title\" content=\"x\"></head>").title == nil)
    }

    @Test func aTitleOutsideTheHeadIsNotTheTitle() {
        #expect(parse("<head></head><body><svg><title>icon</title></svg></body>").title == nil)
        #expect(parse("<head><meta charset=utf-8><body><title>no</title>").title == nil)
        #expect(parse("<head><title>Có</title></HEAD><body><title>Không</title>").title == "Có")
    }

    @Test func textThatLooksLikeTagsButIsNotOneIsSkipped() {
        #expect(parse("<head><script>var s = '<title>fake</title>';</script><title>Thật</title></head>").title == "Thật")
        #expect(parse("<head><!-- <title>commented</title> --><title>Thật</title></head>").title == "Thật")
        #expect(parse("<head><style>/* <title>css</title> */</style><title>Thật</title></head>").title == "Thật")
        #expect(parse("<head><script>if (a < b) { x = '<meta property=\"og:image\" content=\"https://evil.example/x.png\">' }</script></head>").openGraphImage == nil)
    }

    @Test func aTitleThatIsNeverClosedIsStillCut() throws {
        let title = try #require(parse("<head><title>" + String(repeating: "x", count: 5_000)).title)
        #expect(title.count == 200)
    }

    // MARK: Pictures

    @Test func theOpenGraphImage() {
        #expect(parse("<head><meta property=\"og:image\" content=\"https://cdn.example.com/a.png\"></head>").openGraphImage
            == URL(string: "https://cdn.example.com/a.png"))
        #expect(parse("<head><meta content=\"https://cdn.example.com/a.png\" property=\"og:image\"></head>").openGraphImage
            == URL(string: "https://cdn.example.com/a.png"))
        #expect(parse("<head><meta name='og:image' content='https://cdn.example.com/b.png'></head>").openGraphImage
            == URL(string: "https://cdn.example.com/b.png"))
        #expect(parse("<head><meta property=og:image:secure_url content=https://cdn.example.com/c.png></head>").openGraphImage
            == URL(string: "https://cdn.example.com/c.png"))
    }

    @Test func relativeAddressesAreMadeAbsoluteAgainstThePage() {
        #expect(parse("<head><meta property=\"og:image\" content=\"/img/a.png\"></head>").openGraphImage == URL(string: "https://www.example.com/img/a.png"))
        #expect(parse("<head><meta property=\"og:image\" content=\"a.png\"></head>").openGraphImage == URL(string: "https://www.example.com/articles/a.png"))
        #expect(parse("<head><meta property=\"og:image\" content=\"//cdn.example.com/a.png\"></head>").openGraphImage == URL(string: "https://cdn.example.com/a.png"))
    }

    @Test func entitiesInAnAddressAreDecoded() {
        #expect(parse("<head><meta property=\"og:image\" content=\"https://cdn.example.com/a.png?w=1&amp;h=2\"></head>").openGraphImage
            == URL(string: "https://cdn.example.com/a.png?w=1&h=2"))
    }

    @Test func onlyWebAddressesAreTaken() {
        #expect(parse("<head><meta property=\"og:image\" content=\"javascript:alert(1)\"></head>").openGraphImage == nil)
        #expect(parse("<head><meta property=\"og:image\" content=\"data:image/png;base64,AAAA\"></head>").openGraphImage == nil)
        #expect(parse("<head><meta property=\"og:image\" content=\"file:///etc/passwd\"></head>").openGraphImage == nil)
        #expect(parse("<head><meta property=\"og:image\" content=\"ftp://x.example/a.png\"></head>").openGraphImage == nil)
        #expect(parse("<head><meta property=\"og:image\" content=\"\"></head>").openGraphImage == nil)
        #expect(parse("<head><meta property=\"og:image\" content=\"https://x.example/\(String(repeating: "a", count: 3_000))\"></head>").openGraphImage == nil)
    }

    @Test func theIconsTheBiggestKindFirstAndNeverAnSVG() {
        let head = parse("""
        <head>
        <link rel="icon" href="/favicon-32.png">
        <link rel="shortcut icon" href="/favicon.ico">
        <link rel="apple-touch-icon" sizes="180x180" href="/touch.png">
        <link rel="icon" type="image/svg+xml" href="/icon.svg">
        <link rel="icon" type="image/svg+xml" href="/icon?format=1">
        <link rel="icon" href="/other.SVG">
        <link rel="mask-icon" href="/mask.svg">
        <link rel="stylesheet" href="/style.css">
        <link rel="apple-touch-icon-precomposed" href="https://cdn.example.com/pre.png">
        </head>
        """)
        #expect(head.icons.map(\.absoluteString) == [
            "https://www.example.com/touch.png", "https://cdn.example.com/pre.png",
            "https://www.example.com/favicon-32.png", "https://www.example.com/favicon.ico",
        ])
    }

    @Test func aBaseTagIsNotBelieved() {
        let head = parse("<head><base href=\"https://evil.example/\"><meta property=\"og:image\" content=\"/a.png\"></head>")
        #expect(head.openGraphImage == URL(string: "https://www.example.com/a.png"))
    }

    // MARK: Where the head ends

    @Test func nothingAfterTheHeadIsRead() {
        let head = parse("<head><title>Đầu</title></head><body><meta property=\"og:image\" content=\"https://x.example/body.png\"><link rel=icon href=/b.png>")
        #expect(head.title == "Đầu")
        #expect(head.openGraphImage == nil)
        #expect(head.icons.isEmpty)
        #expect(parse("<head><title>Đầu</title><BODY><meta property=\"og:image\" content=\"https://x.example/body.png\">").openGraphImage == nil)
    }

    // MARK: Encodings

    @Test func theHeadersCharsetDecidesTheEncoding() {
        var bytes = Data("<head><title>caf".utf8)
        bytes.append(0xE9)
        bytes.append(contentsOf: Array("</title></head>".utf8))
        #expect(ClipboardLinkHead.parse(bytes, contentType: "text/html; charset=ISO-8859-1", pageURL: page).title == "café")
        #expect(ClipboardLinkHead.parse(bytes, contentType: "text/html; charset=\"windows-1252\"", pageURL: page).title == "café")
    }

    @Test func thePagesOwnCharsetIsUsedWhenTheHeaderHasNone() {
        var bytes = Data("<head><meta charset=\"iso-8859-1\"><title>caf".utf8)
        bytes.append(0xE9)
        bytes.append(contentsOf: Array("</title></head>".utf8))
        #expect(ClipboardLinkHead.parse(bytes, contentType: "text/html", pageURL: page).title == "café")
        #expect(ClipboardLinkHead.parse(bytes, contentType: nil, pageURL: page).title == "café")
    }

    @Test func bytesThatAreNotValidInTheEncodingAreReadAsLatin1() {
        var bytes = Data("<head><title>a".utf8)
        bytes.append(contentsOf: [0xFF, 0xFE, 0xFD])
        bytes.append(contentsOf: Array("b</title></head>".utf8))
        #expect(ClipboardLinkHead.parse(bytes, contentType: "text/html; charset=utf-8", pageURL: page).title == "aÿþýb")
    }

    // MARK: Hostile input

    @Test func garbageDoesNotCrashAndDoesNotRunLong() {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt8 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: seed >> 33)
        }
        for _ in 0..<200 {
            let bytes = Data((0..<2_000).map { _ in next() })
            _ = ClipboardLinkHead.parse(bytes, contentType: nil, pageURL: page)
        }
        // Tag-shaped junk, at the most that is ever read: pieces that never close (the first failed search ends the walk) and pieces that
        // close, which make the scanner search once for every one of them. The parse cannot be interrupted by a time limit, so it has to be
        // linear.
        let pieces = [
            "<meta ", "<link rel=icon href=\"", "<!--", "<", "<title>", "<script>", "<a b='", "</", "<meta property=og:image content=",
            "<!--x-->", "<script></script>", "<style>a</style>", "<template></template>", "<meta property=og:image content=x>",
            "<link rel=icon href=/a.png>", "<title>t</title>", "<a b='c'>", "<br/>", "<!x>", "<?x?>",
        ]
        for piece in pieces {
            let text = String(repeating: piece, count: 512 * 1024 / piece.utf8.count)
            let start = ContinuousClock.now
            _ = ClipboardLinkHead.parse(Data(text.utf8), contentType: nil, pageURL: page)
            #expect(ContinuousClock.now - start < .seconds(3), "\(piece)")
        }
    }

    @Test func aHeadWithNothingInItIsEmpty() {
        #expect(parse("") == ClipboardLinkHead(title: nil, openGraphImage: nil, icons: []))
        #expect(parse("just words, no tags") == ClipboardLinkHead(title: nil, openGraphImage: nil, icons: []))
    }
}
