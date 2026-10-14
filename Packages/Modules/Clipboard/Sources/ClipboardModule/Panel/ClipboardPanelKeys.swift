import AppKit

/// Reads the panel's own shortcuts from key events.
nonisolated enum ClipboardPanelKeys {
    /// Virtual key codes of 1 to 9 on the number row, then on the keypad; they are not in order. Read by key rather than by
    /// what it types, so a layout whose number row types symbols (AZERTY) keeps its shortcuts.
    private static let numberRow: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    private static let keypad: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92]

    /// 1 to 9 for ⌘1 to ⌘9, nil for any other key. Caps Lock and the other state flags change nothing; Shift, Control or
    /// Option make it another shortcut, which is not the panel's.
    static func quickPickNumber(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Int? {
        guard modifiers.intersection([.command, .shift, .control, .option]) == .command else { return nil }
        guard let index = numberRow.firstIndex(of: keyCode) ?? keypad.firstIndex(of: keyCode) else { return nil }
        return index + 1
    }
}
