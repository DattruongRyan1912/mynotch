import AppKit
import SwiftUI

/// The search field of the tab, of the library's toolbar and of the floating panel. AppKit rather than SwiftUI so arrows,
/// Tab, Return and Esc are taken from the field editor before it uses them, which is how the suggestions for an `@` word
/// are driven, and so the notch's and the panel's field take the keyboard exactly when their window becomes key.
struct ClipboardSearchField: NSViewRepresentable {
    @Binding var text: String
    /// The notch's field is dark with no focus ring and takes the keyboard when its panel becomes key; the floating panel's
    /// is the same but follows the system's appearance; the library's follows the system and takes the keyboard only when
    /// asked, through `focusRequest`.
    var look = ClipboardLook.notch
    /// Whether the notch is Liquid Glass, where its field follows the window's appearance instead of being dark.
    var onGlass = false
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
        field.placeholderString = look == .library ? "Tìm trong clipboard" : "Tìm trong lịch sử"
        // The classic notch is black whatever the system appearance; on Liquid Glass the field takes the window's.
        field.appearance = look.fieldAppearance(onGlass: onGlass).flatMap(NSAppearance.init(named:))
        if look.focusesWithWindow { field.focusRingType = .none }
        field.stringValue = text
        field.delegate = context.coordinator
        // The clear button changes the text without a text-change notification, only through the action.
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        if look.focusesWithWindow {
            field.onWindowChange = { [weak coordinator = context.coordinator] window in coordinator?.watch(window) }
        }
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: WindowReportingSearchField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let appearance = look.fieldAppearance(onGlass: onGlass)
        if field.appearance?.name != appearance { field.appearance = appearance.flatMap(NSAppearance.init(named:)) }
        if field.stringValue != text {
            field.stringValue = text
            // Puts the caret after the new text, e.g. after the word a suggestion completed.
            field.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
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

        /// Also sent after a typing pause with unchanged text, so only a change is written.
        @objc func searchChanged(_ sender: NSSearchField) {
            write(sender.stringValue)
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field { write(field.stringValue) }
        }

        private func write(_ text: String) {
            if parent.text != text { parent.text = text }
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
