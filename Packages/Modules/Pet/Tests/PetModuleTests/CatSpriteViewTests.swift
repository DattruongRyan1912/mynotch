import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import PetModule

/// The view's layer and animations, driven directly with plans of the test's own.
@Suite(.serialized) @MainActor struct CatSpriteViewTests {
    /// A lane across the right wing of the rig's notch, in the window's coordinates.
    func lane(of rig: StageRig, clips: Bool = true) -> WalkLane {
        let wing = rig.trailing.windowFrame
        return WalkLane(minX: wing.minX + 2, maxX: wing.maxX - 38, clipsToWings: clips, restingX: wing.midX - 15)
    }

    func framesAnimation(of host: CatSpriteView) throws -> CAKeyframeAnimation {
        try #require(host.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation)
    }

    func walkAnimation(of host: CatSpriteView) throws -> CAKeyframeAnimation {
        try #require(host.sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation)
    }

    @Test func theCatIsDrawnWithNearestNeighbourFilteringAtAWholeNumberOfDevicePixelsToASpritePixel() throws {
        let rig = StageRig()
        let host = rig.trailing
        host.show(plan: CatPlan(pose: .sit, facing: .right, from: 0, to: 0, began: 0, duration: 3), lane: lane(of: rig), elapsed: 0)
        #expect(host.sprite.magnificationFilter == .nearest)
        #expect(host.sprite.minificationFilter == .nearest)
        #expect(host.sprite.contentsGravity == .resize)
        #expect(host.sprite.contents != nil)
        // 32 points at 2x: three device pixels to a sprite pixel, so a cat of 30 by 24 points.
        #expect(host.metrics.pixelScale == 3)
        #expect(host.sprite.bounds.size == CGSize(width: 30, height: 24))
        #expect(host.sprite.bounds.width * 2 == CGFloat(CatArt.width * 3))
        #expect(host.sprite.position.y == SpriteMetrics.floor)
        #expect(host.sprite.position.x * 2 == (host.sprite.position.x * 2).rounded(), "on a device pixel")
        #expect(host.sprite.anchorPoint == .zero)
    }

    @Test func theFramesAreOneKeyframeAnimationOfTheContentsRectThatHoldsEachFrameAndNeverBlendsThem() throws {
        let rig = StageRig()
        let host = rig.trailing
        host.show(plan: CatPlan(pose: .walk, facing: .right, from: 0, to: 0, began: 0, duration: 3), lane: lane(of: rig), elapsed: 0)
        let frames = try framesAnimation(of: host)
        #expect(frames.keyPath == "contentsRect")
        #expect(frames.calculationMode == .discrete)
        #expect(frames.repeatCount == .infinity)
        #expect(frames.values?.count == CatArt.walk.frames.count)
        #expect(frames.duration == CatArt.walk.duration)
        let strip = CatSheets.shared.strip(for: .walk, facing: .right)
        let shown: [CGRect] = (frames.values as? [NSValue])?.map(\.rectValue) ?? []
        let expected: [CGRect] = (0..<4).map { strip.contentsRect(of: $0) }
        #expect(shown == expected)
        #expect(host.sprite.animationKeys() == [CatSpriteView.framesKey], "a cat that stands still has the frames and nothing else")
    }

    @Test func theFramesRunAtTheirOwnRateAndNeverAskTheDisplayForMoreThanTwentyFour() throws {
        let rig = StageRig()
        let host = rig.trailing
        for pose in CatPose.allCases {
            host.show(plan: CatPlan(pose: pose, facing: .right, from: 0, to: 0, began: 0, duration: 3), lane: lane(of: rig), elapsed: 0)
            let range = try framesAnimation(of: host).preferredFrameRateRange
            #expect(range.maximum <= CatSpriteView.frameRateCeiling, "\(pose)")
            let preferred = try #require(range.preferred)
            #expect(preferred <= 12, "\(pose)")
            #expect(preferred == Float(max(CatArt.animation(for: pose).fps, 4)), "\(pose)")
        }
    }

