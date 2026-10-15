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
        var closeRequests = 0
        /// The displays now; a test changes them to unplug one.
        var displays: [PanelDisplay] = []
        /// What the window reports of being seen.
        var windowIsVisible = true
        var handler: (@MainActor (SystemPresenceEvent) -> Void)?
        var eventsStarted = 0
        var eventsStopped = 0
    }
    let recorder = Recorder()

    func makeController(
        placement: LyricsPanelPlacement = LyricsPanelPlacement(), displays: [PanelDisplay]? = nil, interface: NotchInterface? = nil
    ) -> LyricsPanelController {
        let recorder = recorder
        let interface = interface ?? self.interface
        recorder.displays = displays ?? [main, side]
        return LyricsPanelController(
            interface: interface, scheduler: scheduler, placement: placement, displays: { recorder.displays },
            present: { recorder.presented.append($0) }, onPlacementChange: { recorder.saved.append($0) },
            onCloseRequested: { recorder.closeRequests += 1 },
            systemEvents: SystemPresenceEvents(start: { handler in
                recorder.handler = handler
                recorder.eventsStarted += 1
                return {
                    recorder.handler = nil
                    recorder.eventsStopped += 1
                }
            }),
            windowIsVisible: { _ in recorder.windowIsVisible }
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

    @Test func aDragStartsAnywhereInTheContentButNotOnTheCloseButton() throws {
        let controller = makeController()
        controller.show(content: AnyView(Text("la la")))
        let panel = try #require(controller.panel)
        let container = try #require(panel.contentView as? LyricsPanelContainer)
        #expect(container.mouseDownCanMoveWindow)
        #expect(container.hosting.mouseDownCanMoveWindow)
        #expect(container.hosting.acceptsFirstMouse(for: nil))
        // SwiftUI would otherwise size the window to what the content wants, against the user's resizing.
        #expect(container.hosting.sizingOptions.isEmpty)
        #expect(!container.closeButton.mouseDownCanMoveWindow)
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
            let controller = makeController(displays: [main], interface: interface)
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

    // MARK: closing it

    @Test func theCloseButtonIsOnlyThereWhileThePointerIsOverThePanel() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let container = try #require(controller.panel?.contentView as? LyricsPanelContainer)
        #expect(container.closeButton.isHidden)
        container.setHovering(true)
        #expect(!container.closeButton.isHidden)
        container.setHovering(false)
        #expect(container.closeButton.isHidden)
        controller.hide()
    }

    @Test func theCloseButtonSitsInTheTopRightCornerAndKeepsThereWhenResized() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        let container = try #require(panel.contentView as? LyricsPanelContainer)
        container.layoutSubtreeIfNeeded()
        let button = container.closeButton
        #expect(button.frame.maxX < container.bounds.maxX && button.frame.maxX > container.bounds.maxX - 20)
        #expect(button.frame.maxY < container.bounds.maxY && button.frame.maxY > container.bounds.maxY - 20)
        panel.setFrame(CGRect(x: 100, y: 200, width: 700, height: 300), display: false)
        container.layoutSubtreeIfNeeded()
        #expect(container.closeButton.frame.maxX > container.bounds.maxX - 20)
        #expect(container.closeButton.frame.maxY > container.bounds.maxY - 20)
        #expect(container.closeButton.toolTip == "Đóng bảng lời")
        #expect(container.closeButton.accessibilityLabel() == "Đóng bảng lời")
        controller.hide()
    }

    @Test func pressingTheCloseButtonOrChoosingItInTheMenuAsksToClose() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let container = try #require(controller.panel?.contentView as? LyricsPanelContainer)
        container.closeButton.performClick(nil)
        #expect(recorder.closeRequests == 1)
        let menu = try #require(container.hosting.menu)
        #expect(menu === container.menu)
        #expect(menu.items.map(\.title) == ["Đóng bảng lời"])
        let item = try #require(menu.items.first)
        _ = item.target?.perform(item.action, with: item)
        #expect(recorder.closeRequests == 2)
        controller.hide()
    }

    // MARK: being seen

    @Test func thePanelIsSeenOnceItsWindowIs() {
        let controller = makeController()
        recorder.windowIsVisible = false
        controller.show(content: AnyView(Color.clear))
        #expect(!controller.presence.isOnScreen)
        controller.hide()
        recorder.windowIsVisible = true
        controller.show(content: AnyView(Color.clear))
        #expect(controller.presence.isOnScreen)
        controller.hide()
    }

    @Test func aChangeOfTheWindowsOcclusionReachesThePresence() async throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        #expect(controller.presence.isOnScreen)
        recorder.windowIsVisible = false
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        #expect(await eventually { !controller.presence.isOnScreen })
        recorder.windowIsVisible = true
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        #expect(await eventually { controller.presence.isOnScreen })
        controller.hide()
    }

    @Test func displaysAsleepAndALockedScreenTakeThePanelOffScreenWhileItIsUp() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let handler = try #require(recorder.handler)
        handler(.displaysSlept)
        #expect(!controller.presence.isOnScreen)
        handler(.displaysWoke)
        #expect(controller.presence.isOnScreen)
        handler(.screenLocked)
        #expect(!controller.presence.isOnScreen)
        handler(.screenUnlocked)
        #expect(controller.presence.isOnScreen)
        controller.hide()
    }

    @Test func theSystemIsOnlyListenedToWhileThePanelIsUpAndAHiddenPanelIsNeverSeen() throws {
        let controller = makeController()
        #expect(recorder.eventsStarted == 0)
        controller.show(content: AnyView(Color.clear))
        controller.show(content: AnyView(Color.clear))
        #expect(recorder.eventsStarted == 1)
        let handler = try #require(recorder.handler)
        handler(.displaysSlept)
        controller.hide()
        #expect(recorder.eventsStopped == 1)
        #expect(!controller.presence.isOnScreen)
        // The next panel starts clean: the sleep it never saw wake is forgotten.
        controller.show(content: AnyView(Color.clear))
        #expect(controller.presence.isOnScreen)
        #expect(recorder.eventsStarted == 2)
        controller.hide()
    }

    // MARK: displays that come and go while it is up

    @Test func aDisplayThatGoesMovesThePanelToTheMainOneAndItGoesHomeWhenTheDisplayIsBack() throws {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(2000, 400, 600, 180), among: [main, side])
        let controller = makeController(placement: placement)
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        #expect(panel.frame == rect(2000, 400, 600, 180))

        recorder.displays = [main]
        controller.screensChanged()
        #expect(panel.frame == LyricsPanelPlacement.defaultFrame(on: main))
        // The system moving the window as well is not the user's choice.
        panel.setFrame(rect(1000, 500, 600, 180), display: false)
        controller.frameChanged()
        scheduler.advance(by: .seconds(2))
        #expect(recorder.saved.isEmpty)

        recorder.displays = [main, side]
        controller.screensChanged()
        #expect(panel.frame == rect(2000, 400, 600, 180))
        scheduler.advance(by: .seconds(2))
        #expect(recorder.saved.isEmpty)
        controller.hide()
    }

    @Test func aMoveTheUserMakesAfterTheDisplaysSettleIsRememberedAsEver() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        recorder.displays = [main]
        controller.screensChanged()
        scheduler.advance(by: .seconds(2))
        panel.setFrame(rect(300, 300, 500, 150), display: false)
        controller.frameChanged()
        scheduler.advance(by: .seconds(1))
        #expect(recorder.saved.count == 1)
        #expect(recorder.saved.last?.lastDisplay == "MAIN")
        controller.hide()
    }

    @Test func aChangeOfDisplaysThatLeavesThePanelWhereItBelongsMovesNothing() throws {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(200, 300, 500, 150), among: [main, side])
        let controller = makeController(placement: placement)
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        controller.screensChanged()
        #expect(panel.frame == rect(200, 300, 500, 150))
        controller.hide()
    }

    @Test func aMoveWaitingToBeRememberedWhenTheDisplaysChangeIsNotKept() throws {
        let controller = makeController()
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        panel.setFrame(rect(1500, 300, 500, 150), display: false)
        controller.frameChanged()
        recorder.displays = [main]
        controller.screensChanged()
        scheduler.advance(by: .seconds(2))
        #expect(recorder.saved.isEmpty)
        controller.hide()
        #expect(recorder.saved.isEmpty)
    }

    @Test func theSystemsReportOfNewScreensReachesTheController() async throws {
        var placement = LyricsPanelPlacement()
        placement.remember(rect(2000, 400, 600, 180), among: [main, side])
        let controller = makeController(placement: placement)
        controller.show(content: AnyView(Color.clear))
        let panel = try #require(controller.panel)
        recorder.displays = [main]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(await eventually { panel.frame == LyricsPanelPlacement.defaultFrame(on: main) })
        controller.hide()
    }
}
