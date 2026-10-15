import AppKit
import Foundation
import Testing
@testable import ClipboardModule

/// The floating panel's large preview as its model decides it: what opens and closes it, which item it shows, and what
/// Return, Esc, a click and the keyboard leaving do while it is open. The window is replaced by counters.
@Suite final class ClipboardPanelPreviewTests {
    typealias Keys = ClipboardPreviewKeys
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    let state = ClipboardState()
    let actions = FakePanelActions()
    let text: UUID, link: UUID, color: UUID, richText: UUID
    private var model: ClipboardPanelModel!
    var closeCount = 0
    /// What the preview window was told, in order.
    var previewChanges: [Bool] = []

    init() {
        var history = ClipboardHistory()
        var minutes = 8.0
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
        model = makeModel(pinned: false)
    }

    func makeModel(pinned: Bool) -> ClipboardPanelModel {
        let start = Self.start
        let model = ClipboardPanelModel(state: state, actions: actions, isPinned: pinned, now: { start })
        model.onClose = { [unowned self] in
            closeCount += 1
            actions.note("close")
        }
        model.onReturnKeyboard = { [unowned self] in
            actions.note("hand back")
            return true
        }
        model.isKeyboardBack = { [unowned self] in
            actions.note("check")
            return true
        }
        model.onPreviewChange = { [unowned self] open in
            previewChanges.append(open)
            if !open { actions.note("preview closed") }
        }
        return model
    }

    func pin() {
        model.detach()
        model = makeModel(pinned: true)
    }

    func key(_ keyCode: UInt16, _ characters: String? = nil, modifiers: NSEvent.ModifierFlags = [], isRepeat: Bool = false) -> Keys.Key {
        Keys.Key(keyCode: keyCode, characters: characters, modifiers: modifiers, isRepeat: isRepeat)
    }

    var space: Keys.Key { key(49, " ") }
    var down: Keys.Key { key(125, nil, modifiers: [.numericPad, .function]) }
    var escape: Keys.Key { key(53, "\u{1B}") }
    var returnKey: Keys.Key { key(36, "\r") }

    @discardableResult
    func press(_ key: Keys.Key, target: Keys.Target = .searchField, marked: Bool = false) -> Bool {
        model.handlePreviewKey(key, target: target, hasMarkedText: marked)
    }

    // MARK: Opening and closing

    @Test func spaceInAnEmptyFieldOpensThePreviewOnTheSelectedItem() {
        #expect(!model.isPreviewOpen)
        #expect(model.previewedItem == nil)

        #expect(press(space))
        #expect(model.isPreviewOpen)
        #expect(model.previewedItem?.id == text)
        #expect(previewChanges == [true])
    }

    @Test func spaceAgainClosesIt() {
        press(space)
        #expect(press(space))
        #expect(!model.isPreviewOpen)
        #expect(model.previewedItem == nil)
        #expect(previewChanges == [true, false])
    }

    @Test func commandYTogglesWhateverTheFieldHolds() {
        model.searchText = "chào"
        let commandY = key(16, "y", modifiers: .command)
        #expect(press(commandY))
        #expect(model.isPreviewOpen)
        #expect(press(commandY))
        #expect(!model.isPreviewOpen)
    }

    @Test func spaceWhileTypingTypesASpaceAndOpensNothing() {
        model.searchText = "xin"
        #expect(!press(space))
        #expect(!model.isPreviewOpen)
        #expect(previewChanges.isEmpty)
    }

    @Test func spaceAfterAnArrowOpensEvenWithTextInTheField() {
        model.searchText = "@safari "
        model.searchText = "o"
        #expect(!press(down))
        #expect(press(space))
        #expect(model.isPreviewOpen)
    }

    @Test func aTypedLetterEndsTheMovingThroughTheList() {
        model.searchText = "o"
        press(down)
        press(key(0, "a"))
        #expect(!press(space))
    }

