import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import PetModule

/// One cat for each kind of notch: the Mac's own notch and a pill (or a virtual notch) are not the same world, and do not share a brain, the
/// places it must not stop at, the pointer it watches or a click.
@Suite(.serialized) @MainActor struct CatStagesTests {
    /// The Mac's notch and a pill on the display beside it, with one scheduler, one set of things read and one pair of stages.
    func pair(seed: UInt64 = 4) -> (mac: BodyRig, pill: BodyRig) {
        let mac = BodyRig(geometry: Screens.hardware, seed: seed)
        return (mac, BodyRig(geometry: Screens.pill, sharing: mac))
    }

    func reacted(_ stage: CatStage) -> Bool { stage.plan?.move == .pounce || stage.plan?.move == .startled }

    func click(_ host: CatSpriteView) throws {
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: host.window?.windowNumber ?? 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
        host.mouseDown(with: event)
    }

    // MARK: The stages

    @Test func eachKindOfNotchHasACatOfItsOwnAndTheSameOneEveryTime() {
        let rig = BodyRig(geometry: Screens.hardware)
        let stages = rig.stages
        #expect(stages.stage(for: .hardware) === stages.hardware && stages.stage(for: .virtual) === stages.virtual)
        #expect(stages.hardware !== stages.virtual)
        #expect(stages.all.count == 2 && stages.all.contains { $0 === stages.hardware } && stages.all.contains { $0 === stages.virtual })
    }

