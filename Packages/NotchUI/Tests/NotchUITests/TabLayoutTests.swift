import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

private final class TabModule: FeatureModule {
    let descriptor: ModuleDescriptor
    let height: CGFloat?
    init(_ id: ModuleID, height: CGFloat?) {
        descriptor = ModuleDescriptor(id: id, displayName: id.rawValue, systemImage: "circle", defaultEnabled: true, order: 0)
        self.height = height
    }
    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}
    func makeTab() -> NotchTab? {
        NotchTab(id: descriptor.id, title: "T", systemImage: "circle", preferredHeight: height, content: AnyView(EmptyView()))
    }
    func makeSettingsView() -> AnyView? { nil }
}

@Suite struct TabLayoutTests {
    @Test func contentHeightFollowsTheOpenTab() async {
        let harness = RegistryHarness([TabModule("tall", height: 280)])
        await harness.registry.bootstrap()
        #expect(harness.registry.contentHeight(for: .open("tall")) == 280)
        #expect(harness.registry.contentHeight(for: .open("missing")) == NotchTab.defaultHeight)
        #expect(harness.registry.contentHeight(for: .closed) == NotchTab.defaultHeight)
    }

    @Test func shapeStaysInsideItsRectForShortRects() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 10)
        let bounds = NotchShape(topRadius: 8, bottomRadius: 24).path(in: rect).boundingRect
        #expect(rect.insetBy(dx: -0.001, dy: -0.001).contains(bounds))
    }
}
