import AppKit

/// Which keys open, close and act on the large preview, for both windows that have it (the library and the floating panel).
/// Pure, so the whole table is tested without a window; the windows only describe what they have in front of them.
nonisolated enum ClipboardPreviewKeys {
    /// A key press, as the window reads it from its event.
    struct Key: Equatable {
        var keyCode: UInt16
        /// What the key types with no modifier. ⌘Y is found by it, so a layout that moves Y keeps the shortcut.
        var characters: String?
        var modifiers: NSEvent.ModifierFlags
        var isRepeat = false
    }

    /// Where typing would go.
    enum Target: Equatable {
        /// A search field has the keyboard, so Space may be a typed space.
        case searchField
        /// Nothing that takes text has it (the library's cards), so a key is never a typed character.
        case cards
    }

    struct Situation: Equatable {
        var target: Target
        var searchIsEmpty: Bool
        /// The last key that was not one of these was ↑ or ↓: the user is moving through the list.
        var lastKeyWasVerticalArrow: Bool
        /// The field is in the middle of an input method's composition (Telex, VNI), which owns Space, Return and Esc.
        var hasMarkedText = false
        /// An `@` word is being completed; its list takes Return and Esc first.
        var suggestionsAreOpen = false
        var previewIsOpen: Bool
        /// Something is selected that the preview could show.
        var hasItem: Bool
    }

    enum Command: Equatable {
        /// Space and ⌘Y: open the preview, or close it.
        case toggle
        /// Esc, or Tab, while the preview is open: closes only the preview. (Tab would take the keyboard to the next control, and
        /// nothing there could close it.)
        case close
        /// Return while the preview is open: pastes the selected item, the preview going first.
        case activate
        /// A repeat of a key that already did its work: consumed, so it neither flickers the preview nor types.
        case ignore
    }

    private static let masked: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    /// What a key means for the preview in this situation; nil leaves it to the window (a typed space, Esc closing the
    /// panel, Return in the field).
    static func command(for key: Key, in situation: Situation) -> Command? {
        guard !situation.hasMarkedText else { return nil }
        let flags = key.modifiers.intersection(masked)
        switch key.keyCode {
        case 49 where flags.isEmpty:
            guard situation.hasItem || situation.previewIsOpen else { return nil }
            // In a field Space is a character unless the field is empty or the user is moving through the list.
            guard situation.target == .cards || situation.searchIsEmpty || situation.lastKeyWasVerticalArrow else { return nil }
            return toggle(key)
        case 53 where flags.isEmpty:
            guard situation.previewIsOpen, !situation.suggestionsAreOpen else { return nil }
            return .close
        case 48 where flags.isEmpty || flags == .shift:
            guard situation.previewIsOpen, !situation.suggestionsAreOpen else { return nil }
            return .close
        case 36 where flags.isEmpty, 76 where flags.isEmpty:
            guard situation.previewIsOpen, !situation.suggestionsAreOpen else { return nil }
            return key.isRepeat ? .ignore : .activate
        default:
            guard flags == .command, key.characters?.lowercased() == "y", situation.hasItem || situation.previewIsOpen else { return nil }
            return toggle(key)
        }
    }

    /// ↑ or ↓ with nothing held: the user is moving through the list, so the next Space is the preview's.
    static func isVerticalArrow(_ key: Key) -> Bool {
        (key.keyCode == 125 || key.keyCode == 126) && key.modifiers.intersection(masked).isEmpty
    }

    private static func toggle(_ key: Key) -> Command {
        key.isRepeat ? .ignore : .toggle
    }
}
