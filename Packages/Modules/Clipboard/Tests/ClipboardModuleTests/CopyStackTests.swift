import Foundation
import Testing
@testable import ClipboardModule

/// The stack as a value: what it collects, which entry is next, and how the user edits it.
@Suite struct CopyStackTests {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)

    static func item(_ text: String) -> ClipboardItem {
        let content = ClipboardContent.text(text)
        return ClipboardItem(
            id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: date,
            sourceBundleID: "com.apple.Safari", sourceAppName: "Safari"
        )
    }

    static func stack(_ texts: String...) -> CopyStack {
        var stack = CopyStack()
        stack.start()
        for text in texts { stack.collect(item(text)) }
        return stack
    }

    static func texts(_ stack: CopyStack) -> [String] {
        stack.entries.compactMap { $0.item.content.plainText }
    }

    // MARK: When an item is changed

    @Test func anItemThatWasChangedIsReplacedWhereverTheStackHoldsIt() {
        var stack = Self.stack("một", "hai")
        let first = stack.entries[0]
        // The same item copied twice sits on the stack twice.
        stack.collect(first.item)
        var changed = first.item
        changed.content = .text("một nghìn")
        changed.contentHash = ClipboardContent.hash(of: changed.content)

        stack.refresh(with: changed)

        #expect(Self.texts(stack) == ["một nghìn", "hai", "một nghìn"])
        // The entries keep their own ids and places.
        #expect(stack.entries[0].id == first.id)
        #expect(stack.entries.map(\.item.id) == [first.item.id, stack.entries[1].item.id, first.item.id])
        #expect(stack.isOn)
    }

    @Test func changingAnItemThatIsNotOnTheStackChangesNothing() {
        var stack = Self.stack("một")
        let before = stack
        stack.refresh(with: Self.item("khác"))
        #expect(stack == before)
    }

    // MARK: Collecting

    @Test func aNewStackIsOffAndEmpty() {
        let stack = CopyStack()
        #expect(!stack.isOn)
        #expect(stack.entries.isEmpty)
    }

    @Test func collectsInTheOrderOfTheCopiesWhileOn() {
        let stack = Self.stack("một", "hai", "ba")
        #expect(Self.texts(stack) == ["một", "hai", "ba"])
    }

    @Test func collectsNothingWhileOff() {
        var stack = CopyStack()
        let collected = stack.collect(Self.item("một"))
        #expect(!collected)
        #expect(stack.entries.isEmpty)
    }

    @Test func theSameCopyTwiceIsTwoEntriesWithTheirOwnIdentity() {
        var stack = CopyStack()
        stack.start()
        let item = Self.item("một")
        stack.collect(item)
        stack.collect(item)

        #expect(stack.entries.count == 2)
        #expect(Set(stack.entries.map(\.id)).count == 2)
    }

    @Test func startingAStackThatIsAlreadyOnKeepsWhatItHolds() {
        var stack = Self.stack("một")
        stack.start()
        #expect(Self.texts(stack) == ["một"])
    }

    @Test func stoppingEmptiesTheStack() {
        var stack = Self.stack("một", "hai")
        stack.stop()
        #expect(!stack.isOn)
        #expect(stack.entries.isEmpty)
    }

    // MARK: Which one is next

    @Test func firstInPastesTheOldestCopyFirst() {
        let stack = Self.stack("một", "hai", "ba")
        #expect(stack.next(.firstIn)?.item.content.plainText == "một")
    }

    @Test func lastInPastesTheNewestCopyFirst() {
        let stack = Self.stack("một", "hai", "ba")
        #expect(stack.next(.lastIn)?.item.content.plainText == "ba")
    }

    @Test func nothingIsNextInAnEmptyStack() {
        var stack = CopyStack()
        stack.start()
        #expect(stack.next(.firstIn) == nil)
        #expect(stack.next(.lastIn) == nil)
    }

    @Test func removingTheNextEntryAdvancesEitherOrder() throws {
        var first = Self.stack("một", "hai", "ba")
        first.remove(id: try #require(first.next(.firstIn)).id)
        #expect(first.next(.firstIn)?.item.content.plainText == "hai")

        var last = Self.stack("một", "hai", "ba")
        last.remove(id: try #require(last.next(.lastIn)).id)
        #expect(last.next(.lastIn)?.item.content.plainText == "hai")
    }

    // MARK: Editing

    @Test func removingAnEntryLeavesTheOthersInOrder() throws {
        var stack = Self.stack("một", "hai", "ba")
        stack.remove(id: stack.entries[1].id)
        #expect(Self.texts(stack) == ["một", "ba"])
    }

    @Test func removingAnUnknownEntryChangesNothing() {
        var stack = Self.stack("một")
        let before = stack
        stack.remove(id: UUID())
        #expect(stack == before)
    }

    @Test func entriesThatCannotBeUsedCanBeDroppedByCondition() {
        var stack = Self.stack("một", "hai", "ba")
        stack.removeEntries { $0.item.content.plainText != "hai" }
        #expect(Self.texts(stack) == ["hai"])
    }

    @Test func movingAnEntryReordersIt() {
        var stack = Self.stack("một", "hai", "ba")
        // The way a list's drag reports it: row 0 dropped after row 2.
        stack.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(Self.texts(stack) == ["hai", "ba", "một"])

        stack.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(Self.texts(stack) == ["một", "hai", "ba"])
    }

    @Test func clearingEmptiesTheStackButKeepsItOn() {
        var stack = Self.stack("một", "hai")
        stack.clear()
        #expect(stack.isOn)
        #expect(stack.entries.isEmpty)
    }

    // MARK: Disk

    @Test func aStackSurvivesEncodingAndDecoding() throws {
        let stack = Self.stack("một", "hai")
        let decoded = try JSONDecoder().decode(CopyStack.self, from: JSONEncoder().encode(stack))
        #expect(decoded == stack)
        #expect(decoded.isOn)
    }

    @Test func aFileThatSaysOffNeverBringsEntriesBack() throws {
        var stack = Self.stack("một")
        let data = try JSONEncoder().encode(stack)
        let json = try #require(String(data: data, encoding: .utf8)).replacing("\"isOn\":true", with: "\"isOn\":false")
        stack.stop()

        let decoded = try JSONDecoder().decode(CopyStack.self, from: Data(json.utf8))
        #expect(decoded == stack)
    }

    @Test func theOrderSettingHasTwoValuesAndFirstInIsTheDefault() {
        #expect(CopyStackOrder.allCases == [.firstIn, .lastIn])
    }
}
