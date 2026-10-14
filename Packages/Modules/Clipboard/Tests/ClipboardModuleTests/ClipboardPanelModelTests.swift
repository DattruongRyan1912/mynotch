import Foundation
import Testing
@testable import ClipboardModule

/// Stands in for the module: records what the panel asks for.
final class FakePanelActions: ClipboardPanelActions {
    var outcome: ClipboardPaster.Outcome? = .pasted
    private(set) var activated: [UUID] = []

    func activate(_ item: ClipboardItem) -> ClipboardPaster.Outcome? {
        activated.append(item.id)
        return outcome
    }
}

/// The floating panel's view model on a fixture history, newest first: text, link, color, rich text, image, files and
/// a text copied by no app. Windows are replaced by counters.
@Suite final class ClipboardPanelModelTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    let state = ClipboardState()
    let actions = FakePanelActions()
    let text: UUID, link: UUID, color: UUID, richText: UUID, image: UUID, files: UUID, orphan: UUID
    let work: UUID
    private var model: ClipboardPanelModel!
    var closeCount = 0
    var keyboardReturns = 0
    private(set) var pinChanges: [Bool] = []
    private(set) var moves: [CGPoint] = []

    init() {
        var history = ClipboardHistory()
        var minutes = 8.0
        func add(_ content: ClipboardContent, bundle: String?, app: String?) -> UUID {
            minutes -= 1
            return history.add(
                content, hash: ClipboardContent.hash(of: content), source: (bundle, app),
                at: Self.start.addingTimeInterval(-minutes * 60)
            ).id
        }
        orphan = add(.text("không có app"), bundle: nil, app: nil)
        files = add(.files([URL(fileURLWithPath: "/Users/me/Báo cáo quý.pdf")]), bundle: "com.apple.finder", app: "Finder")
        let picture = ClipboardImage(fileName: "a.png", pixelWidth: 640, pixelHeight: 480, byteCount: 10)
        image = add(.image(picture), bundle: "com.apple.Preview", app: "Xem trước")
        richText = add(.richText(plain: "Bảng giá", rtf: Data("{\\rtf1 Bảng giá}".utf8)), bundle: "com.apple.Notes", app: "Ghi chú")
        color = add(.color(hex: "#FF8800"), bundle: "com.apple.Safari", app: "Safari")
        link = add(.link(URL(string: "https://example.com/a")!), bundle: "com.apple.Safari", app: "Safari")
        text = add(.text("Xin chào"), bundle: "com.apple.Notes", app: "Ghi chú")
        work = history.createBoard(name: "Công việc")
        history.pin(itemID: link, to: work)
        state.history = history
        model = makeModel(pinned: false)
    }

    func makeModel(pinned: Bool) -> ClipboardPanelModel {
        let start = Self.start
        let model = ClipboardPanelModel(state: state, actions: actions, isPinned: pinned, now: { start })
        model.onClose = { [unowned self] in closeCount += 1 }
        model.onReturnKeyboard = { [unowned self] in keyboardReturns += 1 }
        model.onPinnedChange = { [unowned self] in pinChanges.append($0) }
        model.onMove = { [unowned self] in moves.append($0) }
        return model
    }

    /// The same fixture's panel, opened pinned.
    func pin() {
        model.detach()
        model = makeModel(pinned: true)
    }

    var ids: [UUID] { model.items.map(\.id) }

    // MARK: What it shows

    @Test func showsTheWholeHistoryNewestFirstAndSelectsTheFirstItem() {
        #expect(ids == [text, link, color, richText, image, files, orphan])
        #expect(model.selectedID == text)
        #expect(model.emptyMessage == nil)
    }

    @Test func followsTheHistoryWhileOpenAndStopsAfterDetach() {
        #expect(state.historyObserverCount == 1)
        let content = ClipboardContent.text("Mới chép")
        let added = state.history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: Self.start).id
        #expect(ids.first == added)

        model.detach()
        #expect(state.historyObserverCount == 0)
    }

    @Test func anEmptyHistoryShowsAMessageAndNothingIsSelected() {
        state.history = ClipboardHistory()
        #expect(model.items.isEmpty)
        #expect(model.selectedID == nil)
        #expect(model.emptyMessage == "Chưa có gì trong lịch sử")

        // Keys have nothing to act on, and none of them closes the panel by accident.
        #expect(model.handleKey(.next))
        #expect(model.handleKey(.activate))
        #expect(actions.activated.isEmpty)
        #expect(closeCount == 0)
    }

    // MARK: Moving

    @Test func downAndUpMoveTheSelectionAndStopAtTheEnds() {
        #expect(model.handleKey(.next))
        #expect(model.selectedID == link)
        #expect(model.handleKey(.next))
        #expect(model.selectedID == color)
        #expect(model.handleKey(.previous))
        #expect(model.selectedID == link)

        for _ in 0..<20 { _ = model.handleKey(.next) }
        #expect(model.selectedID == orphan)
        for _ in 0..<20 { _ = model.handleKey(.previous) }
        #expect(model.selectedID == text)
    }

    @Test func typingStartsTheSelectionOverOnTheFirstMatch() {
        _ = model.handleKey(.next)
        _ = model.handleKey(.next)
        #expect(model.selectedID == color)

        model.searchText = "bảng"
        #expect(model.selectedID == richText)
        #expect(ids == [richText])
    }

    @Test func aNewCopyKeepsTheSelectionOnItsItem() {
        _ = model.handleKey(.next)
        _ = model.handleKey(.next)
        #expect(model.selectedID == color)

        let content = ClipboardContent.text("Mới chép")
        state.history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: Self.start)
        #expect(model.selectedID == color)
    }

    @Test func aDeletedSelectionFallsBackToTheFirstItem() {
        _ = model.handleKey(.next)
        #expect(model.selectedID == link)

        _ = state.history.remove(ids: [link])
        #expect(model.selectedID == text)
    }

    // MARK: ⌘1…⌘9

    @Test func aNumberPicksTheNthItemAndRunsTheAction() {
        #expect(model.pick(number: 3))
        #expect(actions.activated == [color])
        #expect(model.selectedID == color)
    }

    @Test func numbersOutsideTheListOrOneToNinePickNothing() {
        #expect(!model.pick(number: 0))
        #expect(!model.pick(number: 8))
        #expect(!model.pick(number: 10))
        #expect(!model.pick(number: -1))
        #expect(actions.activated.isEmpty)
        #expect(closeCount == 0)
    }

    @Test func numbersFollowTheFilteredList() {
        model.searchText = "@safari "
        #expect(model.pick(number: 2))
        #expect(actions.activated == [color])
    }

    @Test func onlyTheFirstNineItemsHaveAShortcut() {
        for number in 0..<12 {
            let content = ClipboardContent.text("mục \(number)")
            state.history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: Self.start)
        }
        #expect(model.items.count == 19)
        #expect(model.shortcutNumber(of: model.items[0].id) == 1)
        #expect(model.shortcutNumber(of: model.items[8].id) == 9)
        #expect(model.shortcutNumber(of: model.items[9].id) == nil)
        #expect(model.shortcutNumber(of: UUID()) == nil)
        #expect(!model.pick(number: 10))
    }

    // MARK: Search, with the same engine as the tab and the library

    @Test func plainSearchMatchesLikeTheOtherSurfaces() {
        let queries = ["", "xin", "CHAO", "bao cao", "example.com", "ff8800", "không có", "@", "@safari", "@Ghi ", "@link", "@màu", "@image",
                       "@safari @link", "@safari @image", "@notes bảng", "@@", "x@y"]
        for query in queries {
            model.searchText = query
            let expected = ClipboardSearch.filter(state.history, ClipboardQuery(text: query)).map(\.id)
            #expect(ids == expected, "query: \(query)")
        }
    }

    @Test func atFiltersNarrowByKindAndApp() {
        model.searchText = "@link"
        #expect(ids == [link])
        model.searchText = "@safari "
        #expect(ids == [link, color])
        model.searchText = "@safari @color "
        #expect(ids == [color])
        model.searchText = "@ghi chào"
        #expect(ids == [text])
        model.searchText = "@safari zzz"
        #expect(ids.isEmpty)
        #expect(model.emptyMessage == "Không tìm thấy")
    }

    @Test func finishedAtWordsBecomeChipsThatRemoveThemselves() {
        model.searchText = "@safari chào @link "
        #expect(model.chips.map(\.title) == ["Safari", "Link"])

        model.removeChip(model.chips[0])
        #expect(!model.searchText.contains("@safari"))
        #expect(model.chips.map(\.title) == ["Link"])
    }

    @Test func anAtWordBeingTypedOffersSuggestionsThatComplete() {
        model.searchText = "@"
        #expect(model.suggestions.isOpen)

        model.searchText = "@li"
        #expect(model.suggestions.items.first?.token == "@link")
        model.acceptSuggestion(at: 0)
        #expect(model.searchText == "@link ")
        #expect(ids == [link])
        #expect(!model.suggestions.isOpen)
    }

    @Test func returnCompletesASuggestionInsteadOfUsingTheItem() {
        model.searchText = "@li"
        #expect(model.handleKey(.activate))
        #expect(model.searchText == "@link ")
        #expect(actions.activated.isEmpty)
        #expect(closeCount == 0)
    }

    @Test func escapeClosesTheSuggestionsBeforeThePanel() {
        model.searchText = "@"
        #expect(model.handleKey(.close))
        #expect(!model.suggestions.isOpen)
        #expect(closeCount == 0)

        #expect(model.handleKey(.close))
        #expect(closeCount == 1)
    }

    @Test func tabWithNothingToCompleteStaysWithTheField() {
        #expect(!model.handleKey(.complete))
    }

    // MARK: Using an item

    @Test func returnUsesTheSelectedItem() {
        _ = model.handleKey(.next)
        #expect(model.handleKey(.activate))
        #expect(actions.activated == [link])
    }

    @Test func clickingARowSelectsItAndUsesIt() {
        model.activate(image)
        #expect(actions.activated == [image])
        #expect(model.selectedID == image)
    }

    @Test func anItemThatIsNotShownIsNotUsed() {
        model.searchText = "@link"
        model.activate(text)
        model.activate(UUID())
        #expect(actions.activated.isEmpty)
    }

    // MARK: Pinned or not

    @Test(arguments: [ClipboardPaster.Outcome.pasted, .copied, .copiedNeedsPermission])
    func anActionClosesAnUnpinnedPanelWithoutTouchingTheKeyboardHandBack(outcome: ClipboardPaster.Outcome) {
        actions.outcome = outcome
        model.activate(text)
        #expect(closeCount == 1)
        #expect(keyboardReturns == 0)
    }

    @Test(arguments: [ClipboardPaster.Outcome.pasted, .copied, .copiedNeedsPermission])
    func anActionKeepsAPinnedPanelOpenAndHandsTheKeyboardBack(outcome: ClipboardPaster.Outcome) {
        pin()
        actions.outcome = outcome
        model.activate(text)
        #expect(closeCount == 0)
        #expect(keyboardReturns == 1)
    }

    @Test func aPinnedPanelSaysWhatACopyDid() {
        pin()
        actions.outcome = .pasted
        model.activate(text)
        #expect(model.notice == nil)

        actions.outcome = .copied
        model.activate(text)
        #expect(model.notice?.text == "Đã chép")

        actions.outcome = .copiedNeedsPermission
        model.activate(text)
        #expect(model.notice?.text == "Đã chép — nhấn ⌘V để dán")
    }

    @Test func aFailedActionKeepsTheKeyboardAndTheWindowWhetherPinnedOrNot() {
        actions.outcome = .failed
        model.activate(text)
        #expect(closeCount == 0)
        #expect(keyboardReturns == 0)
        #expect(model.notice?.text == "Không chép được mục này")

        pin()
        model.activate(text)
        #expect(closeCount == 0)
        #expect(keyboardReturns == 0)
        #expect(model.notice?.text == "Không chép được mục này")
    }

    @Test func aStoppedModuleClosesThePanel() {
        actions.outcome = nil
        model.activate(text)
        #expect(closeCount == 1)
    }

    @Test func eachNoticeHasItsOwnId() {
        pin()
        actions.outcome = .copied
        model.activate(text)
        let first = model.notice?.id
        model.activate(text)
        #expect(model.notice?.id != first)
    }

    @Test func escapeClosesEvenAPinnedPanelAndEvenWithTextInTheField() {
        pin()
        model.searchText = "chào"
        #expect(model.handleKey(.clearSearch))
        #expect(closeCount == 1)
    }

    @Test func losingTheKeyboardClosesAnUnpinnedPanelOnly() {
        model.focusLost()
        #expect(closeCount == 1)

        pin()
        closeCount = 0
        model.focusLost()
        #expect(closeCount == 0)
    }

    @Test func closingHappensOnceHoweverOftenItIsAsked() {
        model.focusLost()
        model.focusLost()
        _ = model.handleKey(.close)
        model.activate(text)
        #expect(closeCount == 1)
        #expect(actions.activated.isEmpty)
    }

    @Test func aClosedPanelNoLongerActs() {
        model.detach()
        #expect(!model.pick(number: 1))
        model.activate(text)
        #expect(actions.activated.isEmpty)
        #expect(closeCount == 0)
    }

    @Test func pinningTogglesAndIsReported() {
        #expect(!model.isPinned)
        model.togglePin()
        #expect(model.isPinned)
        model.togglePin()
        #expect(!model.isPinned)
        #expect(pinChanges == [true, false])
    }

    @Test func aPanelOpenedPinnedStartsPinned() {
        pin()
        #expect(model.isPinned)
        #expect(pinChanges.isEmpty)
    }

    @Test func aMoveIsReportedOnlyWhilePinned() {
        model.moved(to: CGPoint(x: 10, y: 20))
        #expect(moves.isEmpty)

        model.togglePin()
        model.moved(to: CGPoint(x: 30, y: 40))
        #expect(moves == [CGPoint(x: 30, y: 40)])
    }

    // MARK: Words

    @Test func rowsSayTheirKindContentTimeAndPin() {
        let label = model.accessibilityLabel(for: model.items[1])
        #expect(label.contains("example.com"))
        #expect(label.contains("đã ghim"))
        #expect(!model.accessibilityLabel(for: model.items[0]).contains("đã ghim"))
        let newest = model.items[0]
        #expect(model.timeLabel(for: newest) == ClipboardCardText.relativeTime(newest.copiedAt, now: Self.start))
        #expect(model.timeLabel(for: newest).contains("phút"))
    }
}
