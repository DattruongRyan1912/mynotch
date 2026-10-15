import Foundation

/// What the editor makes of the words it is given, apart from any window: which items it opens on, and what the edited words
/// become, decided as a copy of them would be.
nonisolated enum ClipboardEditing {
    enum Classification: Equatable, Sendable {
        case content(ClipboardContent)
        case refused(ClipboardEditOutcome)
    }

    /// The words the editor starts with: a text's, a rich text's (without its formatting) or a link's address. nil for what is not
    /// edited as words (a picture, files, a colour).
    static func text(of item: ClipboardItem) -> String? {
        switch item.content {
        case .text(let text), .richText(let text, _): text
        case .link(let url): url.absoluteString
        case .color, .image, .files: nil
        }
    }

    /// What `text` becomes in the history, by the same rules as a copy of it (an address is a link, a colour code is a colour), so an
    /// item is never one kind in the history and another once copied back. Blank words and words over the limit of a copy are refused.
    static func classify(_ text: String, colorsWithoutHash: Bool) -> Classification {
        let snapshot = PasteboardSnapshot(types: ["public.utf8-plain-text"], string: text)
        let classifier = ClipboardClassifier(ignoreSensitive: false, colorsWithoutHash: colorsWithoutHash)
        switch classifier.classify(snapshot) {
        case .content(let content, _): return .content(content)
        case .skipped(.tooLarge): return .refused(.tooLarge)
        case .skipped: return .refused(.blank)
        }
    }
}
