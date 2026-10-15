import Foundation
import Testing
@testable import ClipboardModule

/// The inspector as the library's model drives it: it follows the card in focus, says only "locked" for a closed board, remembers
/// whether it is shown, and its buttons use the same paths as the context menu.
@Suite final class ClipboardLibraryInspectorModelTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    let state = ClipboardState()
    let actions: FakeLibraryActions
    let model: ClipboardLibraryModel
    let text: UUID, link: UUID, image: UUID, other: UUID
    let work: UUID, vault: UUID
    var reported: [ClipboardLibraryPreferences] = []

    init() {
        var history = ClipboardHistory()
        var minutes = 5.0
        func add(_ content: ClipboardContent, bundle: String, app: String) -> UUID {
            minutes -= 1
            return history.add(
                content, hash: ClipboardContent.hash(of: content), source: (bundle, app), at: Self.start.addingTimeInterval(-minutes * 60)
            ).id
        }
        other = add(.text("Xin chào"), bundle: "com.apple.Notes", app: "Ghi chú")
        image = add(ClipboardLibraryModelTests.image, bundle: "com.apple.Preview", app: "Xem trước")
        link = add(.link(URL(string: "https://example.com/a")!), bundle: "com.apple.Safari", app: "Safari")
        text = add(.text("Tạm biệt"), bundle: "com.apple.Notes", app: "Ghi chú")
        work = history.createBoard(name: "Công việc")
        vault = history.createBoard(name: "Két")
        history.pin(itemID: link, to: work)
        history.boards[1].lock = ClipboardBoardLock(method: .password, itemCount: 3, isUnlocked: false)
        state.history = history
        actions = FakeLibraryActions(state: state)
        let start = Self.start
        model = ClipboardLibraryModel(state: state, actions: actions, now: { start })
        model.onPreferencesChange = { [unowned self] in reported.append($0) }
    }

    // MARK: What it shows

    @Test func nothingFocusedShowsNothing() {
        #expect(model.inspector == .nothing)
    }

    @Test func theFocusedCardShowsItsFields() throws {
        model.select(link, mode: .replace)
        guard case .item(let info) = model.inspector else {
            Issue.record("Expected the card's fields, got \(model.inspector)")
            return
        }
        #expect(info.id == link)
        #expect(info.kindTitle == "Link")
        #expect(info.sourceAppName == "Safari")
        #expect(info.boards == ["Công việc"])
    }

    @Test func withSeveralSelectedItShowsTheOneTheKeysMovedToLast() {
        model.select(text, mode: .replace)
        model.select(link, mode: .range)
        #expect(model.selectedIDs.count == 2)
        guard case .item(let info) = model.inspector else {
            Issue.record("Expected a card")
            return
        }
        #expect(info.id == model.focusID)
    }

    @Test func itFollowsTheFocusAndEmptiesWhenTheSelectionDoes() {
        model.select(text, mode: .replace)
        model.move(.right, extend: false)
        guard case .item(let moved) = model.inspector else {
            Issue.record("Expected a card")
            return
        }
        #expect(moved.id == model.focusID)
        model.clearSelection()
        #expect(model.inspector == .nothing)
    }

    @Test func aClosedBoardOnShowSaysOnlyThatItIsLocked() {
        model.select(text, mode: .replace)
        model.selection = .board(vault)
        #expect(model.lockedSelectedBoard != nil)
        #expect(model.inspector == .locked)
    }

    @Test func aChangeToTheFocusedItemShowsAtOnce() {
        model.select(text, mode: .replace)
        guard case .item(let before) = model.inspector else {
            Issue.record("Expected a card")
            return
        }
        #expect(before.size == .text(ClipboardTextStats(characters: 8, words: 2, lines: 1)))
        #expect(!before.isEdited)

        #expect(state.history.applyEdit(to: text, content: .text("Tạm biệt các bạn"), mode: .replace, at: Self.start) == .saved(text))

        guard case .item(let after) = model.inspector else {
            Issue.record("Expected a card")
            return
        }
        #expect(after.size == .text(ClipboardTextStats(characters: 16, words: 4, lines: 1)))
        #expect(after.isEdited)
        #expect(model.focusID == text)
    }

    // MARK: Whether it is shown

    @Test func theInspectorStartsHiddenAndKeepsTheLastChoiceByReportingIt() {
        #expect(!model.isInspectorVisible)
        model.toggleInspector()
        #expect(model.isInspectorVisible)
        #expect(reported.last?.inspectorVisible == true)
        model.toggleInspector()
        #expect(reported.last?.inspectorVisible == false)
        #expect(reported.count == 2)
    }

    @Test func aLibraryOpensWithTheChoiceItWasGiven() {
        let shown = ClipboardLibraryModel(
            state: state, actions: actions, preferences: ClipboardLibraryPreferences(inspectorVisible: true)
        )
        #expect(shown.isInspectorVisible)
        #expect(shown.preferences.inspectorVisible)
    }

    @Test func changingOtherThingsReportsTheInspectorToo() {
        model.toggleInspector()
        model.layout = .list
        #expect(reported.last == ClipboardLibraryPreferences(layout: .list, sort: .newest, cardSize: .medium, inspectorVisible: true))
    }

    // MARK: Its buttons

    @Test func pasteUsesTheFocusedCardAndShowsWhatHappened() {
        model.select(text, mode: .replace)
        #expect(model.pasteFocused())
        #expect(actions.pasted.map(\.id) == [text])
        #expect(actions.pasted.first?.plainText == false)
        #expect(model.notice?.text == "Đã chép")
    }

    @Test func pasteClosesTheLargePreviewBeforeAnythingIsWritten() {
        model.select(text, mode: .replace)
        model.togglePreview()
        #expect(model.isPreviewOpen)
        var previewWasOpenWhenPasting: Bool?
        actions.onActivate = { [unowned self] in previewWasOpenWhenPasting = model.isPreviewOpen }
        _ = model.pasteFocused()
        #expect(previewWasOpenWhenPasting == false)
    }

    @Test func copyUsesTheFocusedCard() {
        model.select(link, mode: .replace)
        #expect(model.copySelection())
        #expect(actions.copied == [link])
    }

    @Test func theButtonsDoNothingWithNoCardFocused() {
        #expect(!model.pasteFocused())
        #expect(!model.editFocused())
        #expect(actions.pasted.isEmpty && actions.edited.isEmpty)
    }

    @Test func editOpensTheEditorOnTheFocusedCard() {
        model.select(text, mode: .replace)
        #expect(model.editFocused())
        #expect(actions.edited == [text])
    }

    @Test func editOfAnItemThatCannotBeEditedOpensNothing() {
        model.select(image, mode: .replace)
        #expect(!model.editFocused())
        #expect(actions.edited.isEmpty)
        // The module can refuse too (a stopped module, a board that just locked).
        model.select(text, mode: .replace)
        actions.editOpens = false
        #expect(!model.editFocused())
        #expect(actions.edited == [text])
    }

    @Test func aContextMenuEditOfAnyCardUsesTheSameRules() {
        func card(_ id: UUID) -> ClipboardItem { state.history.items.first { $0.id == id }! }
        #expect(model.edit(card(text)))
        #expect(!model.edit(card(image)))
        #expect(actions.edited == [text])
    }

    @Test func deleteAsksFirstWhenTheCardIsPinned() {
        model.select(link, mode: .replace)
        model.requestDelete([link])
        #expect(model.pendingDeletion == [link])
        model.cancelDelete()
        model.select(text, mode: .replace)
        model.requestDelete([text])
        #expect(actions.deleted == [[text]])
    }
}
