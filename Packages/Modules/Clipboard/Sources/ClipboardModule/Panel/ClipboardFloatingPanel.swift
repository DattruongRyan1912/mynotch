import AppKit
import SwiftUI

/// The panel itself: borderless, non-activating, floating over every Space. It takes typing without making MyNotch the
/// active app, so the app in front stays what ⌘V is sent to.
final class ClipboardFloatingPanel: NSPanel {
    /// ⌘1 to ⌘9. Returns whether the number picked an item; the key is consumed either way.
    var onQuickPick: ((Int) -> Bool)?
    /// Esc that no view handled.
    var onCancel: (() -> Void)?
    var onBecomeKey: (() -> Void)?
    /// Called after key status moved elsewhere, e.g. the user clicked into another app.
    var onResignKey: (() -> Void)?

    init(size: CGSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        // On every Space and next to full-screen apps, and hidden by Mission Control instead of listed in it.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        // MyNotch is never the active app while the panel is open, and a panel that hid then would never show.
        hidesOnDeactivate = false
        allowsToolTipsWhenApplicationIsInactive = true
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        title = "Bảng clipboard"
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let number = ClipboardPanelKeys.quickPickNumber(characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags) {
            _ = onQuickPick?(number)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func becomeKey() {
        super.becomeKey()
        onBecomeKey?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// Invisible 1 pt panel that only takes key status from the clipboard panel and leaves again. A key window that leaves
/// the screen returns the keyboard to the app in front, and doing it with this panel keeps the clipboard panel on
/// screen. The notch hands its keyboard back the same way.
final class ClipboardKeySinkPanel: NSPanel {
    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that accepts the first click even though the app is not active.
final class ClipboardFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
