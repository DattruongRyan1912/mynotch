import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ClipboardModule

/// The rules of locking a board on the history as a value, and what of it may be written to disk.
@Suite final class ClipboardBoardLockHistoryTests {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @discardableResult
    static func add(_ text: String, to history: inout ClipboardHistory, at offset: TimeInterval = 0) -> UUID {
        let content = ClipboardContent.text(text)
        return history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: start + offset).id
    }

    /// Four texts, "bí mật 1" and "bí mật 2" pinned to the board "Két" and the others loose.
    static func fixture() -> (history: ClipboardHistory, board: UUID, secrets: [UUID], loose: [UUID]) {
        var history = ClipboardHistory()
        let secrets = [add("bí mật 1", to: &history, at: 0), add("bí mật 2", to: &history, at: 1)]
        let loose = [add("công khai 1", to: &history, at: 2), add("công khai 2", to: &history, at: 3)]
        let board = history.createBoard(name: "Két")
        history.pin(itemID: secrets[0], to: board)
        history.pin(itemID: secrets[1], to: board)
        return (history, board, secrets, loose)
    }

    // MARK: Locking

    @Test func lockingTakesTheItemsOutOfTheHistoryAndKeepsTheCount() throws {
        var (history, board, secrets, loose) = Self.fixture()
        let removed = history.lockBoard(id: board, method: .password)

        #expect(Set(removed.map(\.id)) == Set(secrets))
        #expect(history.items.map(\.id) == loose.reversed())
        let locked = try #require(history.boards.first)
        #expect(locked.itemIDs.isEmpty)
        #expect(locked.lock == ClipboardBoardLock(method: .password, itemCount: 2, isUnlocked: false))
        #expect(locked.isLocked && locked.isProtected)
        #expect(locked.shownItemCount == 2)
        #expect(locked.name == "Két")
    }

    @Test func itemsComeBackInTheOrderOfThePins() {
        var (history, board, secrets, _) = Self.fixture()
        // The newest pin goes first.
        #expect(history.boards[0].itemIDs == [secrets[1], secrets[0]])
        #expect(history.lockBoard(id: board, method: .password).map(\.id) == [secrets[1], secrets[0]])
    }

    @Test func anItemAlsoPinnedToAnotherBoardLeavesItToo() throws {
        var (history, board, secrets, _) = Self.fixture()
        let other = history.createBoard(name: "Khác")
        history.pin(itemID: secrets[0], to: other)

        _ = history.lockBoard(id: board, method: .password)

        // The only copy in the clear would otherwise stay in the history, readable.
        #expect(history.boards.first { $0.id == other }?.itemIDs == [])
        #expect(!history.items.contains { $0.id == secrets[0] })
    }

    @Test func lockingABoardWithNoItemsOrAnUnknownBoard() {
        var history = ClipboardHistory()
        let board = history.createBoard(name: "Trống")
        #expect(history.lockBoard(id: board, method: .touchID).isEmpty)
        #expect(history.boards[0].lock == ClipboardBoardLock(method: .touchID, itemCount: 0, isUnlocked: false))
        #expect(history.lockBoard(id: UUID(), method: .password).isEmpty)
        #expect(history.boards.count == 1)
    }

    @Test func aPinThatPointsAtNothingIsNotCounted() {
        var (history, board, _, _) = Self.fixture()
        history.boards[0].itemIDs.append(UUID())
        _ = history.lockBoard(id: board, method: .password)
        #expect(history.boards[0].lock?.itemCount == 2)
    }

    // MARK: Opening

    @Test func openingPutsTheItemsBackPinnedInTheirOrder() throws {
        var (history, board, secrets, loose) = Self.fixture()
        let sealed = history.lockBoard(id: board, method: .password)

        let ids = history.unlockBoard(id: board, with: sealed)

        #expect(ids == [secrets[1], secrets[0]])
        #expect(Set(history.items.map(\.id)) == Set(secrets + loose))
        #expect(history.boards[0].itemIDs == [secrets[1], secrets[0]])
        #expect(history.boards[0].lock == ClipboardBoardLock(method: .password, itemCount: 2, isUnlocked: true))
        #expect(!history.boards[0].isLocked && history.boards[0].isProtected)
    }

    @Test func theItemsGoBackWhereTheirDatesPutThem() {
        var (history, board, secrets, _) = Self.fixture()
        let sealed = history.lockBoard(id: board, method: .password)
        _ = history.unlockBoard(id: board, with: sealed)
        // Dates 0, 1 (secrets) and 2, 3 (loose): newest first.
        #expect(history.items.map(\.copiedAt) == [3, 2, 1, 0].map { Self.start + $0 })
        #expect(history.items.map(\.id).suffix(2) == [secrets[1], secrets[0]])
    }

    @Test func aCopyMadeWhileLockedIsNotDuplicatedWhenOpening() throws {
        var (history, board, secrets, _) = Self.fixture()
        let sealed = history.lockBoard(id: board, method: .password)
        // The same words copied again while the board is closed make a new, ordinary item.
        let again = Self.add("bí mật 1", to: &history, at: 50)

        let ids = history.unlockBoard(id: board, with: sealed)

        #expect(ids == [secrets[1], again])
        #expect(history.items.filter { $0.contentHash == sealed.last!.contentHash }.count == 1)
        #expect(history.boards[0].itemIDs == [secrets[1], again])
    }

    @Test func openingABoardThatIsNotLockedChangesNothing() {
        var (history, board, _, _) = Self.fixture()
        let before = history
        #expect(history.unlockBoard(id: board, with: []).isEmpty)
        #expect(history == before)
    }

    // MARK: Pinning

    @Test func nothingCanBePinnedToALockedBoardButToAnOpenOne() throws {
        var (history, board, _, loose) = Self.fixture()
        let sealed = history.lockBoard(id: board, method: .password)

        history.pin(itemID: loose[0], to: board)
        #expect(history.boards[0].itemIDs.isEmpty)

        _ = history.unlockBoard(id: board, with: sealed)
        history.pin(itemID: loose[0], to: board)
        #expect(history.boards[0].itemIDs.first == loose[0])
    }

    // MARK: Removing the lock and deleting

    @Test func removingTheLockLeavesTheItemsPinnedAndOrdinary() {
        var (history, board, secrets, _) = Self.fixture()
        let sealed = history.lockBoard(id: board, method: .password)
        _ = history.unlockBoard(id: board, with: sealed)

        history.removeLock(id: board)

        #expect(history.boards[0].lock == nil)
        #expect(history.boards[0].itemIDs == [secrets[1], secrets[0]])
        #expect(history.persistable == history)
    }

    @Test func deletingAProtectedBoardDeletesItsItems() throws {
        var (history, board, secrets, loose) = Self.fixture()
        let sealed = history.lockBoard(id: board, method: .password)
        _ = history.unlockBoard(id: board, with: sealed)

        let removed = history.deleteProtectedBoard(id: board)

        #expect(Set(removed.map(\.id)) == Set(secrets))
        #expect(history.boards.isEmpty)
        #expect(Set(history.items.map(\.id)) == Set(loose))
    }

    @Test func deletingALockedBoardHasNoItemsInMemoryToRemove() {
        var (history, board, _, loose) = Self.fixture()
        _ = history.lockBoard(id: board, method: .password)
        #expect(history.deleteProtectedBoard(id: board).isEmpty)
        #expect(history.boards.isEmpty)
        #expect(Set(history.items.map(\.id)) == Set(loose))
    }

    // MARK: What may reach the disk

    @Test func anOpenBoardsItemsAreNotWrittenAndItsPinsAreEmptied() throws {
        var (history, board, secrets, loose) = Self.fixture()
        let other = history.createBoard(name: "Khác")
        history.pin(itemID: loose[0], to: other)
        let sealed = history.lockBoard(id: board, method: .password)
        _ = history.unlockBoard(id: board, with: sealed)
        history.pin(itemID: secrets[0], to: other)

        let written = history.persistable

        #expect(Set(written.items.map(\.id)) == Set(loose))
        #expect(written.boards.first { $0.id == board }?.itemIDs == [])
        // A pin to an item that is not written would point at nothing.
        #expect(written.boards.first { $0.id == other }?.itemIDs == [loose[0]])
        // And the history in memory is untouched.
        #expect(history.items.count == 4)
    }

    @Test func aHistoryWithNoLockIsWrittenAsItIs() {
        let (history, _, _, _) = Self.fixture()
        #expect(history.persistable == history)
    }

    @Test func theLockIsNeverWrittenToBoardsJSON() throws {
        var (history, board, _, _) = Self.fixture()
        _ = history.lockBoard(id: board, method: .touchID)
        let json = String(decoding: try JSONEncoder().encode(history.boards), as: UTF8.self)
        #expect(!json.contains("lock") && !json.contains("touchID") && !json.contains("itemCount"))
        #expect(try JSONDecoder().decode([ClipboardBoard].self, from: Data(json.utf8)).first?.lock == nil)
    }

    // MARK: The store never writes them

    let directory = FileManager.default.temporaryDirectory
        .appending(path: "ClipboardBoardLockHistoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func theStoreWritesNoItemOfAnOpenLockedBoard() async throws {
        var (history, board, secrets, _) = Self.fixture()
        let sealed = history.lockBoard(id: board, method: .password)
        _ = history.unlockBoard(id: board, with: sealed)
        let store = ClipboardStore(directory: directory, scheduler: ManualScheduler(), logger: Log.logger(category: "ClipboardBoardLockHistoryTests"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = store.load()

        store.scheduleSave(history)
        await store.flush()

        for name in ["history.json", "boards.json"] {
            let text = try String(contentsOf: directory.appending(path: name), encoding: .utf8)
            #expect(!text.contains("bí mật"), "\(name) holds the text of a locked board")
            #expect(!text.contains(secrets[0].uuidString), "\(name) holds the id of an item of a locked board")
        }
        let reloaded = store.load()
        #expect(reloaded.boards.map(\.name) == ["Két"])
        #expect(reloaded.items.count == 2)
    }
}
