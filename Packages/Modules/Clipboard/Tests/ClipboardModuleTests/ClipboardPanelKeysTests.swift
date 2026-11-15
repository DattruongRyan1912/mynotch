import AppKit
import Testing
@testable import ClipboardModule

/// ⌘1…⌘9 as the floating panel reads them from a key event: by the physical key, so a layout that types symbols on the
/// number row (AZERTY) still has its shortcuts.
@Suite struct ClipboardPanelKeysTests {
    /// kVK_ANSI_1 to kVK_ANSI_9 are not in order.
    static let numberRow: [(code: UInt16, number: Int)] = [(18, 1), (19, 2), (20, 3), (21, 4), (23, 5), (22, 6), (26, 7), (28, 8), (25, 9)]
    static let keypad: [(code: UInt16, number: Int)] = [(83, 1), (84, 2), (85, 3), (86, 4), (87, 5), (88, 6), (89, 7), (91, 8), (92, 9)]

    @Test func commandAndANumberRowKeyFromOneToNineIsAShortcut() {
        for (code, number) in Self.numberRow {
            #expect(ClipboardPanelKeys.quickPickNumber(keyCode: code, modifiers: .command) == number, "key \(code)")
        }
    }

    @Test func theKeypadsDigitsCountToo() {
        for (code, number) in Self.keypad {
            #expect(ClipboardPanelKeys.quickPickNumber(keyCode: code, modifiers: [.command, .numericPad]) == number, "key \(code)")
        }
    }

    @Test func zeroAndEveryOtherKeyAreNot() {
        // 29 is the number row's 0, 82 the keypad's; the rest are letters, V and the bracket keys.
        for code: UInt16 in [29, 82, 0, 9, 8, 24, 27, 30, 53, 36] {
            #expect(ClipboardPanelKeys.quickPickNumber(keyCode: code, modifiers: .command) == nil, "key \(code)")
        }
    }

    @Test func otherModifiersMakeItAnotherShortcut() {
        #expect(ClipboardPanelKeys.quickPickNumber(keyCode: 18, modifiers: []) == nil)
        #expect(ClipboardPanelKeys.quickPickNumber(keyCode: 18, modifiers: .control) == nil)
        #expect(ClipboardPanelKeys.quickPickNumber(keyCode: 18, modifiers: .option) == nil)
        #expect(ClipboardPanelKeys.quickPickNumber(keyCode: 18, modifiers: [.command, .shift]) == nil)
        #expect(ClipboardPanelKeys.quickPickNumber(keyCode: 18, modifiers: [.command, .option]) == nil)
    }

    @Test func capsLockAndTheFunctionFlagDoNotChangeWhatItMeans() {
        #expect(ClipboardPanelKeys.quickPickNumber(keyCode: 21, modifiers: [.command, .capsLock]) == 4)
        #expect(ClipboardPanelKeys.quickPickNumber(keyCode: 21, modifiers: [.command, .function]) == 4)
    }
}
