import AppKit
import MyNotchCore
import SwiftUI

/// Hosts the SwiftUI settings UI in a regular window and brings it to the front.
/// While the window is open the app shows a Dock icon and appears in ⌘Tab, so the window is easy to find again.
final class SettingsWindowController: NSObject {
    private let settings: SettingsStore
    private let registry: ModuleRegistry
    private let permissions: any PermissionCenter
    private let hotkeys: HotkeyRegistry
    private var window: NSWindow?

    init(settings: SettingsStore, registry: ModuleRegistry, permissions: any PermissionCenter, hotkeys: HotkeyRegistry) {
        self.settings = settings
        self.registry = registry
        self.permissions = permissions
        self.hotkeys = hotkeys
    }

    func show() {
        if window == nil {
            let root = SettingsRootView(settings: settings, registry: registry, permissions: permissions, hotkeys: hotkeys)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "MyNotch Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 760, height: 520))
            window.contentMinSize = NSSize(width: 600, height: 400)
            window.isReleasedWhenClosed = false
            // Set only here: the window is reused, so showing it again never registers a second close handler.
            window.delegate = self
            window.center()
            self.window = window
        }
        // Switch the policy first, so the app comes forward as a regular app with its menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    /// Minimizing keeps the window, and so the Dock icon that brings it back; only closing returns to a menu bar app.
    /// Modules open their own titled windows too (language installer, markup editor); stay a regular app while any is visible.
    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        let otherTitledWindowVisible = NSApp.windows.contains {
            $0 !== closing && ($0.isVisible || $0.isMiniaturized) && $0.styleMask.contains(.titled)
        }
        if !otherTitledWindowVisible { NSApp.setActivationPolicy(.accessory) }
    }
}
