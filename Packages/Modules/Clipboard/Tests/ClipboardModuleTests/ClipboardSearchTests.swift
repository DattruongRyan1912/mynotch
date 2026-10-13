import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardSearchTests {
    /// Fixture history, newest first: rich text, color, files, link, image, text.
    let history: ClipboardHistory
    let text: UUID, image: UUID, link: UUID, files: UUID, color: UUID, richText: UUID

    init() {
        var history = ClipboardHistory()
        var date = Date(timeIntervalSinceReferenceDate: 800_000_000)
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

    func ids(_ query: ClipboardQuery) -> [UUID] {
        filter(history, query).map(\.id)
    }

    @Test func emptyQueryReturnsEveryItemNewestFirst() {
        let all = [richText, color, files, link, image, text]
        #expect(ids(ClipboardQuery()) == all)
        #expect(ids(ClipboardQuery(text: "  \n\t ")) == all)
        #expect(filter(history, ClipboardQuery()) == history.items)
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

    @Test func matchesFileNamesAndColorHex() {
        #expect(ids(ClipboardQuery(text: "bao cao quy")) == [files])
        #expect(ids(ClipboardQuery(text: "notes.txt")) == [files])
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
        #expect(filter(history, ClipboardQuery(boardID: board)).map(\.id) == [link, text, color])
        #expect(filter(history, ClipboardQuery(text: "o", boardID: board)).map(\.id) == [link, text])
        #expect(filter(history, ClipboardQuery(kind: .color, boardID: board)).map(\.id) == [color])
        #expect(filter(history, ClipboardQuery(boardID: UUID())).isEmpty)
    }
}
