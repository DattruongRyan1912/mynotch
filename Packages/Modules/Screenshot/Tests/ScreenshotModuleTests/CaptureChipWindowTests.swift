import AppKit
import SwiftUI
import Testing
@testable import ScreenshotModule

/// The chip's window, never put on screen: that it cannot take the keyboard, where it is, and what the pointer reports.
@Suite struct CaptureChipWindowTests {
    let main = ChipScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 862))

    func content(hover: @escaping @MainActor (Bool) -> Void = { _ in }) -> CaptureChipContent {
        CaptureChipContent(thumbnail: nil, edit: {}, copy: {}, hover: hover)
    }

    @Test func thePanelCanNeverTakeTheKeyboardOrActivateTheApp() {
        let panel = CaptureChipPanel()
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.isFloatingPanel)
        #expect(!panel.hidesOnDeactivate)
    }

    @Test func thePanelIsLeftOutOfScreenCaptures() {
        #expect(CaptureChipPanel().sharingType == .none)
    }

    @Test func thePanelFollowsTheUserAcrossSpacesAndFullScreenApps() {
        let behavior = CaptureChipPanel().collectionBehavior
        #expect(behavior.contains(.canJoinAllSpaces))
        #expect(behavior.contains(.fullScreenAuxiliary))
    }

    @Test func theFirstClickPressesAButtonAlthoughMyNotchIsNotActive() {
        let view = CaptureChipHostingView(rootView: AnyView(Color.clear))
        #expect(view.acceptsFirstMouse(for: nil))
    }

    @Test func thePointerComingAndGoingIsReported() {
        var hovers: [Bool] = []
        let view = CaptureChipHostingView(rootView: AnyView(Color.clear))
        view.hover = { hovers.append($0) }

        view.pointerEntered()
        view.pointerExited()

        #expect(hovers == [true, false])
    }

    @Test func theChipIsPlacedInTheCornerOfThePointersScreenWithoutBeingShown() throws {
        let window = SystemCaptureChipWindow(screens: { [main] }, pointer: { CGPoint(x: 700, y: 400) })

        let frame = window.place(content())

        let panel = try #require(window.panel)
        #expect(!panel.isVisible)
        #expect(frame.width > 0 && frame.height > 0)
        #expect(abs(frame.maxX - (1440 - CaptureChipGeometry.margin)) < 1)
        #expect(abs(frame.maxY - (862 - CaptureChipGeometry.margin)) < 1)
        #expect(panel.contentView is CaptureChipHostingView)
    }

    @Test func placingAgainReusesThePanelAndHidingDropsIt() throws {
        let window = SystemCaptureChipWindow(screens: { [main] }, pointer: { .zero })
        window.place(content())
        let first = try #require(window.panel)
        window.place(content())
        #expect(window.panel === first)

        window.hide()
        #expect(window.panel == nil)
        window.hide()
    }

    @Test func theViewsHoverHandlerIsTheOneOfTheContentMostRecentlyPlaced() throws {
        var first: [Bool] = [], second: [Bool] = []
        let window = SystemCaptureChipWindow(screens: { [main] }, pointer: { .zero })
        window.place(content { first.append($0) })
        window.place(content { second.append($0) })

        let hosting = try #require(window.panel?.contentView as? CaptureChipHostingView)
        hosting.pointerEntered()

        #expect(first.isEmpty)
        #expect(second == [true])
    }
}
