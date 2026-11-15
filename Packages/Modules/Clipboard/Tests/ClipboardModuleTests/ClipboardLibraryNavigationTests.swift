import Foundation
import Testing
@testable import ClipboardModule

/// The back and forward list as a value: places are pushed, a new branch cuts off the old forward ones, and it never grows
/// past its bound.
@Suite struct ClipboardLibraryNavigationTests {
    typealias Place = ClipboardLibraryNavigation.Place

    static func place(_ selection: ClipboardLibrarySelection = .all, kind: ClipboardKind? = nil, search: String = "", selected: UUID? = nil) -> Place {
        Place(selection: selection, kindFilter: kind, searchText: search, selectedID: selected)
    }

    static let all = place()
    static let links = place(.kind(.link))
    static let images = place(.kind(.image))
    static let apps = place(.app("com.apple.Safari"))

    @Test func startsOnOnePlaceWithNowhereToGo() {
        let navigation = ClipboardLibraryNavigation(start: Self.all)
        #expect(navigation.current == Self.all)
        #expect(!navigation.canGoBack && !navigation.canGoForward)
        var copy = navigation
        #expect(copy.back() == nil)
        #expect(copy.forward() == nil)
        #expect(copy == navigation)
    }

    @Test func visitingMovesOnAndBackAndForwardWalkTheWay() {
        var navigation = ClipboardLibraryNavigation(start: Self.all)
        navigation.visit(Self.links)
        navigation.visit(Self.images)
        #expect(navigation.current == Self.images)
        #expect(navigation.canGoBack && !navigation.canGoForward)

        #expect(navigation.back() == Self.links)
        #expect(navigation.back() == Self.all)
        #expect(navigation.back() == nil)
        #expect(navigation.current == Self.all)
        #expect(navigation.canGoForward && !navigation.canGoBack)

        #expect(navigation.forward() == Self.links)
        #expect(navigation.forward() == Self.images)
        #expect(navigation.forward() == nil)
    }

    @Test func visitingWhereYouAreChangesNothing() {
        var navigation = ClipboardLibraryNavigation(start: Self.all)
        navigation.visit(Self.all)
        #expect(navigation.places == [Self.all])
        navigation.visit(Self.links)
        navigation.visit(Self.links)
        #expect(navigation.places == [Self.all, Self.links])
    }

    @Test func aNewPlaceAfterGoingBackCutsOffTheOldForwardOnes() {
        var navigation = ClipboardLibraryNavigation(start: Self.all)
        navigation.visit(Self.links)
        navigation.visit(Self.images)
        _ = navigation.back()
        #expect(navigation.current == Self.links)

        navigation.visit(Self.apps)

        #expect(navigation.places == [Self.all, Self.links, Self.apps])
        #expect(!navigation.canGoForward)
        #expect(navigation.back() == Self.links)
    }

    @Test func itKeepsOnlyTheLatestFiftyPlaces() {
        var navigation = ClipboardLibraryNavigation(start: Self.place(search: "0"))
        for number in 1...79 { navigation.visit(Self.place(search: "\(number)")) }
        #expect(ClipboardLibraryNavigation.limit == 50)
        #expect(navigation.places.count == 50)
        #expect(navigation.current.searchText == "79")
        // The oldest are gone; the newest fifty are all reachable and nothing earlier is.
        var steps = 0
        while navigation.back() != nil { steps += 1 }
        #expect(steps == 49)
        #expect(navigation.current.searchText == "30")
        #expect(navigation.forward()?.searchText == "31")
    }

    @Test func reviseChangesWhereYouAreWithoutAddingAPlace() {
        var navigation = ClipboardLibraryNavigation(start: Self.all)
        navigation.visit(Self.links)
        let picked = UUID()
        navigation.revise(Self.place(.kind(.link), selected: picked))
        #expect(navigation.places == [Self.all, Self.place(.kind(.link), selected: picked)])
        #expect(navigation.index == 1)
        // Going back and forward finds the pick where it was left.
        _ = navigation.back()
        #expect(navigation.forward()?.selectedID == picked)
    }

    @Test func reviseInTheMiddleLeavesTheForwardPlacesAlone() {
        var navigation = ClipboardLibraryNavigation(start: Self.all)
        navigation.visit(Self.links)
        navigation.visit(Self.images)
        _ = navigation.back()
        let picked = UUID()
        navigation.revise(Self.place(.kind(.link), selected: picked))
        #expect(navigation.places.map(\.selection) == [.all, .kind(.link), .kind(.image)])
        #expect(navigation.forward() == Self.images)
    }

    @Test func reviseIntoThePlaceBeforeJoinsThemSoBackNeverDoesNothingVisible() {
        var navigation = ClipboardLibraryNavigation(start: Self.all)
        navigation.visit(Self.links)
        // Typing and deleting again leaves a place that equals the one before it.
        navigation.revise(Self.all)
        #expect(navigation.places == [Self.all])
        #expect(navigation.index == 0)
        #expect(!navigation.canGoBack)

        navigation.visit(Self.links)
        navigation.visit(Self.images)
        _ = navigation.back()
        navigation.revise(Self.all)
        #expect(navigation.places == [Self.all, Self.images])
        #expect(navigation.current == Self.all && navigation.index == 0)
        #expect(navigation.forward() == Self.images)
    }

