import CoreGraphics
import Foundation
import MyNotchCore

/// Sends ⌘V to the app with keyboard focus; a protocol so tests never post real key events.
protocol KeystrokeSending {
    func sendPaste()
}

/// Posts ⌘V through the HID event tap, which needs the Accessibility permission.
struct CGEventKeystrokeSender: KeystrokeSending {
    /// kVK_ANSI_V is the physical V key, so layouts that move V get a different shortcut (⌘K on Dvorak).
    private static let vKeyCode: CGKeyCode = 9

    func sendPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Holds back the user's own key presses while ⌘V is posted, so they cannot mix into the shortcut.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval
        )
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
        /// Nothing could be written (e.g. the image file is gone); the pasteboard is unchanged and nothing is pasted.
        case failed
    }

    private let pasteboard: any PasteboardAccess
    private let keystrokes: any KeystrokeSending
    private let scheduler: any Scheduler
    private let isTrusted: () -> Bool
    private let pasteDelay: Duration
    private var pendingPaste: ScheduledAction?

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

    /// Always writes the item first, keeping its source app; with `paste`, ⌘V follows after `pasteDelay` (or the
    /// `delay` of this call, for a window that needs longer to give the keyboard back) when Accessibility is granted.
    @discardableResult
    func perform(_ item: ClipboardItem, imageURL: URL?, paste: Bool, plainTextOnly: Bool = false, delay: Duration? = nil) -> Outcome {
        let written = pasteboard.write(
            item.content, imageURL: imageURL, plainTextOnly: plainTextOnly, sourceBundleID: item.sourceBundleID
        )
        guard written else { return .failed }
        // The pasteboard now holds this item, so an earlier ⌘V still waiting would paste it in the wrong place.
        pendingPaste?.cancel()
        pendingPaste = nil
        guard paste else { return .copied }
        guard isTrusted() else { return .copiedNeedsPermission }
        let keystrokes = keystrokes
        pendingPaste = scheduler.schedule(after: delay ?? pasteDelay) { keystrokes.sendPaste() }
        return .pasted
    }
}
