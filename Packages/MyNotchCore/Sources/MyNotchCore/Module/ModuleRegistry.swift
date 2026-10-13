import Observation
import SwiftUI

/// Owns module lifecycles. A failing module never affects the others.
@Observable
public final class ModuleRegistry {
    public let modules: [any FeatureModule]
    public private(set) var states: [ModuleID: ModuleState] = [:]
    public private(set) var tabs: [NotchTab] = []
    public private(set) var isPaused = false

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let activities: ActivityCenter
    @ObservationIgnored private let permissions: any PermissionCenter
    @ObservationIgnored private let hotkeys: HotkeyRegistry
    @ObservationIgnored private let presenter: any NotchPresenter
    @ObservationIgnored private var contexts: [ModuleID: ModuleContext] = [:]
    @ObservationIgnored private var tabCache: [ModuleID: NotchTab] = [:]

    public init(
        modules: [any FeatureModule],
        settings: SettingsStore,
        activities: ActivityCenter,
        permissions: any PermissionCenter,
        hotkeys: HotkeyRegistry,
        presenter: any NotchPresenter
    ) {
        let sorted = modules.sorted { $0.descriptor.order < $1.descriptor.order }
        precondition(Set(sorted.map(\.descriptor.id)).count == sorted.count, "Duplicate ModuleID")
        self.modules = sorted
        self.settings = settings
        self.activities = activities
        self.permissions = permissions
        self.hotkeys = hotkeys
        self.presenter = presenter
        for module in sorted { states[module.descriptor.id] = .disabled }
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
        for module in modules where isEnabled(module.descriptor.id) {
            await start(module)
        }
    }

    public func setEnabled(_ enabled: Bool, for id: ModuleID) async {
        guard let module = module(id) else { return }
        settings.set(enabled, for: Self.enabledKey(for: module.descriptor))
        if enabled, !isPaused {
            await start(module)
        } else if !enabled {
            await stop(module)
        }
    }

    /// Stops then starts a module again, e.g. after a failure.
    public func retry(_ id: ModuleID) async {
        guard let module = module(id), isEnabled(id), !isPaused else { return }
        await stop(module)
        await start(module)
    }

    /// Restarts enabled modules that were waiting for a permission that is now granted.
    public func refreshPermissions() async {
        guard !isPaused else { return }
        for module in modules {
            guard case .needsPermission = state(of: module.descriptor.id), isEnabled(module.descriptor.id) else { continue }
            await start(module)
        }
    }

    public func pauseAll() async {
        isPaused = true
        for module in modules { await stop(module) }
    }

    public func resumeAll() async {
        isPaused = false
        await bootstrap()
    }

    public func settingsView(for id: ModuleID) -> AnyView? {
        module(id)?.makeSettingsView()
    }

    private func module(_ id: ModuleID) -> (any FeatureModule)? {
        modules.first { $0.descriptor.id == id }
    }

    private func start(_ module: any FeatureModule) async {
        let descriptor = module.descriptor
        let id = descriptor.id
        guard state(of: id) != .running, state(of: id) != .starting else { return }
        if let missing = descriptor.permissions.first(where: { permissions.status(of: $0) != .granted }) {
            states[id] = .needsPermission(missing)
            return
        }
        states[id] = .starting
        let context = ModuleContext(
            id: id,
            settings: ModuleSettings(store: settings, module: id),
            activities: ActivityPublisher(center: activities, module: id),
            presenter: presenter,
            hotkeys: ModuleHotkeys(registry: hotkeys, module: id),
            permissions: permissions
        )
        contexts[id] = context
        do {
            try await module.start(context)
            states[id] = .running
            tabCache[id] = module.makeTab()
        } catch {
            tearDown(id)
            states[id] = ModuleState(error)
            context.logger.error("Module failed to start: \(String(describing: error), privacy: .public)")
        }
        rebuildTabs()
    }

    private func stop(_ module: any FeatureModule) async {
        let id = module.descriptor.id
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
        tabCache[id] = nil
    }

    private func rebuildTabs() {
        tabs = modules.compactMap { tabCache[$0.descriptor.id] }
    }
}
