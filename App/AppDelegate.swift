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
        permissions: permissions, hotkeys: hotkeys, presenter: coordinator,
        scheduler: scheduler, storageRoot: .standard(bundleID: Bundle.main.bundleIdentifier ?? "io.lucasvu.mynotch")
    )
    private lazy var screens = ScreenManager(registry: registry, activities: activities, settings: settings, scheduler: scheduler)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, registry: registry, permissions: permissions, hotkeys: hotkeys
    )
    private var statusItem: StatusItemController?
    private var permissionPolling: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(settingsTarget: self, settingsAction: #selector(showSettings))
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
        observePermissionPolling()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    /// Re-launching the app (e.g. from Finder) opens Settings, so it stays reachable without a menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return true
    }

    @objc private func showSettings() { settingsWindow.show() }

    private func refreshPermissions() {
        Task { await registry.refreshPermissions() }
    }

    /// TCC posts no notification when a permission changes, so poll while a module waits for one.
    private func observePermissionPolling() {
        Task { [weak self, registry] in
            for await needed in Observations({ registry.needsPermissionPolling }) {
                guard let self else { return }
                setPermissionPolling(needed)
            }
        }
    }

    private func setPermissionPolling(_ enabled: Bool) {
        if enabled, permissionPolling == nil {
            permissionPolling = Task { [registry] in
                // `Task.sleep` throws once the task is cancelled, which ends the loop.
                while (try? await Task.sleep(for: .seconds(2))) != nil {
                    await registry.refreshPermissions()
                }
            }
        } else if !enabled {
            permissionPolling?.cancel()
            permissionPolling = nil
        }
    }
}
