import AppKit
import SwiftUI

/// Inline field naming a new board or renaming one. It takes the keyboard as soon as it appears, making the panel
/// key when hovering opened the notch (the user asked to type), and finishes when the panel loses the keyboard:
/// the tab pins the notch while the field is shown, so it must not wait for a click that never comes.
struct ClipboardBoardNameField: NSViewRepresentable {
    @Binding var name: String
    /// Return, or the field lost the keyboard. Called again when the field goes away; the tab ignores repeats.
    let onCommit: () -> Void
    /// Esc.
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WindowReportingTextField {
        let field = WindowReportingTextField()
        field.placeholderString = "Tên board"
        field.stringValue = name
        field.appearance = NSAppearance(named: .darkAqua)
        field.bezelStyle = .roundedBezel
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.onWindowChange = { [weak coordinator = context.coordinator] window in coordinator?.watch(window) }
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: WindowReportingTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != name { field.stringValue = name }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ClipboardBoardNameField
        weak var field: NSTextField?
        private weak var window: NSWindow?

        init(_ parent: ClipboardBoardNameField) {
            self.parent = parent
        }

        func watch(_ window: NSWindow?) {
            if let old = self.window {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: old)
            }
            self.window = window
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidResignKey(_:)), name: NSWindow.didResignKeyNotification, object: window
            )
            Task { [weak self] in
                guard let field = self?.field, let window = field.window else { return }
                window.makeKey()
                // Selects the text too, so a rename starts with the old name selected.
                window.makeFirstResponder(field)
            }
        }

        /// Ends editing, which commits through `controlTextDidEndEditing`.
        @objc private func windowDidResignKey(_ notification: Notification) {
            guard let field, field.currentEditor() != nil else { return }
            field.window?.makeFirstResponder(nil)
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field { parent.name = field.stringValue }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onCommit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch ClipboardKeyCommand(selector, searchIsEmpty: false) {
            case .activate:
                parent.onCommit()
            case .clearSearch, .close:
                parent.onCancel()
            case .next, .previous, nil:
                return false
            }
            return true
        }
    }
}

/// Reports when SwiftUI puts it in a window, the first moment it can watch that window's key status.
final class WindowReportingTextField: NSTextField {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
