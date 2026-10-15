import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ClipboardModule

/// A board's icon, colour and place in the row: the value rules, the way they are stored and the order the notch's drag
/// asks for.
@Suite struct ClipboardBoardStyleTests {
    static let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
    static let c = UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!
    static let d = UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!

    /// Four boards named A to D in that order.
    static func history() -> ClipboardHistory {
        ClipboardHistory(boards: [
            ClipboardBoard(id: a, name: "A", systemImage: "tray.full", itemIDs: []),
            ClipboardBoard(id: b, name: "B", systemImage: "tray.full", itemIDs: []),
            ClipboardBoard(id: c, name: "C", systemImage: "tray.full", itemIDs: []),
            ClipboardBoard(id: d, name: "D", systemImage: "tray.full", itemIDs: []),
        ])
    }

    func names(_ history: ClipboardHistory) -> String {
        history.boards.map(\.name).joined()
    }

    // MARK: Icons

    @Test func theCuratedIconsAreAboutFortyDistinctSymbolsWithTitles() {
        let icons = ClipboardBoardIcon.curated
        #expect(icons.count == 40)
        #expect(Set(icons.map(\.name)).count == icons.count)
        #expect(icons.allSatisfy { !$0.title.isEmpty })
        #expect(Set(icons.map(\.title)).count == icons.count)
        #expect(icons.map(\.name).contains(ClipboardBoardIcon.defaultName))
        #expect(ClipboardBoardIcon.defaultName == "tray.full")
    }

    @Test func everyCuratedIconIsASymbolThisMacHas() {
        for icon in ClipboardBoardIcon.curated {
            #expect(NSImage(systemSymbolName: icon.name, accessibilityDescription: nil) != nil, "\(icon.name) is not an SF Symbol here")
        }
    }

    @Test func aSymbolNameIsLowercaseWordsAndDots() {
        for valid in ["tray.full", "star", "chevron.left.forwardslash.chevron.right", "person.2", "1.circle"] {
            #expect(ClipboardBoardIcon.isValidName(valid), "\(valid)")
        }
        for invalid in ["", " ", "Tray.Full", "../x", "a b", "tray/full", "tray.full\n", String(repeating: "a", count: 65), "tray_full"] {
            #expect(!ClipboardBoardIcon.isValidName(invalid), "\(invalid)")
        }
    }

    // MARK: Colours

    @Test func aBoardStartsWithTheAccentColourAndTheDefaultIcon() {
        var history = ClipboardHistory()
        let id = history.createBoard(name: "A")
        #expect(history.boards == [ClipboardBoard(id: id, name: "A", systemImage: "tray.full", color: .accent, itemIDs: [])])
    }

    @Test func theColoursAreTheAccentAndElevenFixedOnes() {
        #expect(ClipboardBoardColor.allCases.count == 12)
        #expect(ClipboardBoardColor.allCases.first == .accent)
        #expect(Set(ClipboardBoardColor.allCases.map(\.rawValue)).count == 12)
        #expect(ClipboardBoardColor.allCases.allSatisfy { !$0.title.isEmpty })
    }

    // MARK: Changing a board

    @Test func iconAndColourChangeOnlyThatBoard() {
        var history = Self.history()
        history.setBoardIcon(id: Self.b, systemImage: "star")
        history.setBoardColor(id: Self.b, color: .orange)

        #expect(history.boards[1] == ClipboardBoard(id: Self.b, name: "B", systemImage: "star", color: .orange, itemIDs: []))
        #expect(history.boards.map(\.systemImage) == ["tray.full", "star", "tray.full", "tray.full"])
        #expect(history.boards.map(\.color) == [.accent, .orange, .accent, .accent])

        history.setBoardIcon(id: UUID(), systemImage: "heart")
        history.setBoardColor(id: UUID(), color: .red)
        #expect(history.boards.map(\.systemImage) == ["tray.full", "star", "tray.full", "tray.full"])
        #expect(history.boards.map(\.color) == [.accent, .orange, .accent, .accent])
    }

