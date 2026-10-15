import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import TranslationModule

/// The chip's panel and its SwiftUI content, built and measured but never put on a screen.
@Suite struct SelectionChipPanelTests {
    let interface = NotchInterface()
    let screen = ScreenArea(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))

    func makeWindow() -> SystemSelectionChipWindow {
        SystemSelectionChipWindow(interface: interface) { [screen] in [screen] }
    }

    func content(_ text: String = "5 ft 11 in → 180 cm", canDeny: Bool = true) -> SelectionChipContent {
        var deny: (@MainActor () -> Void)?
        if canDeny { deny = {} }
        return SelectionChipContent(kind: .conversion, text: text, open: {}, deny: deny, hover: { _ in })
    }

    @Test func isABorderlessNonActivatingPanelThatNeverTakesTheKeyboard() {
        let panel = SelectionChipPanel()
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.isFloatingPanel)
        #expect(panel.level == .floating)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!panel.ignoresMouseEvents)
        #expect(!panel.isVisible)
    }

    @Test func followsTheHideFromRecordingSetting() throws {
        interface.captureHiding = .always
        let window = makeWindow()
        window.place(content(), near: CGRect(x: 500, y: 400, width: 100, height: 20))
        #expect(try #require(window.panel).sharingType == .none)
        window.hide()
        interface.captureHiding = .never
        window.place(content(), near: CGRect(x: 500, y: 400, width: 100, height: 20))
        #expect(try #require(window.panel).sharingType == .readOnly)
        window.hide()
    }

    @Test func placesTheChipBesideTheSelectionWithoutShowingIt() throws {
        let window = makeWindow()
        let frame = window.place(content(), near: CGRect(x: 500, y: 400, width: 100, height: 20))
        let panel = try #require(window.panel)
        #expect(!panel.isVisible)
        #expect(panel.frame == frame)
        #expect(frame.width > 80)
        #expect(frame.height > 18 && frame.height < 60)
        // Just below the selection, centred on it.
        #expect(frame.maxY < 400)
        #expect(abs(frame.midX - 550) < 1)
        #expect(screen.visibleFrame.contains(frame))
        window.hide()
    }

    @Test func aLongTextStaysWithinTheChipsWidth() throws {
        let window = makeWindow()
        let frame = window.place(content(String(repeating: "dài ", count: 150)), near: CGRect(x: 500, y: 400, width: 100, height: 20))
        #expect(frame.width <= SelectionChipView.maxWidth)
        window.hide()
    }

    @Test func theMenuForDenyingTheAppIsOnlyThereWhenTheAppCanBeDenied() {
        func width(canDeny: Bool) -> CGFloat {
            let view = SelectionChipView(content: content(canDeny: canDeny), interface: interface)
            return NSHostingView(rootView: view).fittingSize.width
        }
        #expect(width(canDeny: true) > width(canDeny: false))
    }

    @Test func hidingDropsThePanel() {
        let window = makeWindow()
        window.place(content(), near: CGRect(x: 500, y: 400, width: 100, height: 20))
        #expect(window.panel != nil)
        window.hide()
        #expect(window.panel == nil)
        window.hide()
    }

    @Test func aSecondPlacementReusesThePanelAndMovesIt() throws {
        let window = makeWindow()
        window.place(content(), near: CGRect(x: 500, y: 400, width: 100, height: 20))
        let panel = try #require(window.panel)
        let frame = window.place(content("22,2 °C"), near: CGRect(x: 700, y: 300, width: 100, height: 20))
        #expect(window.panel === panel)
        #expect(panel.frame == frame)
        window.hide()
    }

    @Test func acceptsTheFirstClickAndWatchesThePointerEvenWhileInactive() {
        let hosting = SelectionChipHostingView(rootView: AnyView(Color.clear), hover: { _ in })
        #expect(hosting.acceptsFirstMouse(for: nil))
        hosting.frame = CGRect(x: 0, y: 0, width: 100, height: 30)
        hosting.updateTrackingAreas()
        #expect(hosting.trackingAreas.contains { $0.options.contains(.activeAlways) && $0.options.contains(.mouseEnteredAndExited) })
    }

    @Test func thePointerEnteringAndLeavingIsReported() {
        let log = HoverLog()
        let hosting = SelectionChipHostingView(rootView: AnyView(Color.clear)) { log.record($0) }
        hosting.pointerEntered()
        hosting.pointerExited()
        #expect(log.values == [true, false])
    }
}

final class HoverLog {
    private(set) var values: [Bool] = []
    func record(_ value: Bool) { values.append(value) }
}
