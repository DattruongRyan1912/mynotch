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

/// Which modifier keys are down right now; a protocol so tests never read the real keyboard.
protocol ModifierState {
    /// Whether ⌃, ⌥, ⌘ or ⇧ is down.
    var isAnyHeld: Bool { get }
}

/// Reads the session's modifier flags, which needs no permission.
struct SystemModifierState: ModifierState {
    private static let watched: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]

    var isAnyHeld: Bool {
        !CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: Self.watched)
    }
}

/// Puts an item back on the pasteboard and optionally pastes it into the front app.
final class ClipboardPaster {
    /// For a paste started by a shortcut: ⌘V is held back until the keys that fired it are up, since the user's ⌃⌥⌘ would
    /// otherwise mix into it, and the caller hears whether it went out.
    struct KeyRelease {
        /// ⌘V was sent.
        let onSent: () -> Void
        /// The keys were still down after `keyReleaseTimeout`: nothing was sent.
        let onTimeout: () -> Void
    }

    /// How often the keys are looked at while they are held, and how long before the paste is given up.
    static let keyPollInterval: Duration = .milliseconds(15)
    static let keyReleaseTimeout: Duration = .seconds(1)

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
    private let modifiers: any ModifierState
    private let pasteDelay: Duration
    private var pendingPaste: ScheduledAction?

    /// `pasteDelay` gives the notch time to close so keyboard focus is back on the previous app before ⌘V.
    init(
        pasteboard: any PasteboardAccess, keystrokes: any KeystrokeSending, scheduler: any Scheduler,
        isTrusted: @escaping () -> Bool, modifiers: any ModifierState, pasteDelay: Duration = .milliseconds(80)
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.scheduler = scheduler
        self.isTrusted = isTrusted
        self.modifiers = modifiers
        self.pasteDelay = pasteDelay
    }

    /// Always writes the item first, keeping its source app; with `paste`, ⌘V follows after `pasteDelay` (or the
    /// `delay` of this call, for a window that needs longer to give the keyboard back) when Accessibility is granted.
    /// `beforePaste` is for a window that holds the keyboard: it runs after the write and the permission check, before
    /// ⌘V is scheduled, hands the keyboard back and says whether a key press would now reach the app in front. When it
    /// says no, nothing is pasted (the item stays on the pasteboard for the user's own ⌘V) and the outcome is `.copied`.
    /// With `afterKeysUp`, the outcome `.pasted` only means ⌘V is on its way: it goes out once no modifier is held (after
    /// the delay, looking every `keyPollInterval`), and `afterKeysUp` says whether it did. A newer paste cancels a waiting
    /// one, which then says nothing.
    @discardableResult
    func perform(
        _ item: ClipboardItem, imageURL: URL?, paste: Bool, plainTextOnly: Bool = false, delay: Duration? = nil,
        beforePaste: (() -> Bool)? = nil, afterKeysUp: KeyRelease? = nil
    ) -> Outcome {
        let written = pasteboard.write(
            item.content, imageURL: imageURL, plainTextOnly: plainTextOnly, sourceBundleID: item.sourceBundleID
        )
        guard written else { return .failed }
        // The pasteboard now holds this item, so an earlier ⌘V still waiting would paste it in the wrong place.
        pendingPaste?.cancel()
        pendingPaste = nil
        guard paste else { return .copied }
        guard isTrusted() else { return .copiedNeedsPermission }
        if let beforePaste, !beforePaste() { return .copied }
        if let afterKeysUp {
            pendingPaste = scheduler.schedule(after: delay ?? pasteDelay) { [weak self] in
                self?.sendOnceKeysAreUp(afterKeysUp, waited: .zero)
            }
        } else {
            let keystrokes = keystrokes
            pendingPaste = scheduler.schedule(after: delay ?? pasteDelay) { keystrokes.sendPaste() }
        }
        return .pasted
    }

    /// Sends ⌘V when no modifier is down; otherwise looks again shortly, until `keyReleaseTimeout`.
    private func sendOnceKeysAreUp(_ release: KeyRelease, waited: Duration) {
        if !modifiers.isAnyHeld {
            keystrokes.sendPaste()
            release.onSent()
        } else if waited >= Self.keyReleaseTimeout {
            release.onTimeout()
        } else {
            pendingPaste = scheduler.schedule(after: Self.keyPollInterval) { [weak self] in
                self?.sendOnceKeysAreUp(release, waited: waited + Self.keyPollInterval)
            }
        }
    }
}
