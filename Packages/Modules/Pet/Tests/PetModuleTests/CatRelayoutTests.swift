import AppKit
import NotchUI
import Testing
@testable import PetModule

/// The wings are where the camera is on the screen the window is on, and that changes without the container's bounds changing: the window
/// moves, it changes screen, the screens are arranged again, a window that had no screen when it was laid out gets one. Each of these lays
/// them out again.
@Suite(.serialized) @MainActor struct CatRelayoutTests {
    /// The camera as the screen would report it if it were at 760 to 990 of 1800 and not at 790 to 1010: the row, which begins at 690, has it
    /// from 70 to 300.
    static let movedAreas: (frame: CGRect, left: CGFloat?, right: CGFloat?) = (Screens.mac.frame, 760, 810)

    /// What a window moved or a screen changed is told with, in the order of the three the container listens to.
    static let triggers: [Notification.Name] = [
        NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification, NSApplication.didChangeScreenParametersNotification,
    ]

    func post(_ name: Notification.Name, _ rig: BodyRig) {
        // The two of a window are about it; the one of the screens is about no window.
        let object: Any? = name == NSApplication.didChangeScreenParametersNotification ? nil : rig.window
        rig.windowNotifications.post(name: name, object: object)
    }

    func wings(_ rig: BodyRig) throws -> (left: CatSpriteView, right: CatSpriteView) {
        (try #require(rig.container.leftWing), try #require(rig.container.rightWing))
    }

    func moveWindow(_ rig: BodyRig, by dx: CGFloat) {
        rig.window.setFrameOrigin(CGPoint(x: rig.window.frame.minX + dx, y: rig.window.frame.minY))
    }

    // MARK: After a move

    @Test func aWindowThatMovedWithoutItsBoundsChangingHasTheWingsFollowIt() throws {
        let rig = BodyRig(geometry: Screens.hardware)
        rig.show()
        let (left, right) = try wings(rig)
        #expect(left.frame == CGRect(x: 0, y: 0, width: 100, height: 38) && right.frame == CGRect(x: 320, y: 0, width: 100, height: 38))
        // 30 points to the right: the camera, which is where the screen has it, is 30 points further to the left in the row.
        moveWindow(rig, by: 30)
        post(NSWindow.didMoveNotification, rig)
        rig.container.layoutSubtreeIfNeeded()
        #expect(rig.container.bounds.width == 420, "the bounds did not change")
        #expect(left.frame == CGRect(x: 0, y: 0, width: 70, height: 38) && right.frame == CGRect(x: 290, y: 0, width: 130, height: 38))
        #expect(try #require(left.screenFrame).maxX == 790 && right.screenFrame?.minX == 1010, "they still end and begin at the camera's edges")
    }

    @Test func aScreenThatReportsTheCameraElsewhereHasTheWingsFollowItOnAChangeOfScreenAndOnAChangeOfTheScreens() throws {
        for name in [NSWindow.didChangeScreenNotification, NSApplication.didChangeScreenParametersNotification] {
            let rig = BodyRig(geometry: Screens.hardware)
            rig.show()
            let (left, right) = try wings(rig)
            #expect(left.frame.width == 100)
            rig.container.screenAreas = { _ in Self.movedAreas }
            post(name, rig)
            rig.container.layoutSubtreeIfNeeded()
            #expect(left.frame.width == 70 && right.frame.minX == 300 && right.frame.width == 120, "\(name.rawValue): \(left.frame) \(right.frame)")
        }
    }

    @Test func aContainerLaidOutWhereTheWindowWasNotHasTheWingsRightOnceTheWindowIsInPlace() throws {
        // The window is nowhere near the screen's top row when the wings are first laid out: the camera is off the row, the cutout is clamped
        // to its edge, and one wing is as wide as the whole row.
        let rig = BodyRig(geometry: Screens.hardware)
        let place = rig.window.frame.origin
        rig.window.setFrameOrigin(CGPoint(x: 5000, y: 5000))
        rig.show()
        let (left, right) = try wings(rig)
        #expect(left.frame.width == 0 && right.frame.width == 420, "the stale layout: \(left.frame) \(right.frame)")
        rig.window.setFrameOrigin(place)
        post(NSWindow.didMoveNotification, rig)
        rig.container.layoutSubtreeIfNeeded()
        #expect(left.frame == CGRect(x: 0, y: 0, width: 100, height: 38) && right.frame == CGRect(x: 320, y: 0, width: 100, height: 38))
        #expect(rig.stage.attachedHosts.count == 2)
    }

    @Test func aContainerLaidOutWithNoWindowHasTheWingsRightTheMomentItIsInOne() throws {
        let rig = BodyRig(geometry: Screens.hardware)
        rig.container.screenAreas = { _ in Self.movedAreas }
        rig.container.configure(geometry: rig.geometry)
        rig.container.layoutSubtreeIfNeeded()
        let (left, right) = try wings(rig)
        #expect(left.frame.width == 100 && right.frame.minX == 320, "from the geometry: there is no screen to ask")
        // It goes into its window and nothing else happens: no configure, no change of bounds.
        rig.window.contentView?.addSubview(rig.container)
        rig.container.layoutSubtreeIfNeeded()
        #expect(left.frame.width == 70 && right.frame.minX == 300, "\(left.frame) \(right.frame)")
    }

    @Test func aWindowThatHasNoScreenYetHasTheWingsLaidOutAgainWhenItGetsOne() throws {
        let rig = BodyRig(geometry: Screens.hardware)
        var hasScreen = false
        rig.container.screenAreas = { _ in hasScreen ? Self.movedAreas : nil }
        rig.show()
        let (left, right) = try wings(rig)
        #expect(left.frame.width == 100, "the geometry's camera, for want of a screen")
        hasScreen = true
        post(NSWindow.didChangeScreenNotification, rig)
        rig.container.layoutSubtreeIfNeeded()
        #expect(left.frame.width == 70 && right.frame.minX == 300 && right.frame.width == 120)
        _ = right
    }

    @Test func withReduceMotionTheRestingCatFollowsTheWingsToo() throws {
        let rig = BodyRig(geometry: Screens.hardware, reducesMotion: true)
        rig.show()
        let (left, _) = try wings(rig)
        #expect(!rig.stage.isTicking, "nothing wakes for this cat, so only what it is told can move it")
        moveWindow(rig, by: 30)
        post(NSWindow.didMoveNotification, rig)
        rig.container.layoutSubtreeIfNeeded()
        #expect(left.frame.width == 70)
        #expect(left.sprite.position.x == left.field.lane.restingX, "set down again in the new lane")
        #expect(CGRect(origin: left.sprite.position, size: left.sprite.bounds.size).maxX <= left.bounds.width, "whole in the view")
    }

    // MARK: What lays them out

    @Test func eachOfTheThreeNotificationsLaysTheWingsOutAgain() {
        for name in Self.triggers {
            let rig = BodyRig(geometry: Screens.hardware)
            rig.show()
            #expect(!rig.container.needsLayout, "laid out")
            post(name, rig)
            #expect(rig.container.needsLayout, "\(name.rawValue)")
        }
    }

    @Test func aNotificationAboutAnotherWindowLaysNothingOut() {
        let rig = BodyRig(geometry: Screens.hardware)
        rig.show()
        let other = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        other.isReleasedWhenClosed = false
        for name in [NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
            rig.windowNotifications.post(name: name, object: other)
            #expect(!rig.container.needsLayout, "\(name.rawValue)")
        }
    }

    @Test func theObserversAreGoneWhenTheViewLeavesItsWindowAndBackWhenItComes() {
        let rig = BodyRig(geometry: Screens.hardware)
        rig.show()
        rig.hide()
        rig.container.needsLayout = false
        for name in Self.triggers {
            post(name, rig)
            #expect(!rig.container.needsLayout, "left: \(name.rawValue)")
        }
        rig.show()
        for name in Self.triggers {
            #expect(!rig.container.needsLayout)
            post(name, rig)
            #expect(rig.container.needsLayout, "back: \(name.rawValue)")
            rig.container.layoutSubtreeIfNeeded()
        }
    }

    @Test func aViewThatMovesToAnotherWindowListensToThatOneAndNoLongerToTheFirst() {
        let rig = BodyRig(geometry: Screens.hardware)
        rig.show()
        let second = NSWindow(contentRect: rig.window.frame, styleMask: .borderless, backing: .buffered, defer: true)
        second.isReleasedWhenClosed = false
        second.contentView?.addSubview(rig.container)
        rig.container.layoutSubtreeIfNeeded()
        #expect(!rig.container.needsLayout)
        rig.windowNotifications.post(name: NSWindow.didMoveNotification, object: rig.window)
        #expect(!rig.container.needsLayout, "not the first window's any more")
        rig.windowNotifications.post(name: NSWindow.didMoveNotification, object: second)
        #expect(rig.container.needsLayout, "the second's")
    }

    @Test func eachTriggerStopsWithTheViewAndLeavesNothingBehindOnTheRealCenterEither() {
        // The real center, where a container that is never given another listens: it is added and removed with the window, and a
        // notification the app posts reaches nothing once the view has gone.
        let rig = BodyRig(geometry: Screens.hardware)
        let container = CatBodyContainer(stages: rig.stages)
        #expect(container.notifications === NotificationCenter.default)
        container.frame = rig.container.frame
        rig.window.contentView?.addSubview(container)
        container.configure(geometry: rig.geometry)
        container.layoutSubtreeIfNeeded()
        container.removeFromSuperview()
        container.needsLayout = false
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(!container.needsLayout)
    }

    // MARK: What the stage sees

    @Test func theStageSeesAViewThatIsNotWhereItWasArrangedAndAsksItsContainerToLayOutAgain() throws {
        let rig = BodyRig(geometry: Screens.hardware)
        rig.show()
        let (left, _) = try wings(rig)
        rig.advance(1)
        // The view's frame is changed without the container laying it out: the stage's own look at it, a quarter of a second later, is
        // what notices.
        left.setFrameSize(NSSize(width: 60, height: 38))
        rig.container.needsLayout = false
        rig.advance(0.25)
        #expect(rig.container.needsLayout, "the container is asked to lay out its views again")
        rig.container.layoutSubtreeIfNeeded()
        #expect(left.frame.width == 100)
    }

    @Test func theStagesOwnLookFindsAWindowThatMovedAndWasNotToldAndOneThatGotItsScreenInSilence() throws {
        // Window moved, nobody told.
        let moved = BodyRig(geometry: Screens.hardware)
        moved.show()
        moved.advance(1)
        moveWindow(moved, by: 30)
        moved.advance(0.25)
        moved.container.layoutSubtreeIfNeeded()
        let left = try wings(moved).left
        #expect(left.frame.width == 70, "\(left.frame)")

        // Screen arrived, nobody told.
        let rig = BodyRig(geometry: Screens.hardware)
        var hasScreen = false
        rig.container.screenAreas = { _ in hasScreen ? Self.movedAreas : nil }
        rig.show()
        rig.advance(1)
        hasScreen = true
        rig.advance(0.25)
        rig.container.layoutSubtreeIfNeeded()
        #expect(try wings(rig).left.frame.width == 70)
    }

    @Test func aLookThatFindsNothingMovedLaysNothingOutAndShowsNothingAgain() {
        let rig = BodyRig(geometry: Screens.hardware)
        rig.show()
        rig.advance(1)
        rig.container.needsLayout = false
        let shown = rig.stage.presentations
        for _ in 0..<40 { rig.advance(0.25) }
        #expect(!rig.container.needsLayout, "ten seconds with everything where it was")
        #expect(rig.stage.presentations - shown <= 12, "only what the cat does shows it, not the looks")
    }
}
