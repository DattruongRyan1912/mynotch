import AppKit
import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardSearchSuggestionsTests {
    func tokens(_ text: String, apps: [ClipboardLibraryApp] = SearchFixtureApps.all) -> [String] {
        ClipboardSearchSuggestions.suggestions(for: text, apps: apps).map(\.token)
    }

    @Test func anAtSignListsTheKindsThenTheAppsInTheOrderGiven() {
        #expect(tokens("@") == ["@text", "@code", "@link", "@image", "@color", "@file", "@Chrome", "@VSCode", "@Safari", "@Notes", "@Lời"])
        #expect(tokens("hello @") == tokens("@"))
    }

    @Test func rowsNameTheKindOrTheApp() throws {
        let rows = ClipboardSearchSuggestions.suggestions(for: "@", apps: SearchFixtureApps.all)
        #expect(rows.map(\.title) == ["Văn bản", "Mã", "Link", "Ảnh", "Màu", "File", "Google Chrome", "Code", "Safari", "Ghi chú", "Lời nhắc"])
        #expect(rows[0].subject == .kind(.text))
        #expect(rows[1].subject == .code)
        #expect(rows[6].subject == .app(bundleID: "com.google.Chrome"))
        #expect(rows[10].subject == .app(bundleID: nil))
    }

    @Test func nothingIsSuggestedUnlessAnAtWordIsBeingTyped() {
        for text in ["", "hello", "hello ", "@link ", "@link\n", "me@", "me@li", " ", "@link hello"] {
            #expect(tokens(text).isEmpty, "\(text.debugDescription)")
        }
    }

    @Test func theListNarrowsAsTheWordGrows() {
        #expect(tokens("@c") == ["@code", "@color", "@Chrome", "@VSCode"])
        #expect(tokens("@co") == ["@code", "@color", "@VSCode"])
        #expect(tokens("@cod") == ["@code", "@VSCode"])
        #expect(tokens("@col") == ["@color"])
        #expect(tokens("@l") == ["@link", "@Lời"])
        #expect(tokens("@li") == ["@link"])
        #expect(tokens("@zzz").isEmpty)
    }

    @Test func matchingIgnoresCaseAndDiacritics() {
        #expect(tokens("@LI") == ["@link"])
        #expect(tokens("@LOI") == ["@Lời"])
        #expect(tokens("@lời") == ["@Lời"])
        #expect(tokens("@GHÍ") == ["@Ghi"])
    }

    @Test func theVietnameseNameOfAKindIsSuggestedWhenItIsWhatMatches() {
        #expect(tokens("@m") == ["@mã", "@màu"])
        #expect(tokens("@mau") == ["@màu"])
        #expect(tokens("@MÀ") == ["@mã", "@màu"])
        // English first when both fit.
        #expect(tokens("@c").first == "@code")
        #expect(tokens("@col").first == "@color")
    }

    @Test func anAppIsOfferedUnderTheNameThatMatched() {
        // The bundle component when it matches.
        #expect(tokens("@v") == ["@VSCode"])
        #expect(tokens("@n") == ["@Notes"])
        // The first word of the display name otherwise.
        #expect(tokens("@gh") == ["@Ghi"])
        #expect(tokens("@goo") == ["@Google"])
        #expect(tokens("@lo") == ["@Lời"])
    }

    @Test func everyTokenOfferedFindsTheAppItCameFrom() throws {
        for typed in ["@", "@c", "@g", "@l", "@s", "@v"] {
            for row in ClipboardSearchSuggestions.suggestions(for: typed, apps: SearchFixtureApps.all) {
                let terms = ClipboardSearchTerms(parsing: row.token + " ", apps: SearchFixtureApps.all)
                let token = try #require(terms.tokens.first, "\(row.token)")
                switch row.subject {
                case .kind(let kind): #expect(token.filter == .kind(kind))
                case .code: #expect(token.filter == .code)
                case .app: #expect(token.title == row.title)
                }
            }
        }
    }

    @Test func aKindAlreadyChosenIsNotOfferedAgain() {
        #expect(tokens("@link @") == ["@Chrome", "@VSCode", "@Safari", "@Notes", "@Lời"])
        #expect(tokens("@link @c") == ["@Chrome", "@VSCode"])
        #expect(tokens("@link @text") == [])
    }

    @Test func codeIsOfferedOnceAndNotWithAnotherKind() {
        #expect(tokens("@code @") == ["@Chrome", "@VSCode", "@Safari", "@Notes", "@Lời"])
        #expect(tokens("@code @c") == ["@Chrome", "@VSCode"])
        #expect(tokens("@text @") == ["@Chrome", "@VSCode", "@Safari", "@Notes", "@Lời"])
        #expect(tokens("@code @text") == [])
    }

    @Test func anAppCalledCodeIsOfferedUnderTheEndOfItsBundleID() {
        // "@Code" would be the code filter; the app is reached as "@VSCode", whatever was typed.
        for typed in ["@c", "@co", "@cod", "@code"] {
            let rows = ClipboardSearchSuggestions.suggestions(for: typed, apps: SearchFixtureApps.all)
            #expect(rows.contains { $0.subject == .app(bundleID: "com.microsoft.VSCode") && $0.token == "@VSCode" }, "\(typed)")
            #expect(!rows.contains { $0.subject != .code && $0.token.lowercased() == "@code" }, "\(typed)")
        }
    }

    @Test func anAppWithNoOtherNameThanCodeIsLeftOut() {
        let apps = [ClipboardLibraryApp(id: "name:Code", bundleID: nil, name: "Code", count: 1)]
        #expect(tokens("@co", apps: apps) == ["@code", "@color"])
    }

    @Test func anAppAlreadyChosenIsNotOfferedAgain() {
        #expect(tokens("@chrome @") == ["@text", "@code", "@link", "@image", "@color", "@file"])
        #expect(tokens("foo @safari @c") == ["@code", "@color"])
        #expect(tokens("@link @chrome @") == [])
    }

    @Test func aWordThatIsNotATokenDoesNotCountAsChosen() {
        #expect(tokens("@nobody @l") == ["@link", "@Lời"])
    }

    @Test func appsWithTheSameTokenAreListedOnce() {
        let apps = [
            ClipboardLibraryApp(id: "com.a.Notes", bundleID: "com.a.Notes", name: "Notes", count: 3),
            ClipboardLibraryApp(id: "com.b.Notes", bundleID: "com.b.Notes", name: "Notes Pro", count: 2),
        ]
        #expect(tokens("@no", apps: apps) == ["@Notes"])
    }

    @Test func aBundleIDThatEndsInADotFallsBackToTheName() {
        let apps = [ClipboardLibraryApp(id: "com.example.", bundleID: "com.example.", name: "Tool", count: 1)]
        #expect(tokens("@t", apps: apps) == ["@text", "@Tool"])
    }

    @Test func onlyTheMostUsedAppsAreListed() {
        let apps = (1...30).map {
            ClipboardLibraryApp(id: "app\($0)", bundleID: "com.example.App\($0)", name: "App \($0)", count: 100 - $0)
        }
        let rows = tokens("@a", apps: apps)
        #expect(rows.count == ClipboardSearchSuggestions.maxApps)
        #expect(rows.first == "@App1")
    }

    @Test func completingReplacesTheWordBeingTyped() throws {
        let link = try #require(ClipboardSearchSuggestions.suggestions(for: "@li", apps: []).first)
        #expect(ClipboardSearchSuggestions.completing("@li", with: link) == "@link ")
        #expect(ClipboardSearchSuggestions.completing("hello @li", with: link) == "hello @link ")
        #expect(ClipboardSearchSuggestions.completing("a  b\t@li", with: link) == "a  b\t@link ")
        #expect(ClipboardSearchSuggestions.completing("@link @li", with: link) == "@link @link ")
    }
}

