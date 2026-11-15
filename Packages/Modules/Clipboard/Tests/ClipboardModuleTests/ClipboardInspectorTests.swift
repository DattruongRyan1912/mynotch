import Foundation
import Testing
@testable import ClipboardModule

/// What the library's inspector says about an item, decided apart from the drawing: the fields of each kind, what a closed board
/// shows, and the numbers of a text.
@Suite struct ClipboardInspectorTests {
    static let copied = Date(timeIntervalSince1970: 1_800_000_000)

    static func history(_ content: ClipboardContent, source: (String?, String?) = ("com.apple.Notes", "Ghi chú")) -> (ClipboardHistory, ClipboardItem) {
        var history = ClipboardHistory()
        history.add(content, hash: ClipboardContent.hash(of: content), source: source, at: copied)
        return (history, history.items[0])
    }

    static func info(of content: ClipboardContent) -> ClipboardInspectorInfo {
        let (history, item) = Self.history(content)
        return ClipboardInspectorInfo(item, in: history)
    }

    static let vietnamese = "Xin chào thế giới\nHôm nay trời đẹp quá, chúng ta cùng đi dạo quanh hồ nhé.\n"
    static let english = "The quick brown fox jumps over the lazy dog while the sun sets slowly over the quiet hills."

    // MARK: Text

    @Test func aTextHasItsSourceDateAndNumbers() {
        var (history, item) = Self.history(.text(Self.vietnamese))
        history.items[0].copyCount = 3
        history.items[0].edited = true
        item = history.items[0]

        let info = ClipboardInspectorInfo(item, in: history)

        #expect(info.id == item.id)
        #expect(info.kindTitle == "Văn bản")
        #expect(info.systemImage == ClipboardKind.text.systemImage)
        #expect(info.sourceAppName == "Ghi chú" && info.sourceBundleID == "com.apple.Notes")
        #expect(info.copiedAt == Self.copied)
        #expect(info.timesCopied == 3)
        #expect(info.isEdited)
        #expect(info.canEdit)
        #expect(info.size == .text(ClipboardTextStats(characters: 17 + 1 + 56 + 1, words: 4 + 13, lines: 2)))
        #expect(info.boards.isEmpty)
    }

    @Test func aRepeatedCopyIsCountedAndAFreshOneIsOnce() {
        #expect(Self.info(of: .text("a")).timesCopied == 1)
        var history = ClipboardHistory()
        for offset in 0..<3 { history.add(.text("a"), hash: "h", source: (nil, nil), at: Self.copied + Double(offset)) }
        #expect(ClipboardInspectorInfo(history.items[0], in: history).timesCopied == 3)
    }

    @Test func aTextWithNoAppHasNoSource() {
        let (history, item) = Self.history(.text("a"), source: (nil, nil))
        let info = ClipboardInspectorInfo(item, in: history)
        #expect(info.sourceAppName == nil && info.sourceBundleID == nil)
    }

    @Test func textNumbersCountVietnameseLettersWordsAndLinesTheWayAPersonWould() {
        // Letters with accents, written in either form, are one character each.
        let composed = "tiếng Việt"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        #expect(ClipboardTextStats(composed) == ClipboardTextStats(characters: 10, words: 2, lines: 1))
        #expect(ClipboardTextStats(decomposed) == ClipboardTextStats(characters: 10, words: 2, lines: 1))
        #expect(ClipboardTextStats("") == ClipboardTextStats(characters: 0, words: 0, lines: 0))
        // A line break at the end does not start another line; blank lines in the middle count.
        #expect(ClipboardTextStats("a\nb\n") == ClipboardTextStats(characters: 4, words: 2, lines: 2))
        #expect(ClipboardTextStats("a\n\nb") == ClipboardTextStats(characters: 4, words: 2, lines: 3))
        #expect(ClipboardTextStats("a\r\nb\r\n") == ClipboardTextStats(characters: 4, words: 2, lines: 2))
        #expect(ClipboardTextStats("  \n \t ") == ClipboardTextStats(characters: 6, words: 0, lines: 2))
        #expect(ClipboardTextStats("👨‍👩‍👧 ok") == ClipboardTextStats(characters: 4, words: 2, lines: 1))
    }

    @Test func aLongTextIsCountedOffTheMainActorAndGivesTheSameNumbers() async {
        let repeats = ClipboardInspectorInfo.inlineLimit / 10
        let long = String(repeating: "Xin chào thế giới\n", count: repeats)
        #expect(long.utf8.count > ClipboardInspectorInfo.inlineLimit)
        let info = Self.info(of: .text(long))
        #expect(info.size == .largeText(byteCount: long.utf8.count))
        let loaded = await ClipboardTextStats.load(long)
        #expect(loaded == ClipboardTextStats(long))
        #expect(loaded.lines == repeats && loaded.words == 4 * repeats && loaded.characters == 18 * repeats)
    }