    @Test func spaceAndSpaceAgainAfterAnArrowOpenThenCloseEvenThoughTheFieldHoldsText() {
        model.searchText = "o"
        press(down)
        #expect(press(space))
        #expect(model.isPreviewOpen)
        #expect(press(space))
        #expect(!model.isPreviewOpen)
    }

    @Test func aHeldSpaceDoesNotFlickerThePreview() {
        press(space)
        #expect(press(key(49, " ", isRepeat: true)))
        #expect(model.isPreviewOpen)
        #expect(previewChanges == [true])
    }

    @Test func spaceDuringAnInputMethodsCompositionIsTheInputMethods() {
        #expect(!press(space, marked: true))
        #expect(!model.isPreviewOpen)
    }

    @Test func thereIsNothingToPreviewInAnEmptyList() {
        state.history = ClipboardHistory()
        #expect(!press(space))
        #expect(!model.isPreviewOpen)
    }

    // MARK: The selection

    @Test func theArrowsMoveTheSelectionAndThePreviewFollowsLive() {
        press(space)
        #expect(model.previewedItem?.id == text)

        #expect(model.handleKey(.next))
        #expect(model.previewedItem?.id == link)
        #expect(model.handleKey(.next))
        #expect(model.previewedItem?.id == color)
        #expect(model.handleKey(.previous))
        #expect(model.previewedItem?.id == link)
        #expect(model.isPreviewOpen)
        #expect(previewChanges == [true])
    }

    @Test func typingWhileItIsOpenShowsTheFirstMatch() {
        press(space)
        model.searchText = "bảng"
        #expect(model.previewedItem?.id == richText)
        #expect(model.isPreviewOpen)
    }

    @Test func aSearchWithNoMatchClosesIt() {
        press(space)
        model.searchText = "zzz không có"
        #expect(!model.isPreviewOpen)
        #expect(previewChanges == [true, false])
    }

    @Test func aDeletedItemClosesItInsteadOfSwitchingToTheFirstOne() {
        _ = model.handleKey(.next)
        press(space)
        #expect(model.previewedItem?.id == link)

        _ = state.history.remove(ids: [link])
        #expect(!model.isPreviewOpen)
        #expect(previewChanges == [true, false])
    }

