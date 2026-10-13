import AppKit
import KeyboardShortcuts
import MyNotchCore
import NotchUI

/// Composition root: builds the shared services and wires them together.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let scheduler = TaskScheduler()
    private let permissions = SystemPermissionCenter()
    private let hotkeys = HotkeyRegistry()
    private let coordinator = NotchCoordinator()
    private lazy var activities = ActivityCenter(scheduler: scheduler)
    private lazy var registry = ModuleRegistry(
        modules: ModuleList.make(), settings: settings, activities: activities,
        permissions: permissions, hotkeys: hotkeys, presenter: coordinator
    )
    private lazy var screens = ScreenManager(registry: registry, activities: activities, settings: settings, scheduler: scheduler)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, registry: registry, permissions: permissions, hotkeys: hotkeys
    )
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.screens = screens
        hotkeys.register(
            "toggleNotch", title: "Mở/đóng notch", owner: nil,
            initial: KeyboardShortcuts.Shortcut(.n, modifiers: [.control, .option])
        ) { [weak self] in self?.coordinator.toggle() }
        statusItem = StatusItemController(
            settings: settings, registry: registry, screens: screens,
            openSettings: { [weak self] in self?.settingsWindow.show() }
        )
        screens.start()
        Task { await registry.bootstrap() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    /// Re-launching the app (e.g. from Finder) opens Settings, so it stays reachable without a menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return true
    }

    private func refreshPermissions() {
        Task { await registry.refreshPermissions() }
    }
}
