import AppKit

/// What a key pressed with the library's cards focused means. ⌘C and ⌘A are not here: they reach the cards through
/// the Edit menu's Copy and Select All, so a focused search field still gets them for its own text.
nonisolated enum ClipboardLibraryKeyCommand: Equatable {
    case move(ClipboardLibraryDirection, extend: Bool)
    case activate, delete, clearSelection

    /// nil leaves the key to the system.
    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection([.shift, .control, .option, .command])
        switch keyCode {
        case 123, 124, 125, 126:
            guard flags.isEmpty || flags == .shift else { return nil }
            let direction: ClipboardLibraryDirection = switch keyCode {
            case 123: .left
            case 124: .right
            case 125: .down
            default: .up
            }
            self = .move(direction, extend: flags == .shift)
        case 36, 76:
            guard flags.isEmpty else { return nil }
            self = .activate
        case 51, 117:
            guard flags.isEmpty || flags == .command else { return nil }
            self = .delete
        case 53:
            guard flags.isEmpty else { return nil }
            self = .clearSelection
        default:
            return nil
        }
    }
}
