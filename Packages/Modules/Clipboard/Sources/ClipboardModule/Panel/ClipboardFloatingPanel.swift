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
    /// What the large preview makes of a key press (Space, ⌘Y, Esc, Return), asked before the search field sees it.
    var onPreviewKey: ClipboardPreviewKeys.Handler?

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

    /// False from the moment a paste hands the keyboard to the app behind until the user comes back to the panel. A window that
    /// can become key gets key status back as soon as the hidden panel that took it leaves (AppKit picks the next candidate), so
    /// a pinned panel that stays on screen could never give the keyboard away; the notch's panel does the same.
    var allowsKeyStatus = true {
        didSet {
            guard allowsKeyStatus != oldValue else { return }
            ClipboardPanelLog.record("allowsKey=\(allowsKeyStatus) \(logSummary)")
        }
    }

    override var canBecomeKey: Bool { allowsKeyStatus }
    override var canBecomeMain: Bool { false }

    /// Geometry and key state, for the trace.
    var logSummary: String {
        "window=\(windowNumber) frame=\(frame.origin.x),\(frame.origin.y) \(frame.width)x\(frame.height) key=\(isKeyWindow)"
    }

    /// Space in the search field is typed text, which never reaches it as a command, so every key press is looked at here first.
    override func sendEvent(_ event: NSEvent) {
        if offersToPreview(event), handlePreviewKey(event) { return }
        // The user is back at the panel: a click takes the keyboard again, as it did before a paste handed it away.
        if !allowsKeyStatus, Self.isClick(event) { allowsKeyStatus = true }
        super.sendEvent(event)
    }

    static func isClick(_ event: NSEvent) -> Bool {
        event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown
    }

    func offersToPreview(_ event: NSEvent) -> Bool {
        event.type == .keyDown
    }

    /// The panel's only text input is its search field, so anything else that has the keyboard is not a place to type.
    func handlePreviewKey(_ event: NSEvent) -> Bool {
        ClipboardPreviewKeys.offer(event, in: self, to: onPreviewKey) { _ in true }
    }

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
