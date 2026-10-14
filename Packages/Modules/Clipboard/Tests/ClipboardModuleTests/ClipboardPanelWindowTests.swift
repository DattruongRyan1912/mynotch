import AppKit
import NotchUI
import Testing
@testable import ClipboardModule

/// The panel's window flags and its screen-recording setting. The panel is made but never put on a screen, so nothing
/// appears and nothing can be captured.
@Suite struct ClipboardPanelWindowTests {
    func makePanel(hiding: CaptureHiding = .never) -> ClipboardFloatingPanel {
        ClipboardPanelController(captureHiding: { hiding }).makePanel()
    }

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

    @Test func aNewPanelIsHiddenFromCaptureWhenTheSettingSaysSo() {
        // The same setting and the same rule as the notch's panels, before the panel is ever shown.
        #expect(makePanel(hiding: .never).sharingType == .readOnly)
        #expect(makePanel(hiding: .always).sharingType == .none)
    }

    @Test func whenCollapsedTheOpenPanelIsShownLikeAnOpenNotch() {
        // "Only while the notch is closed" hides what is collapsed; a panel the user has just opened is not.
        #expect(makePanel(hiding: .whenCollapsed).sharingType == .readOnly)
    }

    @Test func theSettingIsReadAgainWhenThePanelIsMadeAgain() {
        var hiding = CaptureHiding.never
        let controller = ClipboardPanelController(captureHiding: { hiding })
        #expect(controller.makePanel().sharingType == .readOnly)
        hiding = .always
        #expect(controller.makePanel().sharingType == .none)
    }

    @Test func theSettingIsReappliedToAnExistingPanel() {
        var hiding = CaptureHiding.never
        let controller = ClipboardPanelController(captureHiding: { hiding })
        let panel = controller.makePanel()
        hiding = .always
        controller.applyCaptureHiding(to: panel)
        #expect(panel.sharingType == .none)
        hiding = .never
        controller.applyCaptureHiding(to: panel)
        #expect(panel.sharingType == .readOnly)
    }
}