@Suite struct ClipboardSuggestionListTests {
    let apps = SearchFixtureApps.all

    func makeList(_ text: String) -> ClipboardSuggestionList {
        var list = ClipboardSuggestionList()
        list.update(text: text, apps: apps)
        return list
    }

    @Test func itOpensOnTheFirstRowAndClosesWhenThereIsNothingToOffer() {
        var list = makeList("@")
        #expect(list.isOpen)
        #expect(list.highlighted == 0)
        #expect(list.items.count == 11)
        list.update(text: "@zzz", apps: apps)
        #expect(!list.isOpen)
        list.update(text: "", apps: apps)
        #expect(list.items.isEmpty)
    }

    @Test func downAndUpMoveTheHighlightAndWrapAround() {
        var list = makeList("@")
        list.move(1)
        list.move(1)
        #expect(list.highlighted == 2)
        list.move(-1)
        #expect(list.highlighted == 1)
        list.move(-1)
        list.move(-1)
        #expect(list.highlighted == 10)
        list.move(1)
        #expect(list.highlighted == 0)
    }

    @Test func theHighlightSurvivesAnUpdateWithTheSameRows() {
        var list = makeList("@")
        list.move(1)
        list.update(text: "@", apps: apps)
        #expect(list.highlighted == 1)
    }

