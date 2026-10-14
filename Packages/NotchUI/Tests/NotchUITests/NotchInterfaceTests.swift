import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// What windows of MyNotch that are not the notch's own panels learn from the notch: where it is shown and whether the
/// user keeps it out of recordings. No window is shown, so nothing appears on a screen and nothing can be captured.
@Suite struct NotchInterfaceTests {
    func makePanel() -> NSPanel {
        NSPanel(contentRect: CGRect(x: 0, y: 0, width: 100, height: 40), styleMask: [.borderless], backing: .buffered, defer: true)
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func startsWithNothingHiddenAndNoNotch() {
        let interface = NotchInterface()
        #expect(interface.captureHiding == .never)
        #expect(interface.notches.isEmpty)
    }

    @Test func followsTheSettingFromTheMomentItStartsAndThroughEveryChange() async {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        settings.set(.whenCollapsed, for: InterfaceSettings.hideFromCapture)
        let interface = NotchInterface()
        let following = interface.follow(settings)
        defer { following.cancel() }
        // At once, not a turn later: a module that starts right after the screens read the right value.
        #expect(interface.captureHiding == .whenCollapsed)
        settings.set(.always, for: InterfaceSettings.hideFromCapture)
        #expect(await eventually { interface.captureHiding == .always })
        settings.set(.never, for: InterfaceSettings.hideFromCapture)
        #expect(await eventually { interface.captureHiding == .never })
    }

    // MARK: windows that follow the setting

    @Test func aWindowIsNormalOrHiddenFromTheFirstMomentAccordingToTheSettingAndItsStateOfTheNotch() {
        for (hiding, state, expected) in [
            (CaptureHiding.never, NotchState.compact, NSWindow.SharingType.readOnly),
            (.never, .toast, .readOnly),
            (.always, .compact, .none),
            (.always, .toast, .none),
            // Collapsed, such as a widget under the notch: hidden. Expanded, such as a preview while the notch is open: shown.
            (.whenCollapsed, .compact, .none),
            (.whenCollapsed, .toast, .readOnly),
        ] {
            let interface = NotchInterface()
            interface.captureHiding = hiding
            let window = makePanel()
            let follower = CaptureHidingFollower(window, as: state, interface: interface)
            #expect(window.sharingType == expected, "\(hiding) \(state)")
            follower.stop()
        }
    }

    @Test func aWindowFollowsEveryChangeOfTheSettingWhileItIsFollowed() async {
        let interface = NotchInterface()
        let window = makePanel()
        let follower = CaptureHidingFollower(window, as: .compact, interface: interface)
        defer { follower.stop() }
        #expect(window.sharingType == .readOnly)
        interface.captureHiding = .always
        #expect(await eventually { window.sharingType == .none })
        interface.captureHiding = .never
        #expect(await eventually { window.sharingType == .readOnly })
        interface.captureHiding = .whenCollapsed
        #expect(await eventually { window.sharingType == .none })
    }

    @Test func aStoppedFollowerLeavesTheWindowAlone() async {
        let interface = NotchInterface()
        let window = makePanel()
        let follower = CaptureHidingFollower(window, as: .compact, interface: interface)
        follower.stop()
        interface.captureHiding = .always
        try? await Task.sleep(for: .milliseconds(100))
        #expect(window.sharingType == .readOnly)
    }

    // MARK: where the notch is shown

    @Test func aControllerDescribesItsDisplayWithTheGeometryItDraws() {
        let harness = RegistryHarness([])
        let screen = NotchGeometryTests.macBook14
        let config = NotchLayoutConfig(openWidth: 520)
        let controller = NotchWindowController(
            displayID: 7, screen: screen, config: config, scheduler: harness.scheduler, registry: harness.registry,
            activities: harness.activities, delays: { (.milliseconds(150), .milliseconds(300)) }, captureHiding: { .never },
            swipesBetweenTabs: { true }
        )
        defer { controller.close() }
        #expect(controller.display == NotchDisplay(id: 7, screenFrame: screen.frame, geometry: NotchGeometry(screen: screen, config: config)))
    }

    @Test func onlyTheNotchesThatAreShownAreListedInDisplayOrder() {
        func display(_ id: CGDirectDisplayID) -> NotchDisplay {
            NotchDisplay(id: id, screenFrame: NotchGeometryTests.macBook14.frame, geometry: NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig()))
        }
        let listed = NotchInterface.visibleNotches(among: [(display(9), true), (display(2), false), (display(4), true), (display(1), true)])
        #expect(listed.map(\.id) == [1, 4, 9])
        #expect(NotchInterface.visibleNotches(among: []).isEmpty)
        #expect(NotchInterface.visibleNotches(among: [(display(1), false)]).isEmpty)
    }
}
