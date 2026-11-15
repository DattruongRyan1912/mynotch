import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// The panel's window flags, how it follows the screen-recording setting, what its keys do and how the click monitor
/// lives. The panel is made but never put on a screen, so nothing appears, nothing can be captured and no key status
/// moves; no event is posted, the key events are built and handed to the panel directly.
@Suite struct ClipboardPanelWindowTests {
    func makeController(hiding: CaptureHiding = .never, monitor: ClipboardPanelClickMonitor = .system) -> (ClipboardPanelController, NotchInterface) {
        let interface = NotchInterface(captureHiding: hiding)
        return (ClipboardPanelController(interface: interface, clickMonitor: monitor), interface)
    }

    func makePanel(hiding: CaptureHiding = .never) -> ClipboardFloatingPanel {
        makeController(hiding: hiding).0.makePanel()
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    func keyEvent(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        ))
    }

    @Test func theFloatingPanelIsHostedWithTheAccentOfTheNotch() throws {
        let (controller, _) = makeController()
        let background = controller.makeContentView(AnyView(EmptyView()), size: CGSize(width: 100, height: 100))
        #expect(background.subviews.contains { $0 is ClipboardFirstMouseHostingView<ClipboardAccentHost<AnyView>> })
    }

    // MARK: Flags

    @Test func thePanelFloatsOnEverySpaceWithoutTakingTheApplicationForward() {
        let panel = makePanel()

        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level == .floating)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        // Hidden by Mission Control instead of listed in it.
        #expect(panel.collectionBehavior.contains(.transient))
        #expect(!panel.collectionBehavior.contains(.managed))
        // It takes typing, but never becomes the app's main window, and it stays when another app is activated.
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isVisible)
    }

    @Test func thePanelHasNoWindowChromeOfItsOwn() {
        let panel = makePanel()
        #expect(!panel.styleMask.contains(.titled))
        #expect(!panel.isOpaque)
        #expect(panel.hasShadow)
    }

    // MARK: Screen recording

    @Test func aNewPanelIsHiddenFromCaptureWhenTheSettingSaysSo() {
        // The same setting and the same rule as the notch's other windows, before the panel is ever shown.
        #expect(makePanel(hiding: .never).sharingType == .readOnly)
        #expect(makePanel(hiding: .always).sharingType == .none)
    }

    @Test func whenCollapsedTheOpenPanelIsShownLikeAnOpenNotch() {
        // "Only while the notch is closed" hides what is collapsed; a panel the user has just opened is not.
        #expect(makePanel(hiding: .whenCollapsed).sharingType == .readOnly)
    }

    @Test func thePanelFollowsTheSettingWhileItExists() async {
        let (controller, interface) = makeController()
        let panel = controller.makePanel()
        #expect(panel.sharingType == .readOnly)

        interface.captureHiding = .always
        #expect(await eventually { panel.sharingType == .none })
        interface.captureHiding = .never
        #expect(await eventually { panel.sharingType == .readOnly })
        interface.captureHiding = .whenCollapsed
        #expect(await eventually { panel.sharingType == .readOnly })
    }

    @Test func aPanelThatWasLetGoStopsFollowing() async {
        let (controller, interface) = makeController()
        let panel = controller.makePanel()
        controller.stopFollowingSetting()

        interface.captureHiding = .always
        try? await Task.sleep(for: .milliseconds(50))
        #expect(panel.sharingType == .readOnly)
    }

    // MARK: Keys

    @Test func commandAndANumberKeyGoToTheQuickPickAndAreConsumed() throws {
        let panel = makePanel()
        var picked: [Int] = []
        // The model answers false for a number with no item; the key is consumed all the same, so it does not beep.
        panel.onQuickPick = { picked.append($0); return false }

        #expect(panel.performKeyEquivalent(with: try keyEvent("3", code: 20, modifiers: .command)))
        #expect(picked == [3])
    }

    @Test func theNumberRowCountsByPositionNotByWhatItTypes() throws {
        // AZERTY: the key that types 1 unshifted types "&".
        let panel = makePanel()
        var picked: [Int] = []
        panel.onQuickPick = { picked.append($0); return true }

        #expect(panel.performKeyEquivalent(with: try keyEvent("&", code: 18, modifiers: .command)))
        #expect(picked == [1])
    }

    @Test func otherShortcutsAreNotTheQuickPicks() throws {
        let panel = makePanel()
        var picked: [Int] = []
        panel.onQuickPick = { picked.append($0); return true }

        for (characters, code, modifiers) in [
            ("v", UInt16(9), NSEvent.ModifierFlags.command), ("3", 20, [.command, .shift]), ("3", 20, []), ("0", 29, .command),
        ] {
            _ = panel.performKeyEquivalent(with: try keyEvent(characters, code: code, modifiers: modifiers))
        }
        #expect(picked.isEmpty)
    }

    @Test func escapeAndTheKeyboardLeavingAreReported() {
        let panel = makePanel()
        var events: [String] = []
        panel.onCancel = { events.append("cancel") }
        panel.onResignKey = { events.append("resigned key") }

        panel.cancelOperation(nil)
        panel.resignKey()

        #expect(events == ["cancel", "resigned key"])
    }

    // MARK: Clicks in other apps

    final class FakeClickMonitor {
        private(set) var started = 0
        private(set) var stopped = 0
        private(set) var handler: (() -> Void)?

        var monitor: ClipboardPanelClickMonitor {
            ClipboardPanelClickMonitor(
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

    func makeModel(pinned: Bool, close: @escaping () -> Void) -> ClipboardPanelModel {
        let model = ClipboardPanelModel(state: ClipboardState(), actions: FakePanelActions(), isPinned: pinned)
        model.onClose = close
        return model
    }

    @Test func aClickInAnotherAppClosesAnUnpinnedPanelAndLeavesAPinnedOne() {
        let fake = FakeClickMonitor()
        let (controller, _) = makeController(monitor: fake.monitor)
        var closed = 0

        let unpinned = makeModel(pinned: false) { closed += 1 }
        controller.watch(unpinned)
        #expect(fake.started == 1)
        fake.handler?()
        #expect(closed == 1)
        controller.stopWatching()

        let pinned = makeModel(pinned: true) { closed += 1 }
        controller.watch(pinned)
        fake.handler?()
        #expect(closed == 1)
        controller.stopWatching()
    }

    @Test func theMonitorIsRemovedOnceAndOnlyOnce() {
        let fake = FakeClickMonitor()
        let (controller, _) = makeController(monitor: fake.monitor)

        controller.stopWatching()
        #expect(fake.stopped == 0)

        controller.watch(makeModel(pinned: false) {})
        controller.stopWatching()
        controller.stopWatching()
        #expect(fake.started == 1)
        #expect(fake.stopped == 1)
    }

    @Test func watchingAgainReplacesTheEarlierMonitor() {
        let fake = FakeClickMonitor()
        let (controller, _) = makeController(monitor: fake.monitor)

        controller.watch(makeModel(pinned: false) {})
        controller.watch(makeModel(pinned: false) {})
        #expect(fake.started == 2)
        #expect(fake.stopped == 1)
        controller.stopWatching()
        #expect(fake.stopped == 2)
    }

    @Test func aMonitorThatCouldNotBeInstalledIsNotRemoved() {
        var stopped = 0
        let monitor = ClipboardPanelClickMonitor(start: { _ in nil }, stop: { _ in stopped += 1 })
        let (controller, _) = makeController(monitor: monitor)

        controller.watch(makeModel(pinned: false) {})
        controller.stopWatching()
        #expect(stopped == 0)
    }

    @Test func aClickAfterTheModelIsGoneDoesNothing() {
        let fake = FakeClickMonitor()
        let (controller, _) = makeController(monitor: fake.monitor)
        var closed = 0
        var model: ClipboardPanelModel? = makeModel(pinned: false) { closed += 1 }
        controller.watch(model!)
        model = nil

        fake.handler?()
        #expect(closed == 0)
        controller.stopWatching()
    }
}