    @Test func theRealStagesAreTwoAndEachReadsTheMacForItself() {
        let stages = CatStages(scheduler: ManualScheduler())
        #expect(stages.hardware !== stages.virtual, "which is to say two brains, each with a seed of its own")
        for stage in stages.all { #expect(!stage.isAlive && !stage.isTicking && stage.plan == nil) }
    }

    @Test func aViewOfTheMacsNotchAndAViewOfAPillAreShownByDifferentStagesAndNeverTheOthers() throws {
        let (mac, pill) = pair()
        mac.show()
        pill.show()
        let stages = mac.stages
        #expect(mac.hosts.count == 2 && pill.hosts.count == 1)
        #expect(stages.hardware.attachedHosts.count == 2 && stages.hardware.attachedHosts.allSatisfy { host in mac.hosts.contains { $0 === host } })
        #expect(stages.virtual.attachedHosts.count == 1 && stages.virtual.attachedHosts.first === pill.hosts.first)
        #expect(mac.hosts.allSatisfy { $0.stage === stages.hardware } && pill.hosts.allSatisfy { $0.stage === stages.virtual })
        // Two brains: each has a cat of its own, which it has put somewhere of its own.
        #expect(stages.hardware.plan != nil && stages.virtual.plan != nil)
        #expect(mac.scheduler.pendingCount == 2, "a timer for each")
    }

    @Test func thePillsCatHasNoGapsAtAllWhileTheMacsHasTheCamerasAndTheWingsOfOneNotchShareOneStage() throws {
        let (mac, pill) = pair()
        mac.show()
        pill.show()
        let stages = mac.stages
        #expect(stages.virtual.crossingShares().isEmpty, "a pill has no camera to cross")
        let gaps = stages.hardware.crossingShares()
        #expect(gaps.count == 1, "the two wings of one notch have the one crossing: \(gaps)")
        let left = try #require(mac.container.leftWing)
        let crossing = try #require(left.field.crossingShares)
        #expect(gaps == [crossing])
        // And it stays so while they live: the pill's cat is never told of the Mac's camera, and the Mac's is never told of no camera.
        mac.advance(60)
        #expect(stages.virtual.crossingShares().isEmpty && stages.hardware.crossingShares() == [crossing])
    }

    @Test func theTwoWingsOfOneNotchShareOneStageAndOneClockAndBeginTogetherWithAPillOnTheOtherDisplay() throws {
        let (mac, pill) = pair(seed: 3)
        mac.show()
        pill.show()
        let (left, right) = (try #require(mac.container.leftWing), try #require(mac.container.rightWing))
        #expect(left.stage === right.stage && left.stage !== pill.hosts.first?.stage)
        var seen = 0
        for _ in 0..<(4 * 900) {
            mac.advance(0.25)
            guard let one = left.sprite.animation(forKey: CatSpriteView.walkKey), let two = right.sprite.animation(forKey: CatSpriteView.walkKey) else { continue }
            seen += 1
            #expect(one.beginTime == two.beginTime, "not close: equal")
            #expect(left.sprite.animation(forKey: CatSpriteView.framesKey)?.beginTime == right.sprite.animation(forKey: CatSpriteView.framesKey)?.beginTime)
        }
        #expect(seen > 0)
    }

    // MARK: What belongs to a screen

    @Test func aPointerNearThePillsCatMakesThatCatReactAndNotTheMacsAndTheOtherWayRound() throws {
        let (mac, pill) = pair()
        mac.show()
        pill.show()
        let stages = mac.stages
        // Rest a while first, so that nothing is left of what the cats do for themselves.
        mac.advance(30)
        var reactedHardware = false, reactedVirtual = false
        let lane = try #require(pill.hosts.first?.screenFrame)
        mac.pointer.point = CGPoint(x: lane.midX, y: lane.midY)
        for _ in 0..<16 {
            mac.advance(0.25)
            reactedHardware = reactedHardware || reacted(stages.hardware)
            reactedVirtual = reactedVirtual || reacted(stages.virtual)
        }
        #expect(reactedVirtual, "the pointer stopped by the pill's cat")
        #expect(!reactedHardware, "and a pointer on another display is nothing to the Mac's cat")

        // Away, and then by the Mac's wing: the Mac's cat reacts, the pill's does not.
        mac.pointer.point = CGPoint(x: 9000, y: 9000)
        mac.advance(30)
        reactedHardware = false
        reactedVirtual = false
        let wing = try #require(mac.hosts.first?.screenFrame)
        mac.pointer.point = CGPoint(x: wing.midX, y: wing.midY)
        for _ in 0..<16 {
            mac.advance(0.25)
            reactedHardware = reactedHardware || reacted(stages.hardware)
            reactedVirtual = reactedVirtual || reacted(stages.virtual)
        }
        #expect(reactedHardware)
        #expect(!reactedVirtual)
    }

    @Test func aClickOnOneCatIsAStrokeForThatCatAndNoOther() throws {
        let (mac, pill) = pair()
        mac.show()
        pill.show()
        let stages = mac.stages
        mac.advance(1)
        try click(try #require(pill.hosts.first))
        #expect(stages.virtual.strokes == 1 && stages.hardware.strokes == 0)
        #expect(stages.virtual.plan?.move == .purr && stages.hardware.plan?.move != .purr)
        try click(try #require(mac.container.rightWing))
        #expect(stages.virtual.strokes == 1 && stages.hardware.strokes == 1)
        #expect(stages.hardware.plan?.move == .purr)
    }

    // MARK: When a stage runs

    @Test func aStageWithNoViewsDoesNotTickWhileTheOtherOneDoes() {
        let (mac, pill) = pair()
        mac.show()
        let stages = mac.stages
        #expect(stages.hardware.isTicking && !stages.virtual.isTicking)
        #expect(mac.scheduler.pendingCount == 1)
        mac.advance(10)
        #expect(stages.hardware.ticks == 40)
        #expect(stages.virtual.ticks == 0 && stages.virtual.plan == nil && !stages.virtual.isAlive)
        #expect(mac.pointer.reads == 40, "only the stage that is on a notch reads the pointer")

        pill.show()
        #expect(mac.scheduler.pendingCount == 2 && stages.virtual.isTicking)
        mac.advance(1)
        #expect(stages.hardware.ticks == 44 && stages.virtual.ticks == 4)

        mac.hide()
        #expect(mac.scheduler.pendingCount == 1 && !stages.hardware.isAlive && !stages.hardware.isTicking)
        mac.advance(60)
        #expect(stages.hardware.ticks == 44, "nothing for a cat nobody sees")
        pill.hide()
        #expect(mac.scheduler.pendingCount == 0)
    }

    @Test func theSharedSourcesAreReadByTheStagesThatAreAliveAndNoOther() {
        let (mac, pill) = pair()
        mac.show()
        mac.advance(4)
        let alone = (mac.idle.reads, mac.cpu.reads, mac.audio.reads)
        pill.show()
        mac.advance(4)
        // Twice as many once the second stage is alive: one read of each a second for each of them, and a baseline for the one that woke.
        #expect(mac.idle.reads - alone.0 == 8 && mac.audio.reads - alone.2 == 8)
        #expect(mac.cpu.reads - alone.1 == 8 + 1)
    }

    @Test func reduceMotionStillsEveryCatThereIsAndTurningItOffGetsThemAllGoingAgain() {
        let (mac, pill) = pair()
        mac.show()
        pill.show()
        let stages = mac.stages
        mac.advance(3)
        #expect(stages.all.allSatisfy { $0.isTicking })
        mac.knobs.reducesMotion = true
        mac.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { stages.all.allSatisfy { !$0.isTicking } }, seconds: 5))
        #expect(mac.scheduler.pendingCount == 0)
        mac.knobs.reducesMotion = false
        mac.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { stages.all.allSatisfy { $0.isTicking } }, seconds: 5))
        #expect(mac.scheduler.pendingCount == 2)
    }

