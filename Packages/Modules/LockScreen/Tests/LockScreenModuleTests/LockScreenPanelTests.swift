import AppKit
import CoreGraphics
import NotchUI
import SwiftUI
import Testing
@testable import LockScreenModule

@Suite struct LockScreenPanelTests {
    private var size: CGSize { CGSize(width: LockScreenPanel.width, height: 80) }
    private var gap: CGFloat { LockScreenPanel.gap }

    @Test func sitsCentredUnderAHardwareNotch() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
            auxiliaryTopLeftWidth: 656, auxiliaryTopRightWidth: 656, menuBarHeight: 32
        )
        let frame = LockScreenPanel.frame(on: screen, height: 80)
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
        #expect(LockScreenPanel.frame(on: screen, height: 80).midX == 450)
    }

    @Test func usesTheMenuBarHeightWhereThereIsNoNotch() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarHeight: 24
        )
        let frame = LockScreenPanel.frame(on: screen, height: 80)
        #expect(frame.midX == 960)
        #expect(frame.maxY == 1080 - 24 - gap)
    }

    @Test func staysOnAScreenWhoseOriginIsNotZero() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 1512, y: -200, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarHeight: 24
        )
        let frame = LockScreenPanel.frame(on: screen, height: 80)
        let centre: CGFloat = 2472
        let top: CGFloat = 856 - gap
        #expect(frame.midX == centre)
        #expect(frame.maxY == top)
    }

    // MARK: under the notch the display really has

    /// A display without a notch of its own, `menuBarHeight` 24 tall, at `origin` on the desktop.
    private func virtualScreen(at origin: CGPoint = .zero) -> ScreenDescriptor {
        ScreenDescriptor(
            frame: CGRect(x: origin.x, y: origin.y, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarHeight: 24
        )
    }

    /// An interface that shows one notch, on `screen`, laid out from `config`: what `ScreenManager` publishes.
    private func interface(showing config: NotchLayoutConfig, on screen: ScreenDescriptor) -> NotchInterface {
        NotchInterface(notches: [NotchDisplay(id: 1, screenFrame: screen.frame, geometry: NotchGeometry(screen: screen, config: config))])
    }

    @Test func staysTheGapClearOfAFloatingPill() {
        let screen = virtualScreen()
        let frame = LockScreenPanel.frame(
            on: screen, height: 80, interface: interface(showing: NotchLayoutConfig(virtualNotchStyle: .pill), on: screen)
        )
        // The pill hangs 5 pt below the top and is 32 tall (its own height, `pillHeight`'s default), so it ends 37 from the top; the panel
        // starts the gap (8) under that. Measured from the notch only, it would start 3 pt under the pill.
        #expect(frame.maxY == 1080 - 5 - 32 - gap)
        #expect(frame.maxY == 1035)
        #expect(frame.midX == 960)
        #expect(frame.size == size)
    }

    @Test func staysTheGapClearOfATallPillWhateverHeightTheUserGaveIt() {
        let screen = virtualScreen()
        for height in [CGFloat(24), 40, 56] {
            // The notch's own height setting is another one and does not move it.
            let config = NotchLayoutConfig(virtualNotchHeight: 24, virtualNotchStyle: .pill, pillHeight: height)
            let frame = LockScreenPanel.frame(on: screen, height: 80, interface: interface(showing: config, on: screen))
            #expect(frame.maxY == 1080 - NotchGeometry.pillTopGap - height - gap, "\(height)")
            #expect(NotchGeometry.pillTopGap + height + gap == 1080 - frame.maxY, "the gap under the pill is the usual 8 pt")
        }
    }

    @Test func staysTheGapClearOfANotchStuckToTheTopOfADisplayWithoutOne() {
        let screen = virtualScreen()
        let frame = LockScreenPanel.frame(
            on: screen, height: 80, interface: interface(showing: NotchLayoutConfig(virtualNotchStyle: .notch), on: screen)
        )
        #expect(frame.maxY == 1080 - 24 - gap)
    }

    @Test func followsTheVirtualNotchHeightTheUserChose() {
        let screen = virtualScreen()
        for (style, top) in [(VirtualNotchStyle.notch, CGFloat(0)), (.pill, NotchGeometry.pillTopGap)] {
            // A notch is as tall as its setting, a pill as its own: 40 for both here.
            let config = NotchLayoutConfig(virtualNotchWidth: 250, virtualNotchHeight: 40, virtualNotchStyle: style, pillHeight: 40)
            let frame = LockScreenPanel.frame(on: screen, height: 80, interface: interface(showing: config, on: screen))
            #expect(frame.maxY == 1080 - top - 40 - gap, "\(style)")
            #expect(frame.midX == 960, "\(style)")
        }
    }

    @Test func aHardwareNotchIsNeverMovedByThePillSetting() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800), safeAreaTop: 30,
            auxiliaryTopLeftWidth: 400, auxiliaryTopRightWidth: 500, menuBarHeight: 30
        )
        let frame = LockScreenPanel.frame(
            on: screen, height: 80, interface: interface(showing: NotchLayoutConfig(virtualNotchHeight: 40, virtualNotchStyle: .pill), on: screen)
        )
        #expect(frame.maxY == 800 - 30 - gap, "the cutout's own height, with no pill gap above it")
        #expect(frame.midX == 450, "still under the asymmetric cutout")
    }

    @Test func aSecondDisplayIsLaidOutFromTheSameSettingsAsTheNotchOnTheFirst() {
        let main = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
            auxiliaryTopLeftWidth: 656, auxiliaryTopRightWidth: 656, menuBarHeight: 32
        )
        let external = virtualScreen(at: CGPoint(x: 1512, y: -200))
        // The only notch showing is the hardware one, on the main display; the pill setting is still the user's.
        let frame = LockScreenPanel.frame(
            on: external, height: 80, interface: interface(showing: NotchLayoutConfig(virtualNotchStyle: .pill), on: main)
        )
        #expect(frame.midX == 2472)
        #expect(frame.maxY == 880 - 5 - 32 - gap)
    }

    @Test func withNoNotchShowingTheDefaultsAreWhatThePanelGoesBy() {
        let frame = LockScreenPanel.frame(on: virtualScreen(), height: 80, interface: NotchInterface())
        #expect(frame.maxY == 1080 - 24 - gap)
        #expect(frame.midX == 960)
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
