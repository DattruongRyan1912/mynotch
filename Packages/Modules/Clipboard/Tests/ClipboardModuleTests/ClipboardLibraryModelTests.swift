import Foundation
import Testing
@testable import ClipboardModule

/// Stands in for the module: records what the library asks for and changes the state like the module would.
final class FakeLibraryActions: ClipboardLibraryActions {
    let state: ClipboardState
    var outcome: ClipboardPaster.Outcome? = .copied
    private(set) var activated: [UUID] = []
    private(set) var copied: [UUID] = []
    private(set) var deleted: [Set<UUID>] = []
    private(set) var pinned: [(ids: [UUID], board: UUID)] = []

    init(state: ClipboardState) {
        self.state = state
    }

    func activate(_ item: ClipboardItem) -> ClipboardPaster.Outcome? {
        activated.append(item.id)
        return outcome
    }

    func copy(_ item: ClipboardItem, plainText: Bool) -> ClipboardPaster.Outcome? {
        copied.append(item.id)
        return outcome
    }

    func delete(ids: Set<UUID>) {
        deleted.append(ids)
        _ = state.history.remove(ids: ids)
    }

    func pin(ids: [UUID], to boardID: UUID) {
        pinned.append((ids, boardID))
        for id in ids.reversed() { state.history.pin(itemID: id, to: boardID) }
    }

    func createBoard(named name: String) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return state.history.createBoard(name: name)
    }
}

