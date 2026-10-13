import Foundation
import SwiftUI
@testable import MyNotchCore
import MyNotchTestSupport

final class FakeModule: FeatureModule {
    let descriptor: ModuleDescriptor
    var startError: ModuleError?
    var activityOnStart: LiveActivity?
    /// Scheduled one second after `start` through the context's scheduler.
    var actionOnStart: (@MainActor () -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var context: ModuleContext?

    init(_ id: ModuleID, order: Int = 0, defaultEnabled: Bool = true, permissions: [Permission] = []) {
        descriptor = ModuleDescriptor(
            id: id, displayName: id.rawValue, systemImage: "circle",
            defaultEnabled: defaultEnabled, permissions: permissions, order: order
        )
    }

    func start(_ context: ModuleContext) async throws(ModuleError) {
        startCount += 1
        self.context = context
        if let activityOnStart { context.activities.set(activityOnStart) }
        if let actionOnStart { context.scheduler.schedule(after: .seconds(1), actionOnStart) }
        if let startError { throw startError }
    }

    func stop() async { stopCount += 1 }

    func makeTab() -> NotchTab? {
        NotchTab(id: descriptor.id, title: descriptor.displayName, systemImage: "circle", content: AnyView(EmptyView()))
    }

    func makeSettingsView() -> AnyView? { nil }
}

typealias Harness = RegistryHarness
