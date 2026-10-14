import AppKit
import NotchUI
import Testing
@testable import WindowLayoutModule

/// The overlay is built but never shown, so nothing appears on a screen and nothing can be captured.
@Suite struct SnapPreviewOverlayTests {
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func itNeverTakesTheMouseTheKeyboardOrTheFocus() {
        let overlay = SnapPreviewOverlay(interface: NotchInterface())
        defer { overlay.dismiss() }
        #expect(overlay.ignoresMouseEvents)
        #expect(!overlay.canBecomeKey && !overlay.canBecomeMain)
        #expect(overlay.styleMask.contains(.nonactivatingPanel))
        #expect(!overlay.hidesOnDeactivate)
    }

    @Test func itSitsAboveOrdinaryWindowsAndBelowTheNotch() {
        let overlay = SnapPreviewOverlay(interface: NotchInterface())
        defer { overlay.dismiss() }
        #expect(overlay.level.rawValue > NSWindow.Level.normal.rawValue)
        // The notch's own panel is at `.mainMenu + 3`.
        #expect(overlay.level.rawValue < NSWindow.Level.mainMenu.rawValue + 3)
    }

    @Test func itFollowsTheHideFromRecordingSettingFromTheStart() {
        // It only exists while the notch is open with the tiles, so "when collapsed" leaves it visible, as the open notch is.
        for (hiding, expected) in [
            (CaptureHiding.never, NSWindow.SharingType.readOnly), (.whenCollapsed, .readOnly), (.always, .none),
        ] {
            let interface = NotchInterface()
            interface.captureHiding = hiding
            let overlay = SnapPreviewOverlay(interface: interface)
            #expect(overlay.sharingType == expected, "\(hiding)")
            overlay.dismiss()
        }
    }

    @Test func aChangeOfTheSettingReachesItWhileItLives() async {
        let interface = NotchInterface()
        let overlay = SnapPreviewOverlay(interface: interface)
        defer { overlay.dismiss() }
        #expect(overlay.sharingType == .readOnly)
        interface.captureHiding = .always
        #expect(await eventually { overlay.sharingType == .none })
        interface.captureHiding = .never
        #expect(await eventually { overlay.sharingType == .readOnly })
    }

    @Test func aDismissedOverlayStopsFollowing() async {
        let interface = NotchInterface()
        let overlay = SnapPreviewOverlay(interface: interface)
        overlay.dismiss()
        interface.captureHiding = .always
        try? await Task.sleep(for: .milliseconds(100))
        #expect(overlay.sharingType == .readOnly)
    }
}