/// The library's view model on a fixture history, newest first: text, link, color, rich text, image, files and a
/// text copied by no app.
@Suite final class ClipboardLibraryModelTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    let state = ClipboardState()
    let actions: FakeLibraryActions
    let model: ClipboardLibraryModel
    let text: UUID, link: UUID, color: UUID, richText: UUID, image: UUID, files: UUID, orphan: UUID
    let work: UUID, empty: UUID

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
        // Added oldest first, so the newest ends on top.
        orphan = add(.text("không có app"), bundle: nil, app: nil)
        files = add(.files([URL(fileURLWithPath: "/Users/me/Báo cáo quý.pdf")]), bundle: "com.apple.finder", app: "Finder")
        image = add(Self.image, bundle: "com.apple.Preview", app: "Xem trước")
        richText = add(.richText(plain: "Bảng giá", rtf: Data("{\\rtf1 Bảng giá}".utf8)), bundle: "com.apple.Notes", app: "Ghi chú")
        color = add(.color(hex: "#FF8800"), bundle: "com.apple.Safari", app: "Safari")
        link = add(.link(URL(string: "https://example.com/a")!), bundle: "com.apple.Safari", app: "Safari")
        text = add(.text("Xin chào"), bundle: "com.apple.Notes", app: "Ghi chú")
        work = history.createBoard(name: "Công việc")
        empty = history.createBoard(name: "Trống")
        history.pin(itemID: link, to: work)
        history.pin(itemID: image, to: work)
        state.history = history
        actions = FakeLibraryActions(state: state)
        let start = Self.start
        model = ClipboardLibraryModel(state: state, actions: actions, now: { start })
    }

    static let image = ClipboardContent.image(ClipboardImage(fileName: "abc.png", pixelWidth: 4, pixelHeight: 3, byteCount: 10))

    static func label(_ item: ClipboardItem) -> String {
        switch item.content {
        case .image: "ảnh"
        case .files(let urls): urls[0].lastPathComponent
        default: item.content.plainText ?? ""
        }
    }

    var shown: [String] { model.items.map(Self.label) }

    // MARK: What each selection shows

    @Test func allShowsEveryItemNewestFirst() {
        #expect(model.selection == .all)
        #expect(shown == ["Xin chào", "https://example.com/a", "#FF8800", "Bảng giá", "ảnh", "Báo cáo quý.pdf", "không có app"])
    }

    @Test func aBoardShowsItsItemsInHistoryOrder() {
        model.selection = .board(work)
        #expect(shown == ["https://example.com/a", "ảnh"])
        model.selection = .board(empty)
        #expect(shown.isEmpty)
    }

    @Test func aKindShowsItsItemsAndTextIncludesRichText() {
        model.selection = .kind(.text)
        #expect(shown == ["Xin chào", "Bảng giá", "không có app"])
        model.selection = .kind(.color)
        #expect(shown == ["#FF8800"])
        model.selection = .kind(.file)
        #expect(shown == ["Báo cáo quý.pdf"])
    }

    @Test func anAppShowsTheItemsItCopied() {
        model.selection = .app("com.apple.Safari")
        #expect(shown == ["https://example.com/a", "#FF8800"])
    }

    @Test func theKindFilterNarrowsAnySelection() {
        model.kindFilter = .link
        #expect(shown == ["https://example.com/a"])
        model.selection = .board(work)
        #expect(shown == ["https://example.com/a"])
        model.kindFilter = .image
        #expect(shown == ["ảnh"])
        model.selection = .app("com.apple.Notes")
        #expect(shown.isEmpty)
    }

    @Test func aKindFilterThatDisagreesWithAKindSelectionShowsNothing() {
        model.selection = .kind(.text)
        model.kindFilter = .link
        #expect(shown.isEmpty)
        model.kindFilter = .text
        #expect(shown == ["Xin chào", "Bảng giá", "không có app"])
    }

    // MARK: Search

    @Test func searchMatchesLikeTheNotchTab() {
        model.searchText = "bang gia"
        #expect(shown == ["Bảng giá"])
        // The source app's name is searched too, ignoring case and diacritics.
        model.searchText = "GHI CHU"
        #expect(shown == ["Xin chào", "Bảng giá"])
        model.searchText = "chào ghi"
        #expect(shown == ["Xin chào"])
        model.searchText = "  "
        #expect(model.items.count == 7)
    }

    @Test func searchAppliesOnTopOfTheSelectionAndTheKindFilter() {
        model.searchText = "example"
        model.selection = .board(work)
        #expect(shown == ["https://example.com/a"])
        model.selection = .board(empty)
        #expect(shown.isEmpty)
        model.selection = .all
        model.kindFilter = .text
        #expect(shown.isEmpty)
    }

    // MARK: Sort

    @Test func sortsByTimeBothWays() {
        model.sort = .oldest
        #expect(shown == ["không có app", "Báo cáo quý.pdf", "ảnh", "Bảng giá", "#FF8800", "https://example.com/a", "Xin chào"])
        model.sort = .newest
        #expect(shown.first == "Xin chào")
    }

    @Test func sortsByAppThenNewestWithItemsOfNoAppLast() {
        model.sort = .byApp
        // Finder, Ghi chú, Safari, Xem trước (by name, ignoring diacritics), then no app.
        #expect(shown == ["Báo cáo quý.pdf", "Xin chào", "Bảng giá", "https://example.com/a", "#FF8800", "ảnh", "không có app"])
    }

    @Test func sortsByKindThenNewest() {
        model.sort = .byKind
        #expect(shown == ["Xin chào", "Bảng giá", "không có app", "https://example.com/a", "ảnh", "#FF8800", "Báo cáo quý.pdf"])
    }

    // MARK: Counts

    @Test func countsEverySectionOfTheSidebar() {
        let counts = model.counts
        #expect(counts.all == 7)
        #expect(counts.boards == [work: 2, empty: 0])
        #expect(counts.kinds == [.text: 3, .link: 1, .image: 1, .file: 1, .color: 1])
        // By count, then by name; the item no app copied is in no row.
        #expect(counts.apps.map(\.id) == ["com.apple.Notes", "com.apple.Safari", "com.apple.finder", "com.apple.Preview"])
        #expect(counts.apps.map(\.count) == [2, 2, 1, 1])
        #expect(counts.apps.map(\.name) == ["Ghi chú", "Safari", "Finder", "Xem trước"])
    }

    @Test func countsIgnoreTheSearchAndTheFilters() {
        model.searchText = "xin"
        model.kindFilter = .link
        model.selection = .kind(.image)
        #expect(model.counts.all == 7)
        #expect(model.counts.kinds[.text] == 3)
    }

    @Test func anAppRowTakesTheLatestNameAndAppsWithoutABundleGroupByName() {
        state.history.add(.text("mới"), hash: "x", source: ("com.apple.Notes", "Notes"), at: Self.start)
        state.history.add(.text("b"), hash: "y", source: (nil, "CLI tool"), at: Self.start)
        state.history.add(.text("c"), hash: "z", source: (nil, "CLI tool"), at: Self.start)
        let notes = model.counts.apps.first { $0.bundleID == "com.apple.Notes" }
        #expect(notes?.name == "Notes")
        #expect(notes?.count == 3)
        let cli = model.counts.apps.first { $0.bundleID == nil }
        #expect(cli?.name == "CLI tool")
        #expect(cli?.count == 2)
        model.selection = .app(cli!.id)
        #expect(shown == ["c", "b"])
    }

    // MARK: Live updates

    @Test func theLibraryFollowsTheStoreWhileItIsOpen() {
        model.selection = .kind(.link)
        model.searchText = "example"
        state.history.add(.link(URL(string: "https://example.org")!), hash: "new", source: ("com.apple.Safari", "Safari"), at: Self.start)

        #expect(shown == ["https://example.org", "https://example.com/a"])
        #expect(model.counts.all == 8)
        #expect(model.counts.kinds[.link] == 2)
        #expect(model.counts.apps.first { $0.id == "com.apple.Safari" }?.count == 3)

        state.history.pin(itemID: model.items[0].id, to: empty)
        #expect(model.counts.boards[empty] == 1)
        #expect(model.pinnedIDs.contains(model.items[0].id))
    }

    @Test func aSelectionWhoseBoardOrAppIsGoneFallsBackToAll() {
        model.selection = .board(work)
        state.history.deleteBoard(id: work)
        #expect(model.selection == .all)

        model.selection = .app("com.apple.finder")
        _ = state.history.remove(ids: [files])
        #expect(model.selection == .all)
        model.selection = .kind(.file)
        #expect(model.selection == .kind(.file))
    }

    @Test func detachingStopsFollowingTheStore() {
        model.detach()
        state.history.add(.text("sau"), hash: "later", source: (nil, nil), at: Self.start)
        #expect(model.counts.all == 7)
    }

    @Test func aStoppedModuleLeavesAnEmptyLibrary() {
        state.reset()
        #expect(model.items.isEmpty)
        #expect(model.counts.all == 0)
        #expect(model.counts.apps.isEmpty)
    }

    // MARK: Time

    @Test func timesReadFromTheInjectedClock() {
        let item = state.history.items[0]
        #expect(model.timeLabel(for: item) == "1 phút trước")
        let later = ClipboardLibraryModel(state: state, actions: actions, now: { Self.start.addingTimeInterval(30) })
        defer { later.detach() }
        let recent = ClipboardItem(
            id: UUID(), content: .text("x"), contentHash: "x", copiedAt: Self.start, sourceBundleID: nil, sourceAppName: nil
        )
        #expect(later.timeLabel(for: recent) == "Vừa xong")
        #expect(model.timeLabel(for: recent) == "Vừa xong")
        #expect(model.timeLabel(for: state.history.items[6]) == "7 phút trước")
    }

    // MARK: Titles and empty states

    @Test func theTitleNamesTheSelection() {
        #expect(model.title == "Tất cả")
        model.selection = .board(work)
        #expect(model.title == "Công việc")
        model.selection = .kind(.image)
        #expect(model.title == "Ảnh")
        model.selection = .app("com.apple.Notes")
        #expect(model.title == "Ghi chú")
    }

    @Test func emptyStatesSayWhy() {
        #expect(model.emptyMessage == nil)
        model.selection = .board(empty)
        #expect(model.emptyMessage == "Board trống — kéo mục vào đây")
        model.searchText = "xyz"
        #expect(model.emptyMessage == "Không tìm thấy")
        model.searchText = ""
        model.selection = .all
        model.kindFilter = .color
        model.searchText = "xin"
        #expect(model.emptyMessage == "Không tìm thấy")
        state.reset()
        model.searchText = ""
        model.kindFilter = nil
        #expect(model.emptyMessage == "Chưa có gì trong lịch sử")
    }

    @Test func boardTilesShowOnlyForAllWithoutASearch() {
        #expect(model.showsBoardTiles)
        model.searchText = "xin"
        #expect(!model.showsBoardTiles)
        model.searchText = ""
        model.selection = .kind(.text)
        #expect(!model.showsBoardTiles)
    }

    // MARK: Actions

    @Test func theActivationOfAnItemGoesToTheModuleAndReportsWhatHappened() {
        let item = model.items[0]
        #expect(model.activate(item.id))
        #expect(actions.activated == [item.id])
        #expect(model.notice?.text == "Đã chép")

        actions.outcome = .copiedNeedsPermission
        model.activate(item.id)
        #expect(model.notice?.text == "Đã chép — nhấn ⌘V để dán")

        actions.outcome = .failed
        model.activate(item.id)
        #expect(model.notice?.text == "Không chép được mục này")

        actions.outcome = .pasted
        model.activate(item.id)
        #expect(model.notice == nil)
        #expect(!model.activate(UUID()))
    }

    @Test func aNoticeIsDismissedByItsOwnIDOnly() {
        actions.outcome = .copied
        model.activate(model.items[0].id)
        let first = model.notice
        model.activate(model.items[0].id)
        let second = model.notice
        #expect(first != second)

        model.dismissNotice(first!.id)
        #expect(model.notice == second)
        model.dismissNotice(second!.id)
        #expect(model.notice == nil)
    }

    @Test func returnActivatesTheFocusedItemAndCommandCCopiesIt() {
        #expect(!model.activateSelection())
        #expect(!model.copySelection())

        model.select(model.items[2].id, mode: .replace)
        #expect(model.activateSelection())
        #expect(model.copySelection())
        #expect(actions.activated == [model.items[2].id])
        #expect(actions.copied == [model.items[2].id])
    }

    // MARK: Selection

    @Test func aPlainClickSelectsOnlyThatItem() {
        let ids = model.items.map(\.id)
        model.select(ids[1], mode: .replace)
        model.select(ids[3], mode: .replace)
        #expect(model.selectedIDs == [ids[3]])
        #expect(model.focusID == ids[3])
    }

    @Test func commandClickTogglesAnItem() {
        let ids = model.items.map(\.id)
        model.select(ids[1], mode: .replace)
        model.select(ids[3], mode: .toggle)
        #expect(model.selectedIDs == [ids[1], ids[3]])
        #expect(model.focusID == ids[3])
        model.select(ids[3], mode: .toggle)
        #expect(model.selectedIDs == [ids[1]])
        #expect(model.focusID == ids[1])
    }

    @Test func shiftClickSelectsTheRangeFromTheAnchorInDisplayOrder() {
        let ids = model.items.map(\.id)
        model.select(ids[1], mode: .replace)
        model.select(ids[4], mode: .range)
        #expect(model.selectedIDs == Set(ids[1...4]))
        model.select(ids[2], mode: .range)
        #expect(model.selectedIDs == Set(ids[1...2]))
        model.sort = .oldest
        model.select(ids[0], mode: .range)
        #expect(model.selectedIDs == Set(ids[0...1]))
    }

    @Test func aRangeWithoutAnAnchorSelectsJustTheClickedItem() {
        let ids = model.items.map(\.id)
        model.select(ids[3], mode: .range)
        #expect(model.selectedIDs == [ids[3]])
    }

    @Test func selectAllAndClear() {
        model.selection = .kind(.text)
        model.selectAll()
        #expect(model.selectedIDs.count == 3)
        model.clearSelection()
        #expect(model.selectedIDs.isEmpty)
        #expect(model.focusID == nil)
    }

    @Test func itemsThatLeaveTheViewLeaveTheSelection() {
        let ids = model.items.map(\.id)
        model.select(ids[0], mode: .replace)
        model.select(ids[1], mode: .toggle)
        model.searchText = "xin"
        #expect(model.selectedIDs == [ids[0]])
        #expect(model.focusID == ids[0])
        model.searchText = "example"
        #expect(model.selectedIDs.isEmpty)
        #expect(model.focusID == nil)
    }

    // MARK: Keyboard

    @Test func arrowsMoveByOneInTheListAndByAColumnCountInTheGrid() {
        let ids = model.items.map(\.id)
        model.layout = .list
        model.columns = 3
        model.move(.down, extend: false)
        #expect(model.focusID == ids[0])
        model.move(.down, extend: false)
        #expect(model.focusID == ids[1])
        model.move(.up, extend: false)
        #expect(model.focusID == ids[0])
        model.move(.up, extend: false)
        #expect(model.focusID == ids[0])

        model.layout = .grid
        model.move(.right, extend: false)
        #expect(model.focusID == ids[1])
        model.move(.down, extend: false)
        #expect(model.focusID == ids[4])
        // Nothing is below ids[4] (the last row has one card), so it goes to the last card, then stays.
        model.move(.down, extend: false)
        #expect(model.focusID == ids[6])
        model.move(.down, extend: false)
        #expect(model.focusID == ids[6])
        model.move(.up, extend: false)
        #expect(model.focusID == ids[3])
        for _ in 0..<4 { model.move(.left, extend: false) }
        #expect(model.focusID == ids[0])
        model.move(.up, extend: false)
        #expect(model.focusID == ids[0])
    }

    @Test func movingFromTheFirstRowDownReachesAShortLastRow() {
        let ids = model.items.map(\.id)
        model.columns = 4
        model.select(ids[3], mode: .replace)
        model.move(.down, extend: false)
        #expect(model.focusID == ids[6])
        model.move(.down, extend: false)
        #expect(model.focusID == ids[6])
    }

    @Test func shiftArrowsExtendTheRangeFromTheAnchor() {
        let ids = model.items.map(\.id)
        model.layout = .list
        model.select(ids[1], mode: .replace)
        model.move(.down, extend: true)
        model.move(.down, extend: true)
        #expect(model.selectedIDs == Set(ids[1...3]))
        model.move(.up, extend: true)
        #expect(model.selectedIDs == Set(ids[1...2]))
        #expect(model.focusID == ids[2])
    }

    @Test func movingInAnEmptyViewDoesNothing() {
        model.selection = .board(empty)
        model.move(.down, extend: false)
        #expect(model.focusID == nil)
        #expect(model.selectedIDs.isEmpty)
    }

    // MARK: Delete

    @Test func deletingUnpinnedItemsHappensAtOnceAndSelectsTheNeighbour() {
        let ids = model.items.map(\.id)
        model.select(ids[2], mode: .replace)
        model.requestDelete()

        #expect(actions.deleted == [[ids[2]]])
        #expect(model.pendingDeletion == nil)
        #expect(model.items.count == 6)
        #expect(model.selectedIDs == [ids[3]])
        #expect(model.focusID == ids[3])
    }

    @Test func deletingTheLastItemSelectsThePreviousOne() {
        let ids = model.items.map(\.id)
        model.select(ids[6], mode: .replace)
        model.requestDelete()
        #expect(model.selectedIDs == [ids[5]])
    }

    @Test func deletingPinnedItemsAsksFirst() {
        let ids = model.items.map(\.id)
        model.select(ids[1], mode: .replace)
        model.select(ids[0], mode: .toggle)
        model.requestDelete()

        #expect(actions.deleted.isEmpty)
        #expect(model.pendingDeletion == [ids[0], ids[1]])
        #expect(model.pendingDeletionIncludesPinned)

        model.cancelDelete()
        #expect(model.pendingDeletion == nil)
        #expect(model.items.count == 7)

        model.requestDelete()
        model.confirmDelete()
        #expect(actions.deleted == [[ids[0], ids[1]]])
        #expect(model.pendingDeletion == nil)
        #expect(model.items.count == 5)
    }

    @Test func deletingWithNothingSelectedDoesNothing() {
        model.requestDelete()
        #expect(actions.deleted.isEmpty)
        #expect(model.pendingDeletion == nil)
    }

    @Test func aPendingDeletionLosesItemsThatAreGone() {
        let ids = model.items.map(\.id)
        model.select(ids[1], mode: .replace)
        model.requestDelete()
        #expect(model.pendingDeletion == [ids[1]])
        _ = state.history.remove(ids: [ids[1]])
        #expect(model.pendingDeletion == nil)
    }

    // MARK: Boards

    @Test func creatingABoardSelectsIt() throws {
        #expect(model.createBoard(named: "   ") == nil)
        let id = try #require(model.createBoard(named: " Mới "))
        #expect(model.selection == .board(id))
        #expect(model.title == "Mới")
        #expect(model.history.boards.map(\.name) == ["Công việc", "Trống", "Mới"])
    }

    @Test func creatingABoardForAnItemPinsIt() throws {
        let item = model.items[0].id
        let id = try #require(model.createBoard(named: "Mới", pinning: [item]))
        #expect(model.counts.boards[id] == 1)
        #expect(actions.pinned.map(\.ids) == [[item]])
    }

    @Test func droppingTheDraggedItemsOnABoardAddsThem() {
        let ids = model.items.map(\.id)
        #expect(model.beginDrag(of: ids[0]) == [ids[0]])
        #expect(model.drop(onBoard: empty))

        #expect(actions.pinned.map(\.ids) == [[ids[0]]])
        #expect(actions.pinned.map(\.board) == [empty])
        #expect(model.counts.boards[empty] == 1)
        #expect(model.notice?.text == "Đã thêm 1 mục vào “Trống”")
        // The drag is over once dropped.
        #expect(!model.drop(onBoard: empty))
    }

    @Test func draggingASelectedItemCarriesTheWholeSelectionInDisplayOrder() {
        let ids = model.items.map(\.id)
        model.select(ids[4], mode: .replace)
        model.select(ids[2], mode: .toggle)
        #expect(model.beginDrag(of: ids[4]) == [ids[2], ids[4]])
        #expect(model.drop(onBoard: empty))
        #expect(actions.pinned.map(\.ids) == [[ids[2], ids[4]]])
        #expect(model.notice?.text == "Đã thêm 2 mục vào “Trống”")
    }

    @Test func draggingAnUnselectedItemCarriesOnlyIt() {
        let ids = model.items.map(\.id)
        model.select(ids[4], mode: .replace)
        #expect(model.beginDrag(of: ids[1]) == [ids[1]])
        model.endDrag()
        #expect(!model.drop(onBoard: empty))
        #expect(actions.pinned.isEmpty)
    }

    @Test func dropsOnAnUnknownBoardAreRefused() {
        let ids = model.items.map(\.id)
        _ = model.beginDrag(of: ids[0])
        #expect(!model.drop(onBoard: UUID()))
        #expect(actions.pinned.isEmpty)
    }

    @Test func addingTheSelectionToABoardFromTheMenu() {
        let ids = model.items.map(\.id)
        model.select(ids[0], mode: .replace)
        model.select(ids[1], mode: .toggle)
        model.addSelection(toBoard: empty)
        #expect(actions.pinned.map(\.ids) == [[ids[0], ids[1]]])
        #expect(model.counts.boards[empty] == 2)
    }

    // MARK: Preferences

    @Test func viewPreferencesAreReportedWhenTheyChange() {
        var reported: [ClipboardLibraryPreferences] = []
        model.onPreferencesChange = { reported.append($0) }
        model.layout = .list
        model.sort = .byApp
        model.cardSize = .large
        model.layout = .list
        model.selection = .kind(.text)
        model.searchText = "x"

        #expect(reported.count == 3)
        #expect(reported.last == ClipboardLibraryPreferences(layout: .list, sort: .byApp, cardSize: .large))
    }

    @Test func theModelStartsFromThePreferencesItIsGiven() {
        let model = ClipboardLibraryModel(
            state: state, actions: actions, preferences: ClipboardLibraryPreferences(layout: .list, sort: .oldest, cardSize: .small)
        )
        defer { model.detach() }
        #expect(model.layout == .list)
        #expect(model.sort == .oldest)
        #expect(model.cardSize == .small)
        #expect(model.items.last.map(Self.label) == "Xin chào")
    }
}
