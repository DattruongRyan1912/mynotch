import AppKit
import Testing
@testable import ClipboardModule

/// Which keys open, close and act on the large preview, in the library and in the floating panel: one pure table for both.
@Suite struct ClipboardPreviewKeysTests {
    typealias Keys = ClipboardPreviewKeys

    static let space = Keys.Key(keyCode: 49, characters: " ", modifiers: [])
    static let commandY = Keys.Key(keyCode: 16, characters: "y", modifiers: .command)
    static let escape = Keys.Key(keyCode: 53, characters: "\u{1B}", modifiers: [])
    static let returnKey = Keys.Key(keyCode: 36, characters: "\r", modifiers: [])
    static let down = Keys.Key(keyCode: 125, characters: "\u{F701}", modifiers: [.numericPad, .function])
    static let up = Keys.Key(keyCode: 126, characters: "\u{F700}", modifiers: [.numericPad, .function])
    static let left = Keys.Key(keyCode: 123, characters: "\u{F702}", modifiers: [.numericPad, .function])
    static let letter = Keys.Key(keyCode: 0, characters: "a", modifiers: [])

    /// A search field with the keyboard, empty, nothing previewed, an item selected.
    static func field(
        empty: Bool = true, afterArrow: Bool = false, open: Bool = false, marked: Bool = false, suggestions: Bool = false, item: Bool = true
    ) -> Keys.Situation {
        Keys.Situation(
            target: .searchField, searchIsEmpty: empty, lastKeyWasVerticalArrow: afterArrow, hasMarkedText: marked,
            suggestionsAreOpen: suggestions, previewIsOpen: open, hasItem: item
        )
    }

    static func cards(open: Bool = false, item: Bool = true) -> Keys.Situation {
        Keys.Situation(target: .cards, searchIsEmpty: false, lastKeyWasVerticalArrow: false, previewIsOpen: open, hasItem: item)
    }

    // MARK: Space

    @Test func spaceInAnEmptyFieldTogglesThePreview() {
        #expect(Keys.command(for: Self.space, in: Self.field()) == .toggle)
        #expect(Keys.command(for: Self.space, in: Self.field(open: true)) == .toggle)
    }

    @Test func spaceAfterAnArrowTogglesEvenWithTextInTheField() {
        #expect(Keys.command(for: Self.space, in: Self.field(empty: false, afterArrow: true)) == .toggle)
    }

    @Test func spaceWhileTypingIsATypedSpace() {
        #expect(Keys.command(for: Self.space, in: Self.field(empty: false)) == nil)
        #expect(Keys.command(for: Self.space, in: Self.field(empty: false, open: true)) == nil)
    }

    @Test func spaceOnTheCardsAlwaysTogglesBecauseThereIsNowhereToType() {
        #expect(Keys.command(for: Self.space, in: Self.cards()) == .toggle)
        #expect(Keys.command(for: Self.space, in: Self.cards(open: true)) == .toggle)
    }

    @Test func spaceWithNothingToShowIsLeftAlone() {
        #expect(Keys.command(for: Self.space, in: Self.field(item: false)) == nil)
        #expect(Keys.command(for: Self.space, in: Self.cards(item: false)) == nil)
    }

    @Test func aPreviewThatIsOpenCanAlwaysBeClosedBySpaceEvenIfItsItemJustWentAway() {
        #expect(Keys.command(for: Self.space, in: Self.field(open: true, item: false)) == .toggle)
    }

    @Test func spaceBelongsToTheInputMethodWhileItIsComposing() {
        #expect(Keys.command(for: Self.space, in: Self.field(marked: true)) == nil)
        #expect(Keys.command(for: Self.space, in: Self.field(afterArrow: true, marked: true)) == nil)
    }

    @Test func spaceWithAnyModifierIsNotTheShortcut() {
        for modifiers: NSEvent.ModifierFlags in [.shift, .option, .control, .command] {
            let key = Keys.Key(keyCode: 49, characters: " ", modifiers: modifiers)
            #expect(Keys.command(for: key, in: Self.field()) == nil, "\(modifiers)")
        }
    }

