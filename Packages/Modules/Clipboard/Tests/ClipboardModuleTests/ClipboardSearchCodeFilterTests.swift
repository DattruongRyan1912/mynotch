import Foundation
import Testing
@testable import ClipboardModule

/// `@code` and its Vietnamese alias `@mã`, on a history with texts that are code and texts that are not.
@Suite struct ClipboardSearchCodeFilterTests {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    let history: ClipboardHistory
    let swiftCode: UUID, prose: UUID, sql: UUID, link: UUID, json: UUID, python: UUID
    let index = ClipboardSearchIndex()

    init() {
        var history = ClipboardHistory()
        var date = Self.start
        func add(_ content: ClipboardContent, app: String) -> UUID {
            date += 1
            return history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, app), at: date).id
        }
        swiftCode = add(.text("let total = items.reduce(0) { $0 + $1.price }\nprint(total)"), app: "Xcode")
        prose = add(.text("Hôm nay mình đi dạo công viên rồi ăn phở."), app: "Ghi chú")
        sql = add(.richText(plain: "SELECT id, name FROM users WHERE age > 18;", rtf: Data("{\\rtf1 x}".utf8)), app: "Xcode")
        link = add(.link(URL(string: "https://example.com/swift")!), app: "Safari")
        json = add(.text(#"{"name": "An", "tags": ["swift", "code"]}"#), app: "Ghi chú")
        python = add(.text("def add(a, b):\n    return a + b\n\nprint(add(1, 2))"), app: "Xcode")
        self.history = history
    }

    /// The same answer from a fresh search and from the held index.
    func ids(_ text: String, kind: ClipboardKind? = nil) -> Set<UUID> {
        let query = ClipboardQuery(text: text, kind: kind)
        let found = ClipboardSearch.filter(history, query)
        #expect(index.filter(history, query) == found)
        return Set(found.map(\.id))
    }

    @Test func codeKeepsOnlyTheTextsThatAreCode() {
        #expect(ids("@code") == [swiftCode, sql, json, python])
        #expect(ids("@CODE") == ids("@code"))
    }

    @Test func theVietnameseAliasMeansTheSame() {
        #expect(ids("@mã") == ids("@code"))
        #expect(ids("@ma") == ids("@code"))
        #expect(ids("@MÃ") == ids("@code"))
    }

    @Test func codeCombinesWithFreeTextAndApps() {
        #expect(ids("@code total") == [swiftCode])
        #expect(ids("@code swift") == [json])
        #expect(ids("swift @code") == [json])
        #expect(ids("@code @xcode") == [swiftCode, sql, python])
        #expect(ids("@code @xcode print") == [swiftCode, python])
        #expect(ids("@code zzz").isEmpty)
    }

    @Test func codeCombinesWithKinds() {
        #expect(ids("@text @code") == ids("@code"))
        #expect(ids("@link @code").isEmpty)
        #expect(ids("@code", kind: .text) == ids("@code"))
        #expect(ids("@code", kind: .link).isEmpty)
    }

    @Test func aRepeatedCopyStaysCode() {
        var history = history
        let content = ClipboardContent.text("let total = items.reduce(0) { $0 + $1.price }\nprint(total)")
        history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, "Xcode"), at: Self.start + 100)
        let found = ClipboardSearch.filter(history, ClipboardQuery(text: "@code"))
        #expect(found.count == 4)
        #expect(found.first?.id == swiftCode)
    }

    @Test func anItemWithoutADetectionIsNotCode() {
        var history = history
        history.items[0].codeDetection = nil
        #expect(!ClipboardSearch.filter(history, ClipboardQuery(text: "@code")).contains { $0.id == history.items[0].id })
    }

    @Test func aTextThatMentionsCodeIsStillSearchable() {
        var history = ClipboardHistory()
        let content = ClipboardContent.text("mã vạch của sản phẩm")
        history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: Self.start)
        // "mã" as an ordinary word, with no "@", is text.
        #expect(ClipboardSearch.filter(history, ClipboardQuery(text: "mã vạch")).count == 1)
        #expect(ClipboardSearch.filter(history, ClipboardQuery(text: "@mã")).isEmpty)
    }
}
