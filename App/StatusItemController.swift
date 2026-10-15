import AppKit
import MyNotchCore
import NotchUI

/// Menu bar icon and menu.
final class StatusItemController: NSObject {
    private let settings: SettingsStore
    private let registry: ModuleRegistry
    private let screens: ScreenManager
    private let overview: PermissionOverview
    private let hider: MenuBarHiderController
    private let openSettings: () -> Void
    private let openPermissions: () -> Void
    private var item: NSStatusItem?
    private var menu: NSMenu?
    private var visibilityItem: NSMenuItem?
    private var hiderItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var permissionItem: NSMenuItem?
    /// The red dot on the icon while a required permission is missing.
    private var missingDot: NSView?
    /// What running modules added at the top, replaced each time the menu opens.
    private var moduleItems: [NSMenuItem] = []

    init(
        settings: SettingsStore, registry: ModuleRegistry, screens: ScreenManager, overview: PermissionOverview,
        hider: MenuBarHiderController, openSettings: @escaping () -> Void, openPermissions: @escaping () -> Void
    ) {
        self.settings = settings
        self.registry = registry
        self.screens = screens
        self.overview = overview
        self.hider = hider
        self.openSettings = openSettings
        self.openPermissions = openPermissions
        super.init()
        observeVisibility()
        observePermissions()
        observeHider()
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

    /// With the menu-bar hider on, a click on the icon shows or hides the icons and the menu moves to a right-click.
    private func observeHider() {
        Task { [weak self, settings] in
            for await _ in Observations({ settings.value(MenuBarHiderSettings.enabled) }) {
                self?.applyClickBehaviour()
                self?.updateHiderEntry()
            }
        }
    }

    private func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            // A fixed name, so macOS keeps where the user dragged the icon, and the hider's separator can be told to sit on its left.
            item.autosaveName = "MyNotchIcon"
            item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "MyNotch")
            menu = makeMenu()
            self.item = item
            applyClickBehaviour()
            addMissingDot(to: item.button)
            updatePermissionNudge()
            // After the icon exists, so the separator is made after it.
            hider.setToggleItem(item)
        } else if !visible, let item {
            hider.setToggleItem(nil)
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
            menu = nil
            missingDot = nil
        }
    }

    /// The menu opens on a click, or, with the hider on, on a right-click or control-click while a plain click toggles.
    private func applyClickBehaviour() {
        guard let button = item?.button else { return }
        if hider.isEnabled {
            item?.menu = nil
            button.target = self
            button.action = #selector(statusButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // Pressing the button with VoiceOver is a plain click, so the menu needs a way of its own.
            button.setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: "Mở menu MyNotch") { [weak self] in
                    self?.showMenu()
                    return true
                },
            ])
        } else {
            button.target = nil
            button.action = nil
            button.setAccessibilityCustomActions(nil)
            item?.menu = menu
        }
    }

    @objc private func statusButtonClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            hider.toggle()
        }
    }

    /// The menu is attached only for the click that opens it, which keeps the plain click free for the hider.
    private func showMenu() {
        guard let item, let menu else { return }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func updateHiderEntry() {
        hiderItem?.isHidden = !hider.isEnabled
        hiderItem?.title = hider.isCollapsed ? "Hiện icon đã ẩn" : "Ẩn bớt icon menu bar"
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
        let hiderItem = menu.addItem(withTitle: "Ẩn bớt icon menu bar", action: #selector(toggleHiddenIcons), keyEquivalent: "")
        hiderItem.target = self
        hiderItem.isHidden = !hider.isEnabled
        self.hiderItem = hiderItem
        let pauseItem = menu.addItem(withTitle: "Pause All Modules", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        self.pauseItem = pauseItem
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MyNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func openSettingsAction() { openSettings() }

    @objc private func openPermissionsAction() { openPermissions() }

    @objc private func toggleHiddenIcons() { hider.toggle() }

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
        updateHiderEntry()
        // Granting happens in System Settings, so the count is read again each time the menu opens.
        overview.refresh()
        updatePermissionNudge()
        refreshModuleItems(in: menu)
    }
}
