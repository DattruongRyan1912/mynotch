import AppKit

/// What a key the search field's editor is about to handle means for the tab.
nonisolated enum ClipboardKeyCommand: Equatable {
    case next, previous, activate, clearSearch, close
    /// Tab: completes a suggestion; the field keeps the key when there is none.
    case complete

    /// nil leaves the key to the field, so ←/→ still move the caret through a search.
    init?(_ selector: Selector, searchIsEmpty: Bool) {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): self = .next
        case #selector(NSResponder.moveUp(_:)): self = .previous
        case #selector(NSResponder.moveRight(_:)) where searchIsEmpty: self = .next
        case #selector(NSResponder.moveLeft(_:)) where searchIsEmpty: self = .previous
        case #selector(NSResponder.insertNewline(_:)): self = .activate
        case #selector(NSResponder.insertTab(_:)): self = .complete
        case #selector(NSResponder.cancelOperation(_:)): self = searchIsEmpty ? .close : .clearSearch
        default: return nil
        }
    }
}
