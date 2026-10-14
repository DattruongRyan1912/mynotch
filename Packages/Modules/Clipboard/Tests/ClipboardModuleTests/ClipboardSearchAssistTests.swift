import Foundation
import Testing
@testable import ClipboardModule

/// What the notch tab's state and the library's model do with `@` tokens: filter, suggest, complete and show chips.
@Suite struct ClipboardStateSearchTests {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    let state = ClipboardState()
    let chromeText: UUID, safariLink: UUID, chromeColor: UUID

    init() {
        var history = ClipboardHistory()
        func add(_ content: ClipboardContent, bundle: String, app: String, seconds: Double) -> UUID {
            history.add(content, hash: ClipboardContent.hash(of: content), source: (bundle, app), at: Self.start + seconds).id
        }
        chromeText = add(.text("Xin chào"), bundle: "com.google.Chrome", app: "Google Chrome", seconds: 1)
        safariLink = add(.link(URL(string: "https://example.com")!), bundle: "com.apple.Safari", app: "Safari", seconds: 2)
        chromeColor = add(.color(hex: "#FF8800", original: "rgb(255, 136, 0)"), bundle: "com.google.Chrome", app: "Google Chrome", seconds: 3)
        state.history = history
    }

    var visible: [UUID] { state.visibleItems.map(\.id) }

    @Test func tokensFilterWhatTheTabShows() {
        state.query.text = "@link"
        #expect(visible == [safariLink])
        state.query.text = "@chrome"
        #expect(visible == [chromeColor, chromeText])
        state.query.text = "@chrome @color"
        #expect(visible == [chromeColor])
        state.query.text = "@chrome xin"
        #expect(visible == [chromeText])
        state.query.text = ""
        #expect(visible.count == 3)
    }

    @Test func aTokenAndTheKindChipCombine() {
        state.query.kind = .link
        state.query.text = "@chrome"
        #expect(visible.isEmpty)
        state.query.text = "@safari"
        #expect(visible == [safariLink])
    }

    @Test func theListOpensWhileATokenIsBeingTypedAndClosesAfterwards() {
        state.query.text = "@"
        #expect(state.suggestions.isOpen)
        #expect(state.suggestions.items.map(\.token) == ["@text", "@link", "@image", "@color", "@file", "@Chrome", "@Safari"])
        state.query.text = "@ch"
        #expect(state.suggestions.items.map(\.token) == ["@Chrome"])
        state.query.text = "@chrome "
        #expect(!state.suggestions.isOpen)
        state.query.text = "hello"
        #expect(!state.suggestions.isOpen)
    }

    @Test func theKeysMoveCompleteAndCloseTheList() {
        state.query.text = "xin @"
        #expect(state.handleSuggestionKey(.next))
        #expect(state.suggestions.highlighted == 1)
        #expect(state.handleSuggestionKey(.previous))
        #expect(state.handleSuggestionKey(.next))
        // "@link".
        #expect(state.handleSuggestionKey(.complete))
        #expect(state.query.text == "xin @link ")
        #expect(!state.suggestions.isOpen)
        #expect(visible.isEmpty)
        #expect(!state.handleSuggestionKey(.complete))
    }

    @Test func returnCompletesToo() {
        state.query.text = "@ch"
        #expect(state.handleSuggestionKey(.activate))
        #expect(state.query.text == "@Chrome ")
        #expect(visible == [chromeColor, chromeText])
    }

    @Test func escClosesTheListAndLeavesTheText() {
        state.query.text = "@l"
        #expect(state.handleSuggestionKey(.clearSearch))
        #expect(!state.suggestions.isOpen)
        #expect(state.query.text == "@l")
        // A history change with the same text does not bring it back.
        state.history.touch(id: chromeText, at: Self.start + 10)
        #expect(!state.suggestions.isOpen)
        // The next Esc is not for the list.
        #expect(!state.handleSuggestionKey(.clearSearch))
    }

    @Test func aClickCompletesTheRowClicked() {
        state.query.text = "@"
        state.acceptSuggestion(at: 3)
        #expect(state.query.text == "@color ")
        #expect(visible == [chromeColor])
    }

    @Test func movingTheHighlightKeepsTheSelectionAndTheVisibleItems() {
        state.query.text = "@"
        state.selectedID = chromeText
        let before = visible
        _ = state.handleSuggestionKey(.next)
        #expect(state.selectedID == chromeText)
        #expect(visible == before)
    }

    @Test func chipsAreTheFinishedTokens() {
        state.query.text = "@link"
        #expect(state.chips.isEmpty)
        state.query.text = "@link @chrome "
        #expect(state.chips.map(\.raw) == ["@link", "@chrome"])
        #expect(state.chips.map(\.title) == ["Link", "Google Chrome"])
        state.query.text = "plain words"
        #expect(state.chips.isEmpty)
    }

