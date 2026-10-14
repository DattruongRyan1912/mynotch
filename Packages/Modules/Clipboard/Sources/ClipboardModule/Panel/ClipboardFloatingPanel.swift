import AppKit
import SwiftUI

/// The panel itself: borderless, non-activating, floating over every Space. It takes typing without making MyNotch the
/// active app, so the app in front stays what ⌘V is sent to.
final class ClipboardFloatingPanel: NSPanel {
    /// ⌘1 to ⌘9. Returns whether the number picked an item; the key is consumed either way.
    var onQuickPick: ((Int) -> Bool)?
    /// Esc that no view handled.
    var onCancel: (() -> Void)?
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
        if let number = ClipboardPanelKeys.quickPickNumber(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            _ = onQuickPick?(number)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// Hosting view that accepts the first click even though the app is not active.
final class ClipboardFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
