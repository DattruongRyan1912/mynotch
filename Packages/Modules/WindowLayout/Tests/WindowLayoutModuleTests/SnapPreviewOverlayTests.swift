import AppKit
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import NotchUI
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

    // MARK: the accent

    /// The accent of the interface as the settings say it, the way the app's own interface follows them.
    @MainActor
    final class Themed {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let interface = NotchInterface()
        private var following: Task<Void, Never>?

        init() {
            let theme = NotchTheme(settings: settings, systemAccent: { .init(red: 10, green: 132, blue: 255) }, notifications: NotificationCenter())
            following = interface.follow(settings, theme: theme)
        }

        isolated deinit { following?.cancel() }

        func pick(_ palette: NotchAccent.Palette) { settings.set(.palette(palette), for: InterfaceSettings.accent) }
    }

    func rgb(of color: CGColor?) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        guard let color, let converted = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return nil }
        return (converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent)
    }

    func matches(_ color: CGColor?, _ palette: NotchAccent.Palette, alpha: CGFloat) -> Bool {
        guard let actual = rgb(of: color) else { return false }
        let wanted = palette.rgb
        return abs(actual.red - CGFloat(wanted.red) / 255) < 0.01 && abs(actual.green - CGFloat(wanted.green) / 255) < 0.01
            && abs(actual.blue - CGFloat(wanted.blue) / 255) < 0.01 && abs(actual.alpha - alpha) < 0.01
    }

    @Test func theRectangleIsTheInterfacesAccentFromTheStartAndFollowsItWhileItLives() async {
        let themed = Themed()
        themed.pick(.green)
        let overlay = SnapPreviewOverlay(interface: themed.interface)
        defer { overlay.dismiss() }
        let layer = overlay.contentView?.layer
        #expect(matches(layer?.backgroundColor, .green, alpha: 0.2))
        #expect(matches(layer?.borderColor, .green, alpha: 0.7))
        themed.pick(.orange)
        #expect(await eventually { matches(layer?.backgroundColor, .orange, alpha: 0.2) })
        #expect(matches(layer?.borderColor, .orange, alpha: 0.7))
    }

    @Test func aDismissedOverlayStopsFollowingTheAccent() async {
        let themed = Themed()
        themed.pick(.green)
        let overlay = SnapPreviewOverlay(interface: themed.interface)
        let layer = overlay.contentView?.layer
        overlay.dismiss()
        themed.pick(.orange)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(matches(layer?.backgroundColor, .green, alpha: 0.2))
    }
}
