import CoreGraphics
import Foundation
import MyNotchCore

/// Sends ⌘V to the app with keyboard focus; a protocol so tests never post real key events.
protocol KeystrokeSending {
    func sendPaste()
}

/// Posts ⌘V through the HID event tap, which needs the Accessibility permission.
struct CGEventKeystrokeSender: KeystrokeSending {
    /// kVK_ANSI_V
    private static let vKeyCode: CGKeyCode = 9

    func sendPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// Puts an item back on the pasteboard and optionally pastes it into the front app.
final class ClipboardPaster {
    enum Outcome: Equatable {
        case copied, pasted
        /// Paste was asked for without the Accessibility permission, so the item was only copied.
        case copiedNeedsPermission
    }

    private let pasteboard: any PasteboardAccess
    private let keystrokes: any KeystrokeSending
    private let scheduler: any Scheduler
    private let isTrusted: () -> Bool
    private let pasteDelay: Duration

    /// `pasteDelay` gives the notch time to close so keyboard focus is back on the previous app before ⌘V.
    init(
        pasteboard: any PasteboardAccess, keystrokes: any KeystrokeSending, scheduler: any Scheduler,
        isTrusted: @escaping () -> Bool, pasteDelay: Duration = .milliseconds(80)
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.scheduler = scheduler
        self.isTrusted = isTrusted
        self.pasteDelay = pasteDelay
    }

    /// Always writes the item; with `paste`, ⌘V follows after `pasteDelay` when Accessibility is granted.
    @discardableResult
    func perform(_ item: ClipboardItem, imageURL: URL?, paste: Bool, plainTextOnly: Bool = false) -> Outcome {
        pasteboard.write(item.content, imageURL: imageURL, plainTextOnly: plainTextOnly)
        guard paste else { return .copied }
        guard isTrusted() else { return .copiedNeedsPermission }
        let keystrokes = keystrokes
        scheduler.schedule(after: pasteDelay) { keystrokes.sendPaste() }
        return .pasted
    }
}