    @Test func aTextJustUnderTheLimitIsCountedAtOnce() {
        let text = String(repeating: "a", count: ClipboardInspectorInfo.inlineLimit)
        #expect(Self.info(of: .text(text)).size == .text(ClipboardTextStats(text)))
    }

    // MARK: Languages

    @Test func proseGetsTheLanguageItIsWrittenIn() {
        #expect(ClipboardTextLanguage.code(of: Self.vietnamese) == "vi")
        #expect(ClipboardTextLanguage.code(of: Self.english) == "en")
        #expect(Self.info(of: .text(Self.vietnamese)).language == .prose("Tiếng Việt"))
        #expect(Self.info(of: .text(Self.english)).language == .prose("Tiếng Anh"))
    }

    @Test func tooLittleToTellIsNoLanguage() {
        #expect(ClipboardTextLanguage.code(of: "ok") == nil)
        #expect(ClipboardTextLanguage.code(of: "123 456 789 0000 1111") == nil)
        #expect(ClipboardTextLanguage.code(of: "") == nil)
        #expect(Self.info(of: .text("ok")).language == nil)
    }

    @Test func fewLettersAreNotEnoughEvenWhenTheyLookLikeOneLanguage() {
        // Clear enough to the recognizer, but too short to name a language by.
        #expect(ClipboardTextLanguage.code(of: "Chào bạn") == nil)
    }

    @Test func lettersThatAreNoLanguageAtAllAreNotGivenOne() {
        #expect(ClipboardTextLanguage.code(of: "qzxv wkjh bnmq zxcvbnm lkjhgf") == nil)
    }

    @Test func onlyTheStartOfALongTextIsLookedAt() {
        // English for longer than the sample, then a megabyte of Vietnamese the recognizer never sees.
        let long = String(repeating: Self.english + " ", count: 20) + String(repeating: "Xin chào thế giới, hôm nay trời đẹp quá. ", count: 25_000)
        #expect(long.utf8.count > 1_000_000)
        #expect(ClipboardTextLanguage.code(of: long) == "en")
    }

    @Test func codeIsNamedByItsProgrammingLanguageNotItsWords() {
        let code = "func add(_ a: Int, _ b: Int) -> Int {\n    return a + b\n}\n"
        let info = Self.info(of: .text(code))
        #expect(info.language == .code(.swift))
        #expect(info.kindTitle == "Mã Swift")
        #expect(info.systemImage == ClipboardSearchTerms.codeSystemImage)
        #expect(info.size == .text(ClipboardTextStats(code)))
    }

    @Test func anItemThatIsNotProseHasNoNaturalLanguage() {
        #expect(Self.info(of: .link(URL(string: "https://example.com/the/quick/brown/fox/jumps/over/the/lazy/dog")!)).language == nil)
        #expect(Self.info(of: .color(hex: "#FF8800")).language == nil)
    }

    // MARK: The other kinds

    @Test func anImageHasItsPixelsAndBytes() {
        let info = Self.info(of: .image(ClipboardImage(fileName: "a.png", pixelWidth: 1920, pixelHeight: 1080, byteCount: 2_100_000)))
        #expect(info.kindTitle == "Ảnh")
        #expect(info.size == .image(pixelWidth: 1920, pixelHeight: 1080, byteCount: 2_100_000))
        #expect(info.language == nil)
        #expect(!info.canEdit)
    }

    @Test func filesHaveTheirCount() {
        let info = Self.info(of: .files([URL(fileURLWithPath: "/a/1.txt"), URL(fileURLWithPath: "/a/2.txt"), URL(fileURLWithPath: "/a/3.txt")]))
        #expect(info.kindTitle == "File")
        #expect(info.size == .files(count: 3))
        #expect(!info.canEdit)
    }

    @Test func aLinkAndAColourHaveTheLengthOfWhatTheyAre() {
        let link = Self.info(of: .link(URL(string: "https://example.com/a")!))
        #expect(link.kindTitle == "Link")
        #expect(link.size == .characters(21))
        #expect(link.canEdit)
        let color = Self.info(of: .color(hex: "#FF8800", original: "rgb(255, 136, 0)"))
        #expect(color.kindTitle == "Màu")
        #expect(color.size == .characters(16))
        #expect(!color.canEdit)
        #expect(Self.info(of: .color(hex: "#FF8800")).size == .characters(7))
    }