    @Test func aNewCopyWhileItIsOpenKeepsShowingTheSameItem() {
        _ = model.handleKey(.next)
        press(space)
        let content = ClipboardContent.text("Mới chép")
        state.history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: Self.start)
        #expect(model.previewedItem?.id == link)
        #expect(model.isPreviewOpen)
    }

    @Test func anItemOfALockedBoardIsNeverShown() {
        var history = state.history
        let board = history.createBoard(name: "Két")
        history.pin(itemID: text, to: board)
        let index = history.boards.firstIndex { $0.id == board }!
        // A state the module never produces (it takes a locked board's items out of the history), refused all the same.
        history.boards[index].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: false)
        state.history = history

        #expect(!press(space))
        #expect(!model.isPreviewOpen)
        #expect(model.previewedItem == nil)
    }

    @Test func anItemOfAnOpenBoardIsShownLikeAnyOther() {
        var history = state.history
        let board = history.createBoard(name: "Két")
        history.pin(itemID: text, to: board)
        let index = history.boards.firstIndex { $0.id == board }!
        history.boards[index].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: true)
        state.history = history

        #expect(press(space))
        #expect(model.previewedItem?.id == text)
    }

    // MARK: Esc

    @Test func escapeClosesOnlyThePreviewNotThePanel() {
        press(space)
        #expect(press(escape))
        #expect(!model.isPreviewOpen)
        #expect(closeCount == 0)

        // Closed, Esc is the panel's again.
        #expect(!press(escape))
        #expect(model.handleKey(.close))
        #expect(closeCount == 1)
    }

    @Test func theFieldsOwnEscapeAndThePanelsCancelAlsoCloseOnlyThePreview() {
        press(space)
        #expect(model.handleKey(.close))
        #expect(!model.isPreviewOpen)
        #expect(closeCount == 0)

        press(space)
        model.cancel()
        #expect(!model.isPreviewOpen)
        #expect(closeCount == 0)

        model.cancel()
        #expect(closeCount == 1)
    }

    @Test func escapeWithTextInTheFieldAlsoLeavesThePanelOpenWhilePreviewing() {
        model.searchText = "o"
        press(down)
        press(space)
        #expect(model.handleKey(.clearSearch))
        #expect(!model.isPreviewOpen)
        #expect(closeCount == 0)
    }

    @Test func escapeBelongsToTheSuggestionsWhileTheyAreShown() {
        press(space)
        model.searchText = "@"
        #expect(model.suggestions.isOpen)

        #expect(!press(escape))
        #expect(model.handleKey(.close))
        #expect(!model.suggestions.isOpen)
        #expect(model.isPreviewOpen)
    }

    // MARK: Return, a click and ⌘N

    @Test func returnWhilePreviewingClosesThePreviewThenWritesThenClosesThePanelThenChecksThenPastes() {
        press(space)
        #expect(press(returnKey))

        #expect(actions.activated == [text])
        #expect(actions.events == ["preview closed", "write", "close", "check", "paste"])
        #expect(!model.isPreviewOpen)
    }

    @Test func returnFromAPinnedPanelClosesThePreviewThenHandsTheKeyboardBackThenPastes() {
        pin()
        press(space)
        press(returnKey)

        #expect(actions.events == ["preview closed", "write", "hand back", "paste"])
        #expect(closeCount == 0)
        #expect(!model.isPreviewOpen)
    }

    @Test func returnPastesTheItemThePreviewShows() {
        _ = model.handleKey(.next)
        _ = model.handleKey(.next)
        press(space)
        press(returnKey)
        #expect(actions.activated == [color])
    }

    @Test func aHeldReturnPastesOnce() {
        press(space)
        press(returnKey)
        #expect(press(key(36, "\r", isRepeat: true)) == false)
        #expect(actions.activated == [text])
    }

    @Test func returnWhileSuggestionsAreShownCompletesThemInsteadOfPasting() {
        press(space)
        model.searchText = "@li"
        #expect(!press(returnKey))
        #expect(model.handleKey(.activate))
        #expect(model.searchText == "@link ")
        #expect(actions.activated.isEmpty)
    }

    @Test func aClickOnARowAndCommandNCloseThePreviewFirstToo() {
        // Pinned, so the panel is still there for the second.
        pin()
        press(space)
        model.activate(link)
        #expect(actions.events.first == "preview closed")

        press(space)
        model.pick(number: 1)
        #expect(actions.events.filter { $0 == "preview closed" }.count == 2)
    }

    @Test func aFailedCopyStillClosedThePreviewAndKeepsThePanel() {
        actions.outcome = .failed
        press(space)
        model.activate(text)
        #expect(!model.isPreviewOpen)
        #expect(closeCount == 0)
    }

    // MARK: The window going away

    @Test func theKeyboardLeavingAPinnedPanelClosesThePreviewButKeepsThePanel() {
        pin()
        press(space)
        model.focusLost()
        #expect(!model.isPreviewOpen)
        #expect(closeCount == 0)
    }

    @Test func theKeyboardLeavingAnUnpinnedPanelClosesBoth() {
        press(space)
        model.focusLost()
        #expect(!model.isPreviewOpen)
        #expect(closeCount == 1)
    }

    @Test func closingThePanelOrDetachingItClosesThePreview() {
        press(space)
        model.requestClose()
        #expect(previewChanges == [true, false])

        let other = makeModel(pinned: false)
        other.togglePreview()
        other.detach()
        #expect(!other.isPreviewOpen)
    }

    @Test func aClosedPanelOpensNoPreview() {
        model.detach()
        #expect(!press(space))
        model.togglePreview()
        #expect(!model.isPreviewOpen)
    }
}
