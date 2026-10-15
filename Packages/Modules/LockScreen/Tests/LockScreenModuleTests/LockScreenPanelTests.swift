import AppKit
import CoreGraphics
import NotchUI
import SwiftUI
import Testing
@testable import LockScreenModule

@Suite struct LockScreenPanelTests {
    private var size: CGSize { LockScreenPanel.size }
    private var gap: CGFloat { LockScreenPanel.gap }

    @Test func sitsCentredUnderAHardwareNotch() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
            auxiliaryTopLeftWidth: 656, auxiliaryTopRightWidth: 656, menuBarHeight: 32
        )
        let frame = LockScreenPanel.frame(on: screen)
        #expect(frame.size == size)
        #expect(frame.midX == 756)
        #expect(frame.maxY == 982 - 32 - gap)
    }

    @Test func followsAnAsymmetricNotch() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800), safeAreaTop: 30,
            auxiliaryTopLeftWidth: 400, auxiliaryTopRightWidth: 500, menuBarHeight: 30
        )
        // The notch is 100 wide and its centre is 450 from the left edge, 50 left of the screen centre.
        #expect(LockScreenPanel.frame(on: screen).midX == 450)
    }

    @Test func usesTheMenuBarHeightWhereThereIsNoNotch() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarHeight: 24
        )
        let frame = LockScreenPanel.frame(on: screen)
        #expect(frame.midX == 960)
        #expect(frame.maxY == 1080 - 24 - gap)
    }

    @Test func staysOnAScreenWhoseOriginIsNotZero() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 1512, y: -200, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarHeight: 24
        )
        let frame = LockScreenPanel.frame(on: screen)
        let centre: CGFloat = 2472
        let top: CGFloat = 856 - gap
        #expect(frame.midX == centre)
        #expect(frame.maxY == top)
    }

    // MARK: hiding from screen recordings

    /// The panel is built but never shown, so nothing appears on a screen and nothing can be captured.
    func makePanel(_ interface: NotchInterface) -> LockScreenPanel {
        LockScreenPanel(frame: CGRect(x: 0, y: 0, width: 300, height: 80), content: AnyView(EmptyView()), interface: interface)
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func aNewPanelIsHiddenFromRecordingsFromTheStartWhenTheSettingSaysSo() {
        // The panel is a widget under the collapsed notch, so "when collapsed" hides it as well as "always".
        for (hiding, expected) in [
            (CaptureHiding.never, NSWindow.SharingType.readOnly), (.whenCollapsed, .none), (.always, .none),
        ] {
            let interface = NotchInterface()
            interface.captureHiding = hiding
            let panel = makePanel(interface)
            #expect(panel.sharingType == expected, "\(hiding)")
            panel.dismiss()
        }
    }

    @Test func aChangeOfTheSettingReachesAPanelThatIsAlreadyUp() async {
        let interface = NotchInterface()
        let panel = makePanel(interface)
        defer { panel.dismiss() }
        #expect(panel.sharingType == .readOnly)
        interface.captureHiding = .always
        #expect(await eventually { panel.sharingType == .none })
        interface.captureHiding = .never
        #expect(await eventually { panel.sharingType == .readOnly })
        interface.captureHiding = .whenCollapsed
        #expect(await eventually { panel.sharingType == .none })
    }

    @Test func aDismissedPanelStopsFollowingTheSetting() async {
        let interface = NotchInterface()
        let panel = makePanel(interface)
        panel.dismiss()
        interface.captureHiding = .always
        try? await Task.sleep(for: .milliseconds(100))
        #expect(panel.sharingType == .readOnly)
    }

    @Test func aNewPanelLetsEveryClickThroughUntilItIsToldItHasButtons() {
        let panel = makePanel(NotchInterface())
        defer { panel.dismiss() }
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.takesClicks)
        panel.takesClicks = true
        #expect(!panel.ignoresMouseEvents, "the buttons have to be clickable")
        panel.takesClicks = false
        #expect(panel.ignoresMouseEvents)
    }

    @Test func whateverItDoesWithClicksThePanelNeverTakesTheKeyboard() {
        let panel = makePanel(NotchInterface())
        defer { panel.dismiss() }
        for takesClicks in [false, true] {
            panel.takesClicks = takesClicks
            #expect(!panel.canBecomeKey && !panel.canBecomeMain)
            #expect(panel.styleMask.contains(.nonactivatingPanel), "a click never activates MyNotch, so the password field keeps the keyboard")
        }
    }

    @Test func aClickOnTheFirstTryReachesTheButtonBecauseThePanelIsNeverKey() throws {
        let panel = makePanel(NotchInterface())
        defer { panel.dismiss() }
        let hosting = try #require(panel.contentView as? LockScreenHostingView)
        #expect(hosting.acceptsFirstMouse(for: nil))
    }
}