    @Test func aRichTextCanBeEditedAndIsCountedByItsPlainWords() {
        let info = Self.info(of: .richText(plain: "Bảng giá", rtf: Data("{\\rtf1 x}".utf8)))
        #expect(info.canEdit)
        #expect(info.size == .text(ClipboardTextStats(characters: 8, words: 2, lines: 1)))
    }

    // MARK: Boards

    @Test func theBoardsAnItemIsInAreNamedInTheOrderOfTheRow() {
        var (history, item) = Self.history(.text("a"))
        let first = history.createBoard(name: "Công việc")
        _ = history.createBoard(name: "Trống")
        let third = history.createBoard(name: "Cá nhân")
        history.pin(itemID: item.id, to: third)
        history.pin(itemID: item.id, to: first)
        item = history.items[0]
        #expect(ClipboardInspectorInfo(item, in: history).boards == ["Công việc", "Cá nhân"])
    }

    // MARK: What the inspector shows

    @Test func nothingFocusedShowsNothing() {
        let (history, _) = Self.history(.text("a"))
        #expect(ClipboardInspectorContent.make(for: nil, in: history, boardIsLocked: false) == .nothing)
    }

    @Test func anItemShowsItsFields() {
        let (history, item) = Self.history(.text("a"))
        #expect(ClipboardInspectorContent.make(for: item, in: history, boardIsLocked: false) == .item(ClipboardInspectorInfo(item, in: history)))
    }

    @Test func aLockedBoardOnShowShowsOnlyThatItIsLocked() {
        let (history, item) = Self.history(.text("bí mật"))
        #expect(ClipboardInspectorContent.make(for: nil, in: history, boardIsLocked: true) == .locked)
        #expect(ClipboardInspectorContent.make(for: item, in: history, boardIsLocked: true) == .locked)
    }

    @Test func anItemPinnedToAClosedBoardShowsOnlyThatItIsLocked() {
        var (history, item) = Self.history(.text("bí mật"))
        let board = history.createBoard(name: "Két")
        history.pin(itemID: item.id, to: board)
        history.boards[0].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: false)
        item = history.items[0]

        let content = ClipboardInspectorContent.make(for: item, in: history, boardIsLocked: false)

        #expect(content == .locked)
        // Nothing of the item is in what is shown: not even a count or a name.
        #expect(String(describing: content) == "locked")

        // Open, it is an ordinary item with its board named.
        history.boards[0].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: true)
        guard case .item(let info) = ClipboardInspectorContent.make(for: item, in: history, boardIsLocked: false) else {
            Issue.record("Expected the item's fields")
            return
        }
        #expect(info.boards == ["Két"])
    }

    // MARK: Words

    @Test func theDateIsWrittenWithTheDayAndTheTime() {
        let utc = TimeZone(identifier: "UTC")!
        let text = ClipboardInspectorFormat.date(Self.copied, locale: Locale(identifier: "vi_VN"), timeZone: utc)
        // 2027-01-15 08:00:00 UTC, which Vietnamese writes with the time first.
        #expect(text.contains("2027"))
        #expect(text.contains("8:00"))
        #expect(text.contains("15"))
        // In another zone the same moment is another hour.
        #expect(ClipboardInspectorFormat.date(Self.copied, locale: Locale(identifier: "vi_VN"), timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!).contains("15:00"))
    }

    @Test func theCountsAreWrittenInVietnamese() {
        #expect(ClipboardInspectorFormat.times(1) == "1 lần")
        #expect(ClipboardInspectorFormat.times(12) == "12 lần")
        #expect(ClipboardInspectorFormat.size(.text(ClipboardTextStats(characters: 1_234, words: 210, lines: 18)), locale: Locale(identifier: "vi_VN"))
            == "1.234 ký tự · 210 từ · 18 dòng")
        #expect(ClipboardInspectorFormat.size(.files(count: 3), locale: Locale(identifier: "vi_VN")) == "3 file")
        #expect(ClipboardInspectorFormat.size(.characters(7), locale: Locale(identifier: "vi_VN")) == "7 ký tự")
        let image = ClipboardInspectorFormat.size(.image(pixelWidth: 1920, pixelHeight: 1080, byteCount: 2_100_000), locale: Locale(identifier: "vi_VN"))
        #expect(image?.hasPrefix("1920 × 1080 px · ") == true)
        #expect(ClipboardInspectorFormat.size(.largeText(byteCount: 1_000_000), locale: Locale(identifier: "vi_VN")) == nil)
    }
}
