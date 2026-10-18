import Foundation

/// What the capybara decides to do. A value that holds no timer and reads nothing, like the cat's: it is told the time and what the
/// capybara senses, and says whether the picture changed, so every rule of its day is a test with a made-up clock.
///
/// It is calm. What it does with its time is a few long scenes (`CapybaraScene`): soaking in a tub that comes up out of the floor, dozing,
/// eating an orange, sitting, a short slow walk. Each is picked at random, by weights that depend on the time of day, never the same one
/// twice running. On top of that:
/// - the pointer comes within sight and it is sitting: it turns its head, slowly, towards it, and back when it is gone. It never starts,
///   never pounces;
/// - a stroke makes it squint happily, with a small heart, and then it goes on with what it was doing;
/// - the Mac is busy: it is never in a hurry for that. It sweats a little, now and then, and soaks for longer; the walks do not quicken;
/// - the user has been away for the sleep time: it comes out of the tub if it is in it, dozes off, and sleeps, and sits up when the user is
///   back.
///
/// It has what it plays with only while the scene it is in calls for it: the tub from the moment it comes up to the moment it has gone
/// back, an orange until it is picked up, and the peel until it goes. Whatever interrupts a scene ends it first (`wrapUp`), and the props
/// are a state of this brain, so a tub never stays behind.
nonisolated struct CapybaraBrain: Sendable {
    typealias Outcome = BrainOutcome

    /// A user who has touched something this recently is at the Mac.
    static let wakeIdle: TimeInterval = 2
    static let sleepChunk: TimeInterval = 24
    static let happyDuration: TimeInterval = 1.8
    static let turnDuration = CapybaraMove.turn.passDuration
    /// How near the end of the lane it goes when it goes to the end, as a share of it.
    static let edgeInset = 0.04
    /// How long the pose of a capybara that is played with holds, before it holds again.
    static let hostHold: TimeInterval = 8
    /// What it does is held to these moves: a stroke is not taken while it is hopping, getting up or down or turning its head.
    static let unbroken: Set<CapybaraMove> = [.climbIn, .climbOut, .sitDown, .standUp, .lieDown, .sitUp, .turn, .turnBack, .happy, .soakHappy]

    /// The tub: where it stands (a share of the lane: where the capybara is when it is in it) and how far it has come.
    private struct Tub {
        enum Phase { case appearing, waiting, occupied, leaving }
        var place: Double
        /// Where it hops from and back to: room that nobody else stops in either while the tub is there.
        var home: Double
        var phase: Phase
    }

    private(set) var plan: Pose
    /// The scene it is in, nil while it does something that is not one: sleep, a glance at the pointer.
    private(set) var scene: CapybaraScene?
    /// Rises with every scene begun, so a test sees one that repeats.
    private(set) var sceneSerial = 0
    /// How often a prop was found left over when a scene began and had to be cleared: never, which a test checks.
    private(set) var strayProps = 0
    private var lastScene: CapybaraScene?
    private var queue: [CapybaraStep] = []
    private(set) var stance = CapybaraMove.Stance.seated
    private var tub: Tub?
    private var orange: Double?
    private var peel: Double?
    private var peelLeaving = false
    /// Where it hops into the tub from and the way it faces to (1 right, -1 left), worked out when it walks there.
    private var soakStart: (start: Double, direction: Double)?
    private var travel = 0.0
    private var keeper = LaneKeeper()
    private var busyness = 0.0
    private var senses = CatSenses()
    private var generator: SplitMix64
    /// The scene it is the host of, while another character plays on it: it holds still until it is over.
    private var hosting: JointScene.ID?

    init(seed: UInt64, now: TimeInterval, position: Double = 0.5, facing: Facing = .left) {
        generator = SplitMix64(seed: seed)
        plan = Pose(motion: CapybaraMove.sit.motion, facing: facing, from: position, to: position, began: now, duration: 2)
        plan.perch = Perch(dx: CapybaraMove.perchShift)
    }

    var move: CapybaraMove { CapybaraMove(plan.motion) }

    var isAsleep: Bool { move == .sleep }

    /// Whether it has a tub, an orange or a peel out now.
    var hasProps: Bool { tub != nil || orange != nil || peel != nil }

    /// Where the capybara is at `now`.
    func position(at now: TimeInterval) -> Double { plan.position(at: now) }

    // MARK: From outside

    /// A stroke: a happy squint and a heart, and then it goes on with what it was doing.
    mutating func pet(now: TimeInterval) -> Outcome {
        guard !isCrossing(at: now), !Self.unbroken.contains(move) else { return .unchanged }
        // One that is stroked is not played with any more: the scene is over for it, and so for whoever sits on it.
        hosting = nil
        let before = plan
        var steps: [CapybaraStep] = [.stay(stance == .soaking ? .soakHappy : .happy, Self.happyDuration...Self.happyDuration)]
        // What was left of a pose it stayed in goes on afterwards: a soak is not cut short by a stroke.
        if plan.motion.loops, plan.from == plan.to, move != .sleep, plan.end > now {
            let left = max(plan.end - now, 1)
            steps.append(.stay(move, left...left))
        }
        queue.insert(contentsOf: steps, at: 0)
        startQueue(now: now)
        return outcome(since: before)
    }

    /// Back on a notch after being out of sight: sitting where it was, with nothing it was playing with, and nothing it last saw is news.
    mutating func resume(now: TimeInterval) {
        queue = []
        scene = nil
        clearProps()
        hosting = nil
        stance = .seated
        plan = made(.sit, now: now, duration: 2)
    }

    /// Advances the capybara to `now`. `travel` is how far, in points of its picture's pixels, it can walk along the lane.
    mutating func update(now: TimeInterval, senses: CatSenses, tuning: CatTuning, travel: Double, lane: LaneContext) -> Outcome {
        let before = plan
        self.travel = travel
        self.senses = senses
        settle(lane: lane)
        busyness = tuning.reactsToBusyMachine ? min(max((senses.cpuLoad - CatBrain.busyFrom) / (1 - CatBrain.busyFrom), 0), 1) : 0
        guard hosting == nil else {
            // Played on: it holds the pose it is in, for as long as it takes.
            if now >= plan.end { plan = extended(now: now) }
            return outcome(since: before)
        }
        let sticky = Self.unbroken.contains(move) && now < plan.end || isCrossing(at: now)
        if !sticky, interruption(senses, now: now) {
            // Done.
        } else if !sticky, looking(senses, now: now) {
            // Done.
        } else if now >= plan.end {
            advance(senses, tuning: tuning, now: now)
        }
        return outcome(since: before)
    }

    /// Takes the stretches of the lane it must not stop in. One that stands in one when they are taken is put at the nearer end of it, which
    /// is a jump, and then it has nothing it was playing with: a tub would be left across the camera.
    mutating func settle(lane: LaneContext) {
        keeper = LaneKeeper(lane)
        guard hosting == nil, plan.from == plan.to, !(lane.crossing.isEmpty && lane.zones.isEmpty) else { return }
        let here = keeper.settled(plan.to)
        guard here != plan.to else { return }
        if hasProps || stance != .seated {
            clearProps()
            queue = []
            scene = nil
            stance = .seated
            plan = Pose(motion: CapybaraMove.sit.motion, facing: plan.facing, from: here, to: here, began: plan.began, duration: 0)
            plan.perch = Perch(dx: CapybaraMove.perchShift)
            return
        }
        plan.from = here
        plan.to = here
    }

    // MARK: Played on

    var jointScene: JointScene.ID? { hosting }

    /// It gives its back to ride on while it sits or soaks, holding still, with nothing set out for the scene it is in.
    func canJoin(_ invite: JointInvite, now: TimeInterval) -> Bool {
        guard invite.role == .host, invite.scene == .catOnCapybara, hosting == nil, move.givesPerch, plan.from == plan.to,
              !isCrossing(at: now) else { return false }
        if stance == .soaking { return tub?.phase == .occupied && orange == nil && peel == nil }
        // Nothing out, and not a tub on its way into the floor: that is a pose that has a picture of its own to finish.
        return stance == .seated && !hasProps && plan.prop == nil
    }

    mutating func join(_ invite: JointInvite, now: TimeInterval) {
        hosting = invite.scene
    }

    mutating func leaveJoint(now: TimeInterval) -> Outcome {
        hosting = nil
        return .unchanged
    }

    /// The same pose, held for a while longer.
    private func extended(now: TimeInterval) -> Pose {
        var held = plan
        held.began = now
        held.duration = Self.hostHold
        return held
    }

    // MARK: Reacting

    /// What it drops what it is doing for. True when it did: there is only waking.
    private mutating func interruption(_ senses: CatSenses, now: TimeInterval) -> Bool {
        if move == .sleep, senses.idleSeconds < Self.wakeIdle {
            queue = [.stay(.sit, 1.5...2.5)]
            scene = nil
            startQueue(now: now)
            return true
        }
        return false
    }

    /// A capybara that is sitting and has the pointer in sight slowly turns its head towards it, and back when it is gone, and goes on with
    /// its day.
    private mutating func looking(_ senses: CatSenses, now: TimeInterval) -> Bool {
        let wants = senses.pointer?.isInRange ?? false
        switch move {
        case .sit, .blink:
            guard wants, stance == .seated, plan.from == plan.to else { return false }
            plan = made(.turn, now: now, duration: CapybaraMove.turn.passDuration)
            return true
        case .turn:
            guard now >= plan.end else { return false }
            plan = made(wants ? .watch : .turnBack, now: now, duration: wants ? 4 : CapybaraMove.turnBack.passDuration)
            return true
        case .watch:
            if !wants {
                plan = made(.turnBack, now: now, duration: CapybaraMove.turnBack.passDuration)
                return true
            }
            if now >= plan.end { plan = made(.watch, now: now, duration: 4) }
            return true
        default:
            return false
        }
    }

    private func isCrossing(at now: TimeInterval) -> Bool {
        guard plan.from != plan.to else { return false }
        return keeper.isInCrossing(plan.position(at: now))
    }

    // MARK: Moving on

    /// The plan is over: the next step, or the next scene, or sleep.
    private mutating func advance(_ senses: CatSenses, tuning: CatTuning, now: TimeInterval) {
        if senses.idleSeconds >= tuning.sleepThreshold(hour: senses.hour) {
            // Down for the night in steps: out of the tub if it is in it, a doze, then sleep.
            let asleep = CapybaraStep.stay(.sleep, Self.sleepChunk...Self.sleepChunk)
            if move == .sleep {
                plan = made(.sleep, now: now, duration: Self.sleepChunk)
            } else if queue.contains(asleep) {
                startQueue(now: now)
            } else {
                queue = wrapUp() + [.stay(.doze, 5...8), asleep]
                scene = nil
                startQueue(now: now)
            }
            return
        }
        startQueue(now: now)
    }

    /// Begins the next step of the scene, which is the first of a new scene when there is none left.
    private mutating func startQueue(now: TimeInterval) {
        for _ in 0..<12 {
            if queue.isEmpty { beginScene() }
            guard !queue.isEmpty else { break }
            let step = queue.removeFirst()
            if let planned = begin(step, now: now) {
                plan = planned
                return
            }
        }
        // Nothing to do: sits.
        clearProps()
        stance = .seated
        plan = made(.sit, now: now, duration: 2)
    }

    private mutating func beginScene() {
        // The last scene took all it set out with it.
        if hasProps { strayProps += 1 }
        clearProps()
        if stance == .soaking { stance = .standing }
        let night = CatTuning.isNight(hour: senses.hour)
        let busy = busyness > 0
        var choices = CapybaraScene.allCases.filter { $0 != lastScene && $0.weight(night: night, busy: busy) > 0 }
        if choices.isEmpty { choices = [.restSit] }
        let total = choices.reduce(0) { $0 + $1.weight(night: night, busy: busy) }
        var roll = Double.random(in: 0..<total, using: &generator)
        var picked = choices[0]
        for choice in choices {
            let weight = choice.weight(night: night, busy: busy)
            if roll < weight {
                picked = choice
                break
            }
            roll -= weight
        }
        scene = picked
        lastScene = picked
        sceneSerial += 1
        queue = picked.steps(using: &generator, longer: 1 + 0.8 * busyness)
    }

    /// What it has to do to end what it is playing with, in order: out of the tub and the tub back, the peel gone. The orange, which
    /// lies there for a moment before it is picked up, is simply taken away.
    private mutating func wrapUp() -> [CapybaraStep] {
        var steps: [CapybaraStep] = []
        if let tub {
            switch tub.phase {
            case .occupied: steps += [.hopOut, .tubGoes]
            case .appearing, .waiting: steps.append(.tubGoes)
            case .leaving: break
            }
        }
        if peel != nil, !peelLeaving { steps.append(.peelGoes) }
        orange = nil
        return steps
    }

    private mutating func clearProps() {
        tub = nil
        orange = nil
        peel = nil
        peelLeaving = false
        soakStart = nil
    }

    // MARK: Plans

    /// A plan for `step`, from where the capybara is at `now`; nil for a step that takes no time or cannot be done. It gets up, sits down
    /// or lies down first when the step needs it, and the step waits its turn; out of the tub first, whatever the step is.
    private mutating func begin(_ step: CapybaraStep, now: TimeInterval) -> Pose? {
        if stance == .soaking, step.stance != .soaking {
            queue.insert(step, at: 0)
            queue.insert(.hopOut, at: 0)
            return nil
        }
        if step.stance != stance {
            if let hop = hop(to: step.stance) {
                queue.insert(step, at: 0)
                stance = hop.ends
                return made(hop.move, now: now, duration: hop.move.passDuration)
            }
            stance = step.stance
        }
        let planned: Pose?
        switch step {
        case .stay(let move, let seconds):
            if move == .hold { orange = nil }
            if move == .peel { peel = peelPlace(now: now) }
            planned = made(move, now: now, duration: Double.random(in: seconds, using: &generator))
        case .go(let place):
            planned = go(place, now: now)
        case .placeTub:
            planned = placeTub(now: now)
        case .hopIn:
            planned = hopIn(now: now)
        case .hopOut:
            planned = hopOut(now: now)
        case .tubGoes:
            planned = tubGoes(now: now)
        case .placeOrange:
            planned = placeOrange(now: now)
        case .peelGoes:
            planned = peelGoes(now: now)
        }
        if planned != nil { stance = step.endStance }
        return planned
    }

    /// The move that takes the capybara one step nearer a stance, and the one it ends in; nil when it needs none (it just is).
    private func hop(to needed: CapybaraMove.Stance) -> (move: CapybaraMove, ends: CapybaraMove.Stance)? {
        switch (stance, needed) {
        case (.standing, .seated), (.standing, .lying): (.sitDown, .seated)
        case (.seated, .standing): (.standUp, .standing)
        case (.lying, .seated), (.lying, .standing): (.sitUp, .seated)
        case (.seated, .lying): (.lieDown, .lying)
        default: nil
        }
    }

    /// The capybara doing `move` where it is, with whatever it has out (the tub, the orange, the peel).
    private mutating func made(
        _ move: CapybaraMove, now: TimeInterval, duration: TimeInterval, facing: Facing? = nil, from: Double? = nil, to: Double? = nil
    ) -> Pose {
        let there = plan.position(at: now)
        // A capybara in or by its tub is not moved off the place it is at.
        let here = hasProps || hosting != nil ? there : keeper.settled(there)
        var pose = Pose(
            motion: move.motion, facing: facing ?? plan.facing, from: from ?? here, to: to ?? from ?? here, began: now, duration: duration,
            fpsScale: 1
        )
        pose.prop = nextProp()
        if move.givesPerch { pose.perch = Perch(dx: CapybaraMove.perchShift) }
        return pose
    }

    /// What it has out for the pose that is being made, and how far it has come: a tub comes up in one pose and goes in one.
    private mutating func nextProp() -> PoseProp? {
        if var current = tub {
            let look: CapybaraProp
            switch current.phase {
            case .appearing:
                look = .tubAppearing
                current.phase = .waiting
                tub = current
            case .waiting: look = .tubEmpty
            case .occupied: look = .tubRippling
            case .leaving:
                look = .tubGoing
                tub = nil
            }
            return PoseProp(look: look.look, from: current.place, to: current.place, alsoAt: [current.home])
        }
        if let place = peel {
            let look: CapybaraProp = peelLeaving ? .peelGoing : .peel
            if peelLeaving {
                peel = nil
                peelLeaving = false
            }
            return PoseProp(look: look.look, from: place, to: place)
        }
        if let place = orange { return PoseProp(look: CapybaraProp.orange.look, from: place, to: place) }
        return nil
    }

    private func facing(_ direction: Double) -> Facing { direction > 0 ? .right : .left }

    private mutating func go(_ place: CapybaraPlace, now: TimeInterval) -> Pose? {
        let here = plan.position(at: now)
        guard travel >= 1 else {
            queue = []
            return nil
        }
        var target: Double
        switch place {
        case .away(let pixels):
            var right = here <= 0.08 ? true : here >= 0.92 ? false : chance(0.5)
            let distance = Double.random(in: pixels, using: &generator)
            func aim() -> Double { right ? min(here + distance / travel, 1) : max(here - distance / travel, 0) }
            var aimed = aim()
            if abs(aimed - here) * travel < 10 {
                right.toggle()
                aimed = aim()
            }
            target = aimed
        case .farEdge:
            target = here < 0.5 ? 1 - Self.edgeInset : Self.edgeInset
        case .soakStart:
            guard let spot = soakSpot(from: here) else {
                queue = []
                return nil
            }
            soakStart = spot
            target = spot.start
        }
        target = keeper.destination(target, from: here)
        let covered = abs(target - here) * travel
        guard covered >= 1 else { return nil }
        // A walk is as slow as it is, whatever the Mac is doing.
        return made(
            .walk, now: now, duration: covered / CapybaraMove.walk.speed, facing: target == here ? plan.facing : facing(target - here),
            from: here, to: target
        )
    }

    // MARK: The tub

    /// Where there is room to hop into a tub and out again, nearest to `here`: the place it hops from and the way it faces. Both the place
    /// and the tub's are outside the crossing and out of the others' way, and the hop does not go through the camera.
    private func soakSpot(from here: Double) -> (start: Double, direction: Double)? {
        guard travel >= 1 else { return nil }
        let span = CapybaraMove.hopSpan / travel
        let direction = plan.facing == .right ? 1.0 : -1.0
        let starts = [here] + stride(from: 0.0, through: 1.0, by: 0.05).filter { abs($0 - here) > 0.001 }.sorted { abs($0 - here) < abs($1 - here) }
        for start in starts {
            for way in [direction, -direction] where fits(from: start, to: start + way * span, startingAt: here) { return (start, way) }
        }
        return nil
    }

    private func fits(from start: Double, to end: Double, startingAt here: Double) -> Bool {
        guard (0.0...1.0).contains(start), (0.0...1.0).contains(end), keeper.isFree(start), keeper.isFree(end),
              keeper.destination(start, from: here) == start else { return false }
        let (low, high) = (min(start, end), max(start, end))
        if keeper.lane.crossing.contains(where: { high > $0.lowerBound && low < $0.upperBound }) { return false }
        return keeper.reach(from: start).contains(end)
    }

    /// Sits and watches the tub come up out of the floor a hop in front of it.
    private mutating func placeTub(now: TimeInterval) -> Pose? {
        let here = plan.position(at: now)
        guard let spot = soakStart ?? soakSpot(from: here), travel >= 1 else {
            queue = []
            return nil
        }
        let end = here + spot.direction * CapybaraMove.hopSpan / travel
        guard fits(from: here, to: end, startingAt: here) else {
            queue = []
            soakStart = nil
            return nil
        }
        tub = Tub(place: end, home: here, phase: .appearing)
        return made(.sit, now: now, duration: CapybaraProp.tubAppearing.passDuration, facing: facing(spot.direction))
    }

    private mutating func hopIn(now: TimeInterval) -> Pose? {
        guard var current = tub else {
            queue = []
            return nil
        }
        current.phase = .occupied
        tub = current
        return made(.climbIn, now: now, duration: CapybaraMove.climbIn.passDuration, from: plan.position(at: now), to: current.place)
    }

    /// Out of the tub the way it came, backwards, and the tub stands empty.
    private mutating func hopOut(now: TimeInterval) -> Pose? {
        guard tub != nil, travel >= 1 else {
            queue = []
            tub = nil
            return nil
        }
        let here = plan.position(at: now)
        let way = plan.facing == .right ? 1.0 : -1.0
        let out = min(max(here - way * CapybaraMove.hopSpan / travel, 0), 1)
        let pose = made(.climbOut, now: now, duration: CapybaraMove.climbOut.passDuration, from: here, to: out)
        tub?.phase = .waiting
        return pose
    }

    private mutating func tubGoes(now: TimeInterval) -> Pose? {
        guard tub != nil else { return nil }
        tub?.phase = .leaving
        return made(.sit, now: now, duration: CapybaraProp.tubGoing.passDuration)
    }

    // MARK: The orange

    /// Sits while an orange is put down just in front of it, on the side it faces if there is room there and on the other if not.
    private mutating func placeOrange(now: TimeInterval) -> Pose? {
        let here = plan.position(at: now)
        guard travel >= 1 else {
            queue = []
            return nil
        }
        let direction = plan.facing == .right ? 1.0 : -1.0
        for way in [direction, -direction] {
            let reach = way > 0 ? CapybaraMove.orangeReach.right : CapybaraMove.orangeReach.left
            let place = here + reach / travel
            guard (0.0...1.0).contains(place), keeper.isFree(place) else { continue }
            orange = place
            return made(.sit, now: now, duration: Double.random(in: 1.2...2.2, using: &generator), facing: facing(way))
        }
        queue = []
        return nil
    }

    private func peelPlace(now: TimeInterval) -> Double? {
        guard travel >= 1 else { return nil }
        let reach = plan.facing == .right ? CapybaraMove.peelReach.right : CapybaraMove.peelReach.left
        return plan.position(at: now) + reach / travel
    }

    private mutating func peelGoes(now: TimeInterval) -> Pose? {
        guard peel != nil else { return nil }
        peelLeaving = true
        return made(.sit, now: now, duration: CapybaraProp.peelGoing.passDuration)
    }

    // MARK: Small things

    private mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &generator) < probability
    }

    private func outcome(since before: Pose) -> Outcome {
        if plan == before { return .unchanged }
        return plan.looksLike(before) ? .extended : .changed
    }
}

nonisolated extension CapybaraStep {
    /// The stance it leaves the capybara in.
    var endStance: CapybaraMove.Stance {
        switch self {
        case .hopIn: .soaking
        case .hopOut: .standing
        default: stance
        }
    }
}

nonisolated extension CapybaraBrain: CharacterBrain {
    var pose: Pose { plan }
}