    @Test func stoppingTheStagesStopsBoth() {
        let (mac, pill) = pair()
        mac.show()
        pill.show()
        mac.stages.shutDown()
        for stage in mac.stages.all { #expect(!stage.isAlive && !stage.isTicking) }
        #expect(mac.scheduler.pendingCount == 0)
    }

    // MARK: In the notch's tree

    func hosted(_ geometry: NotchGeometry, stages: CatStages, place: PlayPlace = .portal) -> NSWindow {
        let rig = BodyRig(geometry: geometry, place: place)
        let view = CatBodyView(stages: stages, place: place)
            .environment(\.notchGeometry, geometry)
            .environment(\.notchIsOnScreen, true)
            .frame(width: rig.rowWidth, height: geometry.notchSize.height)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: rig.rowWidth, height: geometry.notchSize.height), styleMask: .borderless, backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return window
    }

    @Test func theBodyOfAHardwareNotchIsShownByTheHardwareStageAndTheBodyOfAPillByTheVirtualOne() {
        let stages = BodyRig(geometry: Screens.hardware).stages
        let mac = hosted(Screens.hardware, stages: stages)
        #expect(stages.hardware.attachedHosts.count == 2 && !stages.virtual.isAlive)
        let pill = hosted(Screens.pill, stages: stages)
        #expect(stages.hardware.attachedHosts.count == 2 && stages.virtual.attachedHosts.count == 1)
        mac.contentView = nil
        #expect(!stages.hardware.isAlive && stages.virtual.isAlive)
        pill.contentView = nil
        #expect(!stages.virtual.isAlive)
        // A notch drawn on a screen that has none, which is a virtual one too.
        let drawn = hosted(Screens.notch, stages: stages)
        #expect(stages.virtual.attachedHosts.count == 1 && !stages.hardware.isAlive)
        drawn.contentView = nil
    }

    @Test func theStripOfAHardwareNotchIsShownByTheHardwareStageAndThePillsStaysAsleepForIt() throws {
        let stages = BodyRig(geometry: Screens.hardware).stages
        let activity = CatActivity.make(stages: stages, place: .strip)
        let strip = try #require(activity.bottom)
        let hosting = NSHostingView(rootView: strip.frame(width: 300, height: 26).environment(\.notchIsOnScreen, true))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 26), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        #expect(stages.hardware.attachedHosts.count == 1 && stages.hardware.attachedHosts.first?.role == .strip)
        #expect(!stages.virtual.isAlive)
        window.contentView = nil
        #expect(!stages.hardware.isAlive)
    }
}
