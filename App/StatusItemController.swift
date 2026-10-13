import AppKit
import MyNotchCore
import NotchUI

/// Menu bar icon and menu.
final class StatusItemController: NSObject {
    private let settings: SettingsStore
    private let registry: ModuleRegistry
    private let screens: ScreenManager
    private let openSettings: () -> Void
    private var item: NSStatusItem?
    private var visibilityItem: NSMenuItem?
    private var pauseItem: NSMenuItem?

    init(settings: SettingsStore, registry: ModuleRegistry, screens: ScreenManager, openSettings: @escaping () -> Void) {
        self.settings = settings
        self.registry = registry
        self.screens = screens
        self.openSettings = openSettings
        super.init()
        observeVisibility()
    }

    private func observeVisibility() {
        Task { [weak self, settings] in
            for await visible in Observations({ settings.value(AppSettings.showMenuBarIcon) }) {
                self?.setVisible(visible)
            }
        }
    }

    private func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "MyNotch")
            item.menu = makeMenu()
            self.item = item
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Open Settings…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        let visibilityItem = menu.addItem(withTitle: "Hide Notch", action: #selector(toggleNotchVisibility), keyEquivalent: "")
        visibilityItem.target = self
        self.visibilityItem = visibilityItem
        let pauseItem = menu.addItem(withTitle: "Pause All Modules", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        self.pauseItem = pauseItem
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MyNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func openSettingsAction() { openSettings() }

    @objc private func toggleNotchVisibility() { screens.isHiddenByUser.toggle() }

    @objc private func togglePause() {
        Task { [registry] in registry.isPaused ? await registry.resumeAll() : await registry.pauseAll() }
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        visibilityItem?.title = screens.isHiddenByUser ? "Show Notch" : "Hide Notch"
        pauseItem?.state = registry.isPaused ? .on : .off
    }
}
