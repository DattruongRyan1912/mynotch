import Foundation
import Observation

/// What the library and the floating panel share about their large preview: whether it is open, who is told when that
/// changes (the window that shows it), and whether the last key was ↑ or ↓, which decides what Space means in a search field.
@Observable
final class ClipboardPreviewState {
    typealias Keys = ClipboardPreviewKeys

    private(set) var isOpen = false
    /// Told every time the preview opens (true) or closes (false), never twice in a row for the same answer.
    @ObservationIgnored var onChange: ((Bool) -> Void)?
    @ObservationIgnored private var lastKeyWasVerticalArrow = false

    func open() {
        guard !isOpen else { return }
        isOpen = true
        onChange?(true)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        onChange?(false)
    }

    /// What `key` means for the preview, and the memory of it. A key the preview takes leaves "moving through the list"
    /// as it was, so Space twice after an arrow opens and closes; any other key ends it, so a Space typed after a letter
    /// is a space. ↑ and ↓ in the `@` suggestions move their highlight, not the selection, so they do not start it.
    func command(
        for key: Keys.Key, target: Keys.Target, hasMarkedText: Bool, searchIsEmpty: Bool, suggestionsAreOpen: Bool, hasItem: Bool
    ) -> Keys.Command? {
        let command = Keys.command(for: key, in: Keys.Situation(
            target: target, searchIsEmpty: searchIsEmpty, lastKeyWasVerticalArrow: lastKeyWasVerticalArrow, hasMarkedText: hasMarkedText,
            suggestionsAreOpen: suggestionsAreOpen, previewIsOpen: isOpen, hasItem: hasItem
        ))
        if command == nil { lastKeyWasVerticalArrow = !suggestionsAreOpen && Keys.isVerticalArrow(key) }
        return command
    }
}

/// A window's model, as the preview sees it: the item to draw, and the way to close it.
protocol ClipboardPreviewHosting: AnyObject {
    /// The item the open preview shows, which follows the selection; nil while it is closed.
    var previewedItem: ClipboardItem? { get }
    var isPreviewOpen: Bool { get }
    /// Told when the preview opens or closes, so the window can be shown or taken away.
    var onPreviewChange: ((Bool) -> Void)? { get set }
    func closePreview()
}

nonisolated extension ClipboardHistory {
    /// Whether the item may be shown large: not while it is pinned to a board that is locked. The module takes such items out of
    /// the history, so this only matters for a state it never produces.
    func canPreview(_ id: UUID) -> Bool {
        !boards.contains { $0.isLocked && $0.itemIDs.contains(id) }
    }
}
