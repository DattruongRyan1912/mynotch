import AppKit
import Testing
@testable import ClipboardModule

/// ⌘1…⌘9 as the floating panel reads them from a key event.
@Suite struct ClipboardPanelKeysTests {
    @Test func commandAndADigitFromOneToNineIsAShortcut() {
        for number in 1...9 {
            #expect(ClipboardPanelKeys.quickPickNumber(characters: String(number), modifiers: .command) == number)
        }
    }

    @Test func zeroOtherCharactersAndLongerTextAreNot() {
        for characters in ["0", "a", "v", "-", "12", "", "٣"] {
            #expect(ClipboardPanelKeys.quickPickNumber(characters: characters, modifiers: .command) == nil)
        }
        #expect(ClipboardPanelKeys.quickPickNumber(characters: nil, modifiers: .command) == nil)
    }

    @Test func otherModifiersMakeItAnotherShortcut() {
        #expect(ClipboardPanelKeys.quickPickNumber(characters: "1", modifiers: []) == nil)
        #expect(ClipboardPanelKeys.quickPickNumber(characters: "1", modifiers: .control) == nil)
        #expect(ClipboardPanelKeys.quickPickNumber(characters: "1", modifiers: .option) == nil)
        #expect(ClipboardPanelKeys.quickPickNumber(characters: "1", modifiers: [.command, .shift]) == nil)
        #expect(ClipboardPanelKeys.quickPickNumber(characters: "1", modifiers: [.command, .option]) == nil)
    }

    @Test func capsLockAndTheNumericPadDoNotChangeWhatItMeans() {
        #expect(ClipboardPanelKeys.quickPickNumber(characters: "4", modifiers: [.command, .capsLock]) == 4)
        #expect(ClipboardPanelKeys.quickPickNumber(characters: "4", modifiers: [.command, .numericPad]) == 4)
    }
}
