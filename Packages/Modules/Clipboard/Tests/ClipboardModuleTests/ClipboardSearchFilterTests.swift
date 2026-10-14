import Foundation
import Testing
@testable import ClipboardModule

/// `@kind` and `@app` tokens in the search text, on a history whose items have source apps with bundle IDs.
@Suite struct ClipboardSearchFilterTests {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Added in this order, so newest first the history reads: Safari text, rich text, an @ mention, files, image,
    /// CSS color, hex color, link, Chrome text.
    let history: ClipboardHistory
    let hello: UUID, link: UUID, hex: UUID, css: UUID, image: UUID, files: UUID, mention: UUID, richText: UUID, rocks: UUID
    let index = ClipboardSearchIndex()

    init() {
        var history = ClipboardHistory()
        var date = Self.start
        func add(_ content: ClipboardContent, bundle: String?, app: String?) -> UUID {
            date += 1
            return history.add(content, hash: ClipboardContent.hash(of: content), source: (bundle, app), at: date).id
        }
        hello = add(.text("Xin chào"), bundle: "com.google.Chrome", app: "Google Chrome")
        link = add(.link(URL(string: "https://example.com/a")!), bundle: "com.apple.Safari", app: "Safari")
        hex = add(.color(hex: "#FF8800"), bundle: "com.microsoft.VSCode", app: "Code")
        css = add(.color(hex: "#FF8800", original: "rgb(255, 136, 0)"), bundle: "com.google.Chrome", app: "Google Chrome")
        image = add(
            .image(ClipboardImage(fileName: "abc.png", pixelWidth: 1, pixelHeight: 1, byteCount: 10)),
            bundle: "com.apple.Preview", app: "Xem trước"
        )
        files = add(.files([URL(fileURLWithPath: "/Users/me/Báo cáo.pdf")]), bundle: "com.apple.finder", app: "Finder")
        mention = add(.text("ping @nobody now"), bundle: nil, app: nil)
        richText = add(.richText(plain: "Bảng giá", rtf: Data("{\\rtf1 Bảng giá}".utf8)), bundle: "com.apple.Notes", app: "Ghi chú")
        rocks = add(.text("Chrome rocks"), bundle: "com.apple.Safari", app: "Safari")
        self.history = history
    }

    /// The same answer from a fresh search, from the held index, and with the apps passed in as the library does.
    func ids(_ text: String, kind: ClipboardKind? = nil, boardID: UUID? = nil, in history: ClipboardHistory? = nil) -> [UUID] {
        let history = history ?? self.history
        let query = ClipboardQuery(text: text, kind: kind, boardID: boardID)
        let found = ClipboardSearch.filter(history, query)
        #expect(index.filter(history, query) == found)
        let apps = ClipboardLibraryContent.counts(of: history).apps
        #expect(index.filter(history, query, apps: apps) == found)
        return found.map(\.id)
    }

    @Test func kindTokensKeepOnlyThatKind() {
        #expect(ids("@text") == [mention, richText, rocks, hello].sorted(by: order))
        #expect(ids("@link") == [link])
        #expect(ids("@image") == [image])
        #expect(ids("@file") == [files])
        #expect(ids("@color") == [hex, css].sorted(by: order))
    }

    /// Newest first, as the fixture was built.
    func order(_ a: UUID, _ b: UUID) -> Bool {
        let all = history.items.map(\.id)
        return all.firstIndex(of: a)! < all.firstIndex(of: b)!
    }

    @Test func theVietnameseAliasMeansColor() {
        #expect(ids("@mau") == ids("@color"))
        #expect(ids("@màu") == ids("@color"))
        #expect(ids("@MÀU") == ids("@color"))
        #expect(ids("@màu") == [css, hex].sorted(by: order))
    }

    @Test func textIncludesRichText() {
        #expect(Set(ids("@text")) == [hello, mention, richText, rocks])
    }

    @Test func appTokensKeepTheItemsOfThatApp() {
        #expect(ids("@chrome") == [css, hello].sorted(by: order))
        #expect(ids("@safari") == [link, rocks].sorted(by: order))
        #expect(ids("@code") == [hex])
        #expect(ids("@finder") == [files])
    }

    @Test func appTokensMatchAPrefixOfTheNameOrOfTheBundleComponentIgnoringCaseAndDiacritics() {
        // Name "Google Chrome", component "Chrome".
        #expect(ids("@CHRO") == ids("@chrome"))
        #expect(ids("@goo") == ids("@chrome"))
        // Name "Xem trước", component "Preview".
        #expect(ids("@xem") == [image])
        #expect(ids("@XEM") == [image])
        #expect(ids("@preview") == [image])
        // Name "Ghi chú", component "Notes".
        #expect(ids("@ghi") == [richText])
        #expect(ids("@GHÍ") == [richText])
        #expect(ids("@notes") == [richText])
        // Lowercase bundle ID "finder", no case needed.
        #expect(ids("@FIND") == [files])
    }

