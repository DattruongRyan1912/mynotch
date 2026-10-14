import AppKit

/// Reads the panel's own shortcuts from key events.
nonisolated enum ClipboardPanelKeys {
    /// 1 to 9 for ⌘1 to ⌘9, nil for any other key. Caps Lock and the numeric pad flag change nothing; Shift, Control or
    /// Option make it another shortcut, which is not the panel's.
    static func quickPickNumber(characters: String?, modifiers: NSEvent.ModifierFlags) -> Int? {
        guard modifiers.intersection([.command, .shift, .control, .option]) == .command,
              let characters, characters.count == 1, let number = Int(characters), (1...9).contains(number) else { return nil }
        return number
    }
}
