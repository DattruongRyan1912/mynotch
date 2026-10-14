import AppKit
import MyNotchCore
import NotchUI

/// Menu bar icon and menu.
final class StatusItemController: NSObject {
    private let settings: SettingsStore
    private let registry: ModuleRegistry
    private let screens: ScreenManager
    private let overview: PermissionOverview
    private let openSettings: () -> Void
    private let openPermissions: () -> Void
    private var item: NSStatusItem?
    private var visibilityItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var permissionItem: NSMenuItem?
    /// The red dot on the icon while a required permission is missing.
    private var missingDot: NSView?
    /// What running modules added at the top, replaced each time the menu opens.
    private var moduleItems: [NSMenuItem] = []

    init(
        settings: SettingsStore, registry: ModuleRegistry, screens: ScreenManager, overview: PermissionOverview,
        openSettings: @escaping () -> Void, openPermissions: @escaping () -> Void
    ) {
        self.settings = settings
        self.registry = registry
        self.screens = screens
        self.overview = overview
        self.openSettings = openSettings
        self.openPermissions = openPermissions
        super.init()
        observeVisibility()
        observePermissions()
    }

    private func observeVisibility() {
        Task { [weak self, settings] in
            for await visible in Observations({ settings.value(AppSettings.showMenuBarIcon) }) {
                self?.setVisible(visible)
            }
        }
    }

    /// The icon and the "Thiếu N quyền…" entry follow the count of missing required permissions.
    private func observePermissions() {
        Task { [weak self, overview] in
            for await _ in Observations({ overview.nudgeTitle }) {
                self?.updatePermissionNudge()
            }
        }
    }

    private func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "MyNotch")
            item.menu = makeMenu()
            self.item = item
            addMissingDot(to: item.button)
            updatePermissionNudge()
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
            missingDot = nil
        }
    }

    private func addMissingDot(to button: NSStatusBarButton?) {
        guard let button else { return }
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.setAccessibilityElement(false)
        button.addSubview(dot)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            dot.topAnchor.constraint(equalTo: button.topAnchor, constant: 3),
        ])
        missingDot = dot
    }

    private func updatePermissionNudge() {
        let title = overview.nudgeTitle
        missingDot?.isHidden = title == nil
        item?.button?.toolTip = title.map { "MyNotch: \($0)" }
        permissionItem?.title = title ?? ""
        permissionItem?.isHidden = title == nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let permissionItem = menu.addItem(withTitle: "", action: #selector(openPermissionsAction), keyEquivalent: "")
        permissionItem.target = self
        permissionItem.isHidden = true
        self.permissionItem = permissionItem
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

    @objc private func openPermissionsAction() { openPermissions() }

    @objc private func toggleNotchVisibility() { screens.isHiddenByUser.toggle() }

    @objc private func togglePause() {
        Task { [registry] in registry.isPaused ? await registry.resumeAll() : await registry.pauseAll() }
    }

    /// Entries that running modules offer (`FeatureModule.menuItems`), above the app's own, with a separator.
    private func refreshModuleItems(in menu: NSMenu) {
        moduleItems.forEach(menu.removeItem)
        let entries = registry.menuItems
        moduleItems = entries.map { entry in
            let item = NSMenuItem(title: entry.title, action: #selector(performModuleItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ModuleMenuAction(entry.action)
            return item
        }
        if !moduleItems.isEmpty { moduleItems.append(.separator()) }
        for (index, item) in moduleItems.enumerated() { menu.insertItem(item, at: index) }
    }

    @objc private func performModuleItem(_ item: NSMenuItem) {
        (item.representedObject as? ModuleMenuAction)?.run()
    }
}

/// A module's menu action, boxed because `representedObject` holds objects.
private final class ModuleMenuAction {
    let run: @MainActor () -> Void

    init(_ run: @escaping @MainActor () -> Void) {
        self.run = run
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        visibilityItem?.title = screens.isHiddenByUser ? "Show Notch" : "Hide Notch"
        pauseItem?.state = registry.isPaused ? .on : .off
        // Granting happens in System Settings, so the count is read again each time the menu opens.
        overview.refresh()
        updatePermissionNudge()
        refreshModuleItems(in: menu)
    }
}
