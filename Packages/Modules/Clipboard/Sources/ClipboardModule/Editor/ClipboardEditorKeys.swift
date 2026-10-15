import AppKit

/// The keys the editor window takes before its text view does. Pure, so the whole table is tested without a window.
nonisolated enum ClipboardEditorKeys {
    enum Command: Equatable {
        /// Esc and ⌘W: leave the editor, asking first when there are unsaved words.
        case cancel
        /// A held Esc or ⌘W: swallowed, so it neither asks twice nor reaches the text.
        case ignore
    }

    private static let masked: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    /// nil leaves the key to the text view and the window. Esc while an input method is composing (Telex, VNI) belongs to the method,
    /// which uses it to take back what it is composing; ⌘W is not part of a composition. ⌘W is found by the letter it types, so a
    /// layout that moves W keeps it.
    static func command(for key: ClipboardPreviewKeys.Key, hasMarkedText: Bool) -> Command? {
        let flags = key.modifiers.intersection(masked)
        switch key.keyCode {
        case 53 where flags.isEmpty:
            guard !hasMarkedText else { return nil }
        default:
            guard flags == .command, key.characters?.lowercased() == "w" else { return nil }
        }
        return key.isRepeat ? .ignore : .cancel
    }
}
