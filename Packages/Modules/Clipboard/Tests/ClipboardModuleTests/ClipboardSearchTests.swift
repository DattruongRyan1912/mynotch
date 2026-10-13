import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardSearchTests {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Fixture history, newest first: rich text, color, files, link, image, text.
    let history: ClipboardHistory
    let text: UUID, image: UUID, link: UUID, files: UUID, color: UUID, richText: UUID
    /// Held across queries like the tab does, so every test also checks it agrees with a fresh search.
    let index = ClipboardSearchIndex()

    init() {
        var history = ClipboardHistory()
        var date = Self.start
        func add(_ content: ClipboardContent, from app: String?) -> UUID {
            date += 1
            return history.add(content, hash: ClipboardContent.hash(of: content), source: (bundleID: nil, name: app), at: date).id
        }
        text = add(.text("Đồng hồ thông minh\nGiá tốt"), from: "Ghi chú")
        image = add(.image(ClipboardImage(fileName: "abc.png", pixelWidth: 1, pixelHeight: 1, byteCount: 10)), from: "Ảnh chụp màn hình")
        link = add(.link(URL(string: "https://www.apple.com/vn/iphone?ref=ad")!), from: "Safari")
        files = add(.files([URL(fileURLWithPath: "/Users/me/Báo cáo quý.pdf"), URL(fileURLWithPath: "/tmp/notes.txt")]), from: "Finder")
        color = add(.color(hex: "#FF8800"), from: nil)
        richText = add(.richText(plain: "Hello World", rtf: Data("{\\rtf1 Hello World}".utf8)), from: "Pages")
        self.history = history
    }

    func ids(_ query: ClipboardQuery, in history: ClipboardHistory? = nil) -> [UUID] {
        let history = history ?? self.history
        let found = ClipboardSearch.filter(history, query)
        #expect(index.filter(history, query) == found)
        return found.map(\.id)
    }

    @Test func emptyQueryReturnsEveryItemNewestFirst() {
        let all = [richText, color, files, link, image, text]
        #expect(ids(ClipboardQuery()) == all)
        #expect(ids(ClipboardQuery(text: "  \n\t ")) == all)
        #expect(ClipboardSearch.filter(history, ClipboardQuery()) == history.items)
    }

    @Test func everyWordMustMatch() {
        #expect(ids(ClipboardQuery(text: "thông minh")) == [text])
        #expect(ids(ClipboardQuery(text: "minh  thông")) == [text])
        #expect(ids(ClipboardQuery(text: "thông safari")) == [])
        #expect(ids(ClipboardQuery(text: "o")) == [richText, files, link, text])
    }

    @Test(arguments: ["dong ho", "ĐỒNG HỒ", "đồng hồ", "DONG", "Dồng", "gia tot", "GIÁ"])
    func matchingIgnoresCaseAndDiacriticsIncludingD(query: String) {
        #expect(ids(ClipboardQuery(text: query)) == [text])
    }

    @Test func accentedQueriesMatchUnaccentedText() {
        #expect(ids(ClipboardQuery(text: "hëllö wórld")) == [richText])
        #expect(ids(ClipboardQuery(text: "đhello")) == [])
    }

    @Test func matchesSourceAppNames() {
        #expect(ids(ClipboardQuery(text: "safari")) == [link])
        #expect(ids(ClipboardQuery(text: "ghi chu")) == [text])
        #expect(ids(ClipboardQuery(text: "anh chup")) == [image])
    }

    @Test func matchesLinkHostAndAbsoluteString() {
        #expect(ids(ClipboardQuery(text: "www.apple.com")) == [link])
        #expect(ids(ClipboardQuery(text: "ref=ad")) == [link])
    }

    @Test func matchesFileNamesButNotTheirFolders() {
        #expect(ids(ClipboardQuery(text: "bao cao quy")) == [files])
        #expect(ids(ClipboardQuery(text: "notes.txt")) == [files])
        #expect(ids(ClipboardQuery(text: "users")) == [])
        #expect(ids(ClipboardQuery(text: "tmp")) == [])
    }

    @Test func matchesColorHex() {
        #expect(ids(ClipboardQuery(text: "ff8800")) == [color])
        #expect(ids(ClipboardQuery(text: "#ff88")) == [color])
    }

    @Test func kindFilterUsesTheContentKind() {
        #expect(ids(ClipboardQuery(kind: .text)) == [richText, text])
        #expect(ids(ClipboardQuery(kind: .link)) == [link])
        #expect(ids(ClipboardQuery(kind: .image)) == [image])
        #expect(ids(ClipboardQuery(kind: .file)) == [files])
        #expect(ids(ClipboardQuery(kind: .color)) == [color])
        #expect(ids(ClipboardQuery(text: "hello", kind: .text)) == [richText])
        #expect(ids(ClipboardQuery(text: "hello", kind: .link)) == [])
    }

    @Test func boardFilterKeepsThePinOrder() {
        var history = history
        let board = history.createBoard(name: "Ghim")
        let other = history.createBoard(name: "Khác")
        history.pin(itemID: color, to: board)
        history.pin(itemID: text, to: board)
        history.pin(itemID: link, to: board)
        history.pin(itemID: files, to: other)
        #expect(ids(ClipboardQuery(boardID: board), in: history) == [link, text, color])
        #expect(ids(ClipboardQuery(text: "o", boardID: board), in: history) == [link, text])
        #expect(ids(ClipboardQuery(kind: .color, boardID: board), in: history) == [color])
        #expect(ids(ClipboardQuery(boardID: UUID()), in: history) == [])
    }

    @Test func onlyTheFirst20000CharactersAreSearched() {
        var history = ClipboardHistory()
        let long = String(repeating: "x ", count: 9_997) + "early " + String(repeating: "y", count: 100) + " late"
        let id = history.add(.text(long), hash: "long", source: (bundleID: nil, name: "Ghi chú"), at: Self.start).id
        #expect(ids(ClipboardQuery(text: "early"), in: history) == [id])
        #expect(ids(ClipboardQuery(text: "late"), in: history) == [])
        // The app name is always searchable, however long the content.
        #expect(ids(ClipboardQuery(text: "ghi chu"), in: history) == [id])
    }

    @Test func indexOnlyFoldsNewOrChangedItems() {
        var history = history
        index.update(history)
        #expect(index.foldCount == 6)
        _ = index.filter(history, ClipboardQuery(text: "dong"))
        _ = index.filter(history, ClipboardQuery(text: "dong ho"))
        #expect(index.foldCount == 6)

        history.add(.text("mới"), hash: "new", source: (bundleID: nil, name: nil), at: Self.start + 10)
        #expect(index.filter(history, ClipboardQuery(text: "moi")).count == 1)
        #expect(index.foldCount == 7)

        // Re-copying from the same app keeps the folded text; another app changes what is searchable.
        history.add(.text("Hello World"), hash: ClipboardContent.hash(of: .text("Hello World")), source: (bundleID: nil, name: "Pages"), at: Self.start + 11)
        index.update(history)
        #expect(index.foldCount == 7)
        history.add(.text("Hello World"), hash: ClipboardContent.hash(of: .text("Hello World")), source: (bundleID: nil, name: "TextEdit"), at: Self.start + 12)
        #expect(index.filter(history, ClipboardQuery(text: "textedit")).map(\.id) == [richText])
        #expect(index.foldCount == 8)

        _ = history.remove(ids: [text])
        #expect(index.filter(history, ClipboardQuery(text: "dong")) == [])
        #expect(index.foldCount == 8)
    }
}