    @Test func changingTheStyleKeepsTheItemsAndTheName() {
        var (history, ids) = ClipboardHistoryTests.history([.text("a"), .text("b")])
        let board = history.createBoard(name: "Việc")
        history.pin(itemID: ids[0], to: board)
        history.pin(itemID: ids[1], to: board)
        history.setBoardIcon(id: board, systemImage: "briefcase")
        history.setBoardColor(id: board, color: .teal)

        #expect(history.boards[0].itemIDs == [ids[1], ids[0]])
        #expect(history.boards[0].name == "Việc")
    }

    // MARK: Order

    @Test func aBoardMovesToTheIndexItIsGiven() {
        var history = Self.history()
        history.moveBoard(id: Self.a, to: 2)
        #expect(names(history) == "BCAD")
        history.moveBoard(id: Self.d, to: 0)
        #expect(names(history) == "DBCA")
        history.moveBoard(id: Self.c, to: 1)
        #expect(names(history) == "DCBA")
    }

    @Test func aMoveBeyondTheEndsStopsAtTheEnds() {
        var history = Self.history()
        history.moveBoard(id: Self.b, to: 99)
        #expect(names(history) == "ACDB")
        history.moveBoard(id: Self.c, to: -5)
        #expect(names(history) == "CADB")
    }

    @Test func movingToTheSamePlaceOrAnUnknownBoardChangesNothing() {
        var history = Self.history()
        let before = history
        history.moveBoard(id: Self.b, to: 1)
        history.moveBoard(id: UUID(), to: 0)
        #expect(history == before)
    }

    @Test func aBoardMovesOneStepAtATimeAndStopsAtTheEnds() {
        var history = Self.history()
        history.moveBoard(id: Self.b, by: -1)
        #expect(names(history) == "BACD")
        history.moveBoard(id: Self.b, by: -1)
        #expect(names(history) == "BACD")
        history.moveBoard(id: Self.a, by: 1)
        #expect(names(history) == "BCAD")
        history.moveBoard(id: Self.d, by: 1)
        #expect(names(history) == "BCAD")
        history.moveBoard(id: Self.b, by: 2)
        #expect(names(history) == "CABD")
    }

    @Test func movingBoardsLeavesTheirItemsAndStylesAlone() {
        var history = Self.history()
        history.setBoardColor(id: Self.a, color: .red)
        history.setBoardIcon(id: Self.a, systemImage: "star")
        let item = UUID()
        history.boards[0].itemIDs = [item]
        history.moveBoard(id: Self.a, to: 3)
        #expect(history.boards[3] == ClipboardBoard(id: Self.a, name: "A", systemImage: "star", color: .red, itemIDs: [item]))
    }

    // MARK: What the notch's drag asks for

    @Test func aDragLandsInTheSlotUnderTheCentreOfThePill() {
        let widths: [CGFloat] = [40, 40, 40]
        // Slots start at 0, 44 and 88; the pill's centre is its own slot's middle plus the drag.
        #expect(ClipboardBoardReorder.destination(of: 0, translation: 0, widths: widths, spacing: 4) == 0)
        #expect(ClipboardBoardReorder.destination(of: 0, translation: 20, widths: widths, spacing: 4) == 0)
        #expect(ClipboardBoardReorder.destination(of: 0, translation: 30, widths: widths, spacing: 4) == 1)
        #expect(ClipboardBoardReorder.destination(of: 0, translation: 80, widths: widths, spacing: 4) == 2)
        #expect(ClipboardBoardReorder.destination(of: 2, translation: -30, widths: widths, spacing: 4) == 1)
        #expect(ClipboardBoardReorder.destination(of: 2, translation: -70, widths: widths, spacing: 4) == 0)
        #expect(ClipboardBoardReorder.destination(of: 1, translation: 5, widths: widths, spacing: 4) == 1)
    }

    @Test func aDragPastEitherEndStopsAtTheEnd() {
        let widths: [CGFloat] = [40, 60, 30]
        #expect(ClipboardBoardReorder.destination(of: 1, translation: -900, widths: widths, spacing: 4) == 0)
        #expect(ClipboardBoardReorder.destination(of: 1, translation: 900, widths: widths, spacing: 4) == 2)
    }

