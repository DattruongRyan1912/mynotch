import AppKit
import SwiftUI

/// Gives the library's cards the keyboard: arrows, Return, Delete and Esc through `keyDown`, ⌘C and ⌘A through the
/// Edit menu's Copy and Select All (the view answers `copy:` and `selectAll:`, which also enables those menu items).
/// A search field that has the keyboard keeps all of them for its own text.
struct ClipboardLibraryKeyboard: NSViewRepresentable {
    /// Bumped to take the keyboard back, e.g. after a click on a card ended a search.
    let focusRequest: Int
    let onCommand: (ClipboardLibraryKeyCommand) -> Void
    let onCopy: () -> Void
    let onSelectAll: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> KeyView {
        KeyView()
    }

    func updateNSView(_ view: KeyView, context: Context) {
        view.onCommand = onCommand
        view.onCopy = onCopy
        view.onSelectAll = onSelectAll
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            view.takeKeyboard()
        }
    }

    final class Coordinator {
        var focusRequest = 0
    }

    final class KeyView: NSView {
        var onCommand: (ClipboardLibraryKeyCommand) -> Void = { _ in }
        var onCopy: () -> Void = {}
        var onSelectAll: () -> Void = {}

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            takeKeyboard()
        }

        func takeKeyboard() {
            // After this pass, when SwiftUI has finished putting the window together.
            Task { [weak self] in
                guard let self, let window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            guard let command = ClipboardLibraryKeyCommand(keyCode: event.keyCode, modifiers: event.modifierFlags) else {
                super.keyDown(with: event)
                return
            }
            onCommand(command)
        }

        @objc func copy(_ sender: Any?) {
            onCopy()
        }

        @objc override func selectAll(_ sender: Any?) {
            onSelectAll()
        }
    }
}
