import Foundation
import Testing
@testable import ClipboardModule

/// The apps the fixture history knows, in the order the library lists them: most items first.
enum SearchFixtureApps {
    static let all = [
        ClipboardLibraryApp(id: "com.google.Chrome", bundleID: "com.google.Chrome", name: "Google Chrome", count: 9),
        ClipboardLibraryApp(id: "com.microsoft.VSCode", bundleID: "com.microsoft.VSCode", name: "Code", count: 7),
        ClipboardLibraryApp(id: "com.apple.Safari", bundleID: "com.apple.Safari", name: "Safari", count: 5),
        ClipboardLibraryApp(id: "com.apple.Notes", bundleID: "com.apple.Notes", name: "Ghi chú", count: 3),
        ClipboardLibraryApp(id: "name:Lời nhắc", bundleID: nil, name: "Lời nhắc", count: 1),
    ]
}

@Suite struct ClipboardSearchTermsTests {
    func terms(_ text: String, apps: [ClipboardLibraryApp] = SearchFixtureApps.all) -> ClipboardSearchTerms {
        ClipboardSearchTerms(parsing: text, apps: apps)
    }

    @Test(arguments: [
        ("@text", ClipboardKind.text), ("@link", .link), ("@image", .image), ("@color", .color), ("@file", .file),
        ("@mau", .color), ("@màu", .color), ("@MÀU", .color), ("@Màu", .color), ("@LINK", .link), ("@Image", .image),
    ])
    func kindTokensFilterByKind(input: String, kind: ClipboardKind) {
        let terms = terms(input + " ")
        #expect(terms.kinds == [kind])
        #expect(terms.appPrefixes.isEmpty)
        #expect(terms.text == "")
    }

    @Test func aKindTokenKeepsWhatWasTypedAndNamesItsKindInVietnamese() throws {
        let token = try #require(terms("@màu ").tokens.first)
        #expect(token.raw == "@màu")
        #expect(token.filter == .kind(.color))
        #expect(token.title == "Màu")
        #expect(terms("@mau ").tokens.first?.raw == "@mau")
        #expect(terms("@text ").tokens.first?.title == "Văn bản")
        #expect(terms("@image ").tokens.first?.title == "Ảnh")
    }

    @Test func theRestOfTheTextStaysAFreeTextSearch() {
        #expect(terms("hello @link world").text == "hello world")
        #expect(terms("hello @link world").kinds == [.link])
        #expect(terms("@link hello").text == "hello")
        #expect(terms("hello @link").text == "hello")
        #expect(terms("  a   @link   b  ").text == "a b")
        #expect(terms("no tokens here").text == "no tokens here")
        #expect(terms("").text == "")
    }

    @Test(arguments: [
        ("@chrome ", "Google Chrome", "chrome"),
        ("@Chrome ", "Google Chrome", "chrome"),
        ("@chro ", "Google Chrome", "chro"),
        ("@google ", "Google Chrome", "google"),
        ("@safari ", "Safari", "safari"),
        ("@SAF ", "Safari", "saf"),
        ("@code ", "Code", "code"),
        ("@vscode ", "Code", "vscode"),
        ("@co ", "Code", "co"),
        ("@ghi ", "Ghi chú", "ghi"),
        ("@GHI ", "Ghi chú", "ghi"),
        ("@ghí ", "Ghi chú", "ghi"),
        ("@notes ", "Ghi chú", "notes"),
        ("@loi ", "Lời nhắc", "loi"),
        ("@lời ", "Lời nhắc", "loi"),
    ])
    func appTokensMatchANamePrefixOrABundleComponentPrefix(input: String, app: String, prefix: String) throws {
        let terms = terms(input)
        let token = try #require(terms.tokens.first)
        #expect(terms.tokens.count == 1)
        #expect(token.filter == .app(prefix: prefix))
        #expect(token.title == app)
        #expect(terms.appPrefixes == [prefix])
        #expect(terms.kinds.isEmpty)
        #expect(terms.text == "")
    }

    @Test func aPrefixMustStartTheNameNotJustAppearInIt() {
        #expect(terms("@hrome ").tokens.isEmpty)
        #expect(terms("@hrome ").text == "@hrome")
        #expect(terms("@chrome-extra ").text == "@chrome-extra")
        #expect(terms("@com ").tokens.isEmpty)
    }

    @Test func aKindTokenAndAnAppTokenCombine() {
        let terms = terms("@link @chrome foo")
        #expect(terms.kinds == [.link])
        #expect(terms.appPrefixes == ["chrome"])
        #expect(terms.text == "foo")
        #expect(terms.tokens.map(\.raw) == ["@link", "@chrome"])
    }