    @Test func aTokenAndFreeTextCombine() {
        #expect(ids("@chrome xin") == [hello])
        #expect(ids("xin @chrome") == [hello])
        #expect(ids("@chrome rgb") == [css])
        // "chrome" in the text of a Safari item is found, but not through its source app.
        #expect(ids("@safari chrome") == [rocks])
        #expect(ids("@safari zzz").isEmpty)
    }

    @Test func aKindAndAnAppCombineWithAnd() {
        #expect(ids("@chrome @text") == [hello])
        #expect(ids("@chrome @color") == [css])
        #expect(ids("@color @chrome") == [css])
        #expect(ids("@safari @link") == [link])
        #expect(ids("@safari @image").isEmpty)
        #expect(ids("@chrome @color rgb") == [css])
    }

    @Test func twoOfTheSameDimensionAreBothRequired() {
        #expect(ids("@text @link").isEmpty)
        #expect(ids("@chrome @safari").isEmpty)
        #expect(ids("@text @text") == ids("@text"))
        #expect(ids("@chrome @goo") == ids("@chrome"))
    }

    @Test func anUnknownWordIsSearchedAsText() {
        #expect(ids("@nobody") == [mention])
        #expect(ids("@nobody ping") == [mention])
        #expect(ids("@nobody @text") == [mention])
        #expect(ids("@nobody @link").isEmpty)
        #expect(ids("@zzz").isEmpty)
    }

    @Test func anAtSignAloneChangesNothing() {
        #expect(ids("@") == history.items.map(\.id))
        #expect(ids("@ chrome") == [css, hello, rocks].sorted(by: order))
    }

    @Test func anAppTokenNeverMatchesAnItemWithoutAnApp() {
        #expect(!ids("@chrome").contains(mention))
        #expect(!ids("@g").contains(mention))
        #expect(Set(ids("@g")) == [hello, css, richText])
    }

    @Test func tokensApplyOnTopOfTheKindChipAndTheBoard() {
        #expect(ids("@chrome", kind: .text) == [hello])
        #expect(ids("@text", kind: .link).isEmpty)
        #expect(ids("@text", kind: .text) == ids("@text"))
        var history = history
        let board = history.createBoard(name: "Công việc")
        history.pin(itemID: hello, to: board)
        history.pin(itemID: css, to: board)
        history.pin(itemID: link, to: board)
        // Newest pin first, as the board keeps them.
        #expect(ids("", boardID: board, in: history) == [link, css, hello])
        #expect(ids("@chrome", boardID: board, in: history) == [css, hello])
        #expect(ids("@chrome @color", boardID: board, in: history) == [css])
        #expect(ids("@safari", boardID: board, in: history) == [link])
    }

    @Test func aColorCopiedAsCSSIsFoundByItsTextAndByItsHex() {
        #expect(ids("rgb(255") == [css])
        #expect(ids("136") == [css])
        #expect(ids("#ff8800") == [css, hex].sorted(by: order))
        #expect(ids("ff8800 @chrome") == [css])
    }

    @Test func aRepeatedCopyFromAnotherAppMovesTheItemToThatApp() {
        // The held index has seen the item with its first app.
        #expect(ids("@chrome").contains(hello))
        var history = history
        let content = ClipboardContent.text("Xin chào")
        history.add(content, hash: ClipboardContent.hash(of: content), source: ("com.apple.Safari", "Safari"), at: Self.start + 100)
        #expect(ids("@chrome", in: history) == [css])
        #expect(ids("@safari xin", in: history) == [hello])
    }

    @Test func theBundleIDAloneChangingIsNoticedToo() {
        #expect(ids("@chrome").contains(hello))
        var history = history
        let content = ClipboardContent.text("Xin chào")
        history.add(content, hash: ClipboardContent.hash(of: content), source: ("org.example.Browser", "Google Chrome"), at: Self.start + 100)
        #expect(ids("@browser", in: history) == [hello])
    }

    @Test func theItemsOfAnAppThatHasNoBundleIDAreFoundByName() {
        var history = ClipboardHistory()
        let content = ClipboardContent.text("note")
        let id = history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, "Lời nhắc"), at: Self.start).id
        #expect(ids("@loi", in: history) == [id])
        #expect(ids("@lời", in: history) == [id])
    }
}
