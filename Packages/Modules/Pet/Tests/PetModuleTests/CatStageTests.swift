import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import Testing
@testable import PetModule

@Suite(.serialized) @MainActor struct CatStageTests {
    // MARK: Nothing runs without a view

    @Test func aStageWithNoViewOnAScreenHasNothingRunningAndReadsNothing() {
        let rig = StageRig()
        rig.advance(60)
        #expect(!rig.stage.isAlive)
        #expect(!rig.stage.isTicking)
        #expect(rig.scheduler.pendingCount == 0)
        #expect((rig.idle.reads, rig.cpu.reads, rig.pointer.reads, rig.audio.reads) == (0, 0, 0, 0))
        #expect(rig.stage.plan == nil)
    }

    @Test func theViewsComingIntoAWindowStartsTheCatAndOneWakingEveryQuarterOfASecond() {
        let rig = StageRig()
        rig.show()
        #expect(rig.stage.isAlive)
        #expect(rig.stage.isTicking)
        #expect(rig.scheduler.pendingCount == 1, "one timer, and it is the only one")
        rig.advance(1)
        #expect(rig.stage.ticks == 4)
        rig.advance(3)
        #expect(rig.stage.ticks == 16)
        #expect(rig.scheduler.pendingCount == 1)
    }

    @Test func thePointerIsReadEveryWakingAndTheRestOnceASecond() {
        let rig = StageRig()
        rig.show()
        // The processors are read once as the cat wakes, for a baseline, and then once a second.
        #expect(rig.cpu.reads == 1)
        rig.advance(4)
        #expect(rig.pointer.reads == 16)
        #expect(rig.idle.reads == 4)
        #expect(rig.cpu.reads == 1 + 4)
        #expect(rig.audio.reads == 4)
    }

