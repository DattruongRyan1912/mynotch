import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// The library window follows the screen-recording setting like the notch's windows. The window is made but never put
/// on a screen, so nothing appears and nothing can be captured.
@Suite struct ClipboardLibraryWindowTests {
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func aNewLibraryWindowIsHiddenFromCaptureWhenTheSettingSaysSo() {
        for (hiding, expected) in [
            (CaptureHiding.never, NSWindow.SharingType.readOnly), (.always, .none),
            // Opened by the user like an open notch, so "only while collapsed" shows it.
            (.whenCollapsed, .readOnly),
        ] {
            let controller = ClipboardLibraryWindowController(interface: NotchInterface(captureHiding: hiding))
            #expect(controller.makeWindow(AnyView(EmptyView())).sharingType == expected, "\(hiding)")
        }
    }

    @Test func theLibraryWindowFollowsTheSettingWhileItIsOpen() async {
        let interface = NotchInterface()
        let controller = ClipboardLibraryWindowController(interface: interface)
        let window = controller.makeWindow(AnyView(EmptyView()))
        #expect(window.sharingType == .readOnly)

        interface.captureHiding = .always
        #expect(await eventually { window.sharingType == .none })
        interface.captureHiding = .never
        #expect(await eventually { window.sharingType == .readOnly })
    }

    @Test func aClosedLibraryWindowStopsFollowing() async {
        let interface = NotchInterface()
        let controller = ClipboardLibraryWindowController(interface: interface)
        let window = controller.makeWindow(AnyView(EmptyView()))
        controller.stopFollowingSetting()

        interface.captureHiding = .always
        try? await Task.sleep(for: .milliseconds(50))
        #expect(window.sharingType == .readOnly)
    }
}
