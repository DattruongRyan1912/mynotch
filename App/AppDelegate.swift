import AppKit
import KeyboardShortcuts
import MyNotchCore
import NotchUI

/// Composition root: builds the shared services and wires them together.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore(defaults: .standard)
    private let scheduler = TaskScheduler()
    private let permissions = SystemPermissionCenter()
    private let hotkeys = HotkeyRegistry(backend: KeyboardShortcutsBackend())
    private lazy var services = ServiceRegistry(scheduler: scheduler)
    private let coordinator = NotchCoordinator()
    private lazy var activities = ActivityCenter(scheduler: scheduler)
    private let lockScreen = LockScreenContentCenter()
    private lazy var registry = ModuleRegistry(
        modules: ModuleList.make(), settings: settings, activities: activities, lockScreen: lockScreen,
        permissions: permissions, hotkeys: hotkeys, presenter: coordinator,
        scheduler: scheduler, storageRoot: .standard(bundleID: Bundle.main.bundleIdentifier ?? "io.lucasvu.mynotch"),
        services: services
    )
    private lazy var screens = ScreenManager(registry: registry, activities: activities, settings: settings, scheduler: scheduler)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, registry: registry, permissions: permissions, hotkeys: hotkeys
    )
    private var statusItem: StatusItemController?
    private var permissionPolling: Task<Void, Never>?
    private var repliedToTerminate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(settingsTarget: self, settingsAction: #selector(showSettings))
        coordinator.screens = screens
        NSApp.servicesProvider = ServicesProvider(registry: services)
        // Picks up NSServices changes from a new build without logging out.
        NSUpdateDynamicServices()
        hotkeys.register(
            "toggleNotch", title: "Mở/đóng notch", owner: nil,
            initial: KeyboardShortcuts.Shortcut(.n, modifiers: [.control, .option])
        ) { [weak self] in self?.coordinator.toggle() }
        statusItem = StatusItemController(
            settings: settings, registry: registry, screens: screens,
            openSettings: { [weak self] in self?.settingsWindow.show() }
        )
        screens.start()
        Task { await registry.bootstrap(); services.finishStartup() }
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

    /// Modules save their data in `stop`, so quitting waits for them, but never longer than three seconds.
    /// The deadline is a run-loop timer in `.common` modes, not a Swift task: if `terminate` is ever called from a
    /// main-queue task, AppKit's modal wait for the reply starves Swift tasks, while run-loop timers still fire.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let deadline = Timer(timeInterval: 3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.replyToTerminate() }
        }
        RunLoop.main.add(deadline, forMode: .common)
        Task { await registry.shutdown(); replyToTerminate() }
        return .terminateLater
    }

    /// Shutdown and the deadline both end here; only the first one replies.
    private func replyToTerminate() {
        guard !repliedToTerminate else { return }
        repliedToTerminate = true
        NSApp.reply(toApplicationShouldTerminate: true)
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
