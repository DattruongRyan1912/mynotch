import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import PetModule

/// The view's layers and animations, driven directly with plans of the test's own.
@Suite(.serialized) @MainActor struct CatSpriteViewTests {
    func plan(
        _ move: CatMove, from: Double = 0.3, to: Double? = nil, duration: TimeInterval = 3, scale: Double = 1, delay: Double = 0,
        prop: CatProp? = nil, facing: Facing = .right
    ) -> CatPlan {
        CatPlan(move: move, facing: facing, from: from, to: to ?? from, began: 0, duration: duration, fpsScale: scale, delay: delay, prop: prop)
    }

    func frames(of layer: CALayer) throws -> CAKeyframeAnimation {
        try #require(layer.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation)
    }

    func walk(of layer: CALayer) throws -> CAKeyframeAnimation {
        try #require(layer.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation)
    }

    func places(_ animation: CAKeyframeAnimation) -> [CGFloat] {
        (animation.values as? [NSNumber])?.map { CGFloat($0.doubleValue) } ?? []
    }

    @Test func theCatIsDrawnWithNearestNeighbourFilteringOnePixelToThePoint() throws {
        let rig = StageRig()
        let host = rig.host
        host.show(plan: plan(.sit), elapsed: 0, coat: .tabby)
        #expect(host.sprite.magnificationFilter == .nearest && host.sprite.minificationFilter == .nearest)
        #expect(host.sprite.contentsGravity == .resize)
        #expect(host.sprite.contents != nil)
        #expect(host.sprite.bounds.size == CGSize(width: 32, height: 24), "one pixel of the picture to the point: two on a Retina display")
        #expect(host.sprite.position.y == CatSpriteView.floor)
        #expect(host.sprite.position.x == host.sprite.position.x.rounded(), "on a whole point")
        #expect(host.sprite.anchorPoint == .zero)
        #expect(host.sprite.bounds.height + CatSpriteView.floor <= host.bounds.height)
        #expect(host.prop.magnificationFilter == .nearest)
    }

    @Test func theFramesAreOneKeyframeAnimationOfTheContentsRectThatHoldsEachFrameAndNeverBlendsThem() throws {
        let rig = StageRig()
        let host = rig.host
        host.show(plan: plan(.walk), elapsed: 0, coat: .tabby)
        let animation = try frames(of: host.sprite)
        #expect(animation.keyPath == "contentsRect")
        #expect(animation.calculationMode == .discrete)
        #expect(animation.repeatCount == .infinity)
        #expect(animation.values?.count == 8)
        #expect(animation.duration == CatMove.walk.passDuration)
        let strip = CatSheets.shared.strip(for: .walk, facing: .right, coat: .tabby)
        let shown: [CGRect] = (animation.values as? [NSValue])?.map(\.rectValue) ?? []
        let expected: [CGRect] = (0..<8).map { strip.contentsRect(of: $0) }
        #expect(shown == expected)
        #expect(host.sprite.animationKeys() == [CatSpriteView.framesKey], "a cat that does not go anywhere has the frames and nothing else")
    }

    @Test func aMoveThatIsPlayedOnceIsPlayedOnceAndHeldOnItsLastFrame() throws {
        let rig = StageRig()
        for move in CatMove.allCases where !move.loops {
            rig.host.show(plan: plan(move), elapsed: 0, coat: .tabby)
            let animation = try frames(of: rig.host.sprite)
            #expect(animation.repeatCount == 0 || animation.repeatCount == 1, "\(move)")
            #expect(animation.fillMode == .both && !animation.isRemovedOnCompletion, "\(move): held on its first frame and on its last")
            #expect(abs(animation.duration - move.passDuration) < 1e-9)
        }
        for move in CatMove.allCases where move.loops {
            rig.host.show(plan: plan(move), elapsed: 0, coat: .tabby)
            #expect(try frames(of: rig.host.sprite).repeatCount == .infinity, "\(move)")
        }
    }

    @Test func theFramesRunAtTheirOwnRateAndNeverAskTheDisplayForMoreThanTwentyFour() throws {
        let rig = StageRig()
        for move in CatMove.allCases {
            rig.host.show(plan: plan(move), elapsed: 0, coat: .tabby)
            let range = try frames(of: rig.host.sprite).preferredFrameRateRange
            #expect(range.maximum <= CatSpriteView.frameRateCeiling, "\(move)")
            let preferred = try #require(range.preferred)
            #expect(preferred <= 15, "\(move)")
            #expect(preferred == Float(max(move.fps, 4)), "\(move)")
        }
    }

