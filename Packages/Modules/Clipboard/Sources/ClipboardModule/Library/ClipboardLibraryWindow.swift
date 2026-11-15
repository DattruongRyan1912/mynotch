import AppKit

/// The library's window. It looks at every key press before the search field or the cards do, because Space in the field is typed
/// text and never reaches it as a command; what the large preview makes of the key (Space, ⌘Y, Esc, Return) is its model's to say.
final class ClipboardLibraryWindow: NSWindow {
    var onPreviewKey: ClipboardPreviewKeys.Handler?

    override func sendEvent(_ event: NSEvent) {
        if offersToPreview(event), handlePreviewKey(event) { return }
        super.sendEvent(event)
    }

    func offersToPreview(_ event: NSEvent) -> Bool {
        event.type == .keyDown
    }

    /// Only the search field and the cards are asked: with anything else holding the keyboard (a password, a name being typed, a
    /// sidebar row) the preview takes no key.
    func handlePreviewKey(_ event: NSEvent) -> Bool {
        ClipboardPreviewKeys.offer(event, in: self, to: onPreviewKey) { $0 is ClipboardLibraryKeyboard.KeyView }
    }
}
