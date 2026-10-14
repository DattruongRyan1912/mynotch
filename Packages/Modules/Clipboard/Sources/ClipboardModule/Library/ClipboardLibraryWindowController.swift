import AppKit
import SwiftUI

/// Hosts the library in a regular titled window. One window at a time, made when the library opens and dropped when it
/// closes, so a closed library holds no views. While it is open MyNotch is a regular app, because an accessory app's
/// window cannot take typing; like Settings it returns to a menu bar app once the last titled window closes.
final class ClipboardLibraryWindowController: NSObject, ClipboardLibraryWindowing {
    static let frameAutosaveName = "MyNotch.ClipboardLibrary"

    private var window: NSWindow?
    private var onClose: (() -> Void)?

    var isOpen: Bool { window != nil }

    var isFrontmost: Bool { window?.isKeyWindow == true }

    func show(_ content: AnyView, onClose: @escaping () -> Void) {
        guard window == nil else {
            bringToFront()
            return
        }
        self.onClose = onClose
        let controller = NSHostingController(rootView: content)
        // The toolbar items and the subtitle of the content go into the title bar.
        controller.sceneBridgingOptions = .all
        let window = NSWindow(contentViewController: controller)
        window.title = "Thư viện Clipboard"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 640))
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        // AppKit saves the frame under this name on every move and resize, and restores it the next time.
        if !window.setFrameUsingName(Self.frameAutosaveName) { window.center() }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        self.window = window
        bringToFront()
    }

    func bringToFront() {
        guard let window else { return }
        // Switch the policy first, so the app comes forward as a regular app with its menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    /// The system gives the keyboard to the app that was in front before.
    func yieldKeyboardFocus() {
        NSApp.deactivate()
    }

    func close() {
        window?.close()
    }
}

extension ClipboardLibraryWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        window = nil
        // Dropping the content ends the library's views at once and frees its thumbnails.
        closing.contentViewController = nil
        NSApp.setActivationPolicy(ClipboardLibraryActivation.policyAfterClosing(closing))
        let onClose = onClose
        self.onClose = nil
        onClose?()
    }
}
