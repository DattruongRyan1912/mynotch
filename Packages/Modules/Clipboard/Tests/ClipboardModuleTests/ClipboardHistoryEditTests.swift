import Foundation
import Testing
@testable import ClipboardModule

/// How many times an item was copied, and the rules of editing one on the history as a value: replacing it keeps what it was,
/// saving it as a new item is an ordinary new copy, and neither ever touches a pasteboard.
@Suite struct ClipboardHistoryEditTests {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @discardableResult
    static func add(
        _ content: ClipboardContent, to history: inout ClipboardHistory, at offset: TimeInterval = 0,
        source: (bundleID: String?, name: String?) = ("com.apple.Notes", "Ghi chú")
    ) -> UUID {
        history.add(content, hash: ClipboardContent.hash(of: content), source: source, at: start + offset).id
    }

    /// Texts "một", "hai", "ba" copied in that order (so "ba" is on top), "hai" also pinned to a board.
    static func fixture() -> (history: ClipboardHistory, one: UUID, two: UUID, three: UUID, board: UUID) {
        var history = ClipboardHistory()
        let one = add(.text("một"), to: &history, at: 0)
        let two = add(.text("hai"), to: &history, at: 1)
        let three = add(.text("ba"), to: &history, at: 2)
        let board = history.createBoard(name: "Số")
        history.pin(itemID: two, to: board)
        return (history, one, two, three, board)
    }

    static func hash(_ content: ClipboardContent) -> String {
        ClipboardContent.hash(of: content)
    }

    // MARK: How many times it was copied

    @Test func aNewItemWasCopiedOnce() {
        var history = ClipboardHistory()
        let id = Self.add(.text("một"), to: &history)
        let item = history.items[0]
        #expect(item.id == id)
        #expect(item.timesCopied == 1)
        #expect(item.copyCount == nil)
    }

    @Test func eachRepeatedCopyCountsOnceMore() {
        var history = ClipboardHistory()
        Self.add(.text("một"), to: &history, at: 0)
        Self.add(.text("một"), to: &history, at: 5)
        #expect(history.items[0].timesCopied == 2)
        Self.add(.text("một"), to: &history, at: 9)
        #expect(history.items[0].timesCopied == 3)
        #expect(history.items.count == 1)
    }

    @Test func usingAnItemAgainIsNotAnotherCopy() {
        var history = ClipboardHistory()
        let id = Self.add(.text("một"), to: &history, at: 0)
        Self.add(.text("hai"), to: &history, at: 1)
        history.touch(id: id, at: Self.start + 10)
        #expect(history.items[0].id == id)
        #expect(history.items[0].timesCopied == 1)
    }

