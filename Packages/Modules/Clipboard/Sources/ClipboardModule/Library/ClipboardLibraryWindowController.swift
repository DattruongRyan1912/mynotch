import AppKit
import NotchUI
import SwiftUI

/// Hosts the library in a regular titled window. One window at a time, made when the library opens and dropped when it
/// closes, so a closed library holds no views. While it is open MyNotch is a regular app, because an accessory app's
/// window cannot take typing; like Settings it returns to a menu bar app once the last titled window closes. It stays out
/// of recordings when the user asks for that, as the notch's windows do.
final class ClipboardLibraryWindowController: NSObject, ClipboardLibraryWindowing {
    static let frameAutosaveName = "MyNotch.ClipboardLibrary"

    private let interface: NotchInterface
    private var window: NSWindow?
    private var onClose: (() -> Void)?
    /// Keeps the window out of recordings the way the user asked, while it is open.
    private var captureFollower: CaptureHidingFollower?

    /// `interface` is where the "hide from screen recording" setting comes from: the app's shared one, or a test's own.
    init(interface: NotchInterface = .shared) {
        self.interface = interface
    }

    var isOpen: Bool { window != nil }

    var isFrontmost: Bool { window?.isKeyWindow == true }

    var frame: CGRect? { window?.frame }

    var windowIdentity: ObjectIdentifier? { window.map(ObjectIdentifier.init) }

    func show(_ content: AnyView, model: ClipboardLibraryModel, onClose: @escaping () -> Void) {
        guard window == nil else {
            bringToFront()
            return
        }
        self.onClose = onClose
        let window = makeWindow(content)
        (window as? ClipboardLibraryWindow)?.onPreviewKey = { [weak model] key, target, marked in
            model?.handlePreviewKey(key, target: target, hasMarkedText: marked) ?? false
        }
        window.delegate = self
        // AppKit saves the frame under this name on every move and resize, and restores it the next time.
        if !window.setFrameUsingName(Self.frameAutosaveName) { window.center() }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        self.window = window
        bringToFront()
    }

    /// The window, configured but not on any screen, and already hidden from recordings when the setting says so: there is
    /// no frame in which a recorder could see it. The user opens it like an open notch, so "only while collapsed" shows it.
    func makeWindow(_ content: AnyView) -> NSWindow {
        // The window is outside the notch's views, so it is given the notch's accent here.
        let controller = NSHostingController(rootView: ClipboardAccentHost(interface: interface) { content })
        // The toolbar items and the subtitle of the content go into the title bar.
        controller.sceneBridgingOptions = .all
        let window = ClipboardLibraryWindow(contentViewController: controller)
        window.title = "Thư viện Clipboard"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 640))
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        captureFollower?.stop()
        captureFollower = CaptureHidingFollower(window, as: .toast, interface: interface)
        return window
    }

    func stopFollowingSetting() {
        captureFollower?.stop()
        captureFollower = nil
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
        (closing as? ClipboardLibraryWindow)?.onPreviewKey = nil
        stopFollowingSetting()
        // Dropping the content ends the library's views at once and frees its thumbnails.
        closing.contentViewController = nil
        NSApp.setActivationPolicy(ClipboardLibraryActivation.policyAfterClosing(closing))
        let onClose = onClose
        self.onClose = nil
        onClose?()
    }
}
