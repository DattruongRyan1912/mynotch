import Foundation
import MyNotchCore
import SwiftUI

/// Permission center whose answers tests set directly. Unknown permissions are denied.
public final class FakePermissionCenter: PermissionCenter {
    public var statuses: [Permission: PermissionStatus] = [:]
    /// The user's answer to every `request` prompt.
    public var requestResult: PermissionStatus = .granted
    public private(set) var requested: [Permission] = []
    public private(set) var openedSettings: [Permission] = []
    public init() {}
    public func status(of permission: Permission) -> PermissionStatus { statuses[permission] ?? .denied }

    public func request(_ permission: Permission) async -> PermissionStatus {
        requested.append(permission)
        statuses[permission] = requestResult
        return requestResult
    }

    public func openSystemSettings(for permission: Permission) { openedSettings.append(permission) }
}

/// Presenter that records requests.
public final class FakePresenter: NotchPresenter {
    public private(set) var openedTabs: [ModuleID] = []
    public private(set) var toastCount = 0
    public private(set) var closeCount = 0
    public init() {}
    public func open(tab: ModuleID) { openedTabs.append(tab) }
    public func showToast(_ content: AnyView, duration: Duration) { toastCount += 1 }
    public func close() { closeCount += 1 }
}

/// In-memory shortcuts: nothing reaches the system's hotkeys or the user's defaults. Tests press a shortcut with
/// `trigger` and play the user changing it in Settings with `setShortcut`.
public final class FakeHotkeyBackend: HotkeyBackend {
    /// By raw name. A stored nil is a shortcut the user cleared, which registering again must not bring back.
    private var shortcuts: [String: KeyboardShortcuts.Shortcut?] = [:]
    private var handlers: [String: [@MainActor () -> Void]] = [:]

    public init() {}

    public func makeName(_ rawValue: String, initial: KeyboardShortcuts.Shortcut?) -> KeyboardShortcuts.Name {
        if let initial, shortcuts.index(forKey: rawValue) == nil {
            shortcuts.updateValue(initial, forKey: rawValue)
        }
        // `init(rawValue:)` is the one initializer that writes nothing to the user's defaults.
        return KeyboardShortcuts.Name(rawValue: rawValue)!
    }

    public func onKeyUp(for name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void) {
        handlers[name.rawValue, default: []].append(action)
    }

    public func removeHandler(for name: KeyboardShortcuts.Name) {
        handlers[name.rawValue] = nil
    }

    public func getShortcut(for name: KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? {
        shortcuts[name.rawValue] ?? nil
    }

    public func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?, for name: KeyboardShortcuts.Name) {
        shortcuts.updateValue(shortcut, forKey: name.rawValue)
    }

    /// Presses the shortcut registered as `rawValue` (e.g. "clipboard_openClipboard"), whether or not it has a key
    /// combination. Returns false when nothing is registered under it.
    @discardableResult
    public func trigger(_ rawValue: String) -> Bool {
        guard let actions = handlers[rawValue], !actions.isEmpty else { return false }
        actions.forEach { $0() }
        return true
    }
}

/// Wires a `ModuleRegistry` with in-memory collaborators.
public struct RegistryHarness {
    public let settings = SettingsStore(defaults: makeIsolatedDefaults())
    public let scheduler = ManualScheduler()
    public let permissions = FakePermissionCenter()
    public let presenter = FakePresenter()
    /// Where `hotkeys` keeps its shortcuts; `hotkeyBackend.trigger("clipboard_openClipboard")` presses one.
    public let hotkeyBackend = FakeHotkeyBackend()
    public let hotkeys: HotkeyRegistry
    public let services: ServiceRegistry
    /// Unique per harness under the temporary directory and removed when the test process exits; nothing exists on
    /// disk until a module calls `ensureDirectories()`.
    public let storageRoot: StorageRoot = {
        let base = ScratchFolders.shared.reserve()
        return StorageRoot(applicationSupport: base.appending(path: "ApplicationSupport"), caches: base.appending(path: "Caches"))
    }()
    public let activities: ActivityCenter
    public let lockScreen = LockScreenContentCenter()
    public let registry: ModuleRegistry

    public init(_ modules: [any FeatureModule]) {
        hotkeys = HotkeyRegistry(backend: hotkeyBackend)
        services = ServiceRegistry(scheduler: scheduler)
        activities = ActivityCenter(scheduler: scheduler)
        registry = ModuleRegistry(
            modules: modules, settings: settings, activities: activities, lockScreen: lockScreen,
            permissions: permissions, hotkeys: hotkeys, presenter: presenter,
            scheduler: scheduler, storageRoot: storageRoot, services: services
        )
    }
}

extension RegistryHarness {
    /// The environment the module's Settings rows get right now, so tests can change settings as the page would.
    public func settingsEnvironment(for id: ModuleID) -> ModuleSettingsEnvironment? {
        registry.settingsEnvironment(for: id)
    }
}
