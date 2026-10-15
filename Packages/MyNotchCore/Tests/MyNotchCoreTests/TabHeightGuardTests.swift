import SwiftUI
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// A module whose tab asks for a given height.
private final class AskingModule: FeatureModule {
    let descriptor = ModuleDescriptor(id: "asking", displayName: "Asking", systemImage: "circle", defaultEnabled: true, order: 0)
    let height: CGFloat

    init(height: CGFloat) { self.height = height }

    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}

    func makeTab() -> NotchTab? {
        NotchTab(id: descriptor.id, title: "Asking", systemImage: "circle", preferredHeight: height, content: AnyView(EmptyView()))
    }

    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
}

/// The user's max height for the open notch can be as low as `NotchTab.heightRange.upperBound`, and a tab that asks for
/// more is cut there. The registry, which every running module's tab passes through, stops a debug build that meets one,
/// so a module's own tests (they all start their module in a registry) fail the day a tab grows too tall.
@Suite struct TabHeightGuardTests {
    @Test func aTabThatAsksForTheMostItMayRunsNormally() async {
        let harness = Harness([AskingModule(height: NotchTab.heightRange.upperBound)])
        await harness.registry.bootstrap()
        #expect(harness.registry.tabs.map(\.id) == ["asking"])
    }

    @Test func aTabThatAsksForMoreStopsADebugBuild() async {
        await #expect(processExitsWith: .failure) {
            await Task { @MainActor in
                let harness = Harness([AskingModule(height: NotchTab.heightRange.upperBound + 1)])
                await harness.registry.bootstrap()
            }.value
        }
    }
}