    @Test func capsLockAndTheFunctionFlagsChangeNothing() {
        let key = Keys.Key(keyCode: 49, characters: " ", modifiers: [.capsLock, .function])
        #expect(Keys.command(for: key, in: Self.field()) == .toggle)
    }

    @Test func aHeldSpaceIsSwallowedInsteadOfFlickeringThePreview() {
        let held = Keys.Key(keyCode: 49, characters: " ", modifiers: [], isRepeat: true)
        #expect(Keys.command(for: held, in: Self.field()) == .ignore)
        #expect(Keys.command(for: held, in: Self.cards()) == .ignore)
        // While typing, a held Space is a run of typed spaces.
        #expect(Keys.command(for: held, in: Self.field(empty: false)) == nil)
    }

    // MARK: ⌘Y

    @Test func commandYAlwaysTogglesWhateverTheFieldHolds() {
        #expect(Keys.command(for: Self.commandY, in: Self.field()) == .toggle)
        #expect(Keys.command(for: Self.commandY, in: Self.field(empty: false)) == .toggle)
        #expect(Keys.command(for: Self.commandY, in: Self.field(empty: false, open: true)) == .toggle)
        #expect(Keys.command(for: Self.commandY, in: Self.cards()) == .toggle)
    }

    @Test func commandYIsFoundByTheLetterItTypesNotByItsPosition() {
        // QWERTZ: the key at Y's position types Z, and Y is elsewhere.
        let qwertzY = Keys.Key(keyCode: 6, characters: "y", modifiers: .command)
        let qwertzZ = Keys.Key(keyCode: 16, characters: "z", modifiers: .command)
        #expect(Keys.command(for: qwertzY, in: Self.field()) == .toggle)
        #expect(Keys.command(for: qwertzZ, in: Self.field()) == nil)
        #expect(Keys.command(for: Keys.Key(keyCode: 16, characters: "Y", modifiers: .command), in: Self.field()) == .toggle)
    }

    @Test func commandYWithAnotherModifierIsAnotherShortcut() {
        for modifiers: NSEvent.ModifierFlags in [[.command, .shift], [.command, .option], [.command, .control], []] {
            let key = Keys.Key(keyCode: 16, characters: "y", modifiers: modifiers)
            #expect(Keys.command(for: key, in: Self.field()) == nil, "\(modifiers)")
        }
    }

    @Test func commandYWithNothingToShowOrWhileComposingIsLeftAlone() {
        #expect(Keys.command(for: Self.commandY, in: Self.field(item: false)) == nil)
        #expect(Keys.command(for: Self.commandY, in: Self.field(marked: true)) == nil)
    }

    @Test func aHeldCommandYIsSwallowed() {
        let held = Keys.Key(keyCode: 16, characters: "y", modifiers: .command, isRepeat: true)
        #expect(Keys.command(for: held, in: Self.field()) == .ignore)
    }

    // MARK: Esc and Return

    @Test func escapeClosesOnlyAnOpenPreview() {
        #expect(Keys.command(for: Self.escape, in: Self.field(open: true)) == .close)
        #expect(Keys.command(for: Self.escape, in: Self.cards(open: true)) == .close)
        // Closed: the window's own Esc (close the panel, clear the selection) is left alone.
        #expect(Keys.command(for: Self.escape, in: Self.field()) == nil)
        #expect(Keys.command(for: Self.escape, in: Self.cards()) == nil)
    }

    /// Tab would leave the field for the next control, and nothing there could close the preview: with it open, Tab closes it.
    @Test func tabClosesAnOpenPreviewWhereverTheKeyboardIs() {
        let tab = Keys.Key(keyCode: 48, characters: "\t", modifiers: [])
        let backTab = Keys.Key(keyCode: 48, characters: "\u{19}", modifiers: .shift)
        for key in [tab, backTab] {
            #expect(Keys.command(for: key, in: Self.field(open: true)) == .close)
            #expect(Keys.command(for: key, in: Self.cards(open: true)) == .close)
            // Closed, Tab is the window's.
            #expect(Keys.command(for: key, in: Self.field()) == nil)
            #expect(Keys.command(for: key, in: Self.cards()) == nil)
        }
    }

