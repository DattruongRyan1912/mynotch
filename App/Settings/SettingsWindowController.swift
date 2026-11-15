import AppKit
import MyNotchCore
import SwiftUI

/// Hosts the SwiftUI settings UI in a regular window and brings it to the front.
/// While the window is open the app shows a Dock icon and appears in ⌘Tab, so the window is easy to find again.
final class SettingsWindowController: NSObject {
    private let settings: SettingsStore
    private let registry: ModuleRegistry
    private let permissions: any PermissionCenter
    private let overview: PermissionOverview
    private let hotkeys: HotkeyRegistry
    private let configSync: ConfigSyncService
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    /// Whether the window can be seen (not closed, minimized or covered). Observable.
    var isVisible: Bool { navigation.isWindowVisible }

    init(
        settings: SettingsStore, registry: ModuleRegistry, permissions: any PermissionCenter,
        overview: PermissionOverview, hotkeys: HotkeyRegistry, configSync: ConfigSyncService
    ) {
        self.settings = settings
        self.registry = registry
        self.permissions = permissions
        self.overview = overview
        self.hotkeys = hotkeys
        self.configSync = configSync
    }

    /// Shows the window, on `page` when given and otherwise on the page it was last showing.
    func show(page: SettingsPage? = nil) {
        if let page { navigation.selection = page }
        if window == nil {
            let root = SettingsRootView(
                settings: settings, registry: registry, permissions: permissions, overview: overview,
                hotkeys: hotkeys, configSync: configSync, navigation: navigation
            )
            let controller = NSHostingController(rootView: root)
            controller.sceneBridgingOptions = .all
            let window = NSWindow(contentViewController: controller)
            window.title = "Cài đặt"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.toolbarStyle = .unified
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.isMovableByWindowBackground = false
            window.setContentSize(NSSize(width: 860, height: 600))
            window.contentMinSize = NSSize(width: 680, height: 480)
            window.isReleasedWhenClosed = false
            // Set only here: the window is reused, so showing it again never registers a second close handler.
            window.delegate = self
            window.center()
            self.window = window
        }
        // Switch the policy first, so the app comes forward as a regular app with its menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        setWindowVisible(true)
    }

    private func setWindowVisible(_ visible: Bool) {
        navigation.isWindowVisible = visible
        overview.setWindowVisible(visible)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    /// Granting happens in System Settings, so coming back to this window is the moment to read the statuses again.
    func windowDidBecomeKey(_ notification: Notification) {
        overview.refresh()
    }

    /// The Permissions page polls only while the window can be seen: closed, minimized and covered all stop it.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        setWindowVisible(window?.occlusionState.contains(.visible) == true)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        setWindowVisible(false)
    }

    /// Minimizing keeps the window, and so the Dock icon that brings it back; only closing returns to a menu bar app.
    /// Modules open their own titled windows too (language installer, markup editor); stay a regular app while any is visible.
    func windowWillClose(_ notification: Notification) {
        setWindowVisible(false)
        let closing = notification.object as? NSWindow
        let otherTitledWindowVisible = NSApp.windows.contains {
            $0 !== closing && ($0.isVisible || $0.isMiniaturized) && $0.styleMask.contains(.titled)
        }
        if !otherTitledWindowVisible { NSApp.setActivationPolicy(.accessory) }
    }
}
