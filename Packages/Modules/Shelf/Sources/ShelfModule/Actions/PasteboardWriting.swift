import AppKit

/// Puts recognised text on a pasteboard. A protocol so tests never write to the real one.
protocol PasteboardWriting: AnyObject {
    /// Replaces the pasteboard's contents with `text`. False when the pasteboard refused it.
    func write(_ text: String) -> Bool
}

/// Writes to a real pasteboard, the general one by default. It adds no marker type, as Screenshot's text recognition
/// does: the Clipboard module records the text like any other copy, so it is found again in its history.
final class SystemPasteboard: PasteboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
