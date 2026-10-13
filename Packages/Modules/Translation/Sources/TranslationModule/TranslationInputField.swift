import AppKit
import SwiftUI

/// Multi-line input where Return submits and ⇧Return starts a new line. SwiftUI's text fields submit on both,
/// so this wraps an `NSTextView`.
struct TranslationInputField: NSViewRepresentable {
    let text: String
    /// Each new value moves the keyboard focus into the field.
    let focusRequest: Int
    let onEdit: (String) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.appearance = NSAppearance(named: .darkAqua)
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityLabel("Văn bản cần dịch")
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.field = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Typing already updated the view; only text set elsewhere (selection, Services, swap) is copied in.
        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            // The view may not be in the panel yet when SwiftUI first updates it.
            Task { [weak textView] in
                guard let textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var field: TranslationInputField
        var focusRequest: Int?

        init(_ field: TranslationInputField) {
            self.field = field
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            field.onEdit(textView.string)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // Return while composing (Vietnamese Telex, Japanese) belongs to the input method; ⇧Return is a new line.
                if textView.hasMarkedText() || NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
                field.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                // NSTextView turns Esc into word completion; pass it up so it closes the notch as in other tabs.
                textView.nextResponder?.doCommand(by: selector)
                return true
            default:
                return false
            }
        }
    }
}
