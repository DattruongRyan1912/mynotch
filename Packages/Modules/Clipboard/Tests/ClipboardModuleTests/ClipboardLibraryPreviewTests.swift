import AppKit
import Foundation
import Testing
@testable import ClipboardModule

/// The library's large preview as its model decides it: it shows the focused card, follows the arrows, and closes with Esc,
/// with the card it shows, and before an item is used.
@Suite final class ClipboardLibraryPreviewTests {
    typealias Keys = ClipboardPreviewKeys
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    let state = ClipboardState()
    let actions: FakeLibraryActions
    let model: ClipboardLibraryModel
    let text: UUID, link: UUID, color: UUID, richText: UUID
    let work: UUID
    /// What happened, in order, across the preview window and the action.
    var events: [String] = []

    init() {
        var history = ClipboardHistory()
        var minutes = 6.0
        func add(_ content: ClipboardContent) -> UUID {
            minutes -= 1
            return history.add(
                content, hash: ClipboardContent.hash(of: content), source: ("com.apple.Notes", "Ghi chú"),
                at: Self.start.addingTimeInterval(-minutes * 60)
            ).id
        }
        richText = add(.richText(plain: "Bảng giá", rtf: Data("{\\rtf1 Bảng giá}".utf8)))
        color = add(.color(hex: "#FF8800"))
        link = add(.link(URL(string: "https://example.com/a")!))
        text = add(.text("Xin chào"))
        work = history.createBoard(name: "Công việc")
        history.pin(itemID: link, to: work)
        state.history = history
        actions = FakeLibraryActions(state: state)
        let start = Self.start
        model = ClipboardLibraryModel(state: state, actions: actions, now: { start })
        model.onPreviewChange = { [unowned self] open in events.append(open ? "preview opened" : "preview closed") }
        actions.onActivate = { [unowned self] in events.append("used") }
        // The grid has two columns, so ↓ moves two cards.
        model.columns = 2
    }

    func key(_ keyCode: UInt16, _ characters: String? = nil, modifiers: NSEvent.ModifierFlags = [], isRepeat: Bool = false) -> Keys.Key {
        Keys.Key(keyCode: keyCode, characters: characters, modifiers: modifiers, isRepeat: isRepeat)
    }

    var space: Keys.Key { key(49, " ") }
    var escape: Keys.Key { key(53, "\u{1B}") }
    var returnKey: Keys.Key { key(36, "\r") }

    @discardableResult
    func press(_ key: Keys.Key, target: Keys.Target = .cards, marked: Bool = false) -> Bool {
        model.handlePreviewKey(key, target: target, hasMarkedText: marked)
    }

    // MARK: Opening

    @Test func spaceOnTheCardsShowsTheFocusedCard() {
        model.select(link, mode: .replace)
        #expect(press(space))
        #expect(model.isPreviewOpen)
        #expect(model.previewedItem?.id == link)
        #expect(events == ["preview opened"])
    }

    @Test func spaceWithNoCardFocusedDoesNothing() {
        #expect(!press(space))
        #expect(!model.isPreviewOpen)
        #expect(events.isEmpty)
    }

    @Test func spaceAgainOrCommandYClosesIt() {
        model.select(text, mode: .replace)
        press(space)
        #expect(press(space))
        #expect(!model.isPreviewOpen)

        press(key(16, "y", modifiers: .command))
        #expect(model.isPreviewOpen)
        press(key(16, "y", modifiers: .command))
        #expect(!model.isPreviewOpen)
    }

    @Test func inTheSearchFieldSpaceWorksOnlyWhileItIsEmptyOrAfterAnArrow() {
        model.select(text, mode: .replace)
        #expect(press(space, target: .searchField))
        press(space, target: .searchField)
        #expect(!model.isPreviewOpen)

        model.searchText = "o"
        #expect(model.focusID == text)
        #expect(!press(space, target: .searchField))
        press(key(125, nil, modifiers: [.numericPad, .function]), target: .searchField)
        #expect(press(space, target: .searchField))
        #expect(model.isPreviewOpen)
    }

    /// ↓ in an open `@` list moves the suggestion, not the card, so the Space that follows is a typed space.
    @Test func spaceAfterAnArrowThatMovedTheSuggestionsTypesASpace() {
        model.select(text, mode: .replace)
        model.searchText = "chào @"
        // The list is open and the card is still there, so only the arrow's memory could make Space the preview's.
        #expect(model.suggestions.isOpen)
        #expect(model.focusID == text)
        #expect(!press(key(125, nil, modifiers: [.numericPad, .function]), target: .searchField))
        #expect(!press(space, target: .searchField))
        #expect(!model.isPreviewOpen)
    }

    @Test func spaceDuringACompositionIsTheInputMethods() {
        model.select(text, mode: .replace)
        #expect(!press(space, target: .searchField, marked: true))
        #expect(!model.isPreviewOpen)
    }

    @Test func aHeldSpaceIsSwallowed() {
        model.select(text, mode: .replace)
        press(space)
        #expect(press(key(49, " ", isRepeat: true)))
        #expect(model.isPreviewOpen)
        #expect(events == ["preview opened"])
    }

