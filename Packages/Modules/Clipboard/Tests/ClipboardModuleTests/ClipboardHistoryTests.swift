import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardHistoryTests {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let hour: TimeInterval = 60 * 60
    static let day: TimeInterval = 24 * hour

    static func image(_ name: String, bytes: Int) -> ClipboardContent {
        .image(ClipboardImage(fileName: "\(name).png", pixelWidth: 1, pixelHeight: 1, byteCount: bytes))
    }

    /// Adds `content` copied from TextEdit `offset` seconds after `start`.
    @discardableResult
    static func add(_ content: ClipboardContent, to history: inout ClipboardHistory, at offset: TimeInterval) -> UUID {
        history.add(
            content, hash: ClipboardContent.hash(of: content),
            source: (bundleID: "com.apple.TextEdit", name: "TextEdit"), at: start.addingTimeInterval(offset)
        ).id
    }

    /// History holding `contents` given oldest first, one second apart, so it lists them newest first.
    static func history(_ contents: [ClipboardContent], from offset: TimeInterval = 0) -> (ClipboardHistory, [UUID]) {
        var history = ClipboardHistory()
        let ids = contents.enumerated().map { add($1, to: &history, at: offset + TimeInterval($0)) }
        return (history, ids)
    }

    @Test func addInsertsNewItemsNewestFirst() throws {
        var history = ClipboardHistory()
        let first = history.add(.text("a"), hash: "hash-a", source: (bundleID: "com.apple.Safari", name: "Safari"), at: Self.start)
        let second = history.add(.text("b"), hash: "hash-b", source: (bundleID: nil, name: nil), at: Self.start + 1)
        guard case .inserted(let firstID) = first, case .inserted(let secondID) = second else {
            Issue.record("Expected two insertions, got \(first) and \(second)")
            return
        }
        #expect(first.id == firstID && second.id == secondID && firstID != secondID)
        #expect(history.items.map(\.id) == [secondID, firstID])
        #expect(history.items[1] == ClipboardItem(
            id: firstID, content: .text("a"), contentHash: "hash-a", copiedAt: Self.start,
            sourceBundleID: "com.apple.Safari", sourceAppName: "Safari", codeDetection: .notCode, sensitive: false
        ))
        #expect(history.items[0].sourceBundleID == nil && history.items[0].sourceAppName == nil)
    }

    @Test func addingTheSameHashMovesTheItemToTheTop() throws {
        var history = ClipboardHistory()
        let rtf = Data("{\\rtf1 Bold}".utf8)
        let original = Self.add(.text("Bold"), to: &history, at: 0)
        let other = Self.add(.text("other"), to: &history, at: 1)
        let result = history.add(
            .richText(plain: "Bold", rtf: rtf), hash: ClipboardContent.hash(of: .text("Bold")),
            source: (bundleID: "com.apple.iWork.Pages", name: "Pages"), at: Self.start + 5
        )
        #expect(result == .moved(original))
        #expect(result.id == original)
        #expect(history.items.map(\.id) == [original, other])
        #expect(history.items[0] == ClipboardItem(
            id: original, content: .richText(plain: "Bold", rtf: rtf), contentHash: ClipboardContent.hash(of: .text("Bold")),
            copiedAt: Self.start + 5, sourceBundleID: "com.apple.iWork.Pages", sourceAppName: "Pages", codeDetection: .notCode,
            sensitive: false
        ))
    }

    @Test func touchMovesTheItemToTheTopWithANewDate() {
        var (history, ids) = Self.history([.text("a"), .text("b"), .text("c")])
        history.touch(id: ids[0], at: Self.start + 60)
        #expect(history.items.map(\.id) == [ids[0], ids[2], ids[1]])
        #expect(history.items[0].copiedAt == Self.start + 60)
        let before = history
        history.touch(id: UUID(), at: Self.start + 120)
        #expect(history == before)
    }

    @Test func removeReturnsTheItemsAndUnpinsThem() {
        var (history, ids) = Self.history([.text("a"), Self.image("b", bytes: 10), .text("c")])
        let work = history.createBoard(name: "Công việc")
        let home = history.createBoard(name: "Nhà")
        history.pin(itemID: ids[1], to: work)
        history.pin(itemID: ids[2], to: work)
        history.pin(itemID: ids[1], to: home)
        let removed = history.remove(ids: [ids[1], ids[0], UUID()])
        #expect(removed.map(\.id) == [ids[1], ids[0]])
        #expect(history.items.map(\.id) == [ids[2]])
        #expect(history.boards.map(\.itemIDs) == [[ids[2]], []])
        #expect(!history.isPinned(ids[1]))
    }

    @Test func clearNewerThanACutoffKeepsPinnedAndOlderItems() {
        var (history, ids) = Self.history([.text("old"), .text("at cutoff"), .text("pinned"), .text("new"), .text("newest")])
        let board = history.createBoard(name: "Ghim")
        history.pin(itemID: ids[2], to: board)
        let removed = history.clear(newerThan: Self.start + 1)
        #expect(removed.map(\.id) == [ids[4], ids[3]])
        #expect(history.items.map(\.id) == [ids[2], ids[1], ids[0]])
        #expect(history.boards[0].itemIDs == [ids[2]])
    }

    @Test func clearingEverythingKeepsPinnedItems() {
        var (history, ids) = Self.history([.text("a"), .text("b"), .text("c")])
        let board = history.createBoard(name: "Ghim")
        history.pin(itemID: ids[1], to: board)
        let removed = history.clear(newerThan: nil)
        #expect(removed.map(\.id) == [ids[2], ids[0]])
        #expect(history.items.map(\.id) == [ids[1]])
    }

    @Test func pruneByCountRemovesTheOldestUnpinnedItems() {
        var (history, ids) = Self.history([.text("a"), .text("b"), .text("c"), .text("d"), .text("e")])
        let board = history.createBoard(name: "Ghim")
        history.pin(itemID: ids[0], to: board)
        history.pin(itemID: ids[2], to: board)
        var unchanged = history
        // Only the three unpinned items count toward the limit.
        #expect(unchanged.prune(limit: 3, retention: .forever, imageByteLimit: .max, now: Self.start + 10) == [])
        let removed = history.prune(limit: 1, retention: .forever, imageByteLimit: .max, now: Self.start + 10)
        #expect(removed.map(\.id) == [ids[1], ids[3]])
        #expect(history.items.map(\.id) == [ids[4], ids[2], ids[0]])
    }

    @Test func morePinnedItemsThanTheLimitStillKeepNewUnpinnedItems() {
        var (history, ids) = Self.history([.text("a"), .text("b"), .text("c"), .text("d"), .text("e"), .text("f")])
        let board = history.createBoard(name: "Ghim")
        for id in ids[..<3] { history.pin(itemID: id, to: board) }
        let removed = history.prune(limit: 2, retention: .forever, imageByteLimit: .max, now: Self.start + 10)
        #expect(removed.map(\.id) == [ids[3]])
        #expect(history.items.map(\.id) == [ids[5], ids[4], ids[2], ids[1], ids[0]])
    }

    @Test func pruneByAgeRemovesUnpinnedItemsOlderThanTheRetention() {
        var history = ClipboardHistory()
        let expired = Self.add(.text("expired"), to: &history, at: 0)
        let pinned = Self.add(.text("pinned"), to: &history, at: 1)
        let atCutoff = Self.add(.text("at cutoff"), to: &history, at: Self.day)
        let fresh = Self.add(.text("fresh"), to: &history, at: 1.5 * Self.day)
        let board = history.createBoard(name: "Ghim")
        history.pin(itemID: pinned, to: board)
        var forever = history
        let now = Self.start + 2 * Self.day

        #expect(forever.prune(limit: 100, retention: .forever, imageByteLimit: .max, now: now) == [])
        let removed = history.prune(limit: 100, retention: .day, imageByteLimit: .max, now: now)
        #expect(removed.map(\.id) == [expired])
        #expect(history.items.map(\.id) == [fresh, atCutoff, pinned])
    }

    @Test func pruneByImageBytesRemovesTheOldestUnpinnedImages() {
        var (history, ids) = Self.history([
            Self.image("oldest", bytes: 100), Self.image("old", bytes: 100), .text("text"),
            Self.image("pinned", bytes: 100), Self.image("new", bytes: 100),
        ])
        let board = history.createBoard(name: "Ghim")
        history.pin(itemID: ids[3], to: board)
        let removed = history.prune(limit: 100, retention: .forever, imageByteLimit: 150, now: Self.start + 10)
        #expect(removed.map(\.id) == [ids[0], ids[1]])
        #expect(history.items.map(\.id) == [ids[4], ids[3], ids[2]])
    }

    @Test func imageBytesExactlyAtTheLimitAreKept() {
        var (history, ids) = Self.history([Self.image("a", bytes: 100), Self.image("b", bytes: 150)])
        var atLimit = history
        #expect(atLimit.prune(limit: 100, retention: .forever, imageByteLimit: 250, now: Self.start + 10) == [])
        #expect(history.prune(limit: 100, retention: .forever, imageByteLimit: 249, now: Self.start + 10).map(\.id) == [ids[0]])
    }

    @Test func pinnedImagesDoNotCountTowardTheByteLimit() {
        var (history, ids) = Self.history([Self.image("pinned", bytes: 300), Self.image("b", bytes: 100), .text("text")])
        let board = history.createBoard(name: "Ghim")
        history.pin(itemID: ids[0], to: board)
        #expect(history.prune(limit: 100, retention: .forever, imageByteLimit: 250, now: Self.start + 10) == [])
        let removed = history.prune(limit: 100, retention: .forever, imageByteLimit: 50, now: Self.start + 10)
        #expect(removed.map(\.id) == [ids[1]])
        #expect(history.items.map(\.id) == [ids[2], ids[0]])
    }

    @Test func pruneAppliesCountThenAgeThenImageBytes() {
        let now = Self.start + 10 * Self.day
        var history = ClipboardHistory()
        let beyondLimit = Self.add(.text("beyond limit"), to: &history, at: 6 * Self.day)
        let expired = Self.add(.text("expired"), to: &history, at: 7 * Self.day)
        let oldImage = Self.add(Self.image("old", bytes: 300), to: &history, at: 10 * Self.day - 3 * Self.hour)
        let text = Self.add(.text("text"), to: &history, at: 10 * Self.day - 2 * Self.hour)
        let newImage = Self.add(Self.image("new", bytes: 300), to: &history, at: 10 * Self.day - Self.hour)

        let removed = history.prune(limit: 4, retention: .day, imageByteLimit: 400, now: now)
        #expect(removed.map(\.id) == [beyondLimit, expired, oldImage])
        #expect(history.items.map(\.id) == [newImage, text])
        #expect(history.prune(limit: 4, retention: .day, imageByteLimit: 400, now: now) == [])
    }

    @Test func createAndRenameBoards() {
        var history = ClipboardHistory()
        let work = history.createBoard(name: "Công việc")
        let code = history.createBoard(name: "Code", systemImage: "chevron.left.forwardslash.chevron.right")
        #expect(history.boards == [
            ClipboardBoard(id: work, name: "Công việc", systemImage: "tray.full", itemIDs: []),
            ClipboardBoard(id: code, name: "Code", systemImage: "chevron.left.forwardslash.chevron.right", itemIDs: []),
        ])
        history.renameBoard(id: work, name: "Việc")
        #expect(history.boards.map(\.name) == ["Việc", "Code"])
    }

    @Test func pinPutsTheNewestPinFirstWithoutDuplicates() {
        var (history, ids) = Self.history([.text("a"), .text("b")])
        let board = history.createBoard(name: "Ghim")
        history.pin(itemID: ids[0], to: board)
        history.pin(itemID: ids[1], to: board)
        history.pin(itemID: ids[0], to: board)
        #expect(history.boards[0].itemIDs == [ids[1], ids[0]])
        // Unknown items or boards change nothing.
        history.pin(itemID: UUID(), to: board)
        history.pin(itemID: ids[0], to: UUID())
        #expect(history.boards[0].itemIDs == [ids[1], ids[0]])
    }

    @Test func unpinAndPinnedQueries() {
        var (history, ids) = Self.history([.text("a"), .text("b")])
        let work = history.createBoard(name: "Công việc")
        let home = history.createBoard(name: "Nhà")
        history.pin(itemID: ids[0], to: work)
        history.pin(itemID: ids[0], to: home)
        #expect(history.isPinned(ids[0]) && !history.isPinned(ids[1]))
        #expect(history.boards(containing: ids[0]).map(\.id) == [work, home])
        #expect(history.boards(containing: ids[1]).isEmpty)

        history.unpin(itemID: ids[0], from: work)
        #expect(history.boards(containing: ids[0]).map(\.id) == [home])
        history.unpin(itemID: ids[0], from: home)
        #expect(!history.isPinned(ids[0]))
    }

    @Test func deleteBoardKeepsItsItemsUnpinned() {
        var (history, ids) = Self.history([.text("a"), .text("b")])
        let work = history.createBoard(name: "Công việc")
        let home = history.createBoard(name: "Nhà")
        history.pin(itemID: ids[0], to: work)
        history.deleteBoard(id: work)
        #expect(history.boards.map(\.id) == [home])
        #expect(history.items.map(\.id) == [ids[1], ids[0]])
        #expect(!history.isPinned(ids[0]))
        #expect(history.prune(limit: 1, retention: .forever, imageByteLimit: .max, now: Self.start + 10).map(\.id) == [ids[0]])
    }

    @Test func historyRoundTripsThroughJSON() throws {
        var (history, ids) = Self.history([.text("Xin chào"), .link(URL(string: "https://example.com")!), Self.image("a", bytes: 10)])
        let board = history.createBoard(name: "Công việc", systemImage: "briefcase")
        history.pin(itemID: ids[1], to: board)
        let decoded = try JSONDecoder().decode(ClipboardHistory.self, from: JSONEncoder().encode(history))
        #expect(decoded == history)
    }

    /// Pins the stored shape: renaming a property must not silently orphan saved history.
    static let goldenJSON = """
    {
      "boards" : [
        {
          "id" : "00000000-0000-0000-0000-0000000000B1",
          "itemIDs" : [
            "00000000-0000-0000-0000-000000000002"
          ],
          "name" : "Công việc",
          "systemImage" : "tray.full"
        }
      ],
      "items" : [
        {
          "content" : {
            "link" : {
              "_0" : "https://example.com/a"
            }
          },
          "contentHash" : "hash-link",
          "copiedAt" : 800000060,
          "id" : "00000000-0000-0000-0000-000000000002"
        },
        {
          "content" : {
            "text" : {
              "_0" : "Xin chào"
            }
          },
          "contentHash" : "hash-text",
          "copiedAt" : 800000000,
          "id" : "00000000-0000-0000-0000-000000000001",
          "sourceAppName" : "Safari",
          "sourceBundleID" : "com.apple.Safari"
        }
      ]
    }
    """

    @Test func historyMatchesTheGoldenJSON() throws {
        let textID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let linkID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let boardID = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000B1"))
        let history = ClipboardHistory(
            items: [
                ClipboardItem(
                    id: linkID, content: .link(URL(string: "https://example.com/a")!), contentHash: "hash-link",
                    copiedAt: Self.start + 60, sourceBundleID: nil, sourceAppName: nil
                ),
                ClipboardItem(
                    id: textID, content: .text("Xin chào"), contentHash: "hash-text",
                    copiedAt: Self.start, sourceBundleID: "com.apple.Safari", sourceAppName: "Safari"
                ),
            ],
            boards: [ClipboardBoard(id: boardID, name: "Công việc", systemImage: "tray.full", itemIDs: [linkID])]
        )
        #expect(try JSONDecoder().decode(ClipboardHistory.self, from: Data(Self.goldenJSON.utf8)) == history)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        #expect(String(decoding: try encoder.encode(history), as: UTF8.self) == Self.goldenJSON)
    }

    @Test func missingArraysDecodeAsEmpty() throws {
        #expect(try JSONDecoder().decode(ClipboardHistory.self, from: Data("{}".utf8)) == ClipboardHistory())
        let boardOnly = #"{"boards": [{"id": "00000000-0000-0000-0000-0000000000B1", "name": "A", "systemImage": "tray.full", "itemIDs": []}]}"#
        let decoded = try JSONDecoder().decode(ClipboardHistory.self, from: Data(boardOnly.utf8))
        #expect(decoded.items.isEmpty && decoded.boards.map(\.name) == ["A"])
    }

    @Test func removeDanglingPinsDropsIDsMissingFromItems() {
        var (history, ids) = Self.history([.text("a"), .text("b")])
        let missing = UUID()
        history.boards = [
            ClipboardBoard(id: UUID(), name: "A", systemImage: "tray.full", itemIDs: [missing, ids[1], ids[0]]),
            ClipboardBoard(id: UUID(), name: "B", systemImage: "tray.full", itemIDs: [missing]),
        ]
        history.removeDanglingPins()
        #expect(history.boards.map(\.itemIDs) == [[ids[1], ids[0]], []])
        #expect(history.boards.map(\.name) == ["A", "B"])
    }
}
