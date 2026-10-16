import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

private final class ControllerModule: FeatureModule {
    let descriptor: ModuleDescriptor
    init(_ id: ModuleID, order: Int) {
        descriptor = ModuleDescriptor(id: id, displayName: id.rawValue, systemImage: "circle", defaultEnabled: true, order: order)
    }
    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}
    func makeTab() -> NotchTab? {
        NotchTab(id: descriptor.id, title: descriptor.displayName, systemImage: "circle", content: AnyView(EmptyView()))
    }
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
}

/// What the window controller does when the style of the virtual notch changes while the notch is open: it takes the new geometry
/// (and with it the new panel size) and keeps the model, and the notch stays open. The panel is never shown and no event is posted.
@Suite struct NotchPillControllerTests {
    let harness = RegistryHarness([ControllerModule("a", order: 1), ControllerModule("b", order: 2)])

    func makeController(on screen: ScreenDescriptor, _ style: VirtualNotchStyle) async -> NotchWindowController {
        await harness.registry.bootstrap()
        return NotchWindowController(
            displayID: 1, screen: screen, config: NotchLayoutConfig(virtualNotchStyle: style), scheduler: harness.scheduler,
            registry: harness.registry, activities: harness.activities,
            delays: { (.milliseconds(150), .milliseconds(300)) },
            captureHiding: { .never }, swipesBetweenTabs: { true }
        )
    }

    @Test func aStyleChangeWhileOpenGivesTheControllerTheNewGeometryAndKeepsTheNotchOpen() async {
        let screen = NotchGeometryTests.external
        let controller = await makeController(on: screen, .notch)
        defer { controller.close() }
        controller.model.open(tab: "a")
        #expect(controller.model.displayState == .open("a"))
        #expect(!controller.geometry.isPill)
        #expect(controller.display.geometry.panelSize.height == CGFloat(25 + 240))

        controller.update(displayID: 1, screen: screen, config: NotchLayoutConfig(virtualNotchStyle: .pill))
        #expect(controller.geometry.isPill)
        #expect(controller.display.geometry == NotchGeometry(screen: screen, config: NotchLayoutConfig(virtualNotchStyle: .pill)))
        #expect(controller.display.geometry.panelSize.height == 32 + NotchGeometry.pillTopGap + CGFloat(240), "the panel holds the gap too")
        #expect(controller.model.displayState == .open("a"), "nothing closed it")

        controller.update(displayID: 1, screen: screen, config: NotchLayoutConfig(virtualNotchStyle: .notch))
        #expect(controller.geometry == NotchGeometry(screen: screen, config: NotchLayoutConfig()))
        #expect(controller.model.displayState == .open("a"))
    }

    @Test func everyStateSurvivesAStyleChangeBothWays() async {
        let screen = NotchGeometryTests.external
        let controller = await makeController(on: screen, .notch)
        defer { controller.close() }
        for style in [VirtualNotchStyle.pill, .notch, .pill] {
            controller.model.open(tab: "b")
            controller.update(displayID: 1, screen: screen, config: NotchLayoutConfig(virtualNotchStyle: style))
            controller.model.showToast(AnyView(Color.clear), duration: .seconds(60))
            controller.update(displayID: 1, screen: screen, config: NotchLayoutConfig(virtualNotchStyle: style == .pill ? .notch : .pill))
            controller.model.close()
            controller.update(displayID: 1, screen: screen, config: NotchLayoutConfig(virtualNotchStyle: style))
            #expect(controller.geometry.isPill == (style == .pill))
        }
    }

    @Test func aHardwareNotchTakesTheNewConfigAndStaysTheNotchItWas() async {
        let screen = NotchGeometryTests.macBook14
        let controller = await makeController(on: screen, .notch)
        defer { controller.close() }
        let before = controller.geometry
        controller.update(displayID: 1, screen: screen, config: NotchLayoutConfig(virtualNotchStyle: .pill))
        #expect(!controller.geometry.isPill)
        #expect(controller.geometry.panelSize == before.panelSize)
        #expect(controller.geometry.shape(for: .open(nil)) == before.shape(for: .open(nil)))
        #expect(controller.geometry.topGap == 0)
    }

    @Test func changingToTilesWhileOpenGivesTheControllerTheTallerNotchAndPanelAndKeepsItOpen() async {
        let screen = NotchGeometryTests.macBook14
        let controller = await makeController(on: screen, .notch)
        defer { controller.close() }
        controller.model.open(tab: "a")
        let before = controller.display.geometry
        #expect(!before.opensAsTiles)
        controller.update(displayID: 1, screen: screen, config: NotchLayoutConfig(opensAsTiles: true))
        let tiled = controller.display.geometry
        #expect(tiled.opensAsTiles)
        #expect(tiled.panelSize.height - before.panelSize.height == NotchTilesLayout.extraHeight(tabCount: 2), "the panel holds the taller notch")
        #expect(
            tiled.shapeSize(for: .open("a"), contentHeight: 190, tabCount: 2).height - before.shapeSize(for: .open("a"), contentHeight: 190, tabCount: 2).height
                == NotchTilesLayout.extraHeight(tabCount: 2)
        )
        #expect(controller.model.displayState == .open("a"), "nothing closed it")
        controller.update(displayID: 1, screen: screen, config: NotchLayoutConfig())
        #expect(controller.display.geometry == before)
    }
}
