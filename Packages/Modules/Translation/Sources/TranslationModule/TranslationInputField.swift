import AppKit
import SwiftUI

/// Multi-line input where Return submits and ⇧Return starts a new line. SwiftUI's text fields submit on both,
/// so this wraps an `NSTextView`.
struct TranslationInputField: NSViewRepresentable {
    let text: String
    /// Each new value moves the keyboard focus into the field.
    let focusRequest: Int
    let onEdit: (String) -> Void
    /// Return, with the text the field shows.
    let onSubmit: (String) -> Void
    /// Whether the notch is Liquid Glass, which sets how the field is drawn (see `Look`).
    let onGlass: Bool

    /// How AppKit draws the field. The classic notch is black whatever the system's appearance is, so there the text and the caret
    /// are white and the scroller is dark; on Liquid Glass the field follows the system's appearance and its label colour, so the
    /// text is dark on light glass and light on dark glass, like the text tokens.
    struct Look: Equatable {
        let textColor: NSColor
        /// The scroller's appearance; nil takes the window's.
        let appearance: NSAppearance.Name?

        init(onGlass: Bool) {
            textColor = onGlass ? .labelColor : .white
            appearance = onGlass ? nil : .darkAqua
        }

        @MainActor func apply(to textView: NSTextView, in scrollView: NSScrollView) {
            textView.textColor = textColor
            textView.insertionPointColor = textColor
            scrollView.appearance = appearance.flatMap(NSAppearance.init(named:))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = InputTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.setAccessibilityLabel("Văn bản cần dịch")

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        let look = Look(onGlass: onGlass)
        look.apply(to: textView, in: scrollView)
        context.coordinator.look = look
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.field = self
        guard let textView = scrollView.documentView as? InputTextView else { return }
        // Only when the look changed: setting the colour again would touch text an input method is composing.
        let look = Look(onGlass: onGlass)
        if coordinator.look != look {
            look.apply(to: textView, in: scrollView)
            coordinator.look = look
        }
        // Typing already updated the view; only text set elsewhere (selection, Services, swap) is copied in.
        coordinator.show(text, in: textView)
        if coordinator.focusRequest != focusRequest {
            coordinator.focusRequest = focusRequest
            textView.requestFocus()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var field: TranslationInputField
        var focusRequest: Int?
        var look: Look?
        /// The field's own undo history, so clearing it touches nothing else in the panel.
        private let undoManager = UndoManager()
        /// Text set from outside while an input method was composing (Vietnamese Telex, Japanese).
        private var pendingText: String?

        init(_ field: TranslationInputField) {
            self.field = field
        }

        /// Shows text set from outside. Replacing marked text would cut the input method off mid-word, so that waits
        /// for the composition to end. The undo history goes with the old text: ⌘Z must not bring it back piecemeal.
        func show(_ text: String, in textView: NSTextView) {
            guard textView.string != text else {
                pendingText = nil
                return
            }
            guard !textView.hasMarkedText() else {
                pendingText = text
                return
            }
            pendingText = nil
            textView.string = text
            textView.breakUndoCoalescing()
            undoManager.removeAllActions()
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if let pendingText {
                // The input already holds the outside text; what was composed meanwhile gives way to it.
                if !textView.hasMarkedText() { show(pendingText, in: textView) }
                return
            }
            field.onEdit(textView.string)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // Return while composing belongs to the input method; ⇧Return is a new line.
                if textView.hasMarkedText() || NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
                field.onSubmit(textView.string)
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

/// Keeps a focus request until the field is in the key window. The notch panel turns key only after the tab
/// appears, and only when it was opened on purpose, so a request made earlier would otherwise be lost.
final class InputTextView: NSTextView {
    private var wantsFocus = false

    func requestFocus() {
        wantsFocus = true
        applyPendingFocus()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
        }
        if let newWindow {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: newWindow
            )
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPendingFocus()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        applyPendingFocus()
    }

    /// Sets the window's first responder right away, and again once the window is key, which settles the request.
    private func applyPendingFocus() {
        guard wantsFocus, let window else { return }
        window.makeFirstResponder(self)
        if window.isKeyWindow { wantsFocus = false }
    }
}
