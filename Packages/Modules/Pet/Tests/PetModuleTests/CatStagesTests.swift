import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import PetModule

/// One stage for each display that has pets: the Mac's own notch and a pill are not the same world, and two displays are not either, so they
/// do not share a brain, the places a character must not stop at, the pointer it watches or a click. The two wings of one notch do.
@Suite(.serialized) @MainActor struct CatStagesTests {
    /// The Mac's notch and a pill on the display beside it, with one scheduler, one set of things read and one registry of stages.
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

    @Test func eachDisplayHasAStageOfItsOwnAndTheSameOneEveryTime() throws {
        let (mac, pill) = pair()
        let stages = mac.stages
        let one = try #require(stages.stage(for: Screens.macID))
        let other = try #require(stages.stage(for: Screens.externalID))
        #expect(stages.stage(for: Screens.macID) === one && stages.stage(for: Screens.externalID) === other)
        #expect(one !== other)
        #expect(stages.all.count == 2 && stages.all.contains { $0 === one } && stages.all.contains { $0 === other })
        #expect(mac.stage === one && pill.stage === other)
    }

    @Test func theRealStagesAreOnePerDisplayAndEachReadsTheMacForItself() throws {
        let stages = CatStages(scheduler: ManualScheduler())
        let one = try #require(stages.stage(for: "A"))
        let other = try #require(stages.stage(for: "B"))
        #expect(one !== other, "which is to say two brains, each with a seed of its own")
        for stage in stages.all { #expect(!stage.isAlive && !stage.isTicking && stage.plan == nil && stage.characters == [.cat]) }
    }

    @Test func aViewOfTheMacsNotchAndAViewOfAPillAreShownByTheirDisplaysStagesAndNoOthers() throws {
        let (mac, pill) = pair()
        mac.show()
        pill.show()
        let stages = mac.stages
        let (hardware, virtual) = (try #require(stages.stage(for: Screens.macID)), try #require(stages.stage(for: Screens.externalID)))
        #expect(mac.hosts.count == 2 && pill.hosts.count == 1)
        #expect(hardware.attachedHosts.count == 2 && hardware.attachedHosts.allSatisfy { host in mac.hosts.contains { $0 === host } })
        #expect(virtual.attachedHosts.count == 1 && virtual.attachedHosts.first === pill.hosts.first)
        #expect(mac.hosts.allSatisfy { $0.stage === hardware } && pill.hosts.allSatisfy { $0.stage === virtual })
        // Two brains: each has a cat of its own, which it has put somewhere of its own.
        #expect(hardware.plan != nil && virtual.plan != nil)
        #expect(mac.scheduler.pendingCount == 2, "a timer for each")
    }

    @Test func twoDisplaysOfOneKindAreTwoStagesToo() throws {
        let first = BodyRig(geometry: Screens.pill, seed: 4, display: "PILL-ONE")
        let second = BodyRig(geometry: Screens.pill, screenOrigin: 4000, sharing: first, display: "PILL-TWO")
        first.show()
        second.show()
        let one = try #require(first.stages.stage(for: "PILL-ONE"))
        let other = try #require(first.stages.stage(for: "PILL-TWO"))
        #expect(one !== other && first.stages.all.count == 2)
        #expect(one.attachedHosts.count == 1 && other.attachedHosts.count == 1)
        first.advance(30)
        // A pointer stopped by one display's cat startles that one's and not the other's, though the displays are alike.
        var (reactedOne, reactedOther) = (false, false)
        let lane = try #require(second.hosts.first?.screenFrame)
        first.pointer.point = CGPoint(x: lane.midX, y: lane.midY)
        for _ in 0..<16 {
            first.advance(0.25)
            reactedOne = reactedOne || reacted(one)
            reactedOther = reactedOther || reacted(other)
        }
        #expect(reactedOther && !reactedOne)
    }

    @Test func thePillsCatHasNoGapsAtAllWhileTheMacsHasTheCamerasAndTheWingsOfOneNotchShareOneStage() throws {
        let (mac, pill) = pair()
        mac.show()
        pill.show()
        let (hardware, virtual) = (mac.stage, pill.stage)
        #expect(virtual.crossingShares().isEmpty, "a pill has no camera to cross")
        let gaps = hardware.crossingShares()
        #expect(gaps.count == 1, "the two wings of one notch have the one crossing: \(gaps)")
        let left = try #require(mac.container.leftWing)
        let crossing = try #require(left.field.crossingShares)
        #expect(gaps == [crossing])
        // And it stays so while they live: the pill's cat is never told of the Mac's camera, and the Mac's is never told of no camera.
        mac.advance(60)
        #expect(virtual.crossingShares().isEmpty && hardware.crossingShares() == [crossing])
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
        let (hardware, virtual) = (mac.stage, pill.stage)
        // Rest a while first, so that nothing is left of what the cats do for themselves.
        mac.advance(30)
        var reactedHardware = false, reactedVirtual = false
        let lane = try #require(pill.hosts.first?.screenFrame)
        mac.pointer.point = CGPoint(x: lane.midX, y: lane.midY)
        for _ in 0..<16 {
            mac.advance(0.25)
            reactedHardware = reactedHardware || reacted(hardware)
            reactedVirtual = reactedVirtual || reacted(virtual)
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
            reactedHardware = reactedHardware || reacted(hardware)
            reactedVirtual = reactedVirtual || reacted(virtual)
        }
        #expect(reactedHardware)
        #expect(!reactedVirtual)
    }

    @Test func aClickOnOneCatIsAStrokeForThatCatAndNoOther() throws {
        let (mac, pill) = pair()
        mac.show()
        pill.show()
        let (hardware, virtual) = (mac.stage, pill.stage)
        mac.advance(1)
        try click(try #require(pill.hosts.first))
        #expect(virtual.strokes == 1 && hardware.strokes == 0)
        #expect(virtual.plan?.move == .purr && hardware.plan?.move != .purr)
        try click(try #require(mac.container.rightWing))
        #expect(virtual.strokes == 1 && hardware.strokes == 1)
        #expect(hardware.plan?.move == .purr)
    }

    // MARK: When a stage runs

    @Test func aStageWithNoViewsDoesNotTickWhileTheOtherOneDoes() throws {
        let (mac, pill) = pair()
        mac.show()
        let (hardware, virtual) = (mac.stage, pill.stage)
        #expect(hardware.isTicking && !virtual.isTicking)
        #expect(mac.scheduler.pendingCount == 1)
        mac.advance(10)
        #expect(hardware.ticks == 40)
        #expect(virtual.ticks == 0 && virtual.plan == nil && !virtual.isAlive)
        #expect(mac.pointer.reads == 40, "only the stage that is on a notch reads the pointer")

        pill.show()
        #expect(mac.scheduler.pendingCount == 2 && virtual.isTicking)
        mac.advance(1)
        #expect(hardware.ticks == 44 && virtual.ticks == 4)

        mac.hide()
        #expect(mac.scheduler.pendingCount == 1 && !hardware.isAlive && !hardware.isTicking)
        mac.advance(60)
        #expect(hardware.ticks == 44, "nothing for a cat nobody sees")
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

    @Test func stoppingTheStagesStopsAllOfThem() {
        let (mac, pill) = pair()
        mac.show()
        pill.show()
        let live = mac.stages.all
        mac.stages.shutDown()
        for stage in live { #expect(!stage.isAlive && !stage.isTicking) }
        #expect(mac.scheduler.pendingCount == 0 && mac.stages.all.isEmpty)
        #expect(mac.stages.stage(for: Screens.macID) == nil, "and none is made after")
    }

    // MARK: What the user chose

    @Test func aScreenThatIsNotInTheChoicesHasACatAndSoDoesAWindowOnNoScreenAtAll() throws {
        let rig = BodyRig(geometry: Screens.hardware)
        #expect(rig.stages.screens == PetScreens())
        #expect(try #require(rig.stages.stage(for: "A DISPLAY NOBODY HEARD OF")).characters == [.cat])
        let orphan = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 38), styleMask: .borderless, backing: .buffered, defer: true)
        orphan.isReleasedWhenClosed = false
        let container = CatBodyContainer(stages: rig.stages)
        container.frame = CGRect(x: 0, y: 0, width: 420, height: 38)
        orphan.contentView?.addSubview(container)
        container.configure(geometry: Screens.pill)
        container.layoutSubtreeIfNeeded()
        let lane = try #require(container.lane)
        #expect(lane.stage === rig.stages.stage(for: CatStages.unknownDisplay) && lane.stage != nil, "a display like any other")
        #expect(lane.stage?.characters == [.cat])
    }

    @Test func aScreenWithNoCharactersHasNoStageAndNothingTicksForIt() {
        let (mac, pill) = pair()
        mac.stages.apply(screens: PetScreens().setting([], for: Screens.externalID))
        mac.show()
        pill.show()
        #expect(mac.stages.stage(for: Screens.externalID) == nil)
        #expect(pill.hosts.allSatisfy { $0.stage == nil && !$0.isShowingCat && !$0.isAnimating })
        #expect(mac.scheduler.pendingCount == 1, "only the Mac's cat ticks")
        mac.advance(30)
        #expect(mac.pointer.reads == 120, "and only its stage reads")
        #expect(mac.stages.all.count == 1)
    }

    @Test func givingAScreenACharacterStartsItAtOnceAndTakingItAwayStopsItAtOnce() throws {
        let (mac, pill) = pair()
        mac.stages.apply(screens: PetScreens().setting([], for: Screens.externalID))
        mac.show()
        pill.show()
        mac.advance(2)
        #expect(mac.scheduler.pendingCount == 1)

        // None to a cat: no event of the window's, the view is on a stage and shows it, now.
        mac.stages.apply(screens: PetScreens())
        let stage = try #require(mac.stages.stage(for: Screens.externalID))
        #expect(stage.attachedHosts.count == 1 && stage.isTicking && pill.hosts.allSatisfy { $0.stage === stage })
        #expect(mac.scheduler.pendingCount == 2)
        #expect(pill.hosts.allSatisfy { $0.isShowingCat })
        mac.advance(1)
        #expect(stage.ticks == 4)

        // A cat to none: what ran for it stops, the pending timer with it.
        mac.stages.apply(screens: PetScreens().setting([], for: Screens.externalID))
        #expect(mac.stages.stage(for: Screens.externalID) == nil && !stage.isAlive && !stage.isTicking)
        #expect(mac.scheduler.pendingCount == 1)
        #expect(pill.hosts.allSatisfy { !$0.isShowingCat && !$0.isAnimating && $0.stage == nil })
        let reads = mac.pointer.reads
        mac.advance(10)
        #expect(mac.pointer.reads - reads == 40, "the Mac's cat alone is read for")
    }

    @Test func aChoiceForOneScreenNeverTouchesAnotherScreensStageAndWhatStaysIsNotRestarted() throws {
        let (mac, pill) = pair()
        mac.show()
        pill.show()
        mac.advance(20)
        let before = mac.stage
        let plan = before.plan
        let ticks = before.ticks
        mac.stages.apply(screens: PetScreens().setting([], for: Screens.externalID))
        #expect(mac.stage === before && before.plan == plan && before.ticks == ticks && before.isTicking)
        mac.stages.apply(screens: PetScreens().setting([], for: Screens.externalID).setting([.cat], for: "ANOTHER"))
        #expect(mac.stage === before && before.plan == plan, "a choice for a screen that is not here changes nothing here")
    }

    @Test func aScreenTakenOutAndPutBackKeepsWhatWasChosenForIt() throws {
        let (mac, pill) = pair()
        mac.stages.apply(screens: PetScreens().setting([], for: Screens.externalID))
        mac.show()
        pill.show()
        #expect(pill.hosts.allSatisfy { $0.stage == nil })
        // The display goes: its notch leaves the tree; and comes back, with nobody telling the stages anything.
        pill.hide()
        pill.show()
        #expect(mac.stages.stage(for: Screens.externalID) == nil && pill.hosts.allSatisfy { $0.stage == nil && !$0.isShowingCat })
        #expect(mac.scheduler.pendingCount == 1)
        // And the Mac's own, which was a cat, is a cat when it comes back.
        mac.hide()
        mac.show()
        #expect(mac.stage.attachedHosts.count == 2 && mac.stage.characters == [.cat])
    }

    // MARK: Which display a view is on

    @Test func aViewThatMovesToAnotherDisplayIsShownByThatDisplaysStage() throws {
        let (mac, pill) = pair()
        mac.show()
        pill.show()
        let (hardware, virtual) = (mac.stage, pill.stage)
        let lane = try #require(pill.container.lane)
        #expect(lane.stage === virtual)
        // The pill's window is dragged to the Mac's display, and the news is out.
        pill.displays.put(pill.window, on: Screens.macID)
        pill.screenNotifications.post(name: NSWindow.didChangeScreenNotification, object: pill.window)
        #expect(lane.stage === hardware && hardware.attachedHosts.count == 3 && virtual.attachedHosts.isEmpty)
        #expect(!virtual.isAlive && !virtual.isTicking && hardware.isAlive)
        #expect(lane.isShowingCat, "and the cat is on it at once")
        #expect(mac.scheduler.pendingCount == 1)
        // And back by a rearranging of the displays.
        pill.displays.put(pill.window, on: Screens.externalID)
        pill.screenNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(lane.stage === virtual && virtual.attachedHosts.count == 1 && hardware.attachedHosts.count == 2)
        #expect(mac.scheduler.pendingCount == 2)
    }

    @Test func aViewThatMovedToAnotherDisplayWithNoNewsIsFoundByTheStagesOwnLook() throws {
        let (mac, pill) = pair()
        mac.show()
        pill.show()
        let lane = try #require(pill.container.lane)
        let (hardware, virtual) = (mac.stage, pill.stage)
        mac.advance(1)
        pill.displays.put(pill.window, on: Screens.macID)
        #expect(lane.stage === virtual && pill.container.isStale)
        mac.advance(0.25)
        mac.advance(0.25)
        pill.container.layoutSubtreeIfNeeded()
        #expect(lane.stage === hardware && !pill.container.isStale, "a quarter of a second, and a layout")
        #expect(hardware.attachedHosts.count == 3 && !virtual.isAlive)
    }

    @Test func aViewMovedToADisplayWithNoCharactersIsShownByNobodyAndOneMovedBackIsShownAgain() throws {
        let (mac, pill) = pair()
        mac.stages.apply(screens: PetScreens().setting([], for: "EMPTY"))
        mac.show()
        pill.show()
        let lane = try #require(pill.container.lane)
        pill.displays.put(pill.window, on: "EMPTY")
        pill.screenNotifications.post(name: NSWindow.didChangeScreenNotification, object: pill.window)
        #expect(lane.stage == nil && !lane.isShowingCat && !pill.stage.isAlive)
        pill.displays.put(pill.window, on: Screens.externalID)
        pill.screenNotifications.post(name: NSWindow.didChangeScreenNotification, object: pill.window)
        #expect(lane.stage === pill.stage && lane.isShowingCat)
    }

    // MARK: In the notch's tree

    func hosted(
        _ geometry: NotchGeometry, in rig: BodyRig, on display: DisplayID, place: PlayPlace = .portal, widths: AskedWidths? = nil
    ) -> NSWindow {
        let width = Screens.row(of: geometry, place: place)
        let view = CatBodyView(stages: rig.stages, place: place)
            .environment(\.notchGeometry, geometry)
            .environment(\.notchIsOnScreen, true)
            .frame(width: width, height: geometry.notchSize.height)
            .onNotchStripWidth { widths?.values.append($0) }
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: geometry.notchSize.height), styleMask: .borderless, backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        rig.displays.put(window, on: display)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        settleDisplays(in: window)
        return window
    }

    final class AskedWidths { var values: [CGFloat] = [] }

    @Test func theBodyOfAHardwareNotchIsShownByItsDisplaysStageAndTheBodyOfAPillByTheOthers() throws {
        let rig = BodyRig(geometry: Screens.hardware)
        let stages = rig.stages
        let mac = hosted(Screens.hardware, in: rig, on: Screens.macID)
        let hardware = try #require(stages.stage(for: Screens.macID))
        #expect(hardware.attachedHosts.count == 2 && stages.all.count == 1)
        let pill = hosted(Screens.pill, in: rig, on: Screens.externalID)
        let virtual = try #require(stages.stage(for: Screens.externalID))
        #expect(hardware.attachedHosts.count == 2 && virtual.attachedHosts.count == 1)
        mac.contentView = nil
        #expect(!hardware.isAlive && virtual.isAlive)
        pill.contentView = nil
        #expect(!virtual.isAlive)
        // A notch drawn on a screen that has none, which is another display's like any other.
        let drawn = hosted(Screens.notch, in: rig, on: Screens.externalID)
        #expect(virtual.attachedHosts.count == 1 && !hardware.isAlive)
        drawn.contentView = nil
    }

    @Test func theStripOfAHardwareNotchIsShownByTheStageOfItsDisplayAndAnotherDisplaysStaysAsleepForIt() throws {
        let rig = BodyRig(geometry: Screens.hardware)
        let stages = rig.stages
        let activity = CatActivity.make(stages: stages, place: .strip)
        let strip = try #require(activity.bottom)
        let hosting = NSHostingView(rootView: strip.frame(width: 300, height: 26).environment(\.notchIsOnScreen, true))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 26), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        rig.displays.put(window, on: Screens.macID)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let hardware = try #require(stages.stage(for: Screens.macID))
        #expect(hardware.attachedHosts.count == 1 && hardware.attachedHosts.first?.role == .strip)
        #expect(stages.stage(for: Screens.externalID)?.isAlive != true)
        // The strip is not in a container that hears of its window: the registry does, and puts it on the stage of the display it is on.
        let other = try #require(stages.stage(for: Screens.externalID))
        rig.displays.put(window, on: Screens.externalID)
        rig.screenNotifications.post(name: NSWindow.didChangeScreenNotification, object: window)
        #expect(!hardware.isAlive && other.attachedHosts.count == 1 && other.attachedHosts.first?.role == .strip)
        window.contentView = nil
        #expect(!hardware.isAlive && !other.isAlive)
    }

    @Test func aScreenWithNoCharactersIsAskedForNoRoomAndDrawsNothingAndWhenItGetsOneItIsAskedAndDraws() throws {
        let rig = BodyRig(geometry: Screens.hardware)
        rig.stages.apply(screens: PetScreens().setting([], for: Screens.macID))
        let asked = AskedWidths()
        let window = hosted(Screens.hardware, in: rig, on: Screens.macID, widths: asked)
        #expect(asked.values.allSatisfy { $0 == 0 }, "no room asked for on a screen with no pet, not even for a moment: \(asked.values)")
        #expect(rig.stages.stage(for: Screens.macID) == nil)
        #expect(!rig.stages.all.contains { $0.isAlive })

        rig.stages.apply(screens: PetScreens())
        #expect(runLoop(until: { asked.values.last == 420 - 2 * NotchTokens.stripPadding }, seconds: 10), "\(asked.values)")
        #expect(try #require(rig.stages.stage(for: Screens.macID)).attachedHosts.count == 2)
        window.contentView = nil
    }
}