    @Test func slotsOfDifferentWidthsAreCountedByTheirOwnWidth() {
        // Starts at 0, 104 (100 + 4) and 148 (104 + 40 + 4).
        let widths: [CGFloat] = [100, 40, 40]
        // The pill 2 has its centre at 168; dragged 30 to the left it is at 138, inside slot 1 (104..<148).
        #expect(ClipboardBoardReorder.destination(of: 2, translation: -30, widths: widths, spacing: 4) == 1)
        // Dragged 70 to the left it is at 98, inside slot 0.
        #expect(ClipboardBoardReorder.destination(of: 2, translation: -70, widths: widths, spacing: 4) == 0)
    }

    @Test func aListsDragReportsAnInsertionPointAndTheBoardLandsJustBeforeIt() {
        // A board moved down lands before the row that was at the insertion point, so one place less once it has left its own.
        #expect(ClipboardBoardReorder.index(moving: 0, toOffset: 3) == 2)
        #expect(ClipboardBoardReorder.index(moving: 0, toOffset: 1) == 0)
        #expect(ClipboardBoardReorder.index(moving: 0, toOffset: 4) == 3)
        // Moved up, it lands at the insertion point itself.
        #expect(ClipboardBoardReorder.index(moving: 3, toOffset: 0) == 0)
        #expect(ClipboardBoardReorder.index(moving: 3, toOffset: 1) == 1)
        #expect(ClipboardBoardReorder.index(moving: 2, toOffset: 2) == 2)
        #expect(ClipboardBoardReorder.index(moving: 2, toOffset: 3) == 2)
    }

    @Test func theInsertionPointsOfAListGiveTheOrderTheUserDragged() {
        var history = Self.history()
        // A to between C and D: SwiftUI reports offset 3 for "before D".
        history.moveBoard(id: Self.a, to: ClipboardBoardReorder.index(moving: 0, toOffset: 3))
        #expect(names(history) == "BCAD")
        // D to the top.
        history.moveBoard(id: Self.d, to: ClipboardBoardReorder.index(moving: 3, toOffset: 0))
        #expect(names(history) == "DBCA")
    }

    @Test func noPillsOrABadIndexGivesTheIndexBack() {
        #expect(ClipboardBoardReorder.destination(of: 0, translation: 50, widths: [], spacing: 4) == 0)
        #expect(ClipboardBoardReorder.destination(of: 7, translation: 50, widths: [40, 40], spacing: 4) == 7)
        #expect(ClipboardBoardReorder.destination(of: 0, translation: 50, widths: [40], spacing: 4) == 0)
    }

    // MARK: How it is stored

    static let todaysBoardsJSON = """
    [
      {"id": "00000000-0000-0000-0000-0000000000A1", "name": "Công việc", "systemImage": "tray.full", "itemIDs": []},
      {"id": "00000000-0000-0000-0000-0000000000A2", "name": "Code", "systemImage": "chevron.left.forwardslash.chevron.right", "itemIDs": ["00000000-0000-0000-0000-0000000000C1"]}
    ]
    """

    @Test func aBoardSavedBeforeColoursExistedReadsWithTheAccentAndKeepsItsPlace() throws {
        let boards = try JSONDecoder().decode([ClipboardBoard].self, from: Data(Self.todaysBoardsJSON.utf8))

        #expect(boards.map(\.name) == ["Công việc", "Code"])
        #expect(boards.map(\.color) == [.accent, .accent])
        #expect(boards.map(\.systemImage) == ["tray.full", "chevron.left.forwardslash.chevron.right"])
        #expect(boards[1].itemIDs.count == 1)
    }

    @Test func aColourThatIsNotTheAccentIsStoredAsOneWordAndTheAccentIsLeftOut() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let plain = ClipboardBoard(id: Self.a, name: "A", systemImage: "star", itemIDs: [])
        let blue = ClipboardBoard(id: Self.a, name: "A", systemImage: "star", color: .blue, itemIDs: [])

        let plainText = String(decoding: try encoder.encode(plain), as: UTF8.self)
        let blueText = String(decoding: try encoder.encode(blue), as: UTF8.self)

