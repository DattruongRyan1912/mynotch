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

    /// A translation as the chip shows it: all of it, with the first line of the original over it.
    func translation(lines count: Int, caption: String? = "Good morning my friends") -> SelectionChipContent {
        let text = (1...count).map { "Chào buổi sáng các bạn của tôi số \($0)" }.joined(separator: "\n")
        return SelectionChipContent(kind: .translation, text: text, caption: caption, open: {}, deny: {}, hover: { _ in })
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

    @Test func theButtonForDenyingTheAppIsOnlyThereWhenTheAppCanBeDenied() {
        func width(canDeny: Bool) -> CGFloat {
            let view = SelectionChipView(content: content(canDeny: canDeny), interface: interface)
            return NSHostingView(rootView: view).fittingSize.width
        }
        #expect(width(canDeny: true) > width(canDeny: false))
    }

    // MARK: a whole translation

    @Test func aLongTranslationGrowsTheChipAndKeepsItBelowTheSelection() throws {
        let window = makeWindow()
        let anchor = CGRect(x: 500, y: 600, width: 100, height: 20)
        let frame = window.place(translation(lines: 30), near: anchor)
        #expect(frame.height > 150)
        #expect(frame.height <= SelectionChipLayout.maxHeight)
        #expect(frame.maxY < anchor.minY, "below the selection")
        #expect(screen.visibleFrame.contains(frame))
        window.hide()
    }

    @Test func aTallChipNearTheBottomGoesAboveAndNeverCoversTheSelection() throws {
        let window = makeWindow()
        let anchor = CGRect(x: 500, y: 60, width: 100, height: 20)
        let frame = window.place(translation(lines: 30), near: anchor)
        #expect(frame.minY >= anchor.maxY)
        #expect(!frame.intersects(anchor))
        #expect(screen.visibleFrame.contains(frame))
        window.hide()
    }

    @Test func aTallChipNearTheTopGoesBelow() throws {
        let window = makeWindow()
        let anchor = CGRect(x: 500, y: 830, width: 100, height: 20)
        let frame = window.place(translation(lines: 30), near: anchor)
        #expect(frame.maxY <= anchor.minY)
        #expect(!frame.intersects(anchor))
        window.hide()
    }

    @Test func whenNeitherSideHasRoomForAllOfItTheChipShrinksInsteadOfCoveringTheSelection() throws {
        let small = ScreenArea(frame: CGRect(x: 0, y: 0, width: 800, height: 320), visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 300))
        let window = SystemSelectionChipWindow(interface: interface) { [small] in [small] }
        let anchor = CGRect(x: 300, y: 140, width: 100, height: 20)
        let frame = window.place(translation(lines: 30), near: anchor)
        #expect(!frame.intersects(anchor))
        #expect(small.visibleFrame.contains(frame))
        #expect(frame.height <= SelectionGeometry.room(besides: anchor, screens: [small]) + 1)
        window.hide()
    }

    @Test func aChipWithLessRoomThanItsSmallestFallsBackToTheCompactLineInsteadOfCoveringTheSelection() throws {
        // 64 pt below the selection and 74 above: less than two lines of translation need.
        let tight = ScreenArea(frame: CGRect(x: 0, y: 0, width: 800, height: 190), visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 170))
        let window = SystemSelectionChipWindow(interface: interface) { [tight] in [tight] }
        let anchor = CGRect(x: 300, y: 70, width: 100, height: 20)
        #expect(SelectionGeometry.room(besides: anchor, screens: [tight]) < SelectionChipLayout.minChipHeight)
        let frame = window.place(translation(lines: 30), near: anchor)
        #expect(frame.height < 50)
        #expect(!frame.intersects(anchor))
        #expect(tight.visibleFrame.contains(frame))
        window.hide()
    }

    @Test func aChipWithJustEnoughRoomStaysWhole() throws {
        let enough = ScreenArea(frame: CGRect(x: 0, y: 0, width: 800, height: 230), visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 210))
        let window = SystemSelectionChipWindow(interface: interface) { [enough] in [enough] }
        let anchor = CGRect(x: 300, y: 70, width: 100, height: 20)
        #expect(SelectionGeometry.room(besides: anchor, screens: [enough]) >= SelectionChipLayout.minChipHeight)
        let frame = window.place(translation(lines: 30), near: anchor)
        #expect(frame.height >= SelectionChipLayout.minChipHeight)
        #expect(!frame.intersects(anchor))
        window.hide()
    }

    @Test func aShortTranslationStaysCompactAndAChipIsNarrowerThanTheWidest() throws {
        let window = makeWindow()
        let short = SelectionChipContent(kind: .translation, text: "Xin chào", caption: nil, open: {}, deny: {}, hover: { _ in })
        let frame = window.place(short, near: CGRect(x: 500, y: 400, width: 100, height: 20))
        #expect(frame.height < 90)
        #expect(frame.width < SelectionChipLayout.maxWidth)
        window.hide()
    }

    @Test func aReplacementChipMovesAndResizesThePanel() throws {
        let window = makeWindow()
        let first = window.place(translation(lines: 2), near: CGRect(x: 500, y: 400, width: 100, height: 20))
        let second = window.place(translation(lines: 8), near: CGRect(x: 500, y: 400, width: 100, height: 20))
        #expect(second.height > first.height)
        window.hide()
    }

    // MARK: the menu

    /// A chip in a window that is never shown, which is what makes it listen for menus.
    func hostedChip(
        center: NotificationCenter, log: HoverLog, pointerIsOver: Bool
    ) -> (hosting: SelectionChipHostingView, window: NSWindow) {
        let hosting = SelectionChipHostingView(rootView: AnyView(Color.clear), notifications: center, pointerIsOverChip: { pointerIsOver }) {
            log.record($0)
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 30), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        return (hosting, window)
    }

    @Test func aMenuOpenedFromTheChipHoldsItAndLeavesItWhenTheMenuEndsAwayFromIt() {
        let center = NotificationCenter()
        let log = HoverLog()
        let (_, window) = hostedChip(center: center, log: log, pointerIsOver: false)
        center.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
        #expect(log.values == [true])
        center.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
        #expect(log.values == [true, false])
        window.contentView = nil
    }

    @Test func aMenuThatEndsWithThePointerBackOnTheChipKeepsHolding() {
        let center = NotificationCenter()
        let log = HoverLog()
        let (_, window) = hostedChip(center: center, log: log, pointerIsOver: true)
        center.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
        center.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
        #expect(log.values == [true])
        window.contentView = nil
    }

    @Test func aChipThatLeftItsWindowStopsListeningForMenus() {
        let center = NotificationCenter()
        let log = HoverLog()
        let (_, window) = hostedChip(center: center, log: log, pointerIsOver: false)
        window.contentView = nil
        center.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
        #expect(log.values.isEmpty)
    }

    @Test func aChipThatWasNeverInAWindowDoesNotListenForMenus() {
        let center = NotificationCenter()
        let log = HoverLog()
        let hosting = SelectionChipHostingView(rootView: AnyView(Color.clear), notifications: center, pointerIsOverChip: { false }) {
            log.record($0)
        }
        center.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
        #expect(log.values.isEmpty)
        withExtendedLifetime(hosting) {}
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
