import Observation
import SwiftUI

/// Owns module lifecycles. A failing module never affects the others.
@Observable
public final class ModuleRegistry {
    public let modules: [any FeatureModule]
    public private(set) var states: [ModuleID: ModuleState] = [:]
    public private(set) var isPaused = false
    /// The tabs of the modules that run, in module order; `tabs` is the same list in the user's order.
    private var runningTabs: [NotchTab] = []

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let activities: ActivityCenter
    @ObservationIgnored private let lockScreen: LockScreenContentCenter
    @ObservationIgnored private let permissions: any PermissionCenter
    @ObservationIgnored private let hotkeys: HotkeyRegistry
    @ObservationIgnored private let presenter: any NotchPresenter
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let storageRoot: StorageRoot
    @ObservationIgnored private let services: ServiceRegistry
    /// One per module for the registry's lifetime, shared by its context and its Settings rows.
    @ObservationIgnored private let moduleSettings: [ModuleID: ModuleSettings]
    @ObservationIgnored private var contexts: [ModuleID: ModuleContext] = [:]
    @ObservationIgnored private var tabCache: [ModuleID: NotchTab] = [:]
    /// Last queued lifecycle change per module; the next one waits for it, so start and stop never overlap.
    @ObservationIgnored private var transitions: [ModuleID: Task<Void, Never>] = [:]
    /// Set once by `shutdown()`; from then on nothing starts, whatever the settings say.
    @ObservationIgnored private var isShuttingDown = false

    public init(
        modules: [any FeatureModule],
        settings: SettingsStore,
        activities: ActivityCenter,
        lockScreen: LockScreenContentCenter,
        permissions: any PermissionCenter,
        hotkeys: HotkeyRegistry,
        presenter: any NotchPresenter,
        scheduler: any Scheduler,
        storageRoot: StorageRoot,
        services: ServiceRegistry
    ) {
        let sorted = modules.sorted { $0.descriptor.order < $1.descriptor.order }
        precondition(Set(sorted.map(\.descriptor.id)).count == sorted.count, "Duplicate ModuleID")
        self.modules = sorted
        self.settings = settings
        self.activities = activities
        self.lockScreen = lockScreen
        self.permissions = permissions
        self.hotkeys = hotkeys
        self.presenter = presenter
        self.scheduler = scheduler
        self.storageRoot = storageRoot
        self.services = services
        moduleSettings = Dictionary(uniqueKeysWithValues: sorted.map {
            ($0.descriptor.id, ModuleSettings(store: settings, module: $0.descriptor.id))
        })
        for module in sorted { states[module.descriptor.id] = .disabled }
    }

    /// The order the user gave the tabs of the open notch, as module ids; empty means module order. Ids of modules that
    /// do not run stay in it, so they find their place again.
    public static let tabOrderKey = SettingKey<[ModuleID]>("app.tabOrder", default: [])

    /// The tabs of the modules that run, in the user's order (`tabOrderKey`). Reads the setting, so views that read
    /// it follow a change of the order.
    public var tabs: [NotchTab] {
        let order = TabOrder.merged(stored: settings.value(Self.tabOrderKey), available: runningTabs.map(\.id))
        return order.compactMap { id in runningTabs.first { $0.id == id } }
    }

    public static func enabledKey(for descriptor: ModuleDescriptor) -> SettingKey<Bool> {
        SettingKey("module.\(descriptor.id.rawValue).enabled", default: descriptor.defaultEnabled)
    }

    public func isEnabled(_ id: ModuleID) -> Bool {
        guard let module = module(id) else { return false }
        return settings.value(Self.enabledKey(for: module.descriptor))
    }

    public func state(of id: ModuleID) -> ModuleState { states[id] ?? .disabled }

    /// Starts every enabled module. Call once at launch.
    public func bootstrap() async {
        await reconcile(modules)
    }

    public func setEnabled(_ enabled: Bool, for id: ModuleID) async {
        guard let module = module(id) else { return }
        settings.set(enabled, for: Self.enabledKey(for: module.descriptor))
        await reconcile([module])
    }

    /// Stops then starts a module again, e.g. after a failure.
    public func retry(_ id: ModuleID) async {
        guard let module = module(id), wantsRunning(module) else { return }
        await serialized(module) {
            await self.stop(module)
            if self.wantsRunning(module) { await self.start(module) }
        }
    }

    /// Restarts enabled modules that were waiting for a permission that is now granted.
    public func refreshPermissions() async {
        guard !isPaused else { return }
        await reconcile(modules.filter(waitsForPermission))
    }

    /// TCC sends no notification when a permission changes, so the app polls `refreshPermissions()` while this is true.
    public var needsPermissionPolling: Bool { modules.contains(where: waitsForPermission) }

    /// What the permission center reports now; never prompts.
    public func permissionStatus(of permission: Permission) -> PermissionStatus { permissions.status(of: permission) }

    /// Prompts while the system still can; after an answer only System Settings can change it (`Permission.grantAction`).
    /// Settings-only permissions always request first, which also lists the app in System Settings.
    public func grant(_ permission: Permission) async {
        let before = permissions.status(of: permission)
        switch permission.grantAction(for: before) {
        case .request:
            let after = await permissions.request(permission)
            if before != .notDetermined && after != .granted {
                permissions.openSystemSettings(for: permission)
            }
        case .openSettings:
            permissions.openSystemSettings(for: permission)
        }
        await refreshPermissions()
    }