    @Test func removingPlacesKeepsWhereYouAreAndJoinsWhatBecomesEqual() {
        let board = UUID()
        var navigation = ClipboardLibraryNavigation(start: Self.all)
        navigation.visit(Self.place(.board(board)))
        navigation.visit(Self.all)
        navigation.visit(Self.links)
        navigation.visit(Self.place(.board(board)))
        navigation.visit(Self.images)
        _ = navigation.back()
        _ = navigation.back()
        #expect(navigation.current == Self.links)

        navigation.removePlaces { $0.selection == .board(board) }

        #expect(navigation.places == [Self.all, Self.links, Self.images])
        #expect(navigation.current == Self.links)
        #expect(navigation.back() == Self.all)
        #expect(navigation.forward() == Self.links)
    }

    @Test func removingPlacesNeverRemovesTheOneYouAreOn() {
        let board = UUID()
        var navigation = ClipboardLibraryNavigation(start: Self.all)
        navigation.visit(Self.place(.board(board)))
        navigation.removePlaces { $0.selection == .board(board) }
        #expect(navigation.places.count == 2)
        #expect(navigation.current.selection == .board(board))
    }
}

/// What the library window does with them: which changes are places, what a pick of a card is, and what going back puts back.
@Suite final class ClipboardLibraryNavigationModelTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    let state = ClipboardState()
    let actions: FakeLibraryActions
    let model: ClipboardLibraryModel
    let text: UUID, link: UUID, image: UUID, other: UUID
    let work: UUID, spare: UUID

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
        spare = history.createBoard(name: "Dự phòng")
        history.pin(itemID: link, to: work)
        history.pin(itemID: image, to: work)
        state.history = history
        actions = FakeLibraryActions(state: state)
        let start = Self.start
        model = ClipboardLibraryModel(state: state, actions: actions, now: { start })
    }

    var place: ClipboardLibraryNavigation.Place { model.navigation.current }

    // MARK: Which changes are places

    @Test func aFreshLibraryHasNowhereToGoBack() {
        #expect(!model.canGoBack && !model.canGoForward)
        #expect(!model.goBack() && !model.goForward())
        #expect(model.selection == .all)
    }

    @Test func choosingSomethingInTheSidebarIsAPlaceAndBackPutsTheOldOneBack() {
        model.selection = .board(work)
        model.selection = .kind(.text)
        #expect(model.canGoBack)

        #expect(model.goBack())
        #expect(model.selection == .board(work))
        #expect(model.goBack())
        #expect(model.selection == .all)
        #expect(!model.canGoBack && model.canGoForward)

        #expect(model.goForward())
        #expect(model.selection == .board(work))
        #expect(model.goForward())
        #expect(model.selection == .kind(.text))
        #expect(!model.canGoForward)
    }

    @Test func theKindFilterIsAPlaceToo() {
        model.kindFilter = .link
        #expect(model.items.map(\.id) == [link])
        #expect(model.goBack())
        #expect(model.kindFilter == nil)
        #expect(model.items.count == 4)
        #expect(model.goForward())
        #expect(model.kindFilter == .link)
    }

    @Test func goingBackAndForwardAddsNoPlaces() {
        model.selection = .board(work)
        model.selection = .kind(.text)
        let places = model.navigation.places
        _ = model.goBack()
        _ = model.goBack()
        _ = model.goForward()
        #expect(model.navigation.places == places)
    }

    @Test func aNewChoiceAfterGoingBackStartsANewBranch() {
        model.selection = .board(work)
        model.selection = .kind(.text)
        _ = model.goBack()
        model.selection = .board(spare)
        #expect(!model.canGoForward)
        #expect(model.goBack())
        #expect(model.selection == .board(work))
    }

    @Test func historyIsBoundedToFiftyPlaces() {
        for index in 0..<120 { model.selection = index.isMultiple(of: 2) ? .kind(.text) : .kind(.link) }
        #expect(model.navigation.places.count == 50)
        var steps = 0
        while model.goBack() { steps += 1 }
        #expect(steps == 49)
    }

    // MARK: Searching

    @Test func typingASearchIsOnePlaceNotOnePerLetter() {
        for text in ["T", "Tạ", "Tạm", "Tạm b"] { model.searchText = text }
        #expect(model.navigation.places.count == 2)
        #expect(model.items.map(\.id) == [text])

        #expect(model.goBack())
        #expect(model.searchText == "")
        #expect(model.items.count == 4)
        #expect(model.goForward())
        #expect(model.searchText == "Tạm b")
    }

    @Test func anotherChoiceInTheMiddleOfTypingEndsTheRun() {
        model.searchText = "Tạ"
        model.selection = .kind(.text)
        model.searchText = "Tạm"
        // Search, then the kind (keeping the search), then more typing: three places after the start.
        #expect(model.navigation.places.count == 4)
        #expect(model.goBack())
        #expect(model.searchText == "Tạ" && model.selection == .kind(.text))
    }

    @Test func aSuggestionOrAChipIsItsOwnPlaceWhateverWasTyped() {
        model.searchText = "@im"
        model.acceptSuggestion(at: 0)
        #expect(model.searchText.hasPrefix("@image"))
        #expect(model.navigation.places.count == 3)
        #expect(model.goBack())
        #expect(model.searchText == "@im")

        _ = model.goForward()
        let chip = model.chips[0]
        model.removeChip(chip)
        #expect(model.navigation.places.count == 4)
        #expect(model.goBack())
        #expect(model.searchText.hasPrefix("@image"))
    }

    @Test func removingAChipRightAfterTypingItIsAPlaceOfItsOwn() {
        model.searchText = "@image "
        let chip = model.chips[0]
        model.removeChip(chip)
        #expect(model.searchText == "")
        #expect(model.navigation.places.map(\.searchText) == ["", "@image ", ""])
        #expect(model.goBack())
        #expect(model.searchText == "@image ")
    }

    @Test func typingBackToWhereYouStartedLeavesNoPlaceToGoBackTo() {
        model.searchText = "T"
        model.searchText = ""
        // Going back from a place that looks like the one before it would do nothing the user could see.
        #expect(!model.goBack())
        #expect(model.searchText == "")
    }

    @Test func typingAgainAfterDeletingEverythingStartsANewPlaceAndLeavesTheFirstAlone() {
        model.searchText = "T"
        model.searchText = ""
        model.searchText = "Tạ"
        #expect(model.canGoBack)
        #expect(model.navigation.places.count == 2)
        #expect(model.goBack())
        // The place before the typing is as it was: no search, every card.
        #expect(model.searchText == "")
        #expect(model.items.count == 4)
        #expect(model.goForward())
        #expect(model.searchText == "Tạ")
    }

    // MARK: The selection

    @Test func pickingACardIsPartOfWhereYouAreNotANewPlace() {
        model.select(link, mode: .replace)
        model.select(text, mode: .replace)
        #expect(model.navigation.places.count == 1)
        #expect(place.selectedID == text)
    }

    @Test func goingBackPutsTheSelectionTheWayItWasLeft() {
        model.select(text, mode: .replace)
        model.selection = .kind(.link)
        model.select(link, mode: .replace)

        #expect(model.goBack())
        #expect(model.selection == .all)
        #expect(model.selectedIDs == [text] && model.focusID == text)
        #expect(model.goForward())
        #expect(model.selectedIDs == [link] && model.focusID == link)
    }

    @Test func aSelectionOfAnItemThatIsGoneComesBackAsNoSelection() {
        model.select(text, mode: .replace)
        model.selection = .kind(.link)
        actions.delete(ids: [text])

        #expect(model.goBack())
        #expect(model.selection == .all)
        #expect(model.selectedIDs.isEmpty && model.focusID == nil)
    }

    @Test func aSelectionTheNewPlaceHidesIsNotKept() {
        model.select(text, mode: .replace)
        model.selection = .board(work)
        #expect(model.selectedIDs.isEmpty)
        #expect(place.selectedID == nil)
    }

    @Test func clearingTheSelectionIsRememberedToo() {
        model.select(text, mode: .replace)
        model.clearSelection()
        #expect(place.selectedID == nil)
        model.select(text, mode: .replace)
        model.selectAll()
        #expect(place.selectedID == model.items.last?.id)
    }

    // MARK: A board that goes away

    @Test func aDeletedBoardIsSkippedWhenGoingBack() {
        model.selection = .board(spare)
        model.selection = .kind(.text)
        model.selection = .board(work)
        state.history.deleteBoard(id: spare)

        #expect(model.navigation.places.map(\.selection) == [.all, .kind(.text), .board(work)])
        #expect(model.goBack())
        #expect(model.selection == .kind(.text))
        #expect(model.goBack())
        #expect(model.selection == .all)
    }

    @Test func whenTheBoardOnShowIsDeletedTheFallbackReplacesItsPlace() {
        model.selection = .board(spare)
        state.history.deleteBoard(id: spare)

        #expect(model.selection == .all)
        // Where you are is "all" now, and going back finds the same: nothing to go back to.
        #expect(model.navigation.places == [model.navigation.current])
        #expect(!model.canGoBack)
    }

    @Test func anAppThatNoLongerHasItemsIsSkippedToo() {
        model.selection = .app("com.apple.Safari")
        model.selection = .kind(.text)
        actions.delete(ids: [link])

        #expect(model.goBack())
        #expect(model.selection == .all)
    }

    @Test func creatingABoardIsAPlace() {
        let created = model.createBoard(named: "Mới")
        #expect(created != nil)
        #expect(model.selection == .board(created!))
        #expect(model.goBack())
        #expect(model.selection == .all)
    }
}
