import AppKit
import Foundation
import Testing
@testable import ClipboardModule

/// The notch tab's large preview as its model decides it: the same keys as the library and the panel (the search field is the only
/// place to type; ↑/↓ and, with an empty search, ←/→ move the row), which item it shows, and the notch staying pinned while it is
/// open. The window and the notch are replaced by recorders.
@Suite final class ClipboardTabPreviewTests {
    typealias Keys = ClipboardPreviewKeys
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    let state = ClipboardState()
    let text: UUID, link: UUID, color: UUID, richText: UUID
    let model: ClipboardTabPreviewModel
    /// What happened, in order: the pin, the window, and an item being used.
    var events: [String] = []
    var activated: [UUID] = []

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
        state.history = history
        model = ClipboardTabPreviewModel(state: state)
        model.onPreviewChange = { [unowned self] open in events.append(open ? "preview opened" : "preview closed") }
        model.pinNotch = { [unowned self] pinned in events.append(pinned ? "pinned" : "unpinned") }
        model.onActivate = { [unowned self] item in
            activated.append(item.id)
            events.append("used")
        }
    }

    func key(_ keyCode: UInt16, _ characters: String? = nil, modifiers: NSEvent.ModifierFlags = [], isRepeat: Bool = false) -> Keys.Key {
        Keys.Key(keyCode: keyCode, characters: characters, modifiers: modifiers, isRepeat: isRepeat)
    }

    var space: Keys.Key { key(49, " ") }
    var escape: Keys.Key { key(53, "\u{1B}") }
    var returnKey: Keys.Key { key(36, "\r") }
    var tab: Keys.Key { key(48, "\t") }
    var down: Keys.Key { key(125, nil, modifiers: [.numericPad, .function]) }
    var left: Keys.Key { key(123, nil, modifiers: [.numericPad, .function]) }
    var right: Keys.Key { key(124, nil, modifiers: [.numericPad, .function]) }

    @discardableResult
    func press(_ key: Keys.Key, marked: Bool = false) -> Bool {
        model.handlePreviewKey(key, target: .searchField, hasMarkedText: marked)
    }

    var ids: [UUID] { state.visibleItems.map(\.id) }

    /// What the tab does for → : moves the selection one card along.
    func moveRight() {
        state.selectedID = ClipboardSelection.next(in: ids, current: state.selectedID)
    }

    func moveLeft() {
        state.selectedID = ClipboardSelection.previous(in: ids, current: state.selectedID)
    }

    // MARK: Space and ⌘Y

    @Test func spaceInAnEmptyFieldOpensThePreviewOnTheSelectedCardAndPinsTheNotch() {
        #expect(press(space))
        #expect(model.isPreviewOpen)
        #expect(model.previewedItem?.id == text)
        // Pinned before the window appears, so the notch cannot close under it.
        #expect(events == ["pinned", "preview opened"])
    }

    @Test func spaceAgainClosesItAndUnpinsTheNotch() {
        press(space)
        #expect(press(space))
        #expect(!model.isPreviewOpen)
        #expect(model.previewedItem == nil)
        // The window goes first and the pin after it, so the notch is never left open by a preview that is already gone... nor the
        // other way round while it is shown.
        #expect(events == ["pinned", "preview opened", "preview closed", "unpinned"])
    }

    @Test func commandYTogglesWhateverTheFieldHolds() {
        state.query.text = "chào"
        let commandY = key(16, "y", modifiers: .command)
        #expect(press(commandY))
        #expect(model.isPreviewOpen)
        #expect(press(commandY))
        #expect(!model.isPreviewOpen)
    }

    @Test func spaceWhileTypingTypesASpace() {
        state.query.text = "xin"
        #expect(!press(space))
        #expect(!model.isPreviewOpen)
        #expect(events.isEmpty)
    }

    @Test func spaceAfterAnUpOrDownArrowOpensEvenWithTextInTheField() {
        state.query.text = "o"
        #expect(!press(down))
        #expect(press(space))
        #expect(model.isPreviewOpen)
        #expect(press(space))
        #expect(!model.isPreviewOpen)
    }

    /// ← and → move the row only while the search is empty, and then Space is the preview's anyway; with text they move the caret, so
    /// a Space after them is a space the user is typing into the middle of a word.
    @Test func spaceAfterLeftOrRightIsThePreviewsOnlyWhileThoseKeysMoveTheRow() {
        #expect(!press(right))
        #expect(press(space))
        press(space)

        state.query.text = "xin"
        #expect(!press(left))
        #expect(!press(space))
        #expect(!press(right))
        #expect(!press(space))
        #expect(!model.isPreviewOpen)
    }

    @Test func spaceDuringACompositionIsTheInputMethods() {
        #expect(!press(space, marked: true))
        #expect(!model.isPreviewOpen)
    }

    @Test func aHeldSpaceDoesNotFlickerThePreview() {
        press(space)
        #expect(press(key(49, " ", isRepeat: true)))
        #expect(model.isPreviewOpen)
        #expect(events == ["pinned", "preview opened"])
    }

    @Test func thereIsNothingToPreviewInAnEmptyRow() {
        state.history = ClipboardHistory()
        #expect(!press(space))
        #expect(!model.isPreviewOpen)
        state.history = ClipboardHistory()
        state.query.text = "zzz không có"
        #expect(!press(key(16, "y", modifiers: .command)))
    }

    // MARK: The selection

    @Test func theArrowsMoveTheRowAndThePreviewFollowsLive() {
        press(space)
        moveRight()
        #expect(model.previewedItem?.id == link)
        moveRight()
        #expect(model.previewedItem?.id == color)
        moveLeft()
        #expect(model.previewedItem?.id == link)
        #expect(model.isPreviewOpen)
        #expect(events == ["pinned", "preview opened"])
    }

    @Test func typingWhileItIsOpenShowsTheFirstMatchAndNoMatchClosesIt() {
        press(space)
        state.query.text = "bảng"
        #expect(model.previewedItem?.id == richText)

        state.query.text = "zzz không có"
        #expect(!model.isPreviewOpen)
        #expect(events.contains("unpinned"))
    }

    @Test func aKindFilterThatHidesTheSelectionMovesOnOrClosesItLikeTheRow() {
        press(space)
        state.query.kind = .color
        #expect(model.previewedItem?.id == color)
        state.query.kind = .image
        #expect(!model.isPreviewOpen)
    }

    @Test func aDeletedCardClosesItInsteadOfSwitchingToTheFirstOne() {
        moveRight()
        press(space)
        #expect(model.previewedItem?.id == link)

        _ = state.history.remove(ids: [link])
        #expect(!model.isPreviewOpen)
        #expect(model.previewedItem == nil)
    }

    @Test func aNewCopyWhileItIsOpenOnTheFirstCardKeepsShowingThatCardAndPastesIt() {
        press(space)
        let content = ClipboardContent.text("Mới chép")
        state.history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: Self.start)
        #expect(model.previewedItem?.id == text)

        press(returnKey)
        #expect(activated == [text])
    }

    @Test func aCardOfALockedBoardIsNeverShown() {
        var history = state.history
        let board = history.createBoard(name: "Két")
        history.pin(itemID: text, to: board)
        let index = history.boards.firstIndex { $0.id == board }!
        // A state the module never produces (it takes a locked board's items out of the history), refused all the same.
        history.boards[index].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: false)
        state.history = history

        #expect(!press(space))
        #expect(!model.isPreviewOpen)
    }

    @Test func aCardOfAnOpenBoardIsShownLikeAnyOther() {
        var history = state.history
        let board = history.createBoard(name: "Két")
        history.pin(itemID: text, to: board)
        history.boards[history.boards.firstIndex { $0.id == board }!].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: true)
        state.history = history
        #expect(press(space))
        #expect(model.previewedItem?.id == text)
    }

    @Test func lockingTheBoardWhileItsCardIsShownClosesIt() {
        var history = state.history
        let board = history.createBoard(name: "Két")
        history.pin(itemID: text, to: board)
        history.boards[history.boards.firstIndex { $0.id == board }!].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: true)
        state.history = history
        press(space)
        #expect(model.previewedItem?.id == text)

        // What the module does when the board locks: its items leave the history.
        _ = state.history.lockBoard(id: board, method: .password)
        #expect(!model.isPreviewOpen)
        #expect(model.previewedItem == nil)
    }

    @Test func aStackThatIsOnShowsNoCardsToPreview() {
        state.stack.start()
        #expect(!press(space))
        #expect(model.previewedItem == nil)
    }

    // MARK: Esc, Tab and Return

    @Test func escapeClosesOnlyThePreviewAndTheNotchStaysForItsOwnEscape() {
        press(space)
        #expect(press(escape))
        #expect(!model.isPreviewOpen)
        // Closed, Esc is the tab's again (it closes the notch).
        #expect(!press(escape))
    }

    @Test func tabClosesItAndIsOtherwiseTheFields() {
        #expect(!press(tab))
        press(space)
        #expect(press(tab))
        #expect(!model.isPreviewOpen)
        #expect(!press(tab))
    }

    @Test func escapeTabAndReturnBelongToTheSuggestionsWhileTheyAreShown() {
        press(space)
        state.query.text = "chào @"
        #expect(state.suggestions.isOpen)
        #expect(!press(escape))
        #expect(!press(tab))
        #expect(!press(returnKey))
        #expect(model.isPreviewOpen)
    }

    @Test func spaceAfterAnArrowThatMovedTheSuggestionsTypesASpace() {
        state.query.text = "chào @"
        #expect(state.suggestions.isOpen)
        #expect(!press(down))
        #expect(!press(space))
        #expect(!model.isPreviewOpen)
    }

    @Test func returnClosesThePreviewThenUsesTheShownCard() {
        moveRight()
        press(space)
        events = []
        #expect(press(returnKey))

        #expect(activated == [link])
        #expect(state.selectedID == link)
        // The preview first, whatever order the pin and the window go in, and then the paste.
        #expect(events.last == "used")
        #expect(events.contains("preview closed"))
        #expect(events.firstIndex(of: "preview closed")! < events.firstIndex(of: "used")!)
        #expect(!model.isPreviewOpen)
    }

    @Test func aHeldReturnPastesOnce() {
        press(space)
        press(returnKey)
        press(key(36, "\r", isRepeat: true))
        #expect(activated.count == 1)
    }

    @Test func returnWithoutAPreviewIsTheFieldsOwn() {
        #expect(!press(returnKey))
        #expect(activated.isEmpty)
    }

    // MARK: Pinning

    @Test func theNotchIsPinnedForAsLongAsThePreviewIsOpenAndNotAfter() {
        #expect(events.isEmpty)
        press(space)
        #expect(events.filter { $0 == "pinned" || $0 == "unpinned" } == ["pinned"])
        moveRight()
        press(returnKey)
        #expect(events.filter { $0 == "pinned" || $0 == "unpinned" } == ["pinned", "unpinned"])
    }

    @Test func closingItInAnyWayUnpinsOnce() {
        for close in [{ self.model.closePreview() }, { self.press(self.escape) }, { self.press(self.tab) }, { self.press(self.space) }] as [() -> Any] {
            events = []
            press(space)
            _ = close()
            #expect(events.filter { $0 == "unpinned" }.count == 1)
            #expect(!model.isPreviewOpen)
            // And again does nothing.
            model.closePreview()
            #expect(events.filter { $0 == "unpinned" }.count == 1)
        }
    }

    @Test func theTabLeavingClosesItAndUnpins() {
        press(space)
        model.closePreview()
        #expect(!model.isPreviewOpen)
        #expect(events.last != "pinned")
    }

    @Test func nothingIsPinnedWhenThereIsNothingToShow() {
        state.query.text = "zzz không có"
        press(space)
        press(key(16, "y", modifiers: .command))
        #expect(events.isEmpty)
    }

    // MARK: The tab's own pin rules

    @Test func theTabPinsForMenusNameFieldsPromptsAndThePreview() {
        #expect(!ClipboardTabView.needsPin(menuOpen: false, editing: false, vault: false, previewing: false))
        #expect(ClipboardTabView.needsPin(menuOpen: true, editing: false, vault: false, previewing: false))
        #expect(ClipboardTabView.needsPin(menuOpen: false, editing: true, vault: false, previewing: false))
        #expect(ClipboardTabView.needsPin(menuOpen: false, editing: false, vault: true, previewing: false))
        #expect(ClipboardTabView.needsPin(menuOpen: false, editing: false, vault: false, previewing: true))
    }
}
