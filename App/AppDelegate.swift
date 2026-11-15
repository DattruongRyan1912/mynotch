import AppKit
#if DEBUG
import BatteryModule
import DebugTools
import TodoModule
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
    private lazy var equalizer = EqualizerState(settings: settings)
    private lazy var registry = ModuleRegistry(
        modules: ModuleList.make(activities: activities, equalizer: equalizer), settings: settings, activities: activities, lockScreen: lockScreen,
        permissions: permissions, hotkeys: hotkeys, presenter: coordinator,
        scheduler: scheduler, storageRoot: .standard(bundleID: Bundle.main.bundleIdentifier ?? "io.lucasvu.mynotch"),
        services: services
    )
    private lazy var screens = ScreenManager(registry: registry, activities: activities, settings: settings, scheduler: scheduler)
    private lazy var permissionOverview = PermissionOverview(registry: registry, scheduler: scheduler)
    private lazy var configSync = ConfigSyncService(settings: settings, scheduler: scheduler) { [weak self] updatedKeys in
        guard let self else { return }
        self.equalizer.reloadFromSettings()
        let hasModuleToggle = updatedKeys.contains { $0.hasPrefix("module.") && $0.hasSuffix(".enabled") }
        if hasModuleToggle {
            Task { await self.registry.bootstrap() }
        }
    }
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, registry: registry, permissions: permissions, overview: permissionOverview, hotkeys: hotkeys, configSync: configSync
    )
    private lazy var dashboardWindow = DashboardWindowController(
        registry: registry, scheduler: scheduler, openSettings: { [weak self] in self?.settingsWindow.show() }
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
    private var notificationObservers: [any NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(
            settingsTarget: self, settingsAction: #selector(showSettings),
            dashboardTarget: self, dashboardAction: #selector(showDashboard)
        )
        coordinator.screens = screens
        NSApp.servicesProvider = ServicesProvider(registry: services)
        // Picks up NSServices changes from a new build without logging out.
        NSUpdateDynamicServices()
        hotkeys.register(
            "toggleNotch", title: "Mở/đóng notch", owner: nil,
            initial: KeyboardShortcuts.Shortcut(.n, modifiers: [.control, .option])
        ) { [weak self] in self?.coordinator.toggle() }
        hotkeys.register(
            "toggleDashboard", title: "Mở Bảng điều khiển", owner: nil,
            initial: KeyboardShortcuts.Shortcut(.b, modifiers: [.control, .option])
        ) { [weak self] in self?.dashboardWindow.toggle() }
        MenuBarHiderShortcut.register(in: hotkeys) { [weak self] in self?.menuBarHider.toggle() }
        statusItem = StatusItemController(
            settings: settings, registry: registry, screens: screens, overview: permissionOverview, hider: menuBarHider,
            notice: menuBarNotice,
            openSettings: { [weak self] in self?.settingsWindow.show() },
            openPermissions: { [weak self] in self?.settingsWindow.show(page: .permissions) },
            openDashboard: { [weak self] in self?.dashboardWindow.show() }
        )
        configSync.bootstrap()
        screens.start()
        openPermissionsIfNeeded()
        #if DEBUG
        debugActivities = DebugActivityTrigger(activities: activities)
        debugActivities?.start()
        #endif
        Task { await registry.bootstrap(); services.finishStartup() }
        registry.storageCenter.startAutoClean()
        observePermissionPolling()
        observePermissionFreshness()
        notificationObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("io.lucasvu.mynotch.openDashboard"),
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.dashboardWindow.show() }
            }
        )
        notificationObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("io.lucasvu.mynotch.openDashboardBattery"),
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.dashboardWindow.show(tab: .battery) }
            }
        )
        notificationObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("io.lucasvu.mynotch.openDashboardTodo"),
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.dashboardWindow.show(tab: .todo) }
            }
        )
        notificationObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("io.lucasvu.mynotch.openDashboardProductivity"),
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.dashboardWindow.show(tab: .productivity) }
            }
        )
        notificationObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("io.lucasvu.mynotch.toggleDashboard"),
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.dashboardWindow.toggle() }
            }
        )
        #if DEBUG
        notificationObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("io.lucasvu.mynotch.exportDashboardEvidence"),
                object: nil, queue: .main
            ) { [weak self] _ in
                let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mynotch_evidence", isDirectory: true)
                try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                MainActor.assumeIsolated { self?.dashboardWindow.exportEvidence(to: tmpDir) }
            }
        )
        notificationObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("io.lucasvu.mynotch.runStudioVerification"),
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.runStudioVerification() }
            }
        )
        if CommandLine.arguments.contains("--verify-studio") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.runStudioVerification()
            }
        }
        #endif
        if CommandLine.arguments.contains("--open-dashboard-todo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.dashboardWindow.show(tab: .todo)
            }
        }
        if CommandLine.arguments.contains("--open-dashboard-productivity") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.dashboardWindow.show(tab: .productivity)
            }
        }
        if CommandLine.arguments.contains("--open-dashboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.dashboardWindow.show()
            }
        }
        if CommandLine.arguments.contains("--open-dashboard-cleaner") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.dashboardWindow.show(tab: .cleaner)
            }
        }
        notificationObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("io.lucasvu.mynotch.openDashboardCleaner"),
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.dashboardWindow.show(tab: .cleaner) }
            }
        )
        notificationObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("io.lucasvu.mynotch.switchTab"),
                object: nil, queue: .main
            ) { [weak self] note in
                if let tabRaw = note.userInfo?["tab"] as? String, let tab = DashboardTab(rawValue: tabRaw) {
                    MainActor.assumeIsolated { self?.dashboardWindow.show(tab: tab) }
                }
            }
        )
        notificationObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("io.lucasvu.mynotch.switchTheme"),
                object: nil, queue: .main
            ) { _ in
                let raw = UserDefaults.standard.string(forKey: "io.lucasvu.mynotch.dashboardThemeStyle") ?? ""
                if let style = DashboardThemeStyle(rawValue: raw) {
                    MainActor.assumeIsolated { DashboardThemeStore.shared.setStyle(style) }
                }
            }
        )
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
        configSync.stopWatching()
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

    @objc private func showDashboard() { dashboardWindow.show() }

    private func refreshPermissions() {
        permissionOverview.refresh()
        Task { await registry.refreshPermissions() }
    }

    /// Once on the first launch, and when re-signing made macOS forget the permissions, so nobody has to go looking for
    /// them. The identity is stored even when nothing opens, so the next launch compares against this one.
    private func openPermissionsIfNeeded() {
        let stored = settings.value(AppSettings.permissionIdentity)
        let current = SigningIdentity.current()
        let shouldOpen = permissionOverview.shouldOpenAtLaunch(previousIdentity: stored.isEmpty ? nil : stored, currentIdentity: current)
        if shouldOpen {
            settingsWindow.show(page: .permissions)
            if !stored.isEmpty, current != nil, permissionOverview.status(of: .accessibility) == .denied {
                Task { [weak self] in
                    await self?.permissionOverview.recoverAccessibility()
                }
            }
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

    #if DEBUG
    private var isRunningVerification = false
    private func runStudioVerification() {
        Task { @MainActor in
            guard !self.isRunningVerification else { return }
            self.isRunningVerification = true
            defer { self.isRunningVerification = false }
            let logURL = URL(fileURLWithPath: "/tmp/studio_verification.log")
            try? "".write(to: logURL, atomically: true, encoding: .utf8)
            let iso = ISO8601DateFormatter()
            func record(_ msg: String) {
                let entry = "[\(iso.string(from: Date()))] \(msg)\n"
                print(entry)
                if let data = entry.data(using: .utf8) {
                    if let handle = try? FileHandle(forWritingTo: logURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    } else {
                        try? data.write(to: logURL)
                    }
                }
            }

            let pid = ProcessInfo.processInfo.processIdentifier
            record("=== MYNOTCH STUDIO EMPIRICAL VERIFICATION (PID: \(pid)) ===")

            // 1. Thao tác Battery Studio
            if let battery = self.registry.module(for: "battery") as? BatteryModule {
                let initial = battery.studioStatus()
                record("1. [BATTERY] Initial: limit=\(initial.chargeLimit)%, bypass=\(initial.isBypassEnabled), watts=\(initial.batteryWatts ?? 0)")

                battery.setChargeLimit(60)
                let step60 = battery.studioStatus()
                record("2. [BATTERY] setChargeLimit(60) -> studioStatus.chargeLimit=\(step60.chargeLimit)%")

                battery.setChargeLimit(80)
                let step80 = battery.studioStatus()
                record("3. [BATTERY] setChargeLimit(80) -> studioStatus.chargeLimit=\(step80.chargeLimit)%")

                battery.toggleBypassMode()
                let stepBypass = battery.studioStatus()
                record("4. [BATTERY] toggleBypassMode() -> studioStatus.isBypassEnabled=\(stepBypass.isBypassEnabled)")
                battery.toggleBypassMode()
                let stepBypassRestore = battery.studioStatus()
                record("5. [BATTERY] restoreBypassMode() -> studioStatus.isBypassEnabled=\(stepBypassRestore.isBypassEnabled)")
            } else {
                record("ERROR: BatteryModule not registered")
            }

            // 2. Thao tác Todo Studio & EventKit
            if let todo = self.registry.module(for: "todo") as? TodoModule {
                record("6. [TODO] Initial: hasRemindersAccess=\(todo.hasRemindersAccess), count=\(todo.studioTasks.count)")
                if !todo.hasRemindersAccess {
                    record("7. [TODO] Dispatching non-blocking requestAccess() prompt...")
                    Task.detached {
                        await todo.requestAccess()
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                    record("8. [TODO] Permission prompt dispatched. Current hasRemindersAccess=\(todo.hasRemindersAccess)")
                }

                if todo.hasRemindersAccess {
                    let testTitle = "Thẩm định nghiệm thu Studio !1 10:00"
                    let addSuccess = await todo.addTask(testTitle)
                    record("9. [TODO] addTask('\(testTitle)') -> success=\(addSuccess)")

                    try? await Task.sleep(for: .milliseconds(400))
                    let tasksAfterAdd = todo.studioTasks
                    record("10. [TODO] studioTasks count after add: \(tasksAfterAdd.count)")
                    if let added = tasksAfterAdd.first(where: { $0.title.contains("Thẩm định") }) {
                        record("11. [TODO] Found task id=\(added.id), quadrant=\(added.quadrant) (Q1 DoFirst), isCompleted=\(added.isCompleted)")

                        await todo.moveTask(added.id, toQuadrant: 2)
                        try? await Task.sleep(for: .milliseconds(300))
                        let moved = todo.studioTasks.first(where: { $0.id == added.id })
                        record("12. [TODO] moveTask(to: Q2) -> quadrant=\(moved?.quadrant ?? -1) (Q2 Schedule)")

                        await todo.completeTask(added.id)
                        try? await Task.sleep(for: .milliseconds(300))
                        let completed = todo.studioTasks.first(where: { $0.id == added.id })
                        record("13. [TODO] completeTask() -> isCompleted=\(completed?.isCompleted ?? false)")

                        await todo.undoTask(added.id)
                        try? await Task.sleep(for: .milliseconds(300))
                        let undone = todo.studioTasks.first(where: { $0.id == added.id })
                        record("14. [TODO] undoTask() -> isCompleted=\(undone?.isCompleted ?? true)")
                    }
                } else {
                    record("9. [TODO] Note: System Reminders permission dialog is presented to user. Reminders access is pending user action.")
                }
            } else {
                record("ERROR: TodoModule not registered")
            }

            // 3. Thao tác Theme Switcher
            let initialTheme = DashboardThemeStore.shared.style
            record("15. [THEME] Initial theme=\(initialTheme.rawValue), cornerRadius=\(DashboardTheme.cardCornerRadius)")

            DashboardThemeStore.shared.setStyle(.liquidGlass)
            record("16. [THEME] setStyle(.liquidGlass) -> style=\(DashboardThemeStore.shared.style.rawValue), cornerRadius=\(DashboardTheme.cardCornerRadius)")

            DashboardThemeStore.shared.setStyle(.stripeLight)
            record("17. [THEME] setStyle(.stripeLight) -> style=\(DashboardThemeStore.shared.style.rawValue), cornerRadius=\(DashboardTheme.cardCornerRadius)")

            DashboardThemeStore.shared.setStyle(.softUI)
            record("18. [THEME] restoreStyle(.softUI) -> style=\(DashboardThemeStore.shared.style.rawValue), cornerRadius=\(DashboardTheme.cardCornerRadius)")

            // 4. Chụp ảnh evidence live
            let tmpDir = URL(fileURLWithPath: "/tmp/mynotch_evidence", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            self.dashboardWindow.exportEvidence(to: tmpDir)
            record("19. [EVIDENCE] Exported live studio evidence to \(tmpDir.path)")

            let projectEvidenceDir = URL(fileURLWithPath: "/Users/ryantruong/Project/MyNotch/docs/evidence", isDirectory: true)
            for file in ["dashboard_productivity_clean_ui.png", "habit_studio_heatmap.png", "dashboard_battery_studio.png", "dashboard_todo_studio.png"] {
                let src = tmpDir.appendingPathComponent(file)
                let dst = projectEvidenceDir.appendingPathComponent(file)
                try? FileManager.default.removeItem(at: dst)
                try? FileManager.default.copyItem(at: src, to: dst)
            }
            record("20. [EVIDENCE] Synced live Retina snapshots to \(projectEvidenceDir.path)")

            record("=== KẾT THÚC KIỂM THỬ THỰC NGHIỆM ===")
            if CommandLine.arguments.contains("--verify-studio") {
                try? await Task.sleep(for: .seconds(1))
                exit(0)
            }
        }
    }
    #endif
}
