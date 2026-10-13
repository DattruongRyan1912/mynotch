import AppKit
import MyNotchCore
import SwiftUI

/// Hosts the SwiftUI settings UI in a regular window and brings it to the front.
final class SettingsWindowController {
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
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