    public func pauseAll() async {
        isPaused = true
        await reconcile(modules)
    }

    public func resumeAll() async {
        isPaused = false
        await bootstrap()
    }

    /// Stops every module so it can save its data before the app quits. Enabled settings stay as they are,
    /// so the next launch starts the same modules.
    public func shutdown() async {
        isShuttingDown = true
        await reconcile(modules)
    }

    /// What the status-bar menu adds for the modules that run, in module order.
    public var menuItems: [ModuleMenuItem] {
        modules.filter { state(of: $0.descriptor.id) == .running }.flatMap(\.menuItems)
    }

    /// Built whether or not the module runs, so it can be configured while disabled.
    public func settingsView(for id: ModuleID) -> AnyView? {
        guard let module = module(id), let environment = settingsEnvironment(for: id) else { return nil }
        return module.makeSettingsView(environment)
    }

    /// What `settingsView(for:)` passes to the module; `package` so test support can drive settings like the page does.
    package func settingsEnvironment(for id: ModuleID) -> ModuleSettingsEnvironment? {
        guard let settings = moduleSettings[id] else { return nil }
        return ModuleSettingsEnvironment(
            settings: settings,
            storage: storageRoot.storage(for: id),
            permissions: permissions,
            isRunning: state(of: id) == .running
        )
    }

    private func module(_ id: ModuleID) -> (any FeatureModule)? {
        modules.first { $0.descriptor.id == id }
    }

    private func waitsForPermission(_ module: any FeatureModule) -> Bool {
        if case .needsPermission = state(of: module.descriptor.id) { true } else { false }
    }

    private func wantsRunning(_ module: any FeatureModule) -> Bool {
        isEnabled(module.descriptor.id) && !isPaused && !isShuttingDown
    }

    /// Moves each module toward its wanted state. Modules proceed concurrently, so a slow one never holds up the others;
    /// the wanted state is read when the change actually runs, so late toggles win.
    private func reconcile(_ targets: [any FeatureModule]) async {
        let tasks = targets.map { module in
            Task {
                await self.serialized(module) {
                    self.wantsRunning(module) ? await self.start(module) : await self.stop(module)
                }
            }
        }
        for task in tasks { await task.value }
    }

    private func serialized(_ module: any FeatureModule, _ operation: @escaping @MainActor () async -> Void) async {
        let id = module.descriptor.id
        let previous = transitions[id]
        let task = Task {
            await previous?.value
            await operation()
        }
        transitions[id] = task
        await task.value
    }

    /// Only called from `serialized`, so no other start/stop of this module is in flight.
    private func start(_ module: any FeatureModule) async {
        let descriptor = module.descriptor
        let id = descriptor.id
        guard state(of: id) != .running else { return }
        if let missing = descriptor.permissions.first(where: { permissions.status(of: $0).isMissing }) {
            states[id] = .needsPermission(missing)
            return
        }
        states[id] = .starting
        let context = ModuleContext(
            id: id,
            settings: moduleSettings[id]!,
            activities: ActivityPublisher(center: activities, module: id),
            lockScreen: LockScreenPublisher(center: lockScreen, module: id),
            presenter: ModulePresenter(presenter: presenter, module: id),
            hotkeys: ModuleHotkeys(registry: hotkeys, module: id),
            services: ModuleServices(registry: services, module: id),
            permissions: permissions,
            storage: storageRoot.storage(for: id),
            scheduler: scheduler
        )
        contexts[id] = context
        do {
            try await module.start(context)
            states[id] = .running
            tabCache[id] = module.makeTab().map(Self.checked)
        } catch {
            tearDown(id)
            states[id] = ModuleState(error)
            if case .failed = error {
                context.logger.error("Module failed to start: \(String(describing: error), privacy: .public)")
            } else {
                context.logger.notice("Module failed to start: \(String(describing: error), privacy: .public)")
            }
        }
        rebuildTabs()
    }

    private func stop(_ module: any FeatureModule) async {
        let id = module.descriptor.id
        guard state(of: id) != .disabled else { return }
        if state(of: id) == .running {
            states[id] = .stopping
            await module.stop()
        }
        tearDown(id)
        states[id] = .disabled
        rebuildTabs()
    }

    private func tearDown(_ id: ModuleID) {
        contexts.removeValue(forKey: id)?.cancelAll()
        activities.clearAll(from: id)
        hotkeys.unregisterAll(owner: id)
        services.unregisterAll(owner: id)
        tabCache[id] = nil
    }

    /// Every running module's tab passes here, so a tab that outgrows `NotchTab.heightRange` stops a debug build (and the
    /// module's own tests, which start it) instead of being cut on a user's screen.
    private static func checked(_ tab: NotchTab) -> NotchTab {
        assert(!tab.asksTooMuch, "Tab \(tab.id.rawValue) asks for \(tab.preferredHeight ?? 0) pt; a tab may ask for at most \(NotchTab.heightRange.upperBound) pt")
        return tab
    }

    private func rebuildTabs() {
        runningTabs = modules.compactMap { tabCache[$0.descriptor.id] }
    }
}