    @Test func theCountAndTheEditedFlagAreWrittenOnlyWhenTheyAreSet() throws {
        let plain = ClipboardItem(id: UUID(), content: .text("a"), contentHash: "h", copiedAt: Self.start)
        let plainJSON = try #require(String(data: JSONEncoder().encode(plain), encoding: .utf8))
        #expect(!plainJSON.contains("copyCount") && !plainJSON.contains("edited"))

        var counted = plain
        counted.copyCount = 4
        counted.edited = true
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: JSONEncoder().encode(counted))
        #expect(decoded.copyCount == 4 && decoded.timesCopied == 4)
        #expect(decoded.edited == true && decoded.isEdited)
        // A file from before there was either still reads, as one copy and not edited.
        let old = try JSONDecoder().decode(ClipboardItem.self, from: JSONEncoder().encode(plain))
        #expect(old.timesCopied == 1 && !old.isEdited)
    }

    @Test func theCountAndTheEditedFlagSurviveASealedBoard() throws {
        var item = ClipboardItem(id: UUID(), content: .text("bí mật"), contentHash: "h", copiedAt: Self.start, codeDetection: .notCode)
        item.copyCount = 5
        item.edited = true
        let sealed = try ClipboardVaultPayload.encode(ClipboardVaultPayload.Contents(items: [item], images: [:]))
        let opened = try ClipboardVaultPayload.decode(sealed)
        #expect(opened.items == [item])
        #expect(opened.items.first?.timesCopied == 5 && opened.items.first?.isEdited == true)
    }

    // MARK: What can be edited

    @Test func textsAndLinksCanBeEditedAndTheirWordsAreTheEditorsText() {
        var history = ClipboardHistory()
        let text = Self.add(.text("Xin chào"), to: &history, at: 0)
        let rich = Self.add(.richText(plain: "Bảng giá", rtf: Data("{\\rtf1 x}".utf8)), to: &history, at: 1)
        let link = Self.add(.link(URL(string: "https://example.com/a?b=1")!), to: &history, at: 2)
        let color = Self.add(.color(hex: "#FF8800"), to: &history, at: 3)
        let image = Self.add(
            .image(ClipboardImage(fileName: "a.png", pixelWidth: 1, pixelHeight: 1, byteCount: 1)), to: &history, at: 4
        )
        let files = Self.add(.files([URL(fileURLWithPath: "/tmp/a.txt")]), to: &history, at: 5)

        func item(_ id: UUID) -> ClipboardItem { history.items.first { $0.id == id }! }
        #expect(ClipboardEditing.text(of: item(text)) == "Xin chào")
        #expect(ClipboardEditing.text(of: item(rich)) == "Bảng giá")
        #expect(ClipboardEditing.text(of: item(link)) == "https://example.com/a?b=1")
        #expect(ClipboardEditing.text(of: item(color)) == nil)
        #expect(ClipboardEditing.text(of: item(image)) == nil)
        #expect(ClipboardEditing.text(of: item(files)) == nil)
        #expect([text, rich, link].allSatisfy(history.canEdit))
        #expect(![color, image, files].contains(where: history.canEdit))
        #expect(!history.canEdit(UUID()))
    }

    @Test func anItemOfAClosedBoardCannotBeEdited() {
        // The state a locked board never leaves its items in: still listed, but pinned to a board that is closed.
        var (history, _, two, _, board) = Self.fixture()
        #expect(history.canEdit(two))
        history.boards[0].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: false)
        #expect(!history.canEdit(two))
        #expect(history.applyEdit(to: two, content: .text("mới"), mode: .replace, at: Self.start + 50) == .locked)
        #expect(history.applyEdit(to: two, content: .text("mới"), mode: .saveAsNew, at: Self.start + 50) == .locked)
        #expect(history.items.contains { $0.content == .text("hai") })
        #expect(history.boards.first { $0.id == board }?.itemIDs == [two])
        // An open board is an ordinary place to edit in.
        history.boards[0].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: true)
        #expect(history.canEdit(two))
    }

    // MARK: Replacing

    @Test func replacingKeepsWhatTheItemWasAndDatesItNowOnTop() throws {
        var (history, one, two, three, board) = Self.fixture()
        history.items[1].copyCount = 3
        history.items[1].sensitive = true
        let before = history.items[1]

        let outcome = history.applyEdit(to: two, content: .text("hai mươi"), mode: .replace, at: Self.start + 100)

        #expect(outcome == .saved(two))
        // Used now: on top, dated now, as the history is always newest first.
        #expect(history.items.map(\.id) == [two, three, one])
        let after = history.items[0]
        #expect(after.id == before.id)
        #expect(after.content == .text("hai mươi"))
        #expect(after.contentHash == Self.hash(.text("hai mươi")))
        #expect(after.copiedAt == Self.start + 100 && after.copiedAt != before.copiedAt)
        #expect(history.items.map(\.copiedAt) == history.items.map(\.copiedAt).sorted(by: >))
        // The app that copied it, how often and whether it is a secret stay.
        #expect(after.sourceBundleID == "com.apple.Notes" && after.sourceAppName == "Ghi chú")
        #expect(after.timesCopied == 3)
        #expect(after.sensitive == true)
        #expect(after.isEdited)
        // Its pins stay too.
        #expect(history.boards.first { $0.id == board }?.itemIDs == [two])
    }

    @Test func replacingLooksAtTheNewWordsAgainForCode() throws {
        var history = ClipboardHistory()
        let id = Self.add(.text("một hai ba"), to: &history)
        #expect(history.items[0].codeLanguage == nil)

        let code = "func add(_ a: Int, _ b: Int) -> Int {\n    return a + b\n}\n"
        #expect(history.applyEdit(to: id, content: .text(code), mode: .replace, at: Self.start + 1) == .saved(id))
        #expect(history.items[0].codeLanguage == .swift)

        #expect(history.applyEdit(to: id, content: .text("lại là lời văn"), mode: .replace, at: Self.start + 2) == .saved(id))
        #expect(history.items[0].codeDetection == .notCode)
    }

    @Test func replacingATextWithALinkOrALinkWithTextFollowsWhatItBecame() {
        var history = ClipboardHistory()
        let id = Self.add(.link(URL(string: "https://example.com/a")!), to: &history)
        #expect(history.applyEdit(to: id, content: .text("không còn là link"), mode: .replace, at: Self.start + 1) == .saved(id))
        #expect(history.items[0].content.kind == .text)
        #expect(history.applyEdit(to: id, content: .link(URL(string: "https://example.com/b")!), mode: .replace, at: Self.start + 2) == .saved(id))
        #expect(history.items[0].content == .link(URL(string: "https://example.com/b")!))
        #expect(history.items[0].codeDetection == nil)
    }

    @Test func replacingARichTextLeavesPlainTextWithoutItsFormatting() {
        var history = ClipboardHistory()
        let id = Self.add(.richText(plain: "Bảng giá", rtf: Data("{\\rtf1 x}".utf8)), to: &history)
        #expect(history.applyEdit(to: id, content: .text("Bảng giá mới"), mode: .replace, at: Self.start + 1) == .saved(id))
        #expect(history.items[0].content == .text("Bảng giá mới"))
    }

    @Test func replacingWithTheSameWordsChangesNothing() {
        var (history, _, two, _, _) = Self.fixture()
        let before = history
        #expect(history.applyEdit(to: two, content: .text("hai"), mode: .replace, at: Self.start + 100) == .unchanged)
        #expect(history == before)
        #expect(!history.items[1].isEdited)
    }

    @Test func replacingWithWordsAnotherItemHasIsRefusedAndChangesNothing() {
        var (history, one, two, _, _) = Self.fixture()
        let before = history
        #expect(history.applyEdit(to: two, content: .text("một"), mode: .replace, at: Self.start + 100) == .duplicate(one))
        #expect(history == before)
    }

    @Test func replacingSomethingThatIsNotThereOrNotEditable() {
        var history = ClipboardHistory()
        let color = Self.add(.color(hex: "#FF8800"), to: &history)
        let before = history
        #expect(history.applyEdit(to: UUID(), content: .text("x"), mode: .replace, at: Self.start) == .missing)
        #expect(history.applyEdit(to: color, content: .text("x"), mode: .replace, at: Self.start) == .notEditable)
        #expect(history.applyEdit(to: color, content: .text("x"), mode: .saveAsNew, at: Self.start) == .notEditable)
        #expect(history == before)
    }

    // MARK: Saving as a new item

    @Test func savingAsNewAddsAnItemOnTopAndLeavesTheOriginalAlone() throws {
        var (history, one, two, three, board) = Self.fixture()
        let before = history.items

        let outcome = history.applyEdit(to: two, content: .text("hai mươi"), mode: .saveAsNew, at: Self.start + 100)

        guard case .saved(let newID) = outcome else {
            Issue.record("Expected a new item, got \(outcome)")
            return
        }
        #expect(newID != two)
        #expect(history.items.map(\.id) == [newID, three, two, one])
        #expect(Array(history.items.dropFirst()) == before)
        let new = history.items[0]
        #expect(new.content == .text("hai mươi"))
        #expect(new.copiedAt == Self.start + 100)
        // Written by nobody's copy: no app, and it is not an edit of anything.
        #expect(new.sourceBundleID == nil && new.sourceAppName == nil)
        #expect(!new.isEdited)
        #expect(new.timesCopied == 1)
        #expect(history.boards.first { $0.id == board }?.itemIDs == [two])
    }

    @Test func savingAsNewCarriesTheSecretFlagAlong() {
        var (history, _, two, _, _) = Self.fixture()
        history.items[1].sensitive = true
        guard case .saved(let newID) = history.applyEdit(to: two, content: .text("bí mật mới"), mode: .saveAsNew, at: Self.start + 100) else {
            Issue.record("Expected a new item")
            return
        }
        #expect(history.items.first { $0.id == newID }?.sensitive == true)
    }

    @Test func savingAsNewWithWordsAnotherItemHasMovesThatOneToTheTopKeepingItsSource() {
        var (history, one, two, three, _) = Self.fixture()
        history.items[2].copyCount = 2

        let outcome = history.applyEdit(to: two, content: .text("một"), mode: .saveAsNew, at: Self.start + 100)

        #expect(outcome == .saved(one))
        #expect(history.items.map(\.id) == [one, three, two])
        #expect(history.items[0].copiedAt == Self.start + 100)
        // Not a copy by any app: its source and its count stay.
        #expect(history.items[0].sourceAppName == "Ghi chú")
        #expect(history.items[0].timesCopied == 2)
    }

    @Test func savingAsNewFromAnItemOfAnOpenLockedBoardKeepsTheResultInThatBoard() throws {
        var (history, _, two, _, board) = Self.fixture()
        history.boards[0].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: true)

        guard case .saved(let newID) = history.applyEdit(to: two, content: .text("bí mật hai"), mode: .saveAsNew, at: Self.start + 100) else {
            Issue.record("Expected a new item")
            return
        }
        // A secret changed is as much a secret: it goes into the same board, so it is sealed with it and never written in the clear.
        #expect(history.boards.first { $0.id == board }?.itemIDs == [newID, two])
        #expect(!history.persistable.items.contains { $0.id == newID })
    }

    @Test func savingAsNewWordsWithNoOriginalLeftPinsNothingAndCarriesTheFlag() {
        var history = ClipboardHistory()
        let board = history.createBoard(name: "Số")
        Self.add(.text("khác"), to: &history, at: 0)
        let before = history.items

        let outcome = history.applyEdit(
            to: UUID(), content: .text("bản nháp"), mode: .saveAsNew, at: Self.start + 100, originalWasSensitive: true
        )

        guard case .saved(let newID) = outcome else {
            Issue.record("Expected a new item, got \(outcome)")
            return
        }
        #expect(history.items.map(\.id) == [newID] + before.map(\.id))
        let new = history.items[0]
        #expect(new.content == .text("bản nháp") && new.copiedAt == Self.start + 100)
        #expect(new.sensitive == true)
        #expect(new.sourceBundleID == nil && !new.isEdited)
        #expect(history.boards.first { $0.id == board }?.itemIDs == [])
    }

    @Test func withNoOriginalLeftOnlySavingAsNewIsPossibleAndOnlyWhenTheEditorKnowsIt() {
        var history = ClipboardHistory()
        Self.add(.text("khác"), to: &history, at: 0)
        let before = history
        #expect(history.applyEdit(to: UUID(), content: .text("x"), mode: .replace, at: Self.start, originalWasSensitive: false) == .missing)
        #expect(history.applyEdit(to: UUID(), content: .text("x"), mode: .saveAsNew, at: Self.start) == .missing)
        #expect(history == before)
    }

    @Test func withNoOriginalLeftWordsAnotherItemHasMoveThatItemUpAndPinNothing() {
        var (history, one, _, three, board) = Self.fixture()
        let outcome = history.applyEdit(to: UUID(), content: .text("một"), mode: .saveAsNew, at: Self.start + 100, originalWasSensitive: false)
        #expect(outcome == .saved(one))
        #expect(history.items.map(\.id).first == one)
        #expect(history.boards.first { $0.id == board }?.itemIDs.contains(one) == false)
        #expect(history.items.contains { $0.id == three })
    }

    // MARK: Saving as new when the words are another item's

    /// "một" is ordinary, "hai" and the secret "bí mật" are in the open board "Két", which has a lock.
    static func lockedFixture() -> (history: ClipboardHistory, ordinary: UUID, secret: UUID, other: UUID, vault: UUID, second: UUID) {
        var history = ClipboardHistory()
        let ordinary = add(.text("một"), to: &history, at: 0)
        let secret = add(.text("bí mật"), to: &history, at: 1)
        let other = add(.text("hai"), to: &history, at: 2)
        let vault = history.createBoard(name: "Két")
        let second = history.createBoard(name: "Két hai")
        history.pin(itemID: secret, to: vault)
        history.pin(itemID: other, to: second)
        history.boards[0].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: true)
        history.boards[1].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: true)
        return (history, ordinary, secret, other, vault, second)
    }

    @Test func aSaveFromASecretNeverPinsAnOrdinaryItemWithTheSameWordsIntoItsBoard() {
        var (history, ordinary, secret, _, vault, _) = Self.lockedFixture()
        let before = history

        #expect(history.applyEdit(to: secret, content: .text("một"), mode: .saveAsNew, at: Self.start + 100) == .duplicate(ordinary))

        // Nothing moved, nothing pinned: the ordinary item stays where everyone can see it.
        #expect(history == before)
        #expect(history.boards.first { $0.id == vault }?.itemIDs == [secret])
    }

    @Test func aSaveFromASecretNeverTakesAnItemOfAnotherLockedBoardIntoThisOne() {
        var (history, _, secret, other, vault, second) = Self.lockedFixture()
        let before = history

        #expect(history.applyEdit(to: secret, content: .text("hai"), mode: .saveAsNew, at: Self.start + 100) == .duplicate(other))

        #expect(history == before)
        #expect(history.boards.first { $0.id == vault }?.itemIDs == [secret])
        #expect(history.boards.first { $0.id == second }?.itemIDs == [other])
    }

    @Test func aSaveFromASecretWhoseWordsAreAlreadyInItsOwnBoardJustMovesThemUp() {
        var (history, _, secret, _, vault, _) = Self.lockedFixture()
        let twin = Self.add(.text("bí mật bản hai"), to: &history, at: 3)
        history.pin(itemID: twin, to: vault)

        let outcome = history.applyEdit(to: secret, content: .text("bí mật bản hai"), mode: .saveAsNew, at: Self.start + 100)

        #expect(outcome == .saved(twin))
        #expect(history.items.first?.id == twin)
        #expect(Set(history.boards.first { $0.id == vault }?.itemIDs ?? []) == [secret, twin])
    }

    @Test func aSaveFromAnOrdinaryItemWithWordsInALockedBoardMovesThatItemUpAndPinsNothing() {
        var (history, ordinary, secret, _, vault, _) = Self.lockedFixture()

        #expect(history.applyEdit(to: ordinary, content: .text("bí mật"), mode: .saveAsNew, at: Self.start + 100) == .saved(secret))

        #expect(history.boards.first { $0.id == vault }?.itemIDs == [secret])
        #expect(history.boards.filter { $0.itemIDs.contains(ordinary) }.isEmpty)
    }

    // MARK: What the words become

    @Test func theEditedWordsAreClassifiedLikeACopy() {
        func content(_ text: String, hashless: Bool = true) -> ClipboardContent? {
            guard case .content(let content) = ClipboardEditing.classify(text, colorsWithoutHash: hashless) else { return nil }
            return content
        }
        #expect(content("Xin chào\nthế giới") == .text("Xin chào\nthế giới"))
        #expect(content("  https://example.com/a  ") == .link(URL(string: "https://example.com/a")!))
        #expect(content("không phải link https://example.com") == .text("không phải link https://example.com"))
        #expect(content("#ff8800") == .color(hex: "#FF8800"))
        // Whitespace around the words is the user's to keep.
        #expect(content("  khoảng trắng  ") == .text("  khoảng trắng  "))
    }

    @Test func blankOrHugeWordsAreRefused() {
        #expect(ClipboardEditing.classify("", colorsWithoutHash: true) == .refused(.blank))
        #expect(ClipboardEditing.classify(" \n\t ", colorsWithoutHash: true) == .refused(.blank))
        let huge = String(repeating: "a", count: ClipboardClassifier.maxTextBytes + 1)
        #expect(ClipboardEditing.classify(huge, colorsWithoutHash: true) == .refused(.tooLarge))
        let large = String(repeating: "a", count: ClipboardClassifier.maxTextBytes)
        #expect(ClipboardEditing.classify(large, colorsWithoutHash: true) == .content(.text(large)))
    }
}