        #expect(!plainText.contains("color"))
        #expect(blueText == #"{"color":"blue","id":"00000000-0000-0000-0000-0000000000A1","itemIDs":[],"name":"A","systemImage":"star"}"#)
        #expect(try JSONDecoder().decode(ClipboardBoard.self, from: encoder.encode(blue)) == blue)
        #expect(try JSONDecoder().decode(ClipboardBoard.self, from: encoder.encode(plain)) == plain)
    }

    @Test func aColourFromALaterVersionReadsAsTheAccent() throws {
        let json = #"{"id": "00000000-0000-0000-0000-0000000000A1", "name": "A", "systemImage": "star", "color": "ultraviolet", "itemIDs": [], "sticker": 3}"#
        let board = try JSONDecoder().decode(ClipboardBoard.self, from: Data(json.utf8))
        #expect(board.color == .accent)
        #expect(board.name == "A" && board.systemImage == "star")
        let notAString = #"{"id": "00000000-0000-0000-0000-0000000000A1", "name": "A", "systemImage": "star", "color": 7, "itemIDs": []}"#
        #expect(try JSONDecoder().decode(ClipboardBoard.self, from: Data(notAString.utf8)).color == .accent)
    }
}

/// The files: order, icons and colours reach the disk and come back, and a folder written today still loads.
@Suite final class ClipboardBoardStoreTests {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "ClipboardBoardStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func makeStore() -> ClipboardStore {
        ClipboardStore(directory: directory, scheduler: ManualScheduler(), logger: Log.logger(category: "ClipboardBoardStoreTests"))
    }

    @Test func orderIconsAndColoursComeBackAfterASave() async {
        var history = ClipboardBoardStyleTests.history()
        history.setBoardIcon(id: ClipboardBoardStyleTests.c, systemImage: "briefcase")
        history.setBoardColor(id: ClipboardBoardStyleTests.c, color: .purple)
        history.setBoardColor(id: ClipboardBoardStyleTests.a, color: .gray)
        history.moveBoard(id: ClipboardBoardStyleTests.d, to: 0)
        history.moveBoard(id: ClipboardBoardStyleTests.c, to: 1)
        let store = makeStore()
        _ = store.load()

        store.scheduleSave(history)
        await store.flush()
        let loaded = makeStore().load()

        #expect(loaded.boards.map(\.name) == ["D", "C", "A", "B"])
        #expect(loaded.boards.map(\.systemImage) == ["tray.full", "briefcase", "tray.full", "tray.full"])
        #expect(loaded.boards.map(\.color) == [.accent, .purple, .gray, .accent])
        #expect(loaded == history)
    }

    @Test func aFolderWrittenBeforeColoursLoadsInTheOrderItHadAndSavesBackReadable() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(ClipboardBoardStyleTests.todaysBoardsJSON.utf8).write(to: directory.appending(path: "boards.json"))
        try Data("[]".utf8).write(to: directory.appending(path: "history.json"))

        let store = makeStore()
        var history = store.load()
        #expect(history.boards.map(\.name) == ["Công việc", "Code"])
        #expect(history.boards.map(\.color) == [.accent, .accent])

        history.moveBoard(id: history.boards[1].id, to: 0)
        history.setBoardColor(id: history.boards[0].id, color: .green)
        store.scheduleSave(history)
        await store.flush()

        let reloaded = makeStore().load()
        #expect(reloaded.boards.map(\.name) == ["Code", "Công việc"])
        #expect(reloaded.boards.map(\.color) == [.green, .accent])
        #expect(reloaded.boards[0].itemIDs == history.boards[0].itemIDs)
    }

    @Test func aFileThatNeverUsedColoursIsWrittenWithoutThemSoAnOlderVersionReadsItAsBefore() async throws {
        var history = ClipboardBoardStyleTests.history()
        history.moveBoard(id: ClipboardBoardStyleTests.a, to: 3)
        let store = makeStore()
        _ = store.load()
        store.scheduleSave(history)
        await store.flush()

        let text = try String(contentsOf: directory.appending(path: "boards.json"), encoding: .utf8)
        #expect(!text.contains("color"))
    }
}
