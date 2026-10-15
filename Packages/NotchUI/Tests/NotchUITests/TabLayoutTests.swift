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
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
}

@Suite struct TabLayoutTests {
    @Test func contentHeightFollowsTheOpenTab() async {
        let harness = RegistryHarness([TabModule("tall", height: 280)])
        await harness.registry.bootstrap()
        #expect(harness.registry.contentHeight(for: .open("tall"), tabUnderToast: nil) == 280)
        #expect(harness.registry.contentHeight(for: .open("missing"), tabUnderToast: nil) == NotchTab.defaultHeight)
        #expect(harness.registry.contentHeight(for: .closed, tabUnderToast: nil) == NotchTab.defaultHeight)
    }

    @Test func aTabThatAsksForMoreThanTheDefaultCapIsReportedAsAskedSoTheMaxHeightSettingDecides() async {
        let harness = RegistryHarness([TabModule("huge", height: 380)])
        await harness.registry.bootstrap()
        #expect(harness.registry.contentHeight(for: .open("huge"), tabUnderToast: nil) == 380)
        let tall = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig(maxContentHeight: 400))
        let capped = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
        let asked = harness.registry.contentHeight(for: .open("huge"), tabUnderToast: nil)
        let notch: CGFloat = 32
        #expect(tall.shapeSize(for: .open("huge"), contentHeight: asked).height == notch + 380)
        #expect(capped.shapeSize(for: .open("huge"), contentHeight: asked).height == notch + 300)
    }

    @Test func aToastKeepsTheHeightOfTheTabItCovers() async {
        let harness = RegistryHarness([TabModule("tall", height: 280)])
        await harness.registry.bootstrap()
        #expect(harness.registry.contentHeight(for: .toast, tabUnderToast: "tall") == 280)
        #expect(harness.registry.contentHeight(for: .toast, tabUnderToast: nil) == NotchTab.defaultHeight)
    }

    @Test func shapeStaysInsideItsRectForShortRects() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 10)
        let bounds = NotchShape(topRadius: 8, bottomRadius: 24).path(in: rect).boundingRect
        #expect(rect.insetBy(dx: -0.001, dy: -0.001).contains(bounds))
    }
}
