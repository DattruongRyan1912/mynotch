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

    @Test func theStripComingIntoAWindowStartsTheCatAndOneWakingEveryQuarterOfASecond() {
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
        #expect(rig.host.isAnimating)
        let reads = (rig.idle.reads, rig.cpu.reads, rig.pointer.reads, rig.audio.reads)
        let ticks = rig.stage.ticks

        rig.hide()
        #expect(!rig.stage.isAlive)
        #expect(!rig.stage.isTicking)
        #expect(rig.scheduler.pendingCount == 0, "nothing is scheduled for a cat nobody sees")
        for layer in [rig.host.sprite, rig.host.prop] {
            #expect(layer.animationKeys() == nil || layer.animationKeys()?.isEmpty == true, "no animation on the layer")
            #expect(layer.isHidden)
        }
        #expect(!rig.host.isAnimating)
        rig.advance(600)
        #expect(rig.stage.ticks == ticks)
        #expect((rig.idle.reads, rig.cpu.reads, rig.pointer.reads, rig.audio.reads) == reads)
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
        #expect(plan.move == .sit)
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
        #expect(!rig.host.isAnimating)
        rig.hide()
        rig.show()
        #expect(!rig.stage.isAlive)
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func twoStripsOnTwoDisplaysShareOneCatAndTheLastToLeaveStopsIt() throws {
        let rig = StageRig()
        rig.show()
        let other = CatSpriteView(stage: rig.stage)
        other.frame = CGRect(x: 0, y: 0, width: 420, height: 26)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 26), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(other)
        #expect(rig.stage.attachedHosts.count == 2)
        #expect(rig.host.isShowingCat && other.isShowingCat)
        // The same move, and the place is the same share of each lane.
        let plan = try #require(rig.stage.plan)
        #expect(rig.host.sprite.animation(forKey: CatSpriteView.framesKey) != nil)
        #expect(other.sprite.animation(forKey: CatSpriteView.framesKey) != nil)
        #expect(plan.from == plan.to)
        let shares = [rig.host, other].map { ($0.sprite.position.x - $0.lane.minX) / $0.lane.travel }
        #expect(abs(shares[0] - shares[1]) < 0.02, "\(shares)")
        rig.hide()
        #expect(rig.stage.isAlive, "the other display still shows it")
        other.removeFromSuperview()
        #expect(!rig.stage.isAlive)
        #expect(rig.scheduler.pendingCount == 0)
    }

    // MARK: Where it is drawn

    @Test func theCatIsDrawnInsideTheStripThroughTwentyMinutes() {
        let rig = StageRig()
        rig.show()
        var places = Set<Int>()
        let bounds = rig.host.bounds
        for tick in 0..<(4 * 60 * 20) {
            if tick % (4 * 60) == 0 { rig.cpu.value = tick / (4 * 60) % 7 == 3 ? 0.9 : 0.05 }
            rig.advance(0.25)
            var xs = [rig.host.sprite.position.x]
            if let walk = rig.host.sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation {
                xs += (walk.values as? [NSNumber] ?? []).map { CGFloat($0.doubleValue) }
            }
            for x in xs {
                #expect(x >= 0 && x + CatSpriteView.spriteSize.width <= bounds.width, "the cat at \(x) in \(bounds.width)")
            }
            places.insert(Int(rig.host.sprite.position.x / 20))
        }
        #expect(places.count > 5, "it covers the strip")
    }

    @Test func everyLegBeginsWhereTheCatWasWhenItBeganThroughTwentyMinutes() {
        var legs = 0
        for seed: UInt64 in [5, 9] {
            let rig = StageRig(seed: seed)
            rig.show()
            var previous: CatPlan?
            var shown = rig.stage.presentations
            for tick in 0..<(4 * 60 * 20) {
                let minute = tick / 240
                rig.cpu.value = minute % 5 == 2 ? 0.9 : 0.05
                if tick % 700 == 400 { rig.place(pointerAtShare: Double(tick % 3) / 2, above: -10) } else if tick % 700 == 460 { rig.pointer.point = CGPoint(x: 5000, y: 5000) }
                rig.advance(0.25)
                guard rig.stage.presentations != shown, let plan = rig.stage.plan else { continue }
                shown = rig.stage.presentations
                defer { previous = plan }
                guard let before = previous, before.began != plan.began else { continue }
                legs += 1
                let host = rig.host
                let walk = host.sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation
                let startX = (walk?.values as? [NSNumber])?.first.map { CGFloat($0.doubleValue) } ?? host.sprite.position.x
                // Where the cat was when the plan began: the plan before it, at that moment, on the lane.
                let wasAt = host.lane.x(at: before.position(at: plan.began))
                #expect(abs(startX - wasAt) <= 4, "seed \(seed): a \(plan.move) begins at \(startX), where a \(before.move) had the cat at \(wasAt)")
                // The layer's own value is what the screen shows of a layer that its animation is not drawing: it is where the cat was, and
                // never where the leg is going, for as long as the animation has not taken over.
                #expect(host.sprite.position.x == startX, "seed \(seed): the layer is at \(host.sprite.position.x) and the leg begins at \(startX)")
                if let prop = plan.prop, let path = host.prop.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation {
                    let first = (path.values as? [NSNumber])?.first.map { CGFloat($0.doubleValue) }
                    #expect(host.prop.position.x == first, "seed \(seed): the \(prop.kind) lies at the start of its path")
                }
            }
        }
        #expect(legs > 300)
    }

    @Test func theCatAndWhatItPlaysWithAreShownExactlyWhenThePlanHasThem() {
        let rig = StageRig(seed: 5)
        rig.show()
        var sawMoth = false
        var sawYarn = false
        for _ in 0..<(4 * 60 * 30) {
            rig.advance(0.25)
            guard let plan = rig.stage.plan else { continue }
            #expect(rig.host.isShowingCat)
            #expect(rig.host.isShowingProp == (plan.prop != nil), "\(plan.move)")
            switch plan.prop?.kind {
            case .moth?:
                sawMoth = true
                #expect(rig.host.prop.animation(forKey: CatSpriteView.bobKey) != nil, "a moth bobs")
                #expect(rig.host.prop.animation(forKey: CatSpriteView.framesKey) != nil, "and flutters")
            case .yarn?:
                sawYarn = true
                #expect(rig.host.prop.animation(forKey: CatSpriteView.bobKey) == nil)
                let rolls = plan.prop!.from != plan.prop!.to
                #expect((rig.host.prop.animation(forKey: CatSpriteView.framesKey) != nil) == rolls, "the ball turns only while it rolls")
            case nil:
                #expect(!rig.host.prop.isHidden == false)
            }
        }
        #expect(sawMoth && sawYarn)
    }

    @Test func aHeadThatPeeksIsPlacedBelowTheEdgeSoItsRimIsCutOff() throws {
        var checked = false
        for seed: UInt64 in 1...10 {
            let rig = StageRig(seed: seed)
            rig.show()
            for _ in 0..<(4 * 60 * 20) {
                rig.advance(0.25)
                if rig.stage.plan?.move == .peek {
                    checked = true
                    #expect(rig.host.sprite.position.y == CatSpriteView.floor - CatSpriteView.peekSink)
                } else if rig.stage.plan != nil {
                    #expect(rig.host.sprite.position.y == CatSpriteView.floor)
                }
            }
        }
        #expect(checked)
    }

    @Test func choosingAnotherCoatChangesTheColoursAtOnce() throws {
        let rig = StageRig()
        rig.show()
        let sheets = CatSheets.shared
        let plan = try #require(rig.stage.plan)
        let tabby = sheets.strip(for: plan.move, facing: plan.facing, coat: .tabby)
        #expect(rig.host.sprite.contents as AnyObject === tabby.image)
        rig.stage.coat = .tuxedo
        let after = try #require(rig.stage.plan)
        let tuxedo = sheets.strip(for: after.move, facing: after.facing, coat: .tuxedo)
        #expect(rig.host.sprite.contents as AnyObject === tuxedo.image)
        #expect(tuxedo.image !== tabby.image)
    }

    @Test func aStripThatChangesWidthUnderTheCatMovesTheLaneWithIt() {
        let rig = StageRig()
        rig.show()
        let before = rig.stage.presentations
        rig.host.frame = CGRect(x: 0, y: 0, width: 360, height: 26)
        rig.host.layoutSubtreeIfNeeded()
        rig.stage.hostDidMove(rig.host)
        #expect(rig.stage.presentations > before)
        #expect(rig.host.lane.maxX + 32 == 360 - WalkLane.endInset)
    }

    @Test func aStripThatMovesWithoutTellingTheViewIsFoundOutAtTheNextWaking() throws {
        let rig = StageRig()
        rig.show()
        rig.advance(1)
        let before = rig.stage.presentations
        // Only the superview's place changes: the strip's own frame in its superview does not, but where it is in the window does.
        let shifted = NSView(frame: CGRect(x: 40, y: 0, width: 400, height: 26))
        let content = try #require(rig.window.contentView)
        content.addSubview(shifted)
        shifted.addSubview(rig.host)
        #expect(rig.stage.isAlive)
        rig.advance(0.25)
        #expect(rig.stage.presentations > before)
    }

    // MARK: What it does

    @Test func withTheUserAwayForTheSleepTimeItYawnsLiesDownAndSleeps() throws {
        let rig = StageRig()
        rig.stage.tuning = CatTuning(sleepAfter: 120)
        rig.idle.seconds = 130
        rig.show()
        // The cat finishes what it was doing, which is the two seconds of sitting it starts with.
        rig.advance(1)
        #expect(try #require(rig.stage.plan).move == .sit)
        rig.advance(15)
        #expect(try #require(rig.stage.plan).move == .sleep)
        #expect(rig.host.isAnimating)
        let frames = try #require(rig.host.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation)
        #expect(frames.values?.count == CatMove.sleep.frameCount)
        // It sleeps on without being redrawn.
        let presentations = rig.stage.presentations
        rig.advance(60)
        #expect(rig.stage.presentations == presentations)
    }

    @Test func thePointerComingNearTheStripMakesItPounceOrJump() throws {
        var reactions = Set<CatMove>()
        for seed: UInt64 in 1...20 {
            let rig = StageRig(seed: seed)
            rig.show()
            rig.advance(2)
            rig.place(pointerAtShare: 0.8, above: -30)
            rig.advance(0.25)
            let move = try #require(rig.stage.plan).move
            reactions.insert(move)
            let frames = try #require(rig.host.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation)
            #expect(frames.values?.count == move.frameCount)
        }
        #expect(reactions == [.pounce, .startled])
    }

    @Test func aPointerInSightMakesASittingCatLookAtItAndOneThatLeavesLetsItGoBack() throws {
        let rig = StageRig(seed: 3)
        rig.show()
        rig.advance(0.5)
        rig.place(pointerAtShare: 0.0, above: 60)
        rig.advance(0.5)
        #expect(try #require(rig.stage.plan).move == .lookLeft)
        rig.place(pointerAtShare: 1.0, above: 60)
        rig.advance(0.5)
        #expect(try #require(rig.stage.plan).move == .lookRight)
        rig.pointer.point = CGPoint(x: 5000, y: 5000)
        rig.advance(0.5)
        #expect(![CatMove.lookLeft, .lookRight, .lookUp].contains(try #require(rig.stage.plan).move))
    }

    @Test func aPointerThatStaysFarAwayNeverMakesItPounceOrJump() {
        let rig = StageRig()
        rig.show()
        for _ in 0..<(4 * 60 * 10) {
            rig.advance(0.25)
            let move = rig.stage.plan?.move
            #expect(move != .pounce && move != .startled)
        }
    }

    @Test func soundPlayingMakesItDance() throws {
        let rig = StageRig()
        rig.audio.playing = true
        rig.show()
        rig.advance(1)
        #expect(try #require(rig.stage.plan).move == .dance)
        rig.audio.playing = false
        rig.advance(1)
        #expect(try #require(rig.stage.plan).move != .dance)
    }

    @Test func atNightItSleepsSoonerThanByDay() throws {
        let day = StageRig(hour: 12)
        day.idle.seconds = 100
        day.show()
        day.advance(20)
        #expect(try #require(day.stage.plan).move != .sleep)
        let night = StageRig(hour: 23)
        night.idle.seconds = 100
        night.show()
        night.advance(20)
        #expect(try #require(night.stage.plan).move == .sleep)
    }

    @Test func theCatIsRedrawnOnlyWhenItsPictureChangesNotAtEveryWaking() {
        let rig = StageRig()
        rig.show()
        rig.advance(600)
        #expect(rig.stage.ticks == 2400)
        #expect(rig.stage.presentations < 700, "a new picture every few seconds: \(rig.stage.presentations)")
    }

    // MARK: Petting

    @Test func aClickMakesItPurrWithoutAMewByDefault() throws {
        let rig = StageRig()
        rig.show()
        rig.advance(1)
        rig.stage.catWasClicked()
        #expect(try #require(rig.stage.plan).move == .purr)
        #expect(rig.stage.strokes == 1)
        #expect(rig.meow.plays == 0)
        let frames = try #require(rig.host.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation)
        #expect(frames.values?.count == CatMove.purr.frameCount)
        rig.advance(CatBrain.purrDuration + 1)
        #expect(try #require(rig.stage.plan).move != .purr)
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
        rig.host.mouseDown(with: event)
        #expect(rig.stage.strokes == 1)
        #expect(rig.stage.plan?.move == .purr)
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

        let host = rig.host
        #expect(host.isShowingCat)
        #expect(!host.isShowingProp)
        #expect(host.sprite.animationKeys() == [CatSpriteView.framesKey], "the blink and nothing else: no walk, no frames of a gait")
        let blink = try #require(host.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation)
        #expect(blink.values?.count == CatSpriteView.restingBlinkSlots)
        #expect(blink.duration == CatSpriteView.restingBlinkPeriod)
        #expect(blink.calculationMode == .discrete)
        #expect(blink.repeatCount == .infinity)
        let strip = CatSheets.shared.restingStrip(coat: .tabby)
        let rects = (blink.values as? [NSValue])?.map(\.rectValue) ?? []
        #expect(rects.filter { $0 == strip.contentsRect(of: 1) }.count == 1)
        #expect(rects.filter { $0 == strip.contentsRect(of: 0) }.count == CatSpriteView.restingBlinkSlots - 1)
        #expect(blink.preferredFrameRateRange.maximum <= 4, "slow")
    }

    @Test func withReduceMotionTheCatSitsInTheMiddleOfTheStrip() {
        let rig = StageRig(reducesMotion: true)
        rig.show()
        let x = rig.host.sprite.position.x
        #expect(abs((x + rig.host.sprite.bounds.width / 2) - rig.host.bounds.midX) <= 1)
    }

    @Test func withReduceMotionAClickStillMewsButTheCatDoesNotMove() {
        let rig = StageRig(reducesMotion: true)
        rig.stage.playsMeow = true
        rig.show()
        rig.stage.catWasClicked()
        #expect(rig.meow.plays == 1)
        #expect(rig.host.sprite.animationKeys() == [CatSpriteView.framesKey])
        #expect(rig.stage.plan?.move != .purr)
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
        #expect(rig.host.sprite.animationKeys() == [CatSpriteView.framesKey])

        rig.reducesMotion = false
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { rig.stage.isTicking }, seconds: 5))
        #expect(rig.scheduler.pendingCount == 1)
    }

    @Test func aMotionPreferenceHeardWhileNobodySeesTheCatIsNotHeardAtAll() {
        let rig = StageRig()
        rig.show()
        rig.hide()
        rig.reducesMotion = true
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(!rig.stage.isAlive)
        #expect(rig.scheduler.pendingCount == 0)
        rig.show()
        #expect(!rig.stage.isTicking)
        #expect(rig.scheduler.pendingCount == 0)
    }
}
