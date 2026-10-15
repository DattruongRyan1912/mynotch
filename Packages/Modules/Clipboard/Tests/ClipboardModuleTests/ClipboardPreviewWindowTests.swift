import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// The preview's own window: it is never key (so it cannot break the pinned paste's "no window of MyNotch has the keyboard"
/// check, trip the click-outside monitors or take Esc), follows the screen-recording setting, sits on the host's display and
/// closes on a click anywhere else. Panels are made but never put on a screen, and no event is posted.
@Suite struct ClipboardPreviewWindowTests {
    static let laptop = ClipboardPanelPlacement.Screen(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 806)
    )

    final class FakeClickMonitor {
        private(set) var started = 0
        private(set) var stopped = 0
        private(set) var handler: (@MainActor (ObjectIdentifier?) -> Bool)?

        var monitor: ClipboardPreviewClickMonitor {
            ClipboardPreviewClickMonitor(
                start: { [self] handler in
                    started += 1
                    self.handler = handler
                    return "token"
                },
                stop: { [self] token in
                    #expect(token as? String == "token")
                    stopped += 1
                }
            )
        }
    }

    final class Presented {
        var panels: [ClipboardPreviewPanel] = []
    }

    func makeController(
        hiding: CaptureHiding = .never, monitor: ClipboardPreviewClickMonitor = .system, center: NotificationCenter = NotificationCenter(),
        screens: [ClipboardPanelPlacement.Screen] = [laptop], presented: Presented = Presented()
    ) -> ClipboardPreviewController {
        ClipboardPreviewController(
            interface: NotchInterface(captureHiding: hiding), screens: { screens }, clickMonitor: monitor, center: center,
            orderFront: { presented.panels.append($0) }
        )
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: Never key

    @Test func thePreviewPanelCanNeverBecomeKeyOrMain() {
        let panel = makeController().makePanel(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        panel.makeKey()
        #expect(!panel.isKeyWindow)
        #expect(!panel.isMainWindow)
    }

    @Test func itIsBorderlessAndNonActivatingSoClickingItNeverActivatesMyNotch() {
        let panel = makeController().makePanel(frame: .zero)
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.styleMask.contains(.titled))
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isOpaque)
        #expect(!panel.isVisible)
    }

    @Test func itFloatsAboveTheWindowsItBelongsToOnEverySpace() {
        let panel = makeController().makePanel(frame: .zero)
        #expect(panel.level.rawValue > NSWindow.Level.floating.rawValue)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.transient))
        #expect(!panel.collectionBehavior.contains(.managed))
    }

    @Test func thePreviewIsHostedWithTheAccentOfTheNotchAndTakesTheFirstClick() {
        let background = makeController().makeContentView(AnyView(EmptyView()), size: CGSize(width: 100, height: 100))
        let hosting = background.subviews.first { $0 is ClipboardFirstMouseHostingView<ClipboardAccentHost<AnyView>> }
        #expect(hosting != nil)
        // The panel can never be key, so a click on it is always a first click, which must still reach what is under it.
        #expect(hosting?.acceptsFirstMouse(for: nil) == true)
    }

    // MARK: Screen recording

    @Test func aNewPreviewIsHiddenFromCaptureWhenTheSettingSaysSo() {
        #expect(makeController(hiding: .never).makePanel(frame: .zero).sharingType == .readOnly)
        #expect(makeController(hiding: .always).makePanel(frame: .zero).sharingType == .none)
        // The user opened it, like an open notch, so "only while collapsed" shows it.
        #expect(makeController(hiding: .whenCollapsed).makePanel(frame: .zero).sharingType == .readOnly)
    }

    @Test func thePreviewFollowsTheSettingWhileItExistsAndStopsAfterwards() async {
        let interface = NotchInterface()
        let controller = ClipboardPreviewController(interface: interface, screens: { [Self.laptop] }, orderFront: { _ in })
        let panel = controller.makePanel(frame: .zero)
        #expect(panel.sharingType == .readOnly)
        interface.captureHiding = .always
        #expect(await eventually { panel.sharingType == .none })

        controller.stopFollowingSetting()
        interface.captureHiding = .never
        try? await Task.sleep(for: .milliseconds(50))
        #expect(panel.sharingType == .none)
    }

    // MARK: Showing

    @Test func showingPutsItOnTheHostsDisplayWithTheContentAndWatchesClicks() throws {
        let fake = FakeClickMonitor()
        let presented = Presented()
        let controller = makeController(monitor: fake.monitor, presented: presented)

        controller.show(AnyView(Text("x")), hostFrame: CGRect(x: 100, y: 300, width: 660, height: 420), hostWindow: nil) {}

        let panel = try #require(presented.panels.first)
        #expect(controller.isOpen)
        #expect(presented.panels.count == 1)
        // AppKit puts a window's edges on whole pixels.
        let expected = try #require(ClipboardPreviewPlacement.frame(host: CGRect(x: 100, y: 300, width: 660, height: 420), screens: [Self.laptop]))
        #expect(abs(panel.frame.minX - expected.minX) <= 1 && abs(panel.frame.minY - expected.minY) <= 1)
        #expect(abs(panel.frame.width - expected.width) <= 2 && abs(panel.frame.height - expected.height) <= 2)
        #expect(panel.contentView != nil)
        #expect(!panel.canBecomeKey)
        #expect(fake.started == 1)
    }

    @Test func withoutAnyDisplayNothingIsShown() {
        let fake = FakeClickMonitor()
        let presented = Presented()
        let controller = makeController(monitor: fake.monitor, screens: [], presented: presented)
        controller.show(AnyView(Text("x")), hostFrame: nil, hostWindow: nil) {}
        #expect(!controller.isOpen)
        #expect(presented.panels.isEmpty)
        #expect(fake.started == 0)
    }

    @Test func showingAgainReplacesThePanelAndTheMonitor() throws {
        let fake = FakeClickMonitor()
        let presented = Presented()
        let controller = makeController(monitor: fake.monitor, presented: presented)
        controller.show(AnyView(Text("a")), hostFrame: nil, hostWindow: nil) {}
        let first = try #require(presented.panels.first)

        controller.show(AnyView(Text("b")), hostFrame: nil, hostWindow: nil) {}
        #expect(presented.panels.count == 2)
        #expect(presented.panels[1] !== first)
        #expect(!first.isVisible)
        #expect(fake.started == 2)
        #expect(fake.stopped == 1)
    }

    @Test func closingStopsTheMonitorOnceAndLeavesNothing() async throws {
        let fake = FakeClickMonitor()
        let presented = Presented()
        let controller = makeController(monitor: fake.monitor, presented: presented)
        controller.show(AnyView(Text("x")), hostFrame: nil, hostWindow: nil) {}
        let panel = try #require(presented.panels.first)

        controller.close()
        controller.close()
        #expect(!controller.isOpen)
        #expect(fake.stopped == 1)
        #expect(await eventually { panel.contentView == nil })
    }

    @Test func aMonitorThatCouldNotBeInstalledIsNotRemoved() {
        var stopped = 0
        let monitor = ClipboardPreviewClickMonitor(start: { _ in nil }, stop: { _ in stopped += 1 })
        let controller = makeController(monitor: monitor)
        controller.show(AnyView(Text("x")), hostFrame: nil, hostWindow: nil) {}
        controller.close()
        #expect(stopped == 0)
    }

    // MARK: Clicks

    @Test func aClickInAnotherAppClosesIt() {
        let fake = FakeClickMonitor()
        let controller = makeController(monitor: fake.monitor)
        var outside = 0
        controller.show(AnyView(Text("x")), hostFrame: nil, hostWindow: nil) { outside += 1 }

        #expect(fake.handler?(nil) == false)
        #expect(outside == 1)
    }

    /// A click on the window the preview belongs to is swallowed, so a click that closes the preview does not also press the row or
    /// card under it (which would paste).
    @Test func aClickOnTheHostWindowClosesItAndIsNotPassedOn() {
        let fake = FakeClickMonitor()
        let controller = makeController(monitor: fake.monitor)
        var outside = 0
        let host = NSWindow()
        controller.show(AnyView(Text("x")), hostFrame: nil, hostWindow: ObjectIdentifier(host)) { outside += 1 }

        #expect(fake.handler?(ObjectIdentifier(host)) == true)
        #expect(outside == 1)
    }

    /// Any other window of MyNotch (Settings, a title bar's close button, the notch) closes it too but gets its click.
    @Test func aClickInAnotherWindowOfMyNotchClosesItAndIsPassedOn() {
        let fake = FakeClickMonitor()
        let controller = makeController(monitor: fake.monitor)
        var outside = 0
        let host = NSWindow(), other = NSWindow()
        controller.show(AnyView(Text("x")), hostFrame: nil, hostWindow: ObjectIdentifier(host)) { outside += 1 }

        #expect(fake.handler?(ObjectIdentifier(other)) == false)
        #expect(outside == 1)
    }

    @Test func withNoHostWindowNoClickIsSwallowed() {
        let fake = FakeClickMonitor()
        let controller = makeController(monitor: fake.monitor)
        var outside = 0
        let other = NSWindow()
        controller.show(AnyView(Text("x")), hostFrame: nil, hostWindow: nil) { outside += 1 }

        #expect(fake.handler?(ObjectIdentifier(other)) == false)
        #expect(outside == 1)
    }

    @Test func aClickOnThePreviewItselfDoesNotCloseIt() throws {
        let fake = FakeClickMonitor()
        let presented = Presented()
        let controller = makeController(monitor: fake.monitor, presented: presented)
        var outside = 0
        controller.show(AnyView(Text("x")), hostFrame: nil, hostWindow: nil) { outside += 1 }

        #expect(fake.handler?(ObjectIdentifier(try #require(presented.panels.first))) == false)
        #expect(outside == 0)
    }

    @Test func theApplicationLosingTheFrontClosesIt() {
        let center = NotificationCenter()
        // A fake monitor, so no real event monitor is installed in the test process.
        let controller = makeController(monitor: FakeClickMonitor().monitor, center: center)
        var outside = 0
        controller.show(AnyView(Text("x")), hostFrame: nil, hostWindow: nil) { outside += 1 }

        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(outside == 1)

        controller.close()
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(outside == 1)
    }

    @Test func aClickAfterItClosedDoesNothing() {
        let fake = FakeClickMonitor()
        let controller = makeController(monitor: fake.monitor)
        var outside = 0
        controller.show(AnyView(Text("x")), hostFrame: nil, hostWindow: nil) { outside += 1 }
        controller.close()

        #expect(fake.handler?(nil) == false)
        #expect(outside == 0)
    }
}