    @Test func whenTheLastViewLeavesTheTimerTheReadsAndEveryAnimationStop() {
        let rig = StageRig()
        rig.show()
        rig.advance(5)
        #expect(rig.trailing.isAnimating)
        let reads = (rig.idle.reads, rig.cpu.reads, rig.pointer.reads, rig.audio.reads)
        let ticks = rig.stage.ticks

        rig.hide()
        #expect(!rig.stage.isAlive)
        #expect(!rig.stage.isTicking)
        #expect(rig.scheduler.pendingCount == 0, "nothing is scheduled for a cat nobody sees")
        for host in [rig.leading, rig.trailing] {
            #expect(!host.isAnimating, "no animation on the layer")
            #expect(host.sprite.animationKeys() == nil || host.sprite.animationKeys()?.isEmpty == true)
            #expect(!host.isShowingCat)
        }
        rig.advance(600)
        #expect(rig.stage.ticks == ticks)
        #expect((rig.idle.reads, rig.cpu.reads, rig.pointer.reads, rig.audio.reads) == reads)
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func oneViewLeavingLeavesTheCatAliveForTheOtherAndTheLastTakesItAway() {
        let rig = StageRig()
        rig.show()
        rig.leading.removeFromSuperview()
        #expect(rig.stage.isAlive)
        #expect(rig.stage.isTicking)
        rig.trailing.removeFromSuperview()
        #expect(!rig.stage.isAlive)
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func aViewThatComesBackStartsTheCatAgainWhereItWasAndNoTimerIsLeftOver() throws {
        let rig = StageRig()
        rig.show()
        rig.advance(30)
        let place = try #require(rig.stage.plan).to
        rig.hide()
        rig.advance(120)
        rig.show()
        #expect(rig.scheduler.pendingCount == 1)
        let plan = try #require(rig.stage.plan)
        #expect(plan.pose == .sit)
        #expect(plan.from == place && plan.to == place)
        rig.hide()
        rig.show()
        rig.hide()
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func aStageThatHasBeenShutDownTakesNoMoreViewsAndRunsNothing() {
        let rig = StageRig()
        rig.show()
        rig.advance(2)
        rig.stage.shutDown()
        #expect(!rig.stage.isAlive)
        #expect(rig.scheduler.pendingCount == 0)
        #expect(!rig.trailing.isAnimating)
        rig.hide()
        rig.show()
        #expect(!rig.stage.isAlive)
        #expect(rig.scheduler.pendingCount == 0)
    }

    // MARK: Where it is drawn

    @Test func onAHardwareNotchTheCatIsOnlyInTheRightWingAndTheLeftOneShowsNothing() throws {
        let rig = StageRig(kind: .hardware)
        rig.show()
        #expect(rig.trailing.isShowingCat)
        #expect(rig.trailing.isAnimating)
        #expect(!rig.leading.isShowingCat)
        #expect(!rig.leading.isAnimating, "a wing the cat is never seen in has nothing to animate")
        #expect(rig.trailing.layer?.masksToBounds == true)
    }

    @Test func overBothWingsBothViewsShowTheCatAndAreClippedSoTheCameraIsNeverCrossed() {
        let rig = StageRig(kind: .hardware)
        rig.stage.bothWings = true
        rig.show()
        for host in [rig.leading, rig.trailing] {
            #expect(host.isShowingCat)
            #expect(host.isAnimating)
            #expect(host.layer?.masksToBounds == true, "nothing is drawn outside the wing: the camera is in between")
        }
    }

    @Test func insideAPillBothViewsShowTheCatAndNeitherClipsItSoItCrossesTheMiddle() {
        let rig = StageRig(kind: .virtual)
        rig.show()
        for host in [rig.leading, rig.trailing] {
            #expect(host.isShowingCat)
            #expect(host.layer?.masksToBounds == false)
        }
        // The user's choice of both wings is for a hardware notch.
        rig.stage.bothWings = true
        for host in [rig.leading, rig.trailing] { #expect(host.layer?.masksToBounds == false) }
    }

    @Test func choosingBothWingsWhileTheCatIsOnTheNotchTakesEffectAtOnce() {
        let rig = StageRig(kind: .hardware)
        rig.show()
        #expect(!rig.leading.isShowingCat)
        rig.stage.bothWings = true
        #expect(rig.leading.isShowingCat)
        rig.stage.bothWings = false
        #expect(!rig.leading.isShowingCat)
        #expect(!rig.leading.isAnimating)
    }

    /// Where the sprite is in the window, from the layer's value and, on a walk, the last place its animation holds the foot.
    func extent(of host: CatSpriteView) -> ClosedRange<CGFloat> {
        var places = [host.sprite.position.x]
        if let walk = host.sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation {
            places += (walk.values as? [NSNumber] ?? []).map { CGFloat($0.doubleValue) }
        }
        let origin = host.windowFrame.minX
        return (places.min()! + origin)...(places.max()! + origin + host.sprite.bounds.width)
    }

    @Test func onTheRightWingTheCatNeverLeavesTheWingThroughTenMinutes() {
        let rig = StageRig(kind: .hardware)
        rig.show()
        var walked = false
        let wing = rig.trailing.windowFrame
        for _ in 0..<2400 {
            rig.advance(0.25)
            let reach = extent(of: rig.trailing)
            #expect(reach.lowerBound >= wing.minX && reach.upperBound <= wing.maxX, "\(reach) in \(wing)")
            if rig.trailing.sprite.animation(forKey: CatSpriteView.walkKey) != nil { walked = true }
        }
        #expect(walked)
    }

    @Test func overBothWingsTheCatReachesBothAndNeverGoesPastTheEnds() {
        let rig = StageRig(kind: .hardware, seed: 3)
        rig.stage.bothWings = true
        rig.show()
        var left = CGFloat.infinity
        var right = -CGFloat.infinity
        let (leading, trailing) = (rig.leading.windowFrame, rig.trailing.windowFrame)
        for _ in 0..<(2400 * 4) {
            rig.advance(0.25)
            // CPU busy for stretches, so it runs the whole lane.
            if Int(rig.scheduler.seconds) % 120 == 0 { rig.cpu.value = rig.cpu.value == 0.05 ? 0.9 : 0.05 }
            let reach = extent(of: rig.trailing)
            left = min(left, reach.lowerBound)
            right = max(right, reach.upperBound)
            #expect(reach.lowerBound >= leading.minX && reach.upperBound <= trailing.maxX)
        }
        #expect(left < leading.maxX, "it got to the left wing: \(left)")
        #expect(right > trailing.minX, "and to the right one")
    }

    @Test func theScreenIsAskedWhatKindOfNotchItHasOnceAndNotAtEveryWaking() {
        let rig = StageRig()
        rig.show()
        rig.advance(1)
        let asks = rig.kindAsks
        #expect(asks > 0 && asks <= 4, "once for the window, again as the views move into place: \(asks)")
        rig.advance(120)
        #expect(rig.kindAsks == asks)
    }

    /// Whether the cat, as the plan has it standing, is wholly in one wing or the other, and not in the middle between them.
    func isInAWing(_ rig: StageRig, plan: CatPlan) -> Bool {
        guard let lane = rig.stage.lane(for: rig.trailing) else { return true }
        let x = lane.x(at: plan.to)
        let width = rig.trailing.metrics.size.width
        return x + width <= rig.leading.windowFrame.maxX + 1e-9 || x >= rig.trailing.windowFrame.minX - 1e-9
    }

    @Test(arguments: [NotchKind.hardware, .virtual]) func overBothWingsAndInsideAPillTheCatNeverStopsBetweenThem(kind: NotchKind) {
        for seed: UInt64 in [3, 5, 8] {
            let rig = StageRig(kind: kind, seed: seed)
            rig.stage.bothWings = true
            rig.stage.tuning = CatTuning(sleepAfter: 120)
            rig.show()
            var stood = 0
            var started = Set<CatPose>()
            for tick in 0..<(4 * 60 * 20) {
                let minute = tick / 240
                rig.cpu.value = minute % 7 == 3 ? 0.9 : 0.05
                rig.idle.seconds = minute % 5 == 4 ? 400 : 5
                rig.audio.playing = minute % 6 == 5
                rig.advance(0.25)
                guard let plan = rig.stage.plan else { continue }
                started.insert(plan.pose)
                if plan.from == plan.to, plan.pose != .startled {
                    stood += 1
                    #expect(isInAWing(rig, plan: plan), "\(kind) seed \(seed) minute \(minute): \(plan.pose) at \(plan.to)")
                }
            }
            #expect(stood > 1000)
            // It sat, slept and danced as well as crossed.
            #expect([CatPose.sit, .sleep, .dance, .run].allSatisfy(started.contains), "\(started)")
        }
    }

    @Test func aNotchThatMovesUnderTheCatMovesTheLaneWithIt() {
        let rig = StageRig(kind: .hardware)
        rig.show()
        let before = rig.stage.presentations
        // The wing gets wider.
        rig.trailing.frame = CGRect(x: 249, y: 0, width: 90, height: 32)
        rig.trailing.layoutSubtreeIfNeeded()
        rig.stage.hostDidMove(rig.trailing)
        #expect(rig.stage.presentations > before)
        let lane = rig.stage.lane(for: rig.trailing)
        #expect(lane?.maxX == 249 + 90 - WalkLane.hardwareEndInset - rig.trailing.metrics.size.width)
    }

    @Test func aNotchThatMovesWithoutTellingTheViewsIsFoundOutAtTheNextWaking() throws {
        let rig = StageRig(kind: .hardware)
        rig.show()
        rig.advance(1)
        let before = rig.stage.presentations
        // Only the superview's place changes: the wing's own frame in its superview does not, but where it is in the window does.
        let shifted = NSView(frame: CGRect(x: 40, y: 0, width: 400, height: 32))
        let content = try #require(rig.window.contentView)
        content.addSubview(shifted)
        shifted.addSubview(rig.trailing)
        // Leaving the old superview takes the stage's view off it; it comes back in the new one.
        #expect(rig.stage.isAlive)
        rig.advance(0.25)
        #expect(rig.stage.presentations > before)
    }

    // MARK: What it does

    @Test func withTheUserAwayForTheSleepTimeItYawnsAndSleeps() throws {
        let rig = StageRig()
        rig.stage.tuning = CatTuning(sleepAfter: 120)
        rig.idle.seconds = 130
        rig.show()
        // The cat finishes what it was doing, which is the two seconds of sitting it starts with.
        rig.advance(1)
        #expect(try #require(rig.stage.plan).pose == .sit)
        rig.advance(1.5)
        #expect(try #require(rig.stage.plan).pose == .yawn)
        rig.advance(2)
        #expect(try #require(rig.stage.plan).pose == .sleep)
        #expect(rig.trailing.isAnimating)
        let frames = try #require(rig.trailing.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation)
        #expect(frames.values?.count == CatArt.sleep.frames.count)
        // It sleeps on without being redrawn: the same animation object on the layer a minute later.
        let presentations = rig.stage.presentations
        rig.advance(60)
        #expect(rig.stage.presentations == presentations)
    }

    @Test func thePointerComingNearTheNotchMakesItJump() throws {
        let rig = StageRig()
        rig.show()
        rig.advance(2)
        let wing = try #require(rig.trailing.screenFrame)
        rig.pointer.point = CGPoint(x: wing.midX, y: wing.minY - 30)
        rig.advance(0.25)
        #expect(try #require(rig.stage.plan).pose == .startled)
        let frames = try #require(rig.trailing.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation)
        #expect(frames.values?.count == CatArt.startled.frames.count)
    }

    @Test func thePointerOverTheCameraBetweenTheWingsIsOnTheNotchAndMakesItJump() throws {
        let rig = StageRig()
        rig.show()
        rig.advance(2)
        let leading = try #require(rig.leading.screenFrame)
        let trailing = try #require(rig.trailing.screenFrame)
        // Dead centre between the wings: more than the margin from either of them.
        rig.pointer.point = CGPoint(x: (leading.maxX + trailing.minX) / 2, y: leading.midY)
        #expect(trailing.minX - leading.maxX > 2 * PointerProximity.margin)
        rig.advance(0.25)
        #expect(try #require(rig.stage.plan).pose == .startled)
    }

    @Test func aPointerThatStaysFarAwayNeverMakesItJump() {
        let rig = StageRig()
        rig.show()
        for _ in 0..<2400 {
            rig.advance(0.25)
            #expect(rig.stage.plan?.pose != .startled)
        }
    }

    @Test func busyProcessorsMakeItRun() throws {
        let rig = StageRig()
        rig.cpu.value = 0.9
        rig.show()
        rig.advance(1)
        #expect(try #require(rig.stage.plan).pose == .run)
        #expect(try #require(rig.stage.plan).fpsScale > 1)
        let frames = try #require(rig.trailing.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation)
        #expect(abs(frames.duration - CatArt.run.duration / (1 + CatBrain.runFrameBoost * (0.9 - CatBrain.runOn) / (1 - CatBrain.runOn))) < 1e-9)
    }

    @Test func aSpikeInTheLoadSmoothedOverTwoReadsDoesNotMakeItRunAtOnce() throws {
        let rig = StageRig()
        rig.cpu.value = 0.05
        rig.show()
        rig.advance(3)
        rig.cpu.value = 0.5
        rig.advance(1)
        // One read at 0.5 after calm ones is 0.275: under the threshold.
        #expect(try #require(rig.stage.plan).pose != .run)
        rig.advance(1)
        // A second at 0.5 is 0.39: it runs.
        #expect(try #require(rig.stage.plan).pose == .run)
    }

    @Test func soundPlayingMakesItDance() throws {
        let rig = StageRig()
        rig.audio.playing = true
        rig.show()
        rig.advance(1)
        #expect(try #require(rig.stage.plan).pose == .dance)
        rig.audio.playing = false
        rig.advance(1)
        #expect(try #require(rig.stage.plan).pose != .dance)
    }

    @Test func atNightItSleepsSoonerThanByDay() throws {
        let day = StageRig(hour: 12)
        day.idle.seconds = 100
        day.show()
        day.advance(5)
        #expect(try #require(day.stage.plan).pose != .sleep)
        let night = StageRig(hour: 23)
        night.idle.seconds = 100
        night.show()
        night.advance(5)
        #expect(try #require(night.stage.plan).pose == .sleep)
    }

    @Test func theCatIsRedrawnOnlyWhenItsPictureChangesNotAtEveryWaking() {
        let rig = StageRig()
        rig.show()
        rig.advance(600)
        #expect(rig.stage.ticks == 2400)
        #expect(rig.stage.presentations < 2 * 220, "two views, and a new picture every few seconds: \(rig.stage.presentations)")
    }

    // MARK: Petting

    @Test func aClickMakesItPurrWithoutAMewByDefault() throws {
        let rig = StageRig()
        rig.show()
        rig.advance(1)
        rig.stage.catWasClicked()
        #expect(try #require(rig.stage.plan).pose == .purr)
        #expect(rig.stage.strokes == 1)
        #expect(rig.meow.plays == 0)
        let frames = try #require(rig.trailing.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation)
        #expect(frames.values?.count == CatArt.purr.frames.count)
        // It is over after a while and the cat goes back to being a cat.
        rig.advance(CatBrain.purrDuration + 1)
        #expect(try #require(rig.stage.plan).pose != .purr)
    }

    @Test func aClickMewsWhenTheUserWantsItTo() {
        let rig = StageRig()
        rig.stage.playsMeow = true
        rig.show()
        rig.stage.catWasClicked()
        rig.stage.catWasClicked()
        #expect(rig.meow.plays == 2)
    }

    @Test func aClickOnTheCatsViewIsAStroke() throws {
        let rig = StageRig()
        rig.show()
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: rig.window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
        rig.trailing.mouseDown(with: event)
        #expect(rig.stage.strokes == 1)
        #expect(rig.stage.plan?.pose == .purr)
    }

    // MARK: Reduce Motion

    @Test func withReduceMotionTheCatSitsStillWithAnEyeBlinkAndNothingWakesForIt() throws {
        let rig = StageRig(reducesMotion: true)
        rig.show()
        #expect(rig.stage.isAlive)
        #expect(!rig.stage.isTicking)
        #expect(rig.scheduler.pendingCount == 0, "no timer at all")
        rig.advance(600)
        #expect((rig.idle.reads, rig.cpu.reads, rig.pointer.reads, rig.audio.reads) == (0, 0, 0, 0), "and nothing is read")
        #expect(rig.stage.ticks == 0)

        let host = rig.trailing
        #expect(host.isShowingCat)
        #expect(host.sprite.animationKeys() == [CatSpriteView.framesKey], "the blink and nothing else: no walk, no frames of a gait")
        let blink = try #require(host.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation)
        #expect(blink.values?.count == CatSpriteView.restingBlinkSlots)
        #expect(blink.duration == CatSpriteView.restingBlinkPeriod)
        #expect(blink.calculationMode == .discrete)
        #expect(blink.repeatCount == .infinity)
        // Eyes open for all the slots but one.
        let strip = CatSheets.shared.restingStrip()
        let rects = (blink.values as? [NSValue])?.map(\.rectValue) ?? []
        #expect(rects.filter { $0 == strip.contentsRect(of: 1) }.count == 1)
        #expect(rects.filter { $0 == strip.contentsRect(of: 0) }.count == CatSpriteView.restingBlinkSlots - 1)
        #expect(blink.preferredFrameRateRange.maximum <= 4, "slow")
        #expect(!rig.leading.isShowingCat)
    }

    @Test func withReduceMotionTheCatSitsInTheMiddleOfTheRightWing() throws {
        let rig = StageRig(reducesMotion: true)
        rig.show()
        let lane = try #require(rig.stage.lane(for: rig.trailing))
        let host = rig.trailing
        let x = host.sprite.position.x + host.windowFrame.minX
        #expect(abs(x - lane.restingX) < 1)
        #expect(abs((x + host.sprite.bounds.width / 2) - host.windowFrame.midX) < 1)
    }

    @Test func withReduceMotionAClickStillMewsButTheCatDoesNotMove() {
        let rig = StageRig(reducesMotion: true)
        rig.stage.playsMeow = true
        rig.show()
        rig.stage.catWasClicked()
        #expect(rig.meow.plays == 1)
        #expect(rig.trailing.sprite.animationKeys() == [CatSpriteView.framesKey])
        #expect(rig.stage.plan?.pose != .purr)
    }

    @Test func turningReduceMotionOnWhileTheCatIsOnTheNotchStillsItAndOffGetsItGoingAgain() {
        let rig = StageRig()
        rig.show()
        rig.advance(3)
        #expect(rig.stage.isTicking)
        rig.reducesMotion = true
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { !rig.stage.isTicking }, seconds: 5))
        #expect(rig.scheduler.pendingCount == 0)
        #expect(rig.trailing.sprite.animationKeys() == [CatSpriteView.framesKey])

        rig.reducesMotion = false
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { rig.stage.isTicking }, seconds: 5))
        #expect(rig.scheduler.pendingCount == 1)
    }

    @Test func aMotionPreferenceHeardWhileNobodySeesTheCatIsNotHeardAtAll() {
        let rig = StageRig()
        rig.show()
        rig.hide()
        // The observer is gone with the last view: nothing is listening.
        rig.reducesMotion = true
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(!rig.stage.isAlive)
        #expect(rig.scheduler.pendingCount == 0)
        // And it is read afresh when the cat comes back.
        rig.show()
        #expect(!rig.stage.isTicking)
        #expect(rig.scheduler.pendingCount == 0)
    }
}
