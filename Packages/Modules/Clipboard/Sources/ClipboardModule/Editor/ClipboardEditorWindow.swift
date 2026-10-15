import AppKit

/// The editor's window. It looks at every key press before the text view does, because Esc and ⌘W must leave the editor (asking first
/// when there are unsaved words) however the text view would have taken them. What a key means is `ClipboardEditorKeys`' to say.
final class ClipboardEditorWindow: NSWindow {
    /// Leave the editor, as the model decides. nil leaves every key alone.
    var onCancel: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if handleKey(event) { return }
        super.sendEvent(event)
    }

    /// True when the editor took the key.
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, let onCancel,
              let command = ClipboardEditorKeys.command(for: ClipboardPreviewKeys.Key(event), hasMarkedText: ClipboardPreviewKeys.hasMarkedText(firstResponder))
        else { return false }
        if command == .cancel { onCancel() }
        return true
    }
}
