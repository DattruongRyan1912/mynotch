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
}
