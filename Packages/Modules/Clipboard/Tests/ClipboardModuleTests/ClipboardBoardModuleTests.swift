import Foundation
import MyNotchCore
import Testing
@testable import ClipboardModule

/// Board icons, colours and order as the module changes them, on the same fixture as `ClipboardModuleTests`.
extension ClipboardModuleTests {
    var boardNames: [String] { state.history.boards.map(\.name) }

    /// Three boards, A to C, made the way the tab makes them.
    @discardableResult
    func makeBoards(_ names: [String] = ["A", "B", "C"]) -> [UUID] {
        names.compactMap { module.createBoard(named: $0) }
    }

    @Test func aNewBoardGoesLastWithTheDefaultIconAndColour() async {
        await start()
        let ids = makeBoards()

        #expect(boardNames == ["A", "B", "C"])
        #expect(state.history.boards.map(\.id) == ids)
        #expect(state.history.boards.allSatisfy { $0.systemImage == "tray.full" && $0.color == .accent })
    }

    @Test func theIconAndColourOfOneBoardChange() async {
        await start()
        let ids = makeBoards()

        module.setBoardIcon(ids[1], to: "briefcase")
        module.setBoardColor(ids[1], to: .orange)

        #expect(state.history.boards.map(\.systemImage) == ["tray.full", "briefcase", "tray.full"])
        #expect(state.history.boards.map(\.color) == [.accent, .orange, .accent])
    }

    @Test func aNameThatIsNoSymbolNameIsRefused() async {
        await start()
        let ids = makeBoards(["A"])

        module.setBoardIcon(ids[0], to: "../etc/passwd")
        module.setBoardIcon(ids[0], to: "")
        module.setBoardIcon(ids[0], to: "Star")

        #expect(state.history.boards[0].systemImage == "tray.full")
    }

    @Test func boardsMoveByIndexAndByStep() async {
        await start()
        let ids = makeBoards(["A", "B", "C", "D"])

        module.moveBoard(ids[0], to: 2)
        #expect(boardNames == ["B", "C", "A", "D"])
        module.moveBoard(ids[3], by: -2)
        #expect(boardNames == ["B", "D", "C", "A"])
        module.moveBoard(ids[3], by: -1)
        #expect(boardNames == ["D", "B", "C", "A"])
        module.moveBoard(UUID(), to: 0)
        #expect(boardNames == ["D", "B", "C", "A"])
    }

    @Test func theOrderIconsAndColoursSurviveARestart() async throws {
        await start()
        let ids = makeBoards()
        module.setBoardIcon(ids[2], to: "star")
        module.setBoardColor(ids[2], to: .pink)
        module.moveBoard(ids[2], to: 0)

        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(makeStore().load().boards.map(\.name) == ["C", "A", "B"])
        await harness.registry.setEnabled(true, for: "clipboard")

        #expect(boardNames == ["C", "A", "B"])
        #expect(state.history.boards[0] == ClipboardBoard(id: ids[2], name: "C", systemImage: "star", color: .pink, itemIDs: []))
    }

    @Test func theLibraryFollowsTheNewOrder() async throws {
        await start()
        let ids = makeBoards()
        module.openLibrary()
        let library = try #require(module.library)

        module.moveBoard(ids[0], by: 2)
        module.setBoardColor(ids[0], to: .teal)

        #expect(library.history.boards.map(\.name) == ["B", "C", "A"])
        #expect(library.history.boards[2].color == .teal)
    }

    @Test func pinsGoWithTheirBoardWhenItMoves() async throws {
        await start()
        copy("một")
        let item = try #require(items.first)
        let ids = makeBoards(["A", "B"])
        module.pin(item, to: ids[0])

        module.moveBoard(ids[0], to: 1)

        #expect(state.history.boards.map(\.itemIDs) == [[], [item.id]])
        #expect(state.history.boards(containing: item.id).map(\.name) == ["A"])
    }

    @Test func boardChangesDoNothingWhileTheModuleIsStopped() {
        module.setBoardIcon(UUID(), to: "star")
        module.setBoardColor(UUID(), to: .red)
        module.moveBoard(UUID(), to: 0)
        module.moveBoard(UUID(), by: 1)

        #expect(state.history.boards.isEmpty)
    }
}
