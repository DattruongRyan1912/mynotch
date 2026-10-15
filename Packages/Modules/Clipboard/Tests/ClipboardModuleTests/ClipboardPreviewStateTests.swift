import AppKit
import Testing
@testable import ClipboardModule

/// What the preview remembers between keys: whether the user is moving through the list, which decides what Space means in a field.
@Suite struct ClipboardPreviewStateTests {
    typealias Keys = ClipboardPreviewKeys

    let state = ClipboardPreviewState()
    let down = Keys.Key(keyCode: 125, characters: nil, modifiers: [.numericPad, .function])
    let space = Keys.Key(keyCode: 49, characters: " ", modifiers: [])
    let letter = Keys.Key(keyCode: 0, characters: "a", modifiers: [])

    @discardableResult
    func press(_ key: Keys.Key, empty: Bool = false, suggestions: Bool = false) -> Keys.Command? {
        state.command(
            for: key, target: .searchField, hasMarkedText: false, searchIsEmpty: empty, suggestionsAreOpen: suggestions, hasItem: true
        )
    }

    @Test func spaceAfterAnArrowIsThePreviewsEvenWithTextInTheField() {
        #expect(press(down) == nil)
        #expect(press(space) == .toggle)
    }

    /// While the `@` list is shown, ↑ and ↓ move its highlight and not the selection, so they are not "moving through the list".
    @Test func anArrowThatMovesTheSuggestionsLeavesSpaceATypedSpace() {
        #expect(press(down, suggestions: true) == nil)
        #expect(press(space, suggestions: true) == nil)
        // And the memory is not left behind for when the list has closed (an `@` word finished by a Space).
        #expect(press(space) == nil)
    }

    @Test func anArrowAfterTheSuggestionsClosedCountsAgain() {
        #expect(press(down, suggestions: true) == nil)
        #expect(press(down) == nil)
        #expect(press(space) == .toggle)
    }

    @Test func aLetterEndsItAndAKeyThePreviewTakesLeavesItAlone() {
        press(down)
        #expect(press(letter) == nil)
        #expect(press(space) == nil)

        press(down)
        #expect(press(space) == .toggle)
        #expect(press(space) == .toggle)
    }
}