    @Test func tabBelongsToTheSuggestionsAndTheInputMethodAndOtherShortcuts() {
        let tab = Keys.Key(keyCode: 48, characters: "\t", modifiers: [])
        #expect(Keys.command(for: tab, in: Self.field(open: true, suggestions: true)) == nil)
        #expect(Keys.command(for: tab, in: Self.field(open: true, marked: true)) == nil)
        for modifiers: NSEvent.ModifierFlags in [.command, .option, .control] {
            let other = Keys.Key(keyCode: 48, characters: "\t", modifiers: modifiers)
            #expect(Keys.command(for: other, in: Self.field(open: true)) == nil, "\(modifiers)")
        }
    }

    @Test func returnPastesOnlyWhileThePreviewIsOpen() {
        #expect(Keys.command(for: Self.returnKey, in: Self.field(open: true)) == .activate)
        #expect(Keys.command(for: Self.returnKey, in: Self.cards(open: true)) == .activate)
        #expect(Keys.command(for: Keys.Key(keyCode: 76, characters: "\u{3}", modifiers: []), in: Self.field(open: true)) == .activate)
        #expect(Keys.command(for: Self.returnKey, in: Self.field()) == nil)
    }

    @Test func aHeldReturnPastesOnceNotRepeatedly() {
        let held = Keys.Key(keyCode: 36, characters: "\r", modifiers: [], isRepeat: true)
        #expect(Keys.command(for: held, in: Self.field(open: true)) == .ignore)
    }

    @Test func escapeAndReturnBelongToTheSuggestionsWhileTheyAreShown() {
        #expect(Keys.command(for: Self.escape, in: Self.field(open: true, suggestions: true)) == nil)
        #expect(Keys.command(for: Self.returnKey, in: Self.field(open: true, suggestions: true)) == nil)
    }

    @Test func escapeAndReturnBelongToTheInputMethodWhileItIsComposing() {
        #expect(Keys.command(for: Self.escape, in: Self.field(open: true, marked: true)) == nil)
        #expect(Keys.command(for: Self.returnKey, in: Self.field(open: true, marked: true)) == nil)
    }

    @Test func returnAndEscapeWithAModifierAreOtherShortcuts() {
        for key in [Self.returnKey, Self.escape] {
            let modified = Keys.Key(keyCode: key.keyCode, characters: key.characters, modifiers: .command)
            #expect(Keys.command(for: modified, in: Self.field(open: true)) == nil)
        }
    }

    @Test func otherKeysAreNeverTaken() {
        for key in [Self.letter, Self.down, Self.up, Self.left] {
            #expect(Keys.command(for: key, in: Self.field(open: true)) == nil)
            #expect(Keys.command(for: key, in: Self.cards(open: true)) == nil)
        }
    }

    // MARK: Arrows

    @Test func onlyUpAndDownCountAsMovingThroughTheList() {
        #expect(Keys.isVerticalArrow(Self.down))
        #expect(Keys.isVerticalArrow(Self.up))
        // ← and → move the caret through a search, so a Space after them is a typed one.
        #expect(!Keys.isVerticalArrow(Self.left))
        #expect(!Keys.isVerticalArrow(Keys.Key(keyCode: 124, characters: nil, modifiers: [.numericPad, .function])))
        #expect(!Keys.isVerticalArrow(Self.letter))
        // ⌥↓ moves the caret to the end of a paragraph, not the selection.
        #expect(!Keys.isVerticalArrow(Keys.Key(keyCode: 125, characters: nil, modifiers: [.numericPad, .function, .option])))
        #expect(!Keys.isVerticalArrow(Keys.Key(keyCode: 125, characters: nil, modifiers: [.numericPad, .function, .command])))
    }
}
