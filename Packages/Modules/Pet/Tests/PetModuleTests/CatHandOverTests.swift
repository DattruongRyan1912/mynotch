import AppKit
import Testing
@testable import PetModule

/// What a layer was told, in the order it was told it.
nonisolated final class LayerLog {
    enum Event: Equatable {
        case position(CGPoint)
        case add(String)
        case removeAll
        case remove(String)
    }

    var events: [Event] = []
}

/// A layer that records what the view does to it. Everything else is a layer's own.
nonisolated final class RecordingLayer: CALayer {
    var log = LayerLog()

    override init() { super.init() }

    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? RecordingLayer { log = other.log }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var position: CGPoint {
        get { super.position }
        set {
            log.events.append(.position(newValue))
            super.position = newValue
        }
    }

    override func add(_ animation: CAAnimation, forKey key: String?) {
        log.events.append(.add(key ?? ""))
        super.add(animation, forKey: key)
    }

    override func removeAllAnimations() {
        log.events.append(.removeAll)
        super.removeAllAnimations()
    }

    override func removeAnimation(forKey key: String) {
        log.events.append(.remove(key))
        super.removeAnimation(forKey: key)
    }
}

/// How one walk hands over to the next, as the layer is told about it. The layer's own value is what the screen shows of a layer that
/// no animation is drawing, so from the moment a leg takes the place of another it must be where the new one begins, and the old animation
/// must not go away before it is: the layer is never left to show where the old leg began, which is where it was set to. The old leg is
/// not waited for to say that it is over, either: it may say so late, or not before the next leg is shown.
@Suite(.serialized) @MainActor struct CatHandOverTests {
    struct Rig {
        let host: CatSpriteView
        let sprite: RecordingLayer
        let prop: RecordingLayer

        init() {
            sprite = RecordingLayer()
            prop = RecordingLayer()
            host = CatSpriteView(stage: CatStage(scheduler: ManualSchedulerStub.make()), sprite: sprite, prop: prop)
            host.frame = CGRect(x: 0, y: 0, width: 300, height: CatActivity.stripHeight)
        }

        func clear() {
            sprite.log.events.removeAll()
            prop.log.events.removeAll()
        }
    }

    func positions(_ events: [LayerLog.Event]) -> [CGPoint] {
        events.compactMap { if case .position(let point) = $0 { point } else { nil } }
    }

    func adds(_ events: [LayerLog.Event]) -> [String] {
        events.compactMap { if case .add(let key) = $0 { key } else { nil } }
    }

    func indexOfFirstPosition(_ events: [LayerLog.Event]) -> Int? {
        events.firstIndex { if case .position = $0 { true } else { false } }
    }

    func indexOfFirstAdd(_ events: [LayerLog.Event]) -> Int? {
        events.firstIndex { if case .add = $0 { true } else { false } }
    }

    func walkValues(of layer: CALayer) -> [CGFloat] {
        ((layer.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation)?.values as? [NSNumber])?.map { CGFloat($0.doubleValue) } ?? []
    }

    /// The legs of a long run, a sit, a chase after a moth, a game with a ball of yarn: every kind of hand-over there is.
    var plans: [(name: String, plan: CatPlan)] {
        func plan(
            _ move: CatMove, _ from: Double, _ to: Double, duration: TimeInterval, facing: Facing = .right, prop: CatProp? = nil
        ) -> CatPlan {
            CatPlan(move: move, facing: facing, from: from, to: to, began: 0, duration: duration, prop: prop)
        }
        return [
            ("run to the right", plan(.frantic, 0.1, 1.0, duration: 3)),
            ("run back", plan(.frantic, 1.0, 0.0, duration: 3, facing: .left)),
            ("walk on", plan(.walk, 0.0, 0.5, duration: 5)),
            ("sit", plan(.sit, 0.5, 0.5, duration: 2)),
            ("chase a moth", plan(.chase, 0.5, 0.96, duration: 4, prop: CatProp(kind: .moth, from: 0.6, to: 1.2))),
            ("chase it back", plan(.chase, 0.96, 0.04, duration: 4, facing: .left, prop: CatProp(kind: .moth, from: 0.9, to: -0.2))),
            ("sit and bat the ball", plan(.yarn, 0.3, 0.3, duration: 1.6, prop: CatProp(kind: .yarn, from: 0.45, to: 0.57))),
            ("bat it on", plan(.yarn, 0.3, 0.3, duration: 1.6, prop: CatProp(kind: .yarn, from: 0.57, to: 0.69))),
            ("sit alone", plan(.sit, 0.3, 0.3, duration: 2)),
        ]
    }