    @Test func aKindWinsOverAnAppWithTheSameName() {
        let apps = [ClipboardLibraryApp(id: "com.example.Files", bundleID: "com.example.Files", name: "File", count: 1)]
        #expect(terms("@file ", apps: apps).kinds == [.file])
        #expect(terms("@file ", apps: apps).appPrefixes.isEmpty)
        #expect(terms("@fil ", apps: apps).appPrefixes == ["fil"])
    }

    @Test(arguments: ["@nobody", "@nobody hello", "@@link", "@link,", "@lin", "@links", "@texts", "@#fff", "@1"])
    func anUnknownWordStaysFreeText(input: String) {
        let terms = terms(input)
        #expect(terms.tokens.isEmpty)
        #expect(terms.text == input)
    }

    @Test func wordsThatOnlyContainAnAtSignAreText() {
        #expect(terms("me@example.com").text == "me@example.com")
        #expect(terms("me@link").tokens.isEmpty)
        #expect(terms("a@chrome").text == "a@chrome")
    }

    @Test func anAppTokenNeedsAnAppInTheHistory() {
        #expect(terms("@chrome ", apps: []).tokens.isEmpty)
        #expect(terms("@chrome ", apps: []).text == "@chrome")
        #expect(terms("@link ", apps: []).kinds == [.link])
    }

    @Test func anAtSignAloneIsNeitherATokenNorText() {
        #expect(terms("@").tokens.isEmpty)
        #expect(terms("@").text == "")
        #expect(terms("hello @").text == "hello")
        #expect(terms("@ hello").text == "hello")
    }

    @Test func theSameTokenCountsOnce() {
        #expect(terms("@link @link ").tokens.count == 1)
        #expect(terms("@link @link ").kinds == [.link])
        // Written differently it is two tokens that mean the same.
        #expect(terms("@link @Link ").tokens.count == 2)
    }

    @Test func twoKindsOrTwoAppsAreBothRequired() {
        #expect(terms("@text @link ").kinds == [.text, .link])
        #expect(terms("@chrome @safari ").appPrefixes == ["chrome", "safari"])
    }

    // MARK: Accepted and being typed

    @Test func theLastWordIsStillBeingTypedUntilSomethingFollowsIt() {
        #expect(terms("@link").tokens.map(\.isBeingTyped) == [true])
        #expect(terms("hello @link").tokens.map(\.isBeingTyped) == [true])
        #expect(terms("@link ").tokens.map(\.isBeingTyped) == [false])
        #expect(terms("@link\n").tokens.map(\.isBeingTyped) == [false])
        #expect(terms("@link hello").tokens.map(\.isBeingTyped) == [false])
        #expect(terms("@link @chrome").tokens.map(\.isBeingTyped) == [false, true])
    }

    @Test func chipsAreTheTokensThatAreDone() {
        #expect(terms("@link").chips.isEmpty)
        #expect(terms("@link ").chips.map(\.raw) == ["@link"])
        #expect(terms("@link @chrome").chips.map(\.raw) == ["@link"])
        #expect(terms("@link @chrome ").chips.map(\.raw) == ["@link", "@chrome"])
        #expect(terms("hello").chips.isEmpty)
    }

    // MARK: Removing

    @Test func removingATokenLeavesTheOtherWords() throws {
        let text = "hello @link world @chrome"
        let link = try #require(terms(text).tokens.first)
        #expect(ClipboardSearchTerms.removing(link, from: text) == "hello world @chrome")
        let chrome = try #require(terms(text).tokens.last)
        #expect(ClipboardSearchTerms.removing(chrome, from: text) == "hello @link world")
    }

    @Test func removingATokenTakesEveryCopyOfIt() throws {
        let text = "@link a @link b"
        let link = try #require(terms(text).tokens.first)
        #expect(ClipboardSearchTerms.removing(link, from: text) == "a b")
    }

    @Test func removingATokenKeepsTheOthersFinished() throws {
        let text = "@chrome foo @link "
        let chrome = try #require(terms(text).tokens.first)
        #expect(ClipboardSearchTerms.removing(chrome, from: text) == "foo @link ")
        #expect(terms(ClipboardSearchTerms.removing(chrome, from: text)).chips.map(\.raw) == ["@link"])
        let link = try #require(terms(text).tokens.last)
        #expect(ClipboardSearchTerms.removing(link, from: text) == "@chrome foo ")
    }

    @Test func removingTheOnlyTokenEmptiesTheSearch() throws {
        let link = try #require(terms("@link ").tokens.first)
        #expect(ClipboardSearchTerms.removing(link, from: "@link ") == "")
    }
}
