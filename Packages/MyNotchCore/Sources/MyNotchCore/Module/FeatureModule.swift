import SwiftUI

/// Contract every feature module implements. Modules depend only on MyNotchCore and NotchUI.
public protocol FeatureModule: AnyObject {
    var descriptor: ModuleDescriptor { get }
    func start(_ context: ModuleContext) async throws(ModuleError)
    func stop() async
    func makeTab() -> NotchTab?
    func makeSettingsView() -> AnyView?
}
