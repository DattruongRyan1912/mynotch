import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

private final class SwipeModule: FeatureModule {
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

/// The window controller turns scroll events nobody used into tab changes, in the order of the tab bar. The panel is
/// never shown and no event is posted: the controller is called directly with a trackpad's phases and deltas.
@Suite struct NotchSwipeTests {
    let harness = RegistryHarness([SwipeModule("a", order: 1), SwipeModule("b", order: 2), SwipeModule("c", order: 3)])
    let settings = SettingsStore(defaults: makeIsolatedDefaults())

    func makeController(systemAllows: @escaping () -> Bool = { true }) async -> NotchWindowController {
        await harness.registry.bootstrap()
        harness.putEveryTabOnTheBar()
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
            auxiliaryTopLeftWidth: 663.5, auxiliaryTopRightWidth: 663.5, menuBarHeight: 32
        )
        return NotchWindowController(
            displayID: 1, screen: screen, config: NotchLayoutConfig(), scheduler: harness.scheduler,
            registry: harness.registry, activities: harness.activities,
            delays: { (.milliseconds(150), .milliseconds(300)) },
            captureHiding: { .never },
            swipesBetweenTabs: { [settings] in settings.value(InterfaceSettings.swipeBetweenTabs) },
            systemAllowsSwipe: systemAllows
        )
    }

    /// One trackpad gesture of `distance` points sideways (negative: fingers move left), with momentum after it.
    func swipe(_ controller: NotchWindowController, _ distance: CGFloat, drift: CGFloat = 0) {
        controller.handleScroll(phase: .began, momentumPhase: [], deltaX: 0, deltaY: 0)
        for _ in 0..<5 { controller.handleScroll(phase: .changed, momentumPhase: [], deltaX: distance / 5, deltaY: drift / 5) }
        controller.handleScroll(phase: .ended, momentumPhase: [], deltaX: 0, deltaY: 0)
        controller.handleScroll(phase: [], momentumPhase: .began, deltaX: distance, deltaY: 0)
        for _ in 0..<5 { controller.handleScroll(phase: [], momentumPhase: .changed, deltaX: distance, deltaY: 0) }
        controller.handleScroll(phase: [], momentumPhase: .ended, deltaX: 0, deltaY: 0)
    }

    @Test func aSwipeMovesTheOpenNotchOneTabAndMomentumDoesNotMoveItFurther() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.open(tab: "a")
        swipe(controller, -200)
        #expect(controller.model.state == .open("b"))
        swipe(controller, 200)
        #expect(controller.model.state == .open("a"))
    }

    @Test func theTabBarOrderDecidesWhatNextIs() async {
        harness.settings.set(["c", "a", "b"], for: ModuleRegistry.tabOrderKey)
        let controller = await makeController()
        defer { controller.close() }
        controller.model.open(tab: "c")
        swipe(controller, -200)
        #expect(controller.model.state == .open("a"))
        swipe(controller, -200)
        #expect(controller.model.state == .open("b"))
    }

    @Test func theEndsOfTheTabBarStop() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.open(tab: "a")
        swipe(controller, 200)
        #expect(controller.model.state == .open("a"))
        controller.model.open(tab: "c")
        swipe(controller, -200)
        #expect(controller.model.state == .open("c"))
    }

    @Test func aVerticalOrDiagonalScrollDoesNothing() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.open(tab: "b")
        swipe(controller, 0, drift: 300)
        swipe(controller, -100, drift: 100)
        #expect(controller.model.state == .open("b"))
    }

    @Test func nothingMovesWhileTheNotchIsNotOpen() async {
        let controller = await makeController()
        defer { controller.close() }
        swipe(controller, -200)
        #expect(controller.model.state == .closed)
        controller.model.showToast(AnyView(EmptyView()), duration: .seconds(5))
        swipe(controller, -200)
        #expect(controller.model.state == .toast)
    }

    @Test func theSettingTurnsItOffAndOnAgain() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.open(tab: "a")
        settings.set(false, for: InterfaceSettings.swipeBetweenTabs)
        swipe(controller, -200)
        #expect(controller.model.state == .open("a"))
        settings.set(true, for: InterfaceSettings.swipeBetweenTabs)
        swipe(controller, -200)
        #expect(controller.model.state == .open("b"))
    }

    @Test func theSystemSettingForSwipingBetweenPagesIsRespected() async {
        let controller = await makeController(systemAllows: { false })
        defer { controller.close() }
        controller.model.open(tab: "a")
        swipe(controller, -200)
        #expect(controller.model.state == .open("a"))
    }

    #if DEBUG
    @Test func aSwipeIsLoggedWithTheTabsItMovesBetween() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.open(tab: "a")
        let lines = captureNotchLog { swipe(controller, -200) }
        #expect(lines.contains { $0.contains("swipe next open(a) -> b") })
    }
    #endif

    @Test func scrollEventsThatNoViewUsedReachTheController() throws {
        let hosting = FirstMouseHostingView(rootView: Color.clear)
        var received: [NSEvent] = []
        hosting.onUnusedScroll = { received.append($0) }
        let cgEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: -30, wheel3: 0))
        let event = try #require(NSEvent(cgEvent: cgEvent))
        hosting.scrollWheel(with: event)
        #expect(received.count == 1)
        #expect(received.first?.scrollingDeltaX == event.scrollingDeltaX)
    }
}
