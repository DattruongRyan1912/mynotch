import SwiftUI

/// Contract every feature module implements. Modules depend only on MyNotchCore and NotchUI.
public protocol FeatureModule: AnyObject {
    var descriptor: ModuleDescriptor { get }
    /// If `start` throws, it must release anything it created itself; the registry only cleans up what is owned by the context and does not call `stop()` after a failed start.
    func start(_ context: ModuleContext) async throws(ModuleError)
    /// Called only after a successful `start`; start and stop of one module never overlap.
    func stop() async
    func makeTab() -> NotchTab?
    /// Rows for the module's section in Settings — no Form; the page provides it. nil when there is nothing to configure.
    /// Called whether or not the module runs, so the rows use `environment`, never state from `start`.
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView?
    /// Entries for the status-bar menu, for what the user opens by hand (a window) rather than from the notch.
    /// Only a running module's are shown, and the menu asks each time it opens.
    var menuItems: [ModuleMenuItem] { get }
}

extension FeatureModule {
    public var menuItems: [ModuleMenuItem] { [] }
}

/// One entry a module adds to the status-bar menu. The app draws it; the module decides what it does.
public struct ModuleMenuItem: Identifiable {
    public let id: String
    public let title: String
    public let action: @MainActor () -> Void

    public init(id: String, title: String, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.action = action
    }
}
