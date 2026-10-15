import AppKit
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import MediaModule

/// The floating panel's window. No panel is ever ordered in: `present` records what would be shown instead, so nothing
/// appears on a screen and nothing can be captured.
@Suite struct LyricsPanelControllerTests {
    let main = PanelDisplay(
        key: "MAIN", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805)
    )
    let side = PanelDisplay(
        key: "SIDE", frame: CGRect(x: 1440, y: -100, width: 1920, height: 1080), visibleFrame: CGRect(x: 1440, y: -100, width: 1920, height: 1055)
    )
    let scheduler = ManualScheduler()
    let interface = NotchInterface()
    final class Recorder {
        var presented: [NSPanel] = []
        var saved: [LyricsPanelPlacement] = []
    }
    let recorder = Recorder()

    func makeController(placement: LyricsPanelPlacement = LyricsPanelPlacement(), displays: [PanelDisplay]? = nil) -> LyricsPanelController {
        let shown = displays ?? [main, side]
        let recorder = recorder
        return LyricsPanelController(
            interface: interface, scheduler: scheduler, placement: placement, displays: { shown },
            present: { recorder.presented.append($0) }, onPlacementChange: { recorder.saved.append($0) }
        )
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect { CGRect(x: x, y: y, width: width, height: height) }

    // MARK: the window

    @Test func theWindowNeverTakesTheKeyboardOrActivatesTheApp() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.canBecomeKey && !panel.canBecomeMain)
        #expect(!panel.hidesOnDeactivate)
        controller.hide()
    }

    @Test func theWindowIsBorderlessResizableAndDraggableFromAnywhere() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.resizable))
        #expect(panel.isMovableByWindowBackground)
        #expect(panel.minSize == LyricsPanelPlacement.minimumSize)
        #expect(!panel.isOpaque && panel.backgroundColor == .clear)
        controller.hide()
    }

    @Test func theWindowFloatsOverOtherWindowsOnEverySpaceAndOverFullScreenApps() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        #expect(panel.level == .floating)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
        controller.hide()
    }

    @Test func aDragStartsAnywhereInTheContent() throws {
        let controller = makeController()
        controller.show(content: AnyView(Text("la la")))
        let panel = try #require(controller.panel)
        let hosting = try #require(panel.contentView as? LyricsHostingView)
        #expect(hosting.mouseDownCanMoveWindow)
        #expect(hosting.acceptsFirstMouse(for: nil))
        // SwiftUI would otherwise size the window to what the content wants, against the user's resizing.
        #expect(hosting.sizingOptions.isEmpty)
        controller.hide()
    }

    // MARK: showing and hiding

    @Test func showingPutsThePanelWhereItWasLeftAndPresentsItOnce() throws {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(200, 300, 500, 150), among: [main, side])
        let controller = makeController(placement: placement)
        controller.show(content: AnyView(Color.clear))
        #expect(controller.isShown)
        #expect(controller.panel?.frame == rect(200, 300, 500, 150))
        #expect(recorder.presented.count == 1)
        controller.show(content: AnyView(Color.clear))
        #expect(recorder.presented.count == 2)
        #expect(recorder.presented[0] === recorder.presented[1])
        controller.hide()
    }

    @Test func theFirstTimeItOpensAtTheDefaultPlace() {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        #expect(controller.panel?.frame == LyricsPanelPlacement.defaultFrame(on: main))
        controller.hide()
    }

    @Test func hidingLetsTheWindowAndItsViewsGo() {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = controller.panel
        controller.hide()
        #expect(!controller.isShown)
        #expect(controller.panel == nil)
        #expect(panel?.contentView == nil || panel?.isVisible == false)
        controller.hide()
        #expect(!controller.isShown)
    }

    @Test func showingAgainAfterHidingMakesAFreshPanelWhereTheLastOneWas() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let first = try #require(controller.panel)
        first.setFrame(rect(300, 200, 520, 160), display: false)
        controller.frameChanged()
        controller.hide()
        controller.show(content: AnyView(Color.clear))
        let second = try #require(controller.panel)
        #expect(second !== first)
        #expect(second.frame == rect(300, 200, 520, 160))
        controller.hide()
    }

    // MARK: settings

    @Test func opacityAndClickThroughApplyAtOnceAndWhileItIsUp() throws {
        let controller = makeController()
        controller.apply(opacity: 0.6, clickThrough: true)
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        #expect(abs(panel.alphaValue - 0.6) < 1e-6)
        #expect(panel.ignoresMouseEvents)
        controller.apply(opacity: 1, clickThrough: false)
        #expect(panel.alphaValue == 1)
        #expect(!panel.ignoresMouseEvents)
        controller.hide()
    }

    @Test func opacityStaysWithinWhatCanBeSeen() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        controller.apply(opacity: 0, clickThrough: false)
        #expect(abs(panel.alphaValue - LyricsPanelController.opacityRange.lowerBound) < 1e-6)
        controller.apply(opacity: 7, clickThrough: false)
        #expect(panel.alphaValue == 1)
        controller.hide()
    }

    // MARK: hiding from capture

    @Test func theWindowIsHiddenFromCaptureFromTheFirstMomentWhenTheSettingSaysSo() throws {
        for (hiding, expected) in [(CaptureHiding.never, NSWindow.SharingType.readOnly), (.always, .none), (.whenCollapsed, .none)] {
            let interface = NotchInterface()
            interface.captureHiding = hiding
            let controller = LyricsPanelController(
                interface: interface, scheduler: scheduler, placement: LyricsPanelPlacement(), displays: { [main] },
                present: { _ in }, onPlacementChange: { _ in }
            )
            controller.show(content: AnyView(Color.clear))
            #expect(controller.panel?.sharingType == expected, "\(hiding)")
            controller.hide()
        }
    }

    @Test func theWindowFollowsTheSettingWhileItIsUpAndStopsWhenItGoes() async throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        #expect(panel.sharingType == .readOnly)
        interface.captureHiding = .always
        #expect(await eventually { panel.sharingType == .none })
        controller.hide()
        interface.captureHiding = .never
        try? await Task.sleep(for: .milliseconds(50))
        #expect(panel.sharingType == .none)
    }

    // MARK: remembering where it is left

    @Test func aMoveIsRememberedOnceTheUserStopsMovingIt() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        for x in stride(from: 100.0, through: 400, by: 50) {
            panel.setFrame(rect(x, 300, 500, 150), display: false)
            controller.frameChanged()
            scheduler.advance(by: .milliseconds(100))
        }
        #expect(recorder.saved.isEmpty)
        #expect(scheduler.pendingCount == 1)
        scheduler.advance(by: .seconds(1))
        #expect(recorder.saved.count == 1)
        #expect(recorder.saved.last?.restoredFrame(among: [main, side]) == rect(400, 300, 500, 150))
        controller.hide()
    }

    @Test func movingToAnotherDisplayIsRememberedForThatDisplay() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        panel.setFrame(rect(2000, 400, 600, 180), display: false)
        controller.frameChanged()
        scheduler.advance(by: .seconds(1))
        #expect(recorder.saved.last?.lastDisplay == "SIDE")
        #expect(recorder.saved.last?.restoredFrame(among: [main, side]) == rect(2000, 400, 600, 180))
        controller.hide()
    }

    @Test func theMovesAndResizesTheWindowReportsReachTheController() async throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        panel.setFrame(rect(300, 300, 480, 140), display: false)
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: panel)
        #expect(await eventually { scheduler.pendingCount == 1 })
        scheduler.advance(by: .seconds(1))
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: panel)
        #expect(await eventually { scheduler.pendingCount == 1 })
        scheduler.advance(by: .seconds(1))
        #expect(recorder.saved.count == 2)
        controller.hide()
    }

    @Test func openingThePanelIsNotTheUserMovingIt() throws {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(200, 300, 500, 150), among: [main, side])
        let controller = makeController(placement: placement)
        controller.show(content: AnyView(Color.clear))
        #expect(scheduler.pendingCount == 0)
        scheduler.advance(by: .seconds(1))
        #expect(recorder.saved.isEmpty)
        controller.hide()
        #expect(recorder.saved.isEmpty)
    }

    @Test func hidingRightAfterAMoveStillKeepsIt() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        panel.setFrame(rect(250, 350, 500, 150), display: false)
        controller.frameChanged()
        controller.hide()
        #expect(recorder.saved.count == 1)
        #expect(recorder.saved.last?.restoredFrame(among: [main, side]) == rect(250, 350, 500, 150))
        #expect(scheduler.pendingCount == 0)
    }

    @Test func aHiddenPanelNoLongerHearsTheWindow() async throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        controller.hide()
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: panel)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(scheduler.pendingCount == 0)
        #expect(recorder.saved.isEmpty)
    }
}