    @Test func removingAChipTakesTheTokenOutOfTheText() throws {
        state.query.text = "@chrome xin @color "
        let chrome = try #require(state.chips.first)
        state.removeChip(chrome)
        // The other chip stays a chip: it was finished, and removing one does not unfinish the rest.
        #expect(state.query.text == "xin @color ")
        #expect(state.chips.map(\.raw) == ["@color"])
        #expect(visible == [])
        state.removeChip(try #require(state.chips.first))
        #expect(state.query.text == "xin ")
        #expect(visible == [chromeText])
    }

    @Test func anAppCopiedLaterIsSuggestedAndKnown() {
        state.query.text = "@n"
        #expect(state.suggestions.items.isEmpty)
        let content = ClipboardContent.text("note")
        state.history.add(content, hash: ClipboardContent.hash(of: content), source: ("com.apple.Notes", "Ghi chú"), at: Self.start + 20)
        #expect(state.suggestions.items.map(\.token) == ["@Notes"])
        state.query.text = "@notes"
        #expect(state.visibleItems.map(\.sourceAppName) == ["Ghi chú"])
    }

    @Test func resetClosesTheList() {
        state.query.text = "@"
        state.reset()
        #expect(!state.suggestions.isOpen)
        #expect(state.chips.isEmpty)
    }
}

@Suite final class ClipboardLibrarySearchTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    let state = ClipboardState()
    let model: ClipboardLibraryModel
    let chromeText: UUID, safariLink: UUID, chromeColor: UUID, safariText: UUID

    init() {
        var history = ClipboardHistory()
        func add(_ content: ClipboardContent, bundle: String, app: String, seconds: Double) -> UUID {
            history.add(content, hash: ClipboardContent.hash(of: content), source: (bundle, app), at: Self.start + seconds).id
        }
        chromeText = add(.text("Xin chào"), bundle: "com.google.Chrome", app: "Google Chrome", seconds: 1)
        safariLink = add(.link(URL(string: "https://example.com")!), bundle: "com.apple.Safari", app: "Safari", seconds: 2)
        chromeColor = add(.color(hex: "#FF8800", original: "rgb(255, 136, 0)"), bundle: "com.google.Chrome", app: "Google Chrome", seconds: 3)
        safariText = add(.text("Chrome notes"), bundle: "com.apple.Safari", app: "Safari", seconds: 4)
        state.history = history
        model = ClipboardLibraryModel(state: state, actions: FakeLibraryActions(state: state))
    }

    var shown: [UUID] { model.items.map(\.id) }

    @Test func tokensFilterTheLibrary() {
        model.searchText = "@link"
        #expect(shown == [safariLink])
        model.searchText = "@chrome"
        #expect(shown == [chromeColor, chromeText])
        model.searchText = "@màu"
        #expect(shown == [chromeColor])
        model.searchText = "@safari @text"
        #expect(shown == [safariText])
        model.searchText = "@safari chrome"
        #expect(shown == [safariText])
    }

    @Test func tokensApplyOnTopOfTheSidebarSelectionAndTheKindFilter() {
        model.selection = .app("com.google.Chrome")
        model.searchText = "@color"
        #expect(shown == [chromeColor])
        model.searchText = "@safari"
        #expect(shown.isEmpty)
        model.selection = .all
        model.kindFilter = .text
        model.searchText = "@chrome"
        #expect(shown == [chromeText])
        model.searchText = "@link"
        #expect(shown.isEmpty)
    }

    @Test func anAppTokenSeesAnAppCopiedWhileTheWindowIsOpen() {
        model.searchText = "@notes"
        #expect(shown.isEmpty)
        let content = ClipboardContent.text("note")
        state.history.add(content, hash: ClipboardContent.hash(of: content), source: ("com.apple.Notes", "Ghi chú"), at: Self.start + 20)
        #expect(shown.count == 1)
        #expect(model.suggestions.items.map(\.token) == ["@Notes"])
    }

    @Test func theListOpensWhileATokenIsBeingTypedAndAKeyCompletesIt() {
        model.searchText = "@"
        #expect(model.suggestions.items.map(\.token) == ["@text", "@link", "@image", "@color", "@file", "@Chrome", "@Safari"])
        model.searchText = "@s"
        #expect(model.suggestions.items.map(\.token) == ["@Safari"])
        #expect(model.handleSearchKey(.complete))
        #expect(model.searchText == "@Safari ")
        #expect(!model.suggestions.isOpen)
        #expect(shown == [safariText, safariLink])
        #expect(!model.handleSearchKey(.complete))
    }

    @Test func theArrowKeysAndEscActOnTheListOnlyWhileItIsOpen() {
        model.searchText = "hello"
        for command in [ClipboardKeyCommand.next, .previous, .activate, .clearSearch] {
            #expect(!model.handleSearchKey(command))
        }
        model.searchText = "@"
        #expect(model.handleSearchKey(.next))
        #expect(model.suggestions.highlighted == 1)
        #expect(model.handleSearchKey(.clearSearch))
        #expect(!model.suggestions.isOpen)
        #expect(model.searchText == "@")
    }

    @Test func aSortOrSelectionChangeDoesNotReopenAClosedList() {
        model.searchText = "@"
        _ = model.handleSearchKey(.clearSearch)
        model.sort = .oldest
        model.selection = .kind(.text)
        #expect(!model.suggestions.isOpen)
    }

    @Test func chipsAreTheFinishedTokensAndRemovingOneEditsTheText() throws {
        model.searchText = "@safari"
        #expect(model.chips.isEmpty)
        model.searchText = "@safari @text "
        #expect(model.chips.map(\.title) == ["Safari", "Văn bản"])
        #expect(shown == [safariText])
        model.removeChip(try #require(model.chips.first))
        #expect(model.searchText == "@text ")
        #expect(model.chips.map(\.title) == ["Văn bản"])
        #expect(shown == [safariText, chromeText])
    }

    @Test func theEmptyMessageForATokenThatMatchesNothing() {
        model.searchText = "@image"
        #expect(model.items.isEmpty)
        #expect(model.emptyMessage == "Không tìm thấy")
        #expect(!model.showsBoardTiles)
    }
}
