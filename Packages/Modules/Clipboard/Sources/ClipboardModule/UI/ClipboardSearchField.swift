import AppKit
import SwiftUI

/// The tab's search field. AppKit rather than SwiftUI so arrows, Return and Esc are taken from the field editor
/// before it uses them, and so the field takes the keyboard exactly when the notch panel becomes key.
struct ClipboardSearchField: NSViewRepresentable {
    @Binding var text: String
    /// False while another field of the tab (a board name) has the keyboard.
    var takesFocus: Bool
    /// Changed by the tab to give the keyboard back to this field.
    var focusRequest: Int
    /// Returns whether the command was used; unused keys stay with the field.
    let onCommand: (ClipboardKeyCommand) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WindowReportingSearchField {
        let field = WindowReportingSearchField()
        field.placeholderString = "Tìm trong lịch sử"
        // The notch is always black, whatever the system appearance.
        field.appearance = NSAppearance(named: .darkAqua)
        field.focusRingType = .none
        field.stringValue = text
        field.delegate = context.coordinator
        // The clear button changes the text without a text-change notification, only through the action.
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.onWindowChange = { [weak coordinator = context.coordinator] window in coordinator?.watch(window) }
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: WindowReportingSearchField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if coordinator.focusRequest != focusRequest {
            coordinator.focusRequest = focusRequest
            coordinator.focusIfKey()
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ClipboardSearchField
        weak var field: NSSearchField?
        var focusRequest: Int
        private weak var window: NSWindow?

        init(_ parent: ClipboardSearchField) {
            self.parent = parent
            focusRequest = parent.focusRequest
        }

        /// The panel becomes key when the notch is opened on purpose or the user clicks into a hovered one; that is
        /// when the field takes the keyboard, so hovering never takes typing from the app in front.
        func watch(_ window: NSWindow?) {
            if let old = self.window {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: old)
            }
            self.window = window
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: window
            )
            // SwiftUI is still inserting the field; focus it once that is done.
            Task { [weak self] in self?.focusIfKey() }
        }

        func focusIfKey() {
            guard parent.takesFocus, let field, let window = field.window, window.isKeyWindow,
                  field.currentEditor() == nil else { return }
            window.makeFirstResponder(field)
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            focusIfKey()
        }

        @objc func searchChanged(_ sender: NSSearchField) {
            parent.text = sender.stringValue
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let command = ClipboardKeyCommand(selector, searchIsEmpty: textView.string.isEmpty) else { return false }
            return parent.onCommand(command)
        }
    }
}

/// Reports when SwiftUI puts it in a window, the first moment it can watch that window's key status.
final class WindowReportingSearchField: NSSearchField {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