    @Test func theHighlightStartsAgainWhenTheRowsChange() {
        var list = makeList("@")
        list.move(1)
        list.move(1)
        list.update(text: "@c", apps: apps)
        #expect(list.items.map(\.token) == ["@code", "@color", "@Chrome", "@VSCode"])
        #expect(list.highlighted == 0)
    }

    @Test func movingAClosedListDoesNothing() {
        var list = makeList("hello")
        list.move(1)
        #expect(list.highlighted == 0)
    }

    @Test func tabAndReturnCompleteTheHighlightedRow() {
        for command in [ClipboardKeyCommand.complete, .activate] {
            var list = makeList("hello @c")
            list.move(2)
            var text = "hello @c"
            #expect(list.handle(command, text: &text))
            #expect(text == "hello @Chrome ")
        }
    }

    @Test func aCompletedTextClosesTheList() {
        var list = makeList("@l")
        var text = "@l"
        #expect(list.handle(.complete, text: &text))
        #expect(text == "@link ")
        list.update(text: text, apps: apps)
        #expect(!list.isOpen)
    }

    @Test func aRowCanBeChosenByIndexLikeAClick() {
        let list = makeList("@")
        var text = "@"
        list.accept(4, into: &text)
        #expect(text == "@color ")
        list.accept(99, into: &text)
        #expect(text == "@color ")
    }

    @Test func upAndDownKeysMoveWhileItIsOpen() {
        var list = makeList("@")
        var text = "@"
        #expect(list.handle(.next, text: &text))
        #expect(list.highlighted == 1)
        #expect(list.handle(.previous, text: &text))
        #expect(list.highlighted == 0)
        #expect(text == "@")
    }

    @Test func escClosesTheListUntilTheTextChanges() {
        for command in [ClipboardKeyCommand.clearSearch, .close] {
            var list = makeList("@l")
            var text = "@l"
            #expect(list.handle(command, text: &text))
            #expect(!list.isOpen)
            #expect(text == "@l")
            // The same text, e.g. after the library's history changed, stays closed.
            list.update(text: "@l", apps: apps)
            #expect(!list.isOpen)
            // Typing on opens it again.
            list.update(text: "@li", apps: apps)
            #expect(list.items.map(\.token) == ["@link"])
            // And so does going back to the text it was closed on.
            list.update(text: "@l", apps: apps)
            #expect(list.isOpen)
        }
    }

    @Test func keysAreLeftAloneWhileItIsClosed() {
        var list = makeList("hello")
        var text = "hello"
        for command in [ClipboardKeyCommand.next, .previous, .activate, .complete, .clearSearch, .close] {
            #expect(!list.handle(command, text: &text))
        }
        #expect(text == "hello")
    }
}
