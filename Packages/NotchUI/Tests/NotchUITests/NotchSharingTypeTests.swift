import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// The window controller keeps its panel's sharing type in step with the setting and the notch's state. The panel is
/// never shown, so nothing appears on a screen and nothing can be captured.
@Suite struct NotchSharingTypeTests {
    let harness = RegistryHarness([])
    let settings = SettingsStore(defaults: makeIsolatedDefaults())

    func makeController() -> NotchWindowController {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
            auxiliaryTopLeftWidth: 663.5, auxiliaryTopRightWidth: 663.5, menuBarHeight: 32
        )
        return NotchWindowController(
            displayID: 1, screen: screen, config: NotchLayoutConfig(), scheduler: harness.scheduler,
            registry: harness.registry, activities: harness.activities,
            delays: { (.milliseconds(150), .milliseconds(300)) },
            captureHiding: { [settings] in settings.value(InterfaceSettings.hideFromCapture) },
            swipesBetweenTabs: { true }
        )
    }

    /// The controller follows state and settings through `Observations`, which deliver on a later main-actor turn.
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func aNewPanelIsNormalUnlessTheSettingHidesIt() {
        let normal = makeController()
        #expect(normal.sharingType == .readOnly)
        normal.close()

        settings.set(.always, for: InterfaceSettings.hideFromCapture)
        let hidden = makeController()
        // Before it is ever shown, so there is no frame in which a recorder could see it.
        #expect(hidden.sharingType == .none)
        hidden.close()
    }

    @Test func changingTheSettingChangesTheOpenPanelsToo() async {
        let controller = makeController()
        defer { controller.close() }
        settings.set(.always, for: InterfaceSettings.hideFromCapture)
        #expect(await eventually { controller.sharingType == .none })
        settings.set(.never, for: InterfaceSettings.hideFromCapture)
        #expect(await eventually { controller.sharingType == .readOnly })
    }

    @Test func whenCollapsedTheNotchIsHiddenUntilItOpensAndAgainOnceItCloses() async {
        settings.set(.whenCollapsed, for: InterfaceSettings.hideFromCapture)
        let controller = makeController()
        defer { controller.close() }
        #expect(controller.sharingType == .none)

        controller.model.open(tab: nil)
        #expect(await eventually { controller.sharingType == .readOnly })

        controller.model.close()
        #expect(await eventually { controller.sharingType == .none })
    }

    @Test func aCollapsedNotchWithAnActivityIsStillHidden() async {
        settings.set(.whenCollapsed, for: InterfaceSettings.hideFromCapture)
        let controller = makeController()
        defer { controller.close() }
        harness.activities.set(LiveActivity(id: "a", leading: AnyView(EmptyView()), trailing: AnyView(EmptyView())), from: "m")
        #expect(await eventually { controller.model.displayState == .compact })
        #expect(controller.sharingType == .none)
    }

    #if DEBUG
    @Test func theSwitchIsLoggedWithItsReason() {
        let controller = makeController()
        defer { controller.close() }
        let lines = captureNotchLog {
            settings.set(.always, for: InterfaceSettings.hideFromCapture)
            controller.refreshSharingType()
        }
        #expect(lines.contains { $0.contains("sharing readOnly -> none") && $0.contains("hiding=always") })
        // Nothing to switch, nothing to log.
        #expect(captureNotchLog { controller.refreshSharingType() }.filter { $0.contains("sharing") }.isEmpty)
    }
    #endif
}
