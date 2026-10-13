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
    public init() {}
    public func open(tab: ModuleID) { openedTabs.append(tab) }
    public func showToast(_ content: AnyView, duration: Duration) { toastCount += 1 }
    public func close() {}
}

/// Wires a `ModuleRegistry` with in-memory collaborators.
public struct RegistryHarness {
    public let settings = SettingsStore(defaults: makeIsolatedDefaults())
    public let scheduler = ManualScheduler()
    public let permissions = FakePermissionCenter()
    public let presenter = FakePresenter()
    public let hotkeys = HotkeyRegistry()
    /// Unique per harness under the temporary directory; nothing exists on disk until a module calls `ensureDirectories()`.
    public let storageRoot: StorageRoot = {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "MyNotchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return StorageRoot(applicationSupport: base.appending(path: "ApplicationSupport"), caches: base.appending(path: "Caches"))
    }()
    public let activities: ActivityCenter
    public let registry: ModuleRegistry

    public init(_ modules: [any FeatureModule]) {
        activities = ActivityCenter(scheduler: scheduler)
        registry = ModuleRegistry(
            modules: modules, settings: settings, activities: activities,
            permissions: permissions, hotkeys: hotkeys, presenter: presenter,
            scheduler: scheduler, storageRoot: storageRoot
        )
    }
}

extension RegistryHarness {
    /// The environment the module's Settings rows get right now, so tests can change settings as the page would.
    public func settingsEnvironment(for id: ModuleID) -> ModuleSettingsEnvironment? {
        registry.settingsEnvironment(for: id)
    }
}
