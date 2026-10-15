import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// The light tap on the trackpad that goes with a gesture. A fake stands in for the system's performer, so nothing is
/// ever felt in a test and no setting of the machine matters.
@Suite struct HapticsTests {
    final class Performer: HapticPerformer {
        var performed: [Haptic] = []
        func perform(_ haptic: Haptic) { performed.append(haptic) }
    }

    let performer = Performer()
    let settings = SettingsStore(defaults: makeIsolatedDefaults())

    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func aTapIsPerformedWhenTheSettingIsOn() {
        let interface = NotchInterface(performer: performer)
        interface.feel(.alignment)
        interface.feel(.levelChange)
        #expect(performer.performed == [.alignment, .levelChange])
    }

    @Test func nothingIsPerformedWhenTheSettingIsOff() {
        let interface = NotchInterface(performer: performer)
        interface.hapticsEnabled = false
        interface.feel(.alignment)
        interface.feel(.levelChange)
        #expect(performer.performed.isEmpty)
    }

    @Test func tapsAreOnByDefault() {
        #expect(NotchInterface(performer: performer).hapticsEnabled)
        #expect(InterfaceSettings.haptics.defaultValue)
        #expect(SettingsStore(defaults: makeIsolatedDefaults()).value(InterfaceSettings.haptics))
    }

    @Test func theSettingIsFollowedFromTheMomentItStartsAndThroughEveryChange() async {
        let interface = NotchInterface(performer: performer)
        settings.set(false, for: InterfaceSettings.haptics)
        let following = interface.follow(settings)
        defer { following.cancel() }
        #expect(!interface.hapticsEnabled)
        interface.feel(.alignment)
        #expect(performer.performed.isEmpty)
        settings.set(true, for: InterfaceSettings.haptics)
        #expect(await eventually { interface.hapticsEnabled })
        interface.feel(.alignment)
        #expect(performer.performed == [.alignment])
        settings.set(false, for: InterfaceSettings.haptics)
        #expect(await eventually { !interface.hapticsEnabled })
    }

    @Test func followingTheHapticsSettingStillFollowsTheCaptureSetting() async {
        let interface = NotchInterface(performer: performer)
        let following = interface.follow(settings)
        defer { following.cancel() }
        settings.set(.always, for: InterfaceSettings.hideFromCapture)
        #expect(await eventually { interface.captureHiding == .always })
        settings.set(false, for: InterfaceSettings.haptics)
        #expect(await eventually { !interface.hapticsEnabled })
        #expect(interface.captureHiding == .always)
    }

    @Test func eachTapIsOneOfTheSystemsPatterns() {
        #expect(Haptic.alignment.pattern == .alignment)
        #expect(Haptic.levelChange.pattern == .levelChange)
    }

    @Test func theSettingIsKeptForTheNextLaunch() {
        let defaults = makeIsolatedDefaults()
        SettingsStore(defaults: defaults).set(false, for: InterfaceSettings.haptics)
        #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.haptics) == false)
        #expect(InterfaceSettings.haptics.name == "interface.haptics")
    }

    // MARK: from a gesture to the performer

    private final class Module: FeatureModule {
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

    @Test func aGestureOnTheNotchReachesThePerformerThroughTheInterfaceOnlyWhileTheSettingIsOn() async {
        let harness = RegistryHarness([Module("a", order: 1), Module("b", order: 2)])
        await harness.registry.bootstrap()
        let interface = NotchInterface(performer: performer)
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
            auxiliaryTopLeftWidth: 663.5, auxiliaryTopRightWidth: 663.5, menuBarHeight: 32
        )
        let controller = NotchWindowController(
            displayID: 1, screen: screen, config: NotchLayoutConfig(), scheduler: harness.scheduler,
            registry: harness.registry, activities: harness.activities, delays: { (.milliseconds(150), .milliseconds(300)) },
            captureHiding: { .never }, swipesBetweenTabs: { true }, systemAllowsSwipe: { true },
            swipeToOpen: { .medium }, feel: { [interface] in interface.feel($0) }
        )
        defer { controller.close() }
        func swipe(dx: CGFloat = 0, dy: CGFloat = 0) {
            controller.handleScroll(phase: .began, momentumPhase: [], deltaX: 0, deltaY: 0)
            for _ in 0..<5 { controller.handleScroll(phase: .changed, momentumPhase: [], deltaX: dx / 5, deltaY: dy / 5) }
            controller.handleScroll(phase: .ended, momentumPhase: [], deltaX: 0, deltaY: 0)
        }
        controller.model.pointerEntered()
        swipe(dy: 200)
        swipe(dx: -200)
        #expect(controller.model.state == .open("b"))
        #expect(performer.performed == [.levelChange, .alignment])
        interface.hapticsEnabled = false
        swipe(dx: 200)
        swipe(dy: -200)
        #expect(controller.model.state == .closed)
        #expect(performer.performed == [.levelChange, .alignment])
    }
}