    @Test func aCatThatRunsHarderPlaysItsFramesFaster() throws {
        let rig = StageRig()
        rig.host.show(plan: plan(.frantic, scale: 1), elapsed: 0, coat: .tabby)
        let slow = try frames(of: rig.host.sprite)
        rig.host.show(plan: plan(.frantic, scale: 1.5), elapsed: 0, coat: .tabby)
        let fast = try frames(of: rig.host.sprite)
        #expect(abs(slow.duration / fast.duration - 1.5) < 1e-9)
        #expect(try #require(fast.preferredFrameRateRange.preferred) > (try #require(slow.preferredFrameRateRange.preferred)))
    }

    @Test func aWalkMovesTheFootAFewPointsAtATimeAtTheMovesPaceAndHoldsEachPlaceUntilTheNextStep() throws {
        let rig = StageRig()
        let host = rig.host
        let lane = host.lane
        let distance = (0.9 - 0.1) * Double(lane.travel)
        host.show(plan: plan(.walk, from: 0.1, to: 0.9, duration: distance / CatMove.walk.speed), elapsed: 0, coat: .tabby)
        let animation = try walk(of: host.sprite)
        #expect(animation.keyPath == "position.x")
        #expect(animation.calculationMode == .discrete)
        let stops = places(animation)
        #expect(stops.count > 20)
        // Two points a frame, which is the pace of a walk: twelve of those a second.
        for (before, after) in zip(stops, stops.dropFirst()) { #expect(abs((after - before) - 2) < 1e-9, "\(after - before)") }
        for place in stops { #expect(place == place.rounded()) }
        #expect(stops.first == lane.x(at: 0.1).rounded())
        #expect(abs((stops.last ?? 0) - lane.x(at: 0.9)) <= 1.5)
        // The layer is where the cat stands until the leg says it is over.
        #expect(host.sprite.position.x == stops.first)
        try arrive(host.sprite)
        #expect(host.sprite.position.x == stops.last)
        #expect(animation.fillMode == .both && !animation.isRemovedOnCompletion, "held on its first place until it begins and on its last")
        #expect(Set(host.sprite.animationKeys() ?? []) == [CatSpriteView.framesKey, CatSpriteView.walkKey])
        // The steps come twelve a second.
        #expect(abs(Double(stops.count) / animation.duration - 12) < 1)
    }

    @Test func aTrotAndAChaseTakeBiggerStepsAtTheSameRate() throws {
        let rig = StageRig()
        for move in [CatMove.trot, .chase, .frantic] {
            let distance = 0.8 * Double(rig.host.lane.travel)
            rig.host.show(plan: plan(move, from: 0.1, to: 0.9, duration: distance / move.speed), elapsed: 0, coat: .tabby)
            let stops = places(try walk(of: rig.host.sprite))
            let step = stops[1] - stops[0]
            #expect(abs(step - move.advance) < 1e-9, "\(move)")
        }
    }

    // MARK: Turning round

    @Test func aLegBeginsExactlyWhereTheLastOneEndedEvenWhenThatIsNotWhereTheShareRoundsTo() throws {
        let rig = StageRig()
        let host = rig.host
        // Steps of five points: from 32 they land on 237, and the share of 0.9 is at 236.
        host.show(plan: plan(.walk, from: 0.1, to: 0.9, duration: 3.4), elapsed: 0, coat: .tabby)
        let stops = places(try walk(of: host.sprite))
        #expect(stops[1] - stops[0] == 5)
        let endedAt = try #require(stops.last)
        let shareX = host.lane.x(at: 0.9).rounded()
        #expect(endedAt != shareX, "the end of a leg is not where the share rounds to: \(endedAt) and \(shareX)")

        // The leg has not said it is over (a render server that is a little late): the next one begins at its end all the same.
        host.show(plan: plan(.walk, from: 0.9, to: 0.2, duration: 3, facing: .left), elapsed: 0, coat: .tabby)
        #expect(places(try walk(of: host.sprite)).first == endedAt, "the next leg starts there, and not a point from it")
        #expect(host.sprite.position.x == endedAt, "and the layer is there until the leg is away")
    }

    @Test func aCatThatStaysWhereItEndedStaysThereToTheOnePoint() throws {
        let rig = StageRig()
        let host = rig.host
        host.show(plan: plan(.walk, from: 0.1, to: 0.9, duration: 3.4), elapsed: 0, coat: .tabby)
        let endedAt = try #require(places(try walk(of: host.sprite)).last)
        #expect(endedAt != host.lane.x(at: 0.9).rounded())
        try arrive(host.sprite)
        host.show(plan: plan(.sit, from: 0.9), elapsed: 0, coat: .tabby)
        #expect(host.sprite.position.x == endedAt)
        #expect(host.sprite.animationKeys() == [CatSpriteView.framesKey], "and does not walk the few points to the share's place")
    }

    @Test func aPlanThatBeginsSomewhereElseBeginsThereAndNotWhereTheLayerWas() throws {
        let rig = StageRig()
        let host = rig.host
        host.show(plan: plan(.walk, from: 0.1, to: 0.9, duration: 8), elapsed: 0, coat: .tabby)
        // A pounce that came mid-leg began where the cat was then, which is nowhere near where the leg was going.
        host.show(plan: plan(.pounce, from: 0.4, to: 0.5, duration: 0.8, delay: 0.625), elapsed: 0, coat: .tabby)
        #expect(places(try walk(of: host.sprite)).first == host.lane.x(at: 0.4).rounded())
        // And a cat that was not on show begins at the plan's own place.
        host.stopShowing()
        host.show(plan: plan(.sit, from: 0.7), elapsed: 0, coat: .tabby)
        #expect(host.sprite.position.x == host.lane.x(at: 0.7).rounded())
    }

    @Test func theCatIsTurnedByTheMirrorImageOfItsPicturesAndNeverByTransformingItsLayer() throws {
        let rig = StageRig()
        let host = rig.host
        host.show(plan: plan(.walk, from: 0.1, to: 0.9, duration: 8), elapsed: 0, coat: .tabby)
        let size = host.sprite.bounds.size
        host.show(plan: plan(.walk, from: 0.9, to: 0.1, duration: 8, facing: .left), elapsed: 0, coat: .tabby)
        #expect(CATransform3DIsIdentity(host.sprite.transform), "no flip of the layer, which would move it about its anchor")
        #expect(host.sprite.bounds.size == size && host.sprite.anchorPoint == .zero)
        #expect(host.sprite.contents as AnyObject === CatSheets.shared.strip(for: .walk, facing: .left, coat: .tabby).image)
    }

    @Test func everyAnimationHoldsItsFirstValueFromTheMomentItIsAddedSoNothingShowsBeforeItBegins() throws {
        let rig = StageRig()
        let host = rig.host
        host.show(
            plan: plan(.chase, from: 0.1, to: 0.9, duration: 4, prop: CatProp(kind: .moth, from: 0.2, to: 1.2)), elapsed: 0, coat: .tabby
        )
        for layer in [host.sprite, host.prop] {
            for key in layer.animationKeys() ?? [] {
                #expect((layer.animation(forKey: key)?.fillMode == .both), "\(key) holds its first value until it begins and its last when it is over")
            }
        }
    }

    @Test func theLayerIsWhereTheCatStandsAndNeverWhereItIsGoingWhileTheAnimationHasNotTakenOver() throws {
        let rig = StageRig()
        let host = rig.host
        let lane = host.lane
        host.show(
            plan: plan(.chase, from: 0.1, to: 0.9, duration: 4, prop: CatProp(kind: .moth, from: 0.2, to: 1.2)), elapsed: 0, coat: .tabby
        )
        // What the screen shows of a layer that its animation is not (yet) drawing: the layer's own value.
        let (cat, moth) = (try walk(of: host.sprite), try walk(of: host.prop))
        host.sprite.removeAllAnimations()
        host.prop.removeAllAnimations()
        #expect(host.sprite.position.x == places(cat).first, "the cat at the start of its leg, not at its end \(places(cat).last ?? 0)")
        #expect(host.sprite.position.x < lane.x(at: 0.2))
        #expect(host.prop.position.x == places(moth).first, "and the moth at the start of its path")
        #expect(host.prop.position.x < lane.x(at: 0.4))
    }

    @Test func aLegIsBegunAtTheTimeItIsAddedAndNotAtTheCommit() throws {
        let rig = StageRig()
        let host = rig.host
        let before = host.sprite.convertTime(CACurrentMediaTime(), from: nil)
        host.show(plan: plan(.walk, from: 0.1, to: 0.9, duration: 6), elapsed: 0, coat: .tabby)
        let after = host.sprite.convertTime(CACurrentMediaTime(), from: nil)
        for key in [CatSpriteView.framesKey, CatSpriteView.walkKey] {
            let begin = try #require(host.sprite.animation(forKey: key)?.beginTime)
            #expect(begin >= before && begin <= after, "\(key) begins now, never at a time that is yet to come: \(begin - after)")
        }
    }

    @Test func aLegThatIsOverMovesTheLayerToItsEndOnlyIfItIsStillTheLegOnShow() throws {
        let rig = StageRig()
        let host = rig.host
        host.show(plan: plan(.walk, from: 0.1, to: 0.9, duration: 8), elapsed: 0, coat: .tabby)
        let first = try walk(of: host.sprite)
        let firstEnd = try #require(places(first).last)
        // Another leg takes its place before it is over, and then the first one is heard to say that it is: it is not the one to say so.
        host.show(plan: plan(.walk, from: 0.5, to: 0.2, duration: 8, facing: .left), elapsed: 0, coat: .tabby)
        let place = host.sprite.position.x
        first.delegate?.animationDidStop?(first, finished: true)
        #expect(host.sprite.position.x == place, "the layer was not moved to \(firstEnd) by a leg that had been replaced")
        // A leg that was removed rather than run to its end does not say it is over either.
        let second = try walk(of: host.sprite)
        second.delegate?.animationDidStop?(second, finished: false)
        #expect(host.sprite.position.x == place)
        // And one that is heard when the view has stopped showing the cat does nothing.
        host.stopShowing()
        second.delegate?.animationDidStop?(second, finished: true)
        #expect(host.sprite.isHidden)
    }

    @Test func aWalkToTheLeftStepsTheOtherWayAndIsPlayedFromTheMirrorImage() throws {
        let rig = StageRig()
        rig.host.show(plan: plan(.walk, from: 0.9, to: 0.1, duration: 8, facing: .left), elapsed: 0, coat: .tabby)
        let stops = places(try walk(of: rig.host.sprite))
        #expect(stops == stops.sorted(by: >))
        #expect(rig.host.sprite.contents as AnyObject === CatSheets.shared.strip(for: .walk, facing: .left, coat: .tabby).image)
        #expect(rig.host.sprite.contents as AnyObject !== CatSheets.shared.strip(for: .walk, facing: .right, coat: .tabby).image)
    }

    @Test func aPounceCrouchesInPlaceAndThenLeaps() throws {
        let rig = StageRig()
        rig.host.show(plan: plan(.pounce, from: 0.3, to: 0.5, duration: 0.8, delay: 0.625), elapsed: 0, coat: .tabby)
        let stops = places(try walk(of: rig.host.sprite))
        let from = rig.host.lane.x(at: 0.3).rounded()
        let held = stops.prefix { $0 == from }.count
        #expect(Double(held) / Double(stops.count) > 0.5, "most of the plan is the crouch: \(held) of \(stops.count)")
        #expect(stops.last == rig.host.lane.x(at: 0.5).rounded() || abs((stops.last ?? 0) - rig.host.lane.x(at: 0.5)) <= 2)
    }

    @Test func walkStopsAreEvenlySpacedAndNeverSkipPastTheEnd() {
        let upward: [CGFloat] = (0...5).map { CGFloat($0) * 2 }
        let downward: [CGFloat] = (0...5).map { (10 as CGFloat) - CGFloat($0) * 2 }
        #expect(CatSpriteView.walkStops(from: 0, to: 10, step: 2) == upward)
        #expect(CatSpriteView.walkStops(from: 10, to: 0, step: 2) == downward)
        #expect(CatSpriteView.walkStops(from: 3, to: 3, step: 2) == [3])
        #expect(CatSpriteView.walkStops(from: 0, to: 0.2, step: 2) == [0, 2], "a step is the least it moves")
        #expect(CatSpriteView.walkStops(from: 0, to: 5, step: 0) == [0])
    }

    /// An animation that was shown `elapsed` seconds into its plan began that long ago, on the layer's own time, which is not the time it was
    /// added at. It is never given a `timeOffset`: that wraps an animation round, so that one held when it is over is held on its first value.
    func expectBegan(
        _ animation: CAAnimation, ago: TimeInterval, between before: CFTimeInterval, and after: CFTimeInterval, _ label: String
    ) {
        #expect(animation.timeOffset == 0, "\(label): a time offset wraps the animation round, and holds its first value when it is over")
        #expect(
            animation.beginTime >= before - ago - 1e-9 && animation.beginTime <= after - ago + 1e-9,
            "\(label): began \(after - animation.beginTime) seconds ago, not \(ago)"
        )
    }

    @Test func aPlanThatIsAlreadyUnderWayBeganThatLongAgoAndIsNeverGivenATimeOffset() throws {
        let rig = StageRig()
        let host = rig.host
        func show(_ plan: CatPlan, elapsed: TimeInterval) -> (before: CFTimeInterval, after: CFTimeInterval) {
            let before = host.sprite.convertTime(CACurrentMediaTime(), from: nil)
            host.show(plan: plan, elapsed: elapsed, coat: .tabby)
            return (before, host.sprite.convertTime(CACurrentMediaTime(), from: nil))
        }
        var (before, after) = show(plan(.walk, from: 0.1, to: 0.9, duration: 10), elapsed: 1.3)
        expectBegan(try walk(of: host.sprite), ago: 1.3, between: before, and: after, "walk")
        expectBegan(
            try frames(of: host.sprite), ago: 1.3.truncatingRemainder(dividingBy: CatMove.walk.passDuration), between: before, and: after, "frames"
        )
        // One that has run past its end is held at the end rather than asked for a time it does not have.
        (before, after) = show(plan(.walk, from: 0.1, to: 0.9, duration: 4), elapsed: 9)
        expectBegan(try walk(of: host.sprite), ago: 4, between: before, and: after, "a walk run past its end")
        (before, after) = show(plan(.yawn), elapsed: 99)
        expectBegan(try frames(of: host.sprite), ago: CatMove.yawn.passDuration, between: before, and: after, "a move played once is held on its last frame")
        // The moth is as far along as the cat is.
        (before, after) = show(plan(.chase, from: 0.1, to: 0.9, duration: 4, prop: CatProp(kind: .moth, from: 0.2, to: 1.2)), elapsed: 0.7)
        expectBegan(try walk(of: host.prop), ago: 0.7, between: before, and: after, "the moth's path")
        expectBegan(try frames(of: host.prop), ago: 0.7.truncatingRemainder(dividingBy: PropArt.moth.duration), between: before, and: after, "its wings")
        let bob = try #require(host.prop.animation(forKey: CatSpriteView.bobKey))
        expectBegan(bob, ago: 0.7.truncatingRemainder(dividingBy: bob.duration), between: before, and: after, "its bob")
    }

    @Test func noAnimationOfAnyMoveIsEverGivenATimeOffsetWhateverTheTimeItIsShownAt() throws {
        let rig = StageRig()
        let host = rig.host
        let props: [CatProp?] = [nil, CatProp(kind: .moth, from: 0.2, to: 1.2), CatProp(kind: .yarn, from: 0.4, to: 0.7)]
        for move in CatMove.allCases {
            for elapsed in [0.000_02, 0.002, 0.3, 11] {
                for item in props {
                    host.show(plan: plan(move, from: 0.2, to: move.advance > 0 ? 0.8 : 0.2, duration: 4, prop: item), elapsed: elapsed, coat: .tabby)
                    for layer in [host.sprite, host.prop] {
                        for key in layer.animationKeys() ?? [] {
                            #expect(layer.animation(forKey: key)?.timeOffset == 0, "\(move) at \(elapsed), \(key)")
                        }
                    }
                }
            }
        }
    }

    @Test func aNewPlanTakesTheOldAnimationsAwayFirst() throws {
        let rig = StageRig()
        rig.host.show(plan: plan(.walk, from: 0.1, to: 0.9, duration: 8), elapsed: 0, coat: .tabby)
        #expect(rig.host.sprite.animation(forKey: CatSpriteView.walkKey) != nil)
        rig.host.show(plan: plan(.sit), elapsed: 0, coat: .tabby)
        #expect(rig.host.sprite.animation(forKey: CatSpriteView.walkKey) == nil, "no walk left over from the plan before")
        #expect(rig.host.sprite.animationKeys() == [CatSpriteView.framesKey])
    }

    @Test func stoppingTakesTheCatTheMothAndEveryAnimationAway() {
        let rig = StageRig()
        rig.host.show(plan: plan(.chase, from: 0.1, to: 0.9, duration: 4, prop: CatProp(kind: .moth, from: 0.2, to: 1.2)), elapsed: 0, coat: .tabby)
        #expect(rig.host.isShowingProp && rig.host.isAnimating)
        rig.host.stopShowing()
        #expect(!rig.host.isAnimating)
        #expect(!rig.host.isShowingCat && !rig.host.isShowingProp)
    }

    // MARK: Props

    @Test func aMothFlutterGoesAcrossTheStripAndBobsOnTheWay() throws {
        let rig = StageRig()
        let lane = rig.host.lane
        let item = CatProp(kind: .moth, from: 0.2, to: 1.2)
        rig.host.show(plan: plan(.chase, from: 0.1, to: 0.9, duration: 4, prop: item), elapsed: 0, coat: .tabby)
        let host = rig.host
        let wings = try frames(of: host.prop)
        #expect(wings.values?.count == 2 && wings.repeatCount == .infinity)
        #expect(abs(wings.duration - PropArt.moth.duration) < 1e-9)
        let across = places(try walk(of: host.prop))
        #expect(across.first == lane.unboundedX(at: 0.2).rounded())
        #expect((across.last ?? 0) > lane.maxX, "it leaves at the end of the strip, and the strip's edge cuts it off")
        let bob = try #require(host.prop.animation(forKey: CatSpriteView.bobKey) as? CAKeyframeAnimation)
        #expect(bob.keyPath == "position.y" && bob.repeatCount == .infinity)
        let heights = (bob.values as? [NSNumber])?.map { CGFloat($0.doubleValue) } ?? []
        #expect(Set(heights).count > 3, "it bobs")
        for height in heights { #expect(height > CatSpriteView.mothHeight - 3 && height + 7 < host.bounds.height, "\(height)") }
        #expect(host.prop.bounds.size == CGSize(width: 11, height: 7))
    }

    @Test func aBallOfYarnLiesStillOrRollsAndTurnsWhileItRolls() throws {
        let rig = StageRig()
        let host = rig.host
        let lane = host.lane
        host.show(plan: plan(.walk, from: 0.1, to: 0.3, duration: 3, prop: CatProp(kind: .yarn, from: 0.5, to: 0.5)), elapsed: 0, coat: .tabby)
        #expect(host.isShowingProp)
        #expect(host.prop.animationKeys() == nil || host.prop.animationKeys()?.isEmpty == true, "nothing runs for a ball that lies")
        #expect(host.prop.position.x == lane.unboundedX(at: 0.5).rounded())
        #expect(host.prop.position.y == CatSpriteView.floor)
        #expect(host.prop.bounds.size == CGSize(width: 12, height: 12))

        host.show(plan: plan(.yarn, from: 0.4, duration: 1.6, prop: CatProp(kind: .yarn, from: 0.5, to: 0.62)), elapsed: 0, coat: .tabby)
        let turning = try frames(of: host.prop)
        #expect(turning.values?.count == 4)
        let stops = places(try walk(of: host.prop))
        #expect(stops.first == lane.unboundedX(at: 0.5).rounded())
        #expect(abs((stops.last ?? 0) - lane.unboundedX(at: 0.62)) <= 2)
        #expect(host.prop.position.x == stops.first, "it is where it lay until it has rolled")
        try arrive(host.prop)
        #expect(host.prop.position.x == stops.last, "and where it stopped once it has")
    }

    @Test func aPlanWithNothingToPlayWithHidesWhatWasThere() {
        let rig = StageRig()
        rig.host.show(plan: plan(.yarn, prop: CatProp(kind: .yarn, from: 0.5, to: 0.6)), elapsed: 0, coat: .tabby)
        #expect(rig.host.isShowingProp)
        rig.host.show(plan: plan(.sit), elapsed: 0, coat: .tabby)
        #expect(!rig.host.isShowingProp)
        #expect(rig.host.prop.animationKeys() == nil || rig.host.prop.animationKeys()?.isEmpty == true)
    }

    // MARK: Hits

    @Test func onlyTheCatTakesAClickAndTheRestOfTheStripLeavesItToTheNotch() throws {
        let rig = StageRig()
        rig.show()
        let host = rig.host
        let sprite = host.sprite.frame
        let inside = host.convert(CGPoint(x: sprite.midX, y: sprite.midY), to: host.superview)
        #expect(host.hitTest(inside) === host)
        // A point on the strip a long way from the cat.
        let farX = sprite.midX < host.bounds.midX ? host.bounds.maxX - 6 : host.bounds.minX + 6
        let away = host.convert(CGPoint(x: farX, y: 13), to: host.superview)
        #expect(host.hitTest(away) == nil)
        #expect(host.hitTest(CGPoint(x: -500, y: -500)) == nil)
        // A moth is no part of the cat, and takes no clicks.
        host.show(plan: plan(.chase, from: 0.1, to: 0.9, duration: 4, prop: CatProp(kind: .moth, from: 0.5, to: 1.2)), elapsed: 0, coat: .tabby)
        let propPoint = host.convert(CGPoint(x: host.prop.frame.midX, y: host.prop.frame.midY), to: host.superview)
        #expect(host.hitTest(propPoint) == nil || host.sprite.frame.insetBy(dx: -2, dy: -2).contains(host.convert(propPoint, from: host.superview)))
    }

    @Test func aStripWithNoCatInItTakesNoClicks() {
        let rig = StageRig()
        rig.show()
        rig.hide()
        #expect(rig.host.hitTest(CGPoint(x: 150, y: 10)) == nil)
    }

    @Test func theFirstClickIsTakenEvenThoughTheNotchIsNeverActive() {
        let rig = StageRig()
        #expect(rig.host.acceptsFirstMouse(for: nil))
        #expect(!rig.host.mouseDownCanMoveWindow)
    }

    // MARK: In SwiftUI

    final class Counter {
        var bodies = 0
        var taps = 0
        /// Every width the views under the notch asked for.
        var stripWidths: [CGFloat] = []
    }

    /// The strip as the collapsed notch lays it out, under a tap that opens the notch.
    struct Strip: View {
        let stage: CatStage
        let counter: Counter
        var onScreen = true

        var body: some View {
            let _ = counter.bodies += 1
            CatStripView(stage: stage)
                .frame(width: 300, height: CatActivity.stripHeight)
                .environment(\.notchIsOnScreen, onScreen)
                .onNotchStripWidth { counter.stripWidths.append($0) }
                .contentShape(Rectangle())
                .gesture(TapGesture().onEnded { counter.taps += 1 }, including: .all)
        }
    }

    func hosted(_ rig: StageRig, counter: Counter, onScreen: Bool = true) -> (CountingHostingView<Strip>, NSWindow) {
        let hosting = CountingHostingView(rootView: Strip(stage: rig.stage, counter: counter, onScreen: onScreen))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 26), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    @Test func theViewIsInTheTreeOnlyWhileTheNotchCanBeSeen() {
        let rig = StageRig()
        let counter = Counter()
        let (hosting, window) = hosted(rig, counter: counter)
        #expect(rig.stage.isAlive)
        #expect(rig.stage.attachedHosts.count == 1)
        #expect(rig.scheduler.pendingCount == 1)

        hosting.rootView = Strip(stage: rig.stage, counter: counter, onScreen: false)
        #expect(runLoop(until: { !rig.stage.isAlive }, seconds: 10))
        #expect(rig.scheduler.pendingCount == 0)

        hosting.rootView = Strip(stage: rig.stage, counter: counter, onScreen: true)
        #expect(runLoop(until: { rig.stage.isAlive }, seconds: 10))
        window.contentView = nil
        #expect(!rig.stage.isAlive)
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func aCatThatIsNotOnScreenIsNeverMadeAtAll() {
        let rig = StageRig()
        let (_, window) = hosted(rig, counter: Counter(), onScreen: false)
        #expect(!rig.stage.isAlive)
        #expect(rig.stage.attachedHosts.isEmpty)
        #expect(rig.scheduler.pendingCount == 0)
        window.contentView = nil
    }

    @Test func aMinuteOfTheCatLivingIsNoWorkForSwiftUIAtAll() {
        let rig = StageRig(seed: 5)
        rig.cpu.value = 0.9
        let counter = Counter()
        let (hosting, window) = hosted(rig, counter: counter)
        rig.advance(1)
        let (bodies, layouts, presentations) = (counter.bodies, hosting.layouts, rig.stage.presentations)
        // A minute of a cat that runs, pounces, sleeps and wakes, as busy a minute as it gets.
        for second in 0..<60 {
            if second == 20 { rig.place(pointerAtShare: 0.5, above: -10) }
            if second == 30 { rig.cpu.value = 0.05 }
            rig.advance(1)
        }
        #expect(rig.stage.presentations > presentations, "the cat did move")
        #expect(counter.bodies == bodies, "no body evaluated")
        #expect(hosting.layouts == layouts, "no layout pass")
        window.contentView = nil
    }

    @Test func theCatAsksTheNotchForNothingAndNeverReportsAStripWidth() {
        let rig = StageRig()
        let counter = Counter()
        let (hosting, window) = hosted(rig, counter: counter)
        rig.advance(30)
        #expect(counter.stripWidths.allSatisfy { $0 == 0 }, "nobody asks for a width: \(counter.stripWidths)")
        #expect(hosting.fittingSize == CGSize(width: 300, height: 26))
        window.contentView = nil
    }

    @Test func theStripIsAsBigAsItIsOfferedAndTheDefaultOtherwise() {
        #expect(CatSprite.size(for: .init(width: 280, height: 26)) == CGSize(width: 280, height: 26))
        #expect(CatSprite.size(for: .unspecified) == CatSprite.defaultSize)
        #expect(CatSprite.size(for: .init(width: 90, height: nil)) == CGSize(width: 90, height: 26))
    }

    /// What was found by looking: in a plain hosting view nothing between the cat's view and the hosting view clips what is drawn outside
    /// the strip's own bounds, so only the view itself cuts a moth that flies out of the strip. The notch's own tree has more in it (its
    /// shape clips), which this does not cover.
    @Test func inAPlainHostingViewNothingAboveTheCatsViewClipsItBeyondItsOwnBounds() throws {
        let rig = StageRig()
        let (hosting, window) = hosted(rig, counter: Counter())
        let cat = try #require(rig.stage.attachedHosts.first)
        #expect(cat.clipsToBounds, "the view clips its own layers, which is what cuts a moth that leaves")
        var view = cat.superview
        var between: [NSView] = []
        while let current = view, current !== hosting.superview {
            between.append(current)
            view = current.superview
        }
        #expect(between.count >= 2)
        for ancestor in between { #expect(ancestor.layer?.masksToBounds != true, "\(type(of: ancestor)) masks") }
        window.contentView = nil
    }

    @Test func aClickOnTheCatInTheNotchsOwnViewTreeReachesTheCatAndNotTheNotchsTap() throws {
        let rig = StageRig()
        rig.stage.playsMeow = true
        let counter = Counter()
        let (hosting, window) = hosted(rig, counter: counter)
        let cat = try #require(rig.stage.attachedHosts.first)
        let sprite = cat.sprite.frame
        let point = cat.convert(CGPoint(x: sprite.midX, y: sprite.midY), to: hosting.superview)
        let hit = hosting.hitTest(point)
        #expect(hit === cat, "the cat is what a click on it lands on: \(String(describing: hit))")

        // The empty strip is no cat: it falls through to what the notch does with a click, which is to open.
        let farX = sprite.midX < cat.bounds.midX ? cat.bounds.maxX - 6 : cat.bounds.minX + 6
        let away = hosting.convert(CGPoint(x: farX, y: 13), to: hosting.superview)
        #expect(!(hosting.hitTest(away) is CatSpriteView))

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
        (hit as? CatSpriteView)?.mouseDown(with: event)
        #expect(rig.stage.strokes == 1)
        #expect(rig.meow.plays == 1)
        #expect(counter.taps == 0, "the click went no further: the notch did not open")
        window.contentView = nil
    }
}
