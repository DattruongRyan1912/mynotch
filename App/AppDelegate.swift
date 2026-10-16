import AppKit
#if DEBUG
import DebugTools
#endif
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
        modules: ModuleList.make(activities: activities), settings: settings, activities: activities, lockScreen: lockScreen,
        permissions: permissions, hotkeys: hotkeys, presenter: coordinator,
        scheduler: scheduler, storageRoot: .standard(bundleID: Bundle.main.bundleIdentifier ?? "io.lucasvu.mynotch"),
        services: services
    )
    private lazy var screens = ScreenManager(registry: registry, activities: activities, settings: settings, scheduler: scheduler)
    private lazy var permissionOverview = PermissionOverview(registry: registry, scheduler: scheduler)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, registry: registry, permissions: permissions, overview: permissionOverview, hotkeys: hotkeys
    )
    private lazy var menuBarNotice = MenuBarNotice(presenter: coordinator)
    private lazy var menuBarHider = MenuBarHiderController(settings: settings, scheduler: scheduler, notice: menuBarNotice)
    private var statusItem: StatusItemController?
    #if DEBUG
    private var debugActivities: DebugActivityTrigger?
    #endif
    private var permissionPolling: Task<Void, Never>?
    /// Keeps the optional permissions' statuses current while the Settings window or the notch is open.
    private lazy var permissionRefresh = PermissionRefreshLoop(
        scheduler: scheduler,
        shouldRun: { [weak self] in self?.permissionRefreshWanted ?? false },
        refresh: { [weak self] in self?.refreshPermissions() }
    )
    private let systemSettingsReturn = SystemSettingsReturn(ownBundleID: Bundle.main.bundleIdentifier ?? "io.lucasvu.mynotch")
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
        MenuBarHiderShortcut.register(in: hotkeys) { [weak self] in self?.menuBarHider.toggle() }
        statusItem = StatusItemController(
            settings: settings, registry: registry, screens: screens, overview: permissionOverview, hider: menuBarHider,
            notice: menuBarNotice,
            openSettings: { [weak self] in self?.settingsWindow.show() },
            openPermissions: { [weak self] in self?.settingsWindow.show(page: .permissions) }
        )
        screens.start()
        openPermissionsIfNeeded()
        #if DEBUG
        debugActivities = DebugActivityTrigger(activities: activities)
        debugActivities?.start()
        #endif
        Task { await registry.bootstrap(); services.finishStartup() }
        observePermissionPolling()
        observePermissionFreshness()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        // Permissions are granted in System Settings; coming back from it is the moment the statuses are most likely to differ.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                if self?.systemSettingsReturn.activated(bundleID) == true { self?.refreshPermissions() }
            }
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
        #if DEBUG
        debugActivities?.stop()
        #endif
        // The wait for the modules can last seconds; the icons the hider holds off the screen come back first.
        menuBarHider.expandNow()
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
        permissionOverview.refresh()
        Task { await registry.refreshPermissions() }
    }

    /// Once on the first launch, and when re-signing made macOS forget the permissions, so nobody has to go looking for
    /// them. The identity is stored even when nothing opens, so the next launch compares against this one.
    private func openPermissionsIfNeeded() {
        let stored = settings.value(AppSettings.permissionIdentity)
        let current = SigningIdentity.current()
        if permissionOverview.shouldOpenAtLaunch(previousIdentity: stored.isEmpty ? nil : stored, currentIdentity: current) {
            settingsWindow.show(page: .permissions)
        }
        settings.set(current ?? "unreadable", for: AppSettings.permissionIdentity)
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

    private var permissionRefreshWanted: Bool {
        PermissionRefreshLoop.isWanted(
            missingOptional: permissionOverview.missingOptionalCount,
            settingsVisible: settingsWindow.isVisible, notchOpen: screens.isAnyNotchExpanded
        )
    }

    /// Nothing waits on an optional permission, so `observePermissionPolling` never runs for one: the loop covers it while
    /// the Settings window or the notch shows the status.
    private func observePermissionFreshness() {
        Task { [weak self] in
            for await _ in Observations({ [weak self] in self?.permissionRefreshWanted ?? false }) {
                self?.permissionRefresh.update()
            }
        }
    }

    private func setPermissionPolling(_ enabled: Bool) {
        if enabled, permissionPolling == nil {
            permissionPolling = Task { [registry, overview = permissionOverview] in
                // `Task.sleep` throws once the task is cancelled, which ends the loop.
                while (try? await Task.sleep(for: .seconds(2))) != nil {
                    await registry.refreshPermissions()
                    // The same poll keeps the status-bar dot and the sidebar badge honest after a grant in System Settings.
                    overview.refresh()
                }
            }
        } else if !enabled {
            permissionPolling?.cancel()
            permissionPolling = nil
        }
    }
}