    // MARK: Following the selection

    @Test func theArrowsMoveTheFocusAndThePreviewFollows() {
        model.select(text, mode: .replace)
        press(space)

        model.move(.right, extend: false)
        #expect(model.previewedItem?.id == link)
        model.move(.down, extend: false)
        #expect(model.previewedItem?.id == richText)
        model.move(.left, extend: false)
        #expect(model.previewedItem?.id == color)
        #expect(events == ["preview opened"])
    }

    @Test func aRangeSelectionShowsTheFocusedCard() {
        model.select(text, mode: .replace)
        press(space)
        model.move(.right, extend: true)
        #expect(model.previewedItem?.id == link)
    }

    @Test func aSearchThatHidesTheFocusedCardClosesIt() {
        model.select(text, mode: .replace)
        press(space)
        model.searchText = "bảng"
        #expect(!model.isPreviewOpen)
        #expect(events == ["preview opened", "preview closed"])
    }

    @Test func anotherSelectionWithNoCardsClosesIt() {
        model.select(link, mode: .replace)
        press(space)
        model.selection = .board(work)
        #expect(model.previewedItem?.id == link)

        model.kindFilter = .image
        #expect(!model.isPreviewOpen)
    }

    @Test func aDeletedCardClosesItInsteadOfShowingTheNextOne() {
        model.select(link, mode: .replace)
        press(space)
        _ = state.history.remove(ids: [link])
        #expect(!model.isPreviewOpen)
        #expect(model.previewedItem == nil)
    }

    @Test func whenTheFocusFallsToAnotherSelectedCardThePreviewStillClosesInsteadOfSwitching() {
        model.select(text, mode: .replace)
        model.select(link, mode: .toggle)
        #expect(model.focusID == link)
        press(space)
        #expect(model.previewedItem?.id == link)

        _ = state.history.remove(ids: [link])
        #expect(model.focusID == text)
        #expect(!model.isPreviewOpen)
        #expect(model.previewedItem == nil)
    }

    @Test func deletingTheFocusedCardFromTheLibraryClosesItToo() {
        // Not pinned to a board, so there is no question to answer first.
        model.select(text, mode: .replace)
        press(space)
        model.requestDelete()
        #expect(!model.isPreviewOpen)
        #expect(events.last == "preview closed")
        #expect(model.focusID == link)
    }

    @Test func aCardOfALockedBoardIsNeverShown() {
        var history = state.history
        history.boards[history.boards.firstIndex { $0.id == work }!].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: false)
        state.history = history
        model.select(link, mode: .replace)

        #expect(!press(space))
        #expect(!model.isPreviewOpen)
    }

    @Test func aLockedBoardOnShowHasNothingToPreview() {
        var history = state.history
        history.boards[history.boards.firstIndex { $0.id == work }!].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: false)
        state.history = history
        model.selection = .board(work)
        #expect(model.lockedSelectedBoard != nil)
        #expect(!press(space, target: .searchField))
        #expect(!model.isPreviewOpen)
    }

    // MARK: Esc and Return

    @Test func escapeClosesOnlyThePreviewAndKeepsTheSelection() {
        model.select(link, mode: .replace)
        press(space)
        #expect(press(escape))
        #expect(!model.isPreviewOpen)
        #expect(model.selectedIDs == [link])
        #expect(model.focusID == link)

        // Closed, Esc is the library's own (clearing the selection) again.
        #expect(!press(escape))
    }

    @Test func tabClosesOnlyThePreviewAndKeepsTheSelection() {
        let tab = key(48, "\t")
        model.select(link, mode: .replace)
        #expect(!press(tab))
        press(space)
        #expect(press(tab, target: .searchField))
        #expect(!model.isPreviewOpen)
        #expect(model.selectedIDs == [link])
        #expect(!press(tab))
    }

    @Test func returnClosesThePreviewThenUsesTheFocusedCard() {
        model.select(link, mode: .replace)
        press(space)
        #expect(press(returnKey))

        #expect(actions.activated == [link])
        #expect(events == ["preview opened", "preview closed", "used"])
    }

    @Test func returnInTheSearchFieldPastesTheFocusedCardToo() {
        model.select(link, mode: .replace)
        press(space, target: .searchField)
        #expect(press(returnKey, target: .searchField))
        #expect(events == ["preview opened", "preview closed", "used"])
    }

    @Test func returnWithoutAPreviewIsNotTheirs() {
        model.select(link, mode: .replace)
        #expect(!press(returnKey))
        #expect(actions.activated.isEmpty)
    }

    @Test func aDoubleClickOnACardClosesThePreviewBeforeUsingIt() {
        model.select(link, mode: .replace)
        press(space)
        model.activate(text)
        #expect(events == ["preview opened", "preview closed", "used"])
    }

    // MARK: The window going away

    @Test func detachingClosesThePreview() {
        model.select(link, mode: .replace)
        press(space)
        model.detach()
        #expect(!model.isPreviewOpen)
        #expect(events == ["preview opened", "preview closed"])
    }
}