    @Test func aCatThatRunsHarderPlaysItsFramesFaster() throws {
        let rig = StageRig()
        let host = rig.trailing
        host.show(plan: CatPlan(pose: .run, facing: .right, from: 0, to: 0, began: 0, duration: 3, fpsScale: 1), lane: lane(of: rig), elapsed: 0)
        let slow = try framesAnimation(of: host)
        host.show(plan: CatPlan(pose: .run, facing: .right, from: 0, to: 0, began: 0, duration: 3, fpsScale: 1.5), lane: lane(of: rig), elapsed: 0)
        let fast = try framesAnimation(of: host)
        #expect(abs(slow.duration / fast.duration - 1.5) < 1e-9)
        let (fastRate, slowRate) = (try #require(fast.preferredFrameRateRange.preferred), try #require(slow.preferredFrameRateRange.preferred))
        #expect(fastRate > slowRate)
    }

    @Test func aWalkMovesTheFootOneSpritePixelAtATimeAndHoldsEachPlaceUntilTheNextStep() throws {
        let rig = StageRig()
        let host = rig.trailing
        let lane = lane(of: rig)
        host.show(plan: CatPlan(pose: .walk, facing: .right, from: 0, to: 1, began: 0, duration: 2), lane: lane, elapsed: 0)
        let walk = try walkAnimation(of: host)
        #expect(walk.keyPath == "position.x")
        #expect(walk.calculationMode == .discrete)
        #expect(walk.duration == 2)
        let places = (walk.values as? [NSNumber])?.map { CGFloat($0.doubleValue) } ?? []
        #expect(places.count > 5)
        for (before, after) in zip(places, places.dropFirst()) {
            #expect(abs((after - before) - host.metrics.step) < 1e-9, "one sprite pixel: \(after - before)")
        }
        for place in places { #expect(place * 2 == (place * 2).rounded(), "on a device pixel: \(place)") }
        // From the left end of the lane to as near its right end as whole steps get.
        let origin = host.windowFrame.minX
        #expect(places.first == (lane.minX - origin))
        #expect(abs((places.last ?? 0) - (lane.maxX - origin)) <= host.metrics.step / 2 + 1e-9)
        // What the layer holds when the animation is done is where the walk ended.
        #expect(host.sprite.position.x == places.last)
        #expect(walk.fillMode == .forwards)
        #expect(!walk.isRemovedOnCompletion)
        #expect(Set(host.sprite.animationKeys() ?? []) == [CatSpriteView.framesKey, CatSpriteView.walkKey])
    }

    @Test func aWalkToTheLeftStepsTheOtherWayAndIsPlayedFromTheMirrorImage() throws {
        let rig = StageRig()
        let host = rig.trailing
        host.show(plan: CatPlan(pose: .walk, facing: .left, from: 1, to: 0, began: 0, duration: 2), lane: lane(of: rig), elapsed: 0)
        let places = (try walkAnimation(of: host).values as? [NSNumber])?.map { CGFloat($0.doubleValue) } ?? []
        #expect(places == places.sorted(by: >))
        let left = CatSheets.shared.strip(for: .walk, facing: .left)
        #expect(host.sprite.contents as AnyObject === left.image)
        let right = CatSheets.shared.strip(for: .walk, facing: .right)
        #expect(host.sprite.contents as AnyObject !== right.image)
    }

    @Test func walkStopsAreEvenlySpacedAndNeverSkipPastTheEnd() {
        let upward: [CGFloat] = (0...7).map { CGFloat($0) * 1.5 }
        let downward: [CGFloat] = (0...7).map { (10 as CGFloat) - CGFloat($0) * 1.5 }
        #expect(CatSpriteView.walkStops(from: 0, to: 10, step: 1.5) == upward)
        #expect(CatSpriteView.walkStops(from: 10, to: 0, step: 1.5) == downward)
        #expect(CatSpriteView.walkStops(from: 3, to: 3, step: 1.5) == [3])
        #expect(CatSpriteView.walkStops(from: 0, to: 0.2, step: 1.5) == [0, 1.5], "a step is the least it moves")
        #expect(CatSpriteView.walkStops(from: 0, to: 5, step: 0) == [0])
    }

    @Test func aPlanThatIsAlreadyUnderWayIsPlayedFromWhereItIs() throws {
        let rig = StageRig()
        let host = rig.trailing
        host.show(plan: CatPlan(pose: .walk, facing: .right, from: 0, to: 1, began: 0, duration: 4), lane: lane(of: rig), elapsed: 1.3)
        let frames = try framesAnimation(of: host)
        #expect(abs(frames.timeOffset - 1.3.truncatingRemainder(dividingBy: CatArt.walk.duration)) < 1e-9)
        #expect(abs(try walkAnimation(of: host).timeOffset - 1.3) < 1e-9)
        // And one that has run past its end is held at the end rather than asked for a time it does not have.
        host.show(plan: CatPlan(pose: .walk, facing: .right, from: 0, to: 1, began: 0, duration: 4), lane: lane(of: rig), elapsed: 9)
        #expect(try walkAnimation(of: host).timeOffset == 4)
    }

    @Test func aNewPlanTakesTheOldAnimationsAwayFirst() throws {
        let rig = StageRig()
        let host = rig.trailing
        host.show(plan: CatPlan(pose: .walk, facing: .right, from: 0, to: 1, began: 0, duration: 2), lane: lane(of: rig), elapsed: 0)
        #expect(host.sprite.animation(forKey: CatSpriteView.walkKey) != nil)
        host.show(plan: CatPlan(pose: .sit, facing: .right, from: 1, to: 1, began: 2, duration: 3), lane: lane(of: rig), elapsed: 0)
        #expect(host.sprite.animation(forKey: CatSpriteView.walkKey) == nil, "no walk left over from the plan before")
        #expect(host.sprite.animationKeys() == [CatSpriteView.framesKey])
    }

    @Test func stoppingTakesTheCatAndEveryAnimationAway() {
        let rig = StageRig()
        let host = rig.trailing
        host.show(plan: CatPlan(pose: .walk, facing: .right, from: 0, to: 1, began: 0, duration: 2), lane: lane(of: rig), elapsed: 0)
        host.stopShowing()
        #expect(!host.isAnimating)
        #expect(!host.isShowingCat)
    }

    @Test func aLaneThatCrossesTheCameraClipsTheViewAndOneInsideAPillDoesNot() {
        let rig = StageRig()
        let host = rig.trailing
        host.show(plan: CatPlan(pose: .sit, facing: .right, from: 0, to: 0, began: 0, duration: 3), lane: lane(of: rig, clips: true), elapsed: 0)
        #expect(host.layer?.masksToBounds == true)
        host.show(plan: CatPlan(pose: .sit, facing: .right, from: 0, to: 0, began: 0, duration: 3), lane: lane(of: rig, clips: false), elapsed: 0)
        #expect(host.layer?.masksToBounds == false)
    }

    // MARK: Hits

    @Test func onlyTheCatTakesAClickAndTheRestOfTheWingLeavesItToTheNotch() throws {
        let rig = StageRig()
        rig.show()
        let host = rig.trailing
        let sprite = host.sprite.frame
        let inside = host.convert(CGPoint(x: sprite.midX, y: sprite.midY), to: host.superview)
        #expect(host.hitTest(inside) === host)
        // The wing's far corner, away from the cat.
        let away = host.convert(CGPoint(x: host.bounds.maxX - 1, y: host.bounds.maxY - 1), to: host.superview)
        let cat = host.convert(sprite, to: host.superview)
        if !cat.insetBy(dx: -3, dy: -3).contains(away) { #expect(host.hitTest(away) == nil) }
        let corner = host.convert(CGPoint(x: host.bounds.minX + 0.5, y: host.bounds.maxY - 0.5), to: host.superview)
        #expect(host.hitTest(corner) == nil || cat.insetBy(dx: -3, dy: -3).contains(corner))
        // Outside the view altogether: not its click.
        #expect(host.hitTest(CGPoint(x: -500, y: -500)) == nil)
    }

    @Test func aWingWithNoCatInItTakesNoClicks() {
        let rig = StageRig()
        rig.show()
        let host = rig.leading
        #expect(!host.isShowingCat)
        #expect(host.hitTest(host.convert(CGPoint(x: host.bounds.midX, y: host.bounds.midY), to: host.superview)) == nil)
        rig.hide()
        #expect(rig.trailing.hitTest(CGPoint(x: 280, y: 10)) == nil)
    }

    @Test func theFirstClickIsTakenEvenThoughTheNotchIsNeverActive() {
        let rig = StageRig()
        #expect(rig.trailing.acceptsFirstMouse(for: nil))
        #expect(!rig.trailing.mouseDownCanMoveWindow)
    }

    // MARK: In SwiftUI

    final class Counter {
        var bodies = 0
        var taps = 0
        /// Every width the views under the notch asked for.
        var stripWidths: [CGFloat] = []
    }

    /// Both wings as the collapsed notch lays them out, under a tap that opens the notch.
    struct Wings: View {
        let stage: CatStage
        let counter: Counter
        var onScreen = true

        var body: some View {
            let _ = counter.bodies += 1
            HStack(spacing: 0) {
                CatWingView(stage: stage, role: .leading).frame(width: 64)
                Spacer(minLength: 185)
                CatWingView(stage: stage, role: .trailing).frame(width: 64)
            }
            .frame(width: 313, height: 32)
            .environment(\.notchIsOnScreen, onScreen)
            .onNotchStripWidth { counter.stripWidths.append($0) }
            .contentShape(Rectangle())
            .gesture(TapGesture().onEnded { counter.taps += 1 }, including: .all)
        }
    }

    func host(_ rig: StageRig, counter: Counter, onScreen: Bool = true) -> (CountingHostingView<Wings>, NSWindow) {
        let hosting = CountingHostingView(rootView: Wings(stage: rig.stage, counter: counter, onScreen: onScreen))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 313, height: 32), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    @Test func theViewsAreInTheTreeOnlyWhileTheNotchCanBeSeen() {
        let rig = StageRig()
        let counter = Counter()
        let (hosting, window) = host(rig, counter: counter)
        #expect(rig.stage.isAlive)
        #expect(rig.stage.attachedHosts.count == 2)
        #expect(rig.scheduler.pendingCount == 1)

        hosting.rootView = Wings(stage: rig.stage, counter: counter, onScreen: false)
        #expect(runLoop(until: { !rig.stage.isAlive }, seconds: 10))
        #expect(rig.scheduler.pendingCount == 0)

        hosting.rootView = Wings(stage: rig.stage, counter: counter, onScreen: true)
        #expect(runLoop(until: { rig.stage.isAlive }, seconds: 10))
        window.contentView = nil
        #expect(!rig.stage.isAlive)
        #expect(rig.scheduler.pendingCount == 0)
    }

    /// What was found by looking: in a plain hosting view nothing between the cat's view and the hosting view clips what is drawn outside
    /// the wing, so a cat inside a pill (whose view does not clip itself) is drawn where it is. The notch's own tree has more in it
    /// (its shape clips), which this does not cover.
    @Test func inAPlainHostingViewNothingAboveTheCatsViewClipsItToTheWing() throws {
        let rig = StageRig()
        let (hosting, window) = host(rig, counter: Counter())
        let cat = try #require(rig.stage.attachedHosts.first { $0.role == .trailing })
        var view = cat.superview
        var between: [NSView] = []
        while let current = view, current !== hosting.superview {
            between.append(current)
            view = current.superview
        }
        #expect(between.count >= 2, "the platform view's host and the hosting view")
        for ancestor in between {
            #expect(!ancestor.clipsToBounds, "\(type(of: ancestor)) clips")
            #expect(ancestor.layer?.masksToBounds != true, "\(type(of: ancestor)) masks")
        }
        window.contentView = nil
    }

    @Test func aCatThatIsNotOnScreenIsNeverMadeAtAll() {
        let rig = StageRig()
        let (_, window) = host(rig, counter: Counter(), onScreen: false)
        #expect(!rig.stage.isAlive)
        #expect(rig.stage.attachedHosts.isEmpty)
        #expect(rig.scheduler.pendingCount == 0)
        window.contentView = nil
    }

    @Test func aMinuteOfTheCatLivingIsNoWorkForSwiftUIAtAll() {
        let rig = StageRig()
        rig.cpu.value = 0.9
        let counter = Counter()
        let (hosting, window) = host(rig, counter: counter)
        rig.advance(1)
        let (bodies, layouts, presentations) = (counter.bodies, hosting.layouts, rig.stage.presentations)
        // A minute of a cat that runs, jumps when the pointer comes, sleeps and wakes, as busy a minute as it gets.
        for second in 0..<60 {
            if second == 20 { rig.pointer.point = CGPoint(x: 100, y: 800) }
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
        let (hosting, window) = host(rig, counter: counter)
        rig.advance(30)
        #expect(counter.stripWidths.allSatisfy { $0 == 0 }, "nobody asks for a width: \(counter.stripWidths)")
        #expect(hosting.fittingSize == CGSize(width: 313, height: 32))
        window.contentView = nil
    }

    @Test func theWingIsAsBigAsItIsOfferedAndTheDefaultOtherwise() {
        #expect(CatSprite.size(for: .init(width: 64, height: 30)) == CGSize(width: 64, height: 30))
        #expect(CatSprite.size(for: .unspecified) == CatSprite.defaultSize)
        #expect(CatSprite.size(for: .init(width: 90, height: nil)) == CGSize(width: 90, height: 32))
    }

    @Test func aClickOnTheCatInTheNotchsOwnViewTreeReachesTheCatAndNotTheNotchsTap() throws {
        let rig = StageRig()
        rig.stage.playsMeow = true
        let counter = Counter()
        let (hosting, window) = host(rig, counter: counter)
        let cat = try #require(rig.stage.attachedHosts.first { $0.role == .trailing })
        let sprite = cat.sprite.frame
        let point = cat.convert(CGPoint(x: sprite.midX, y: sprite.midY), to: hosting.superview)
        let hit = hosting.hitTest(point)
        #expect(hit === cat, "the cat is what a click on it lands on: \(String(describing: hit))")

        // The empty left wing is no cat: it falls through to what the notch does with a click, which is to open.
        let wing = rig.stage.attachedHosts.first { $0.role == .leading }
        let leftPoint = hosting.convert(CGPoint(x: (wing?.windowFrame.midX ?? 32), y: 16), to: hosting.superview)
        #expect(!(hosting.hitTest(leftPoint) is CatSpriteView))

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