    @Test func theLayerIsSetToWhereTheNewLegBeginsBeforeTheOldAnimationGoesAwayAndNothingWaitsForTheOldLegToSayItIsOver() throws {
        let rig = Rig()
        let (host, sprite) = (rig.host, rig.sprite)
        let lane = host.lane
        // Where the cat stands after the leg before: the last place of its walk, or the place it was put at.
        var stands: CGFloat?
        var propStands: CGFloat?
        for (name, plan) in plans {
            let modelBefore = sprite.position.x
            rig.clear()
            host.show(plan: plan, elapsed: 0, coat: .tabby)
            let events = sprite.log.events

            let written = positions(events)
            #expect(written.count == 1, "\(name): the layer is told where it is once, not \(written.count) times")
            let place = try #require(written.first, "\(name)")
            let set = try #require(indexOfFirstPosition(events), "\(name)")
            let removal = try #require(events.firstIndex(of: .removeAll), "\(name): the old animations go")
            let first = try #require(indexOfFirstAdd(events), "\(name): and the new ones come")
            #expect(set < removal, "\(name): the layer is set to where the new leg begins before the old animation is removed: \(events)")
            #expect(removal < first, "\(name): and the new animations are added after the old are gone")
            #expect(events.prefix(set).allSatisfy { if case .remove = $0 { false } else if case .removeAll = $0 { false } else { true } }, "\(name)")
            #expect(events.filter { $0 == .removeAll }.count == 1 && !events.contains(.remove(CatSpriteView.walkKey)), "\(name)")

            // The leg begins where the animation's first place is, which is where the layer is.
            let values = walkValues(of: sprite)
            if let beginning = values.first {
                #expect(place.x == beginning, "\(name): the layer is at the first place of the walk, \(beginning), not \(place.x)")
            }
            // It is where the cat stood after the leg before, if that is where this plan says it begins (the near enough), and not where that
            // leg began, nor where this one is going.
            let nominal = lane.x(at: plan.from).rounded()
            if let stands, abs(stands - nominal) <= CatSpriteView.continuityLimit {
                #expect(place.x == stands, "\(name): on from \(stands), not \(place.x)")
            } else {
                #expect(place.x == nominal, "\(name): at \(nominal), the place the plan gives, not \(place.x)")
            }
            if name == "run back" {
                #expect(modelBefore != place.x, "\(name): the layer was at the start of the leg before, \(modelBefore), and was not waited for to be moved")
                #expect(abs(place.x - lane.x(at: 1.0)) <= 2, "\(name): and now at the end of that leg, \(place.x)")
            }
            #expect(place.y == (plan.move == .peek ? CatSpriteView.floor - CatSpriteView.peekSink : CatSpriteView.floor), "\(name)")
            stands = values.last ?? place.x

            try checkProp(of: rig, for: plan, name: name, stands: &propStands)
        }
    }

    /// The same for what the cat plays with: it goes on from where it stood.
    private func checkProp(of rig: Rig, for plan: CatPlan, name: String, stands: inout CGFloat?) throws {
        let events = rig.prop.log.events
        guard let item = plan.prop else {
            #expect(positions(events).isEmpty && adds(events).isEmpty, "\(name): nothing is set or added to a prop that is not there: \(events)")
            #expect(rig.host.prop.isHidden && events.contains(.removeAll), "\(name): it is taken away")
            stands = nil
            return
        }
        let set = try #require(indexOfFirstPosition(events), "\(name): prop")
        let removal = try #require(events.firstIndex(of: .removeAll), "\(name): prop")
        #expect(set < removal, "\(name): the prop is set where its path begins before its old animations go: \(events)")
        if let first = indexOfFirstAdd(events) { #expect(removal < first, "\(name): prop") }
        #expect(positions(events).count == 1, "\(name): prop")
        let place = try #require(positions(events).first)
        let values = walkValues(of: rig.prop)
        if let beginning = values.first { #expect(place.x == beginning, "\(name): the prop is at the first place of its path") }
        let nominal = rig.host.lane.unboundedX(at: item.from).rounded()
        if let before = stands, abs(before - nominal) <= CatSpriteView.continuityLimit {
            #expect(place.x == before, "\(name): the prop goes on from \(before), not \(place.x)")
        } else {
            #expect(place.x == nominal, "\(name): the prop begins at \(nominal), not \(place.x)")
        }
        stands = values.last ?? place.x
    }

    @Test func aPropThatGoesOnIsSetWhereItStoodAndNotWhereItsLastPathBegan() throws {
        let rig = Rig()
        let host = rig.host
        let lane = host.lane
        let bat = { (from: Double, to: Double) in
            CatPlan(move: .yarn, facing: .right, from: 0.3, to: 0.3, began: 0, duration: 1.6, prop: CatProp(kind: .yarn, from: from, to: to))
        }
        host.show(plan: bat(0.45, 0.57), elapsed: 0, coat: .tabby)
        let ended = try #require(walkValues(of: rig.prop).last)
        let started = try #require(walkValues(of: rig.prop).first)
        #expect(ended != started)
        // The ball has not been heard to stop rolling: its layer is still at the start of its path.
        #expect(rig.prop.position.x == started)
        rig.clear()
        host.show(plan: bat(0.57, 0.69), elapsed: 0, coat: .tabby)
        let events = rig.prop.log.events
        let place = try #require(positions(events).first)
        #expect(abs(ended - lane.unboundedX(at: 0.57)) <= CatSpriteView.continuityLimit)
        #expect(place.x == ended, "the ball goes on from \(ended), and not from \(started) where its layer was")
        #expect(try #require(indexOfFirstPosition(events)) < (try #require(events.firstIndex(of: .removeAll))))
    }

    @Test func aCatThatIsMadeToRestIsSetBeforeItsAnimationsGo() throws {
        let rig = Rig()
        rig.host.show(plan: plans[0].plan, elapsed: 0, coat: .tabby)
        rig.clear()
        rig.host.showResting(coat: .tabby)
        let events = rig.sprite.log.events
        let set = try #require(indexOfFirstPosition(events))
        let removal = try #require(events.firstIndex(of: .removeAll))
        #expect(set < removal, "\(events)")
        #expect(try #require(indexOfFirstAdd(events)) > removal)
    }
}
