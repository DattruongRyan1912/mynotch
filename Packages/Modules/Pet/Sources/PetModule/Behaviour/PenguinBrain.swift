import Foundation

/// What the penguin decides to do. A value that holds no timer and reads nothing, like the others': it is told the time and what the
/// penguin senses, and says whether the picture changed, so every rule of its day is a test with a made-up clock.
///
/// It is clumsy. What it does with its time is a handful of scenes (`PenguinScene`) picked at random by weights that depend on the time of
/// day, never the same one twice running: standing about, waddling, flapping, standing with its head tucked in, slipping and falling over,
/// fishing at a hole in the ice that opens in front of it, and its signature, lying down on its belly and gliding. On top of that:
/// - **it crosses the camera on its belly.** A waddle is never sent through the crossing; a glide is, which makes the glide the way through
///   the portal on a notch (`crossOver` is a glide to the far end of the lane);
/// - the Mac is busy: it waddles faster, by up to half as much again, and is never frantic. The glide, which is already quick, is the
///   glide, and nothing it does is in more of a hurry than that. With the setting off nothing of the load is read at all;
/// - the pointer comes near: it turns to face it and flaps, and turns back when the pointer has gone. It looks for no more than
///   `freezeLimit` seconds, and not again until the pointer has gone away. A fisher pulls its line in first, one lying down gets up;
/// - a stroke makes it jump for joy with its flippers up (with its rod in them if it is fishing), and then it goes on with what it was doing;
/// - the user has been away for the sleep time: it finishes what it is in, takes its line in if it is fishing, gets up if it is lying, tucks
///   its head in and sleeps on its feet, and untucks when the user is back.
///
/// It has what it plays with only while the scene it is in calls for it: the hole from the moment the ice cracks to the moment it has
/// closed. Whatever interrupts a scene ends it first (`wrapUp`), and the props are a state of this brain, so a hole never stays behind.
nonisolated struct PenguinBrain: Sendable {
    typealias Outcome = BrainOutcome

    /// A user who has touched something this recently is at the Mac.
    static let wakeIdle: TimeInterval = 2
    static let sleepChunk: TimeInterval = 24
    /// A jump for joy, and a moment to be pleased with itself.
    static let happyDuration: TimeInterval = 1.2
    /// How near the end of the lane it goes when it goes to the end, as a share of it.
    static let edgeInset = 0.04
    /// How long it looks at the pointer, at the most, and how long after the pointer has gone it goes on looking.
    static let freezeLimit: TimeInterval = 15
    static let releaseDelay: TimeInterval = 0.9
    /// The load from which the Mac is busy enough to quicken the waddle (as the cat's), and how busy a burst of work is, whatever the load.
    static let busyFrom = CatBrain.busyFrom
    static let burstBusyness = 0.8
    /// What it drops everything for is held to these moves: a stroke or a stare is not taken while it is lying down, gliding, slipping,
    /// getting up, tucking, untucking, turning, casting, pulling a fish in, swallowing it or taking the line in, or jumping for joy.
    static let unbroken: Set<PenguinMove> = [
        .lookTurn, .lookBack, .bellyDown, .slide, .slip, .getUp, .tuck, .untuck, .cast, .pull, .gulp, .reel, .happy, .fishHappy,
    ]

    /// The hole: where it is (a share of the lane), where the penguin stands to fish in it, and how far it has come.
    private struct Hole {
        enum Phase { case appearing, waiting, occupied, leaving }
        var place: Double
        var home: Double
        var phase: Phase
    }

    private(set) var plan: Pose
    /// The scene it is in, nil while it does something that is not one: sleep, a look at the pointer.
    private(set) var scene: PenguinScene?
    /// Rises with every scene begun, so a test sees one that repeats.
    private(set) var sceneSerial = 0
    /// How often a prop was found left over when a scene began and had to be cleared: never, which a test checks.
    private(set) var strayProps = 0
    private var lastScene: PenguinScene?
    private var queue: [PenguinStep] = []
    private(set) var stance = PenguinMove.Stance.standing
    private var hole: Hole?
    /// Where it fishes from and the way the hole is (1 right, -1 left), worked out when it walks there.
    private var holeSpot: (start: Double, direction: Double)?
    private var travel = 0.0
    private var keeper = LaneKeeper()
    /// What the penguin keeps to when it waddles: the lane with the crossing shut. A waddle never goes through it.
    private var walkKeeper = LaneKeeper()
    private(set) var busyness = 0.0
    private var senses = CatSenses()
    private var generator: SplitMix64
    /// What it was in the middle of when it turned to look, to go on with: a wait with its line in, a flap.
    private var resumeStep: PenguinStep?
    private var frozenSince: TimeInterval = 0
    private var lastNear: TimeInterval = 0
    /// It has looked as long as it will, and does not look again until the pointer has gone away.
    private var tired = false
    private var lastFreezeEnd = -TimeInterval.infinity

    init(seed: UInt64, now: TimeInterval, position: Double = 0.5, facing: Facing = .left) {
        generator = SplitMix64(seed: seed)
        plan = Pose(motion: PenguinMove.stand.motion, facing: facing, from: position, to: position, began: now, duration: 2)
    }

    var move: PenguinMove { PenguinMove(plan.motion) }

    var isAsleep: Bool { move == .sleep }

    /// Whether it has a hole out now.
    var hasProps: Bool { hole != nil }

    /// Where the penguin is at `now`.
    func position(at now: TimeInterval) -> Double { plan.position(at: now) }

    /// How much faster than its own pace it waddles now, for the Mac's load.
    var quickening: Double { 1 + PenguinMove.busyBoost * busyness }

    // MARK: From outside

    /// A stroke: a jump for joy, and then it goes on with what it was doing.
    mutating func pet(now: TimeInterval) -> Outcome {
        guard !isCrossing(at: now), !Self.unbroken.contains(move) else { return .unchanged }
        let before = plan
        let joy = Self.happyDuration...Self.happyDuration
        var steps: [PenguinStep] = [.stay(stance == .fishing ? .fishHappy : .happy, joy)]
        if isStaring {
            // A stroke ends a stare, and what it was doing before it goes on.
            lastFreezeEnd = now
            if let resumeStep { steps.append(resumeStep) }
            resumeStep = nil
        } else if stance == .lying {
            // Flat on its belly, it jumps up for joy and has had enough of that: what was left of the scene is not gone on with.
            queue = []
            scene = nil
        } else if let left = leftOfPlan(now: now) {
            steps.append(left)
        }
        queue.insert(contentsOf: steps, at: 0)
        startQueue(now: now)
        return outcome(since: before)
    }

    /// Back on a notch after being out of sight: standing where it was, with nothing it was playing with, and nothing it last saw is news.
    mutating func resume(now: TimeInterval) {
        queue = []
        scene = nil
        clearProps()
        stance = .standing
        resumeStep = nil
        tired = false
        lastFreezeEnd = -.infinity
        plan = made(.stand, now: now, duration: 2)
    }

    /// Advances the penguin to `now`. `travel` is how far, in points of its picture's pixels, it can walk along the lane.
    mutating func update(now: TimeInterval, senses: CatSenses, tuning: CatTuning, travel: Double, lane: LaneContext) -> Outcome {
        let before = plan
        self.travel = travel
        self.senses = senses
        settle(lane: lane)
        // With the reaction off a busy Mac and a quiet one are the same to it: nothing of the load is read.
        busyness = tuning.reactsToBusyMachine ? min(max((senses.cpuLoad - Self.busyFrom) / (1 - Self.busyFrom), 0), 1) : 0
        if tuning.reactsToBusyMachine, senses.busyBurst { busyness = max(busyness, Self.burstBusyness) }
        let sticky = Self.unbroken.contains(move) && now < plan.end || isCrossing(at: now)
        if !sticky, interruption(senses, now: now) {
            // Done.
        } else if !sticky, looking(senses, tuning: tuning, now: now) {
            // Done.
        } else if now >= plan.end {
            advance(senses, tuning: tuning, now: now)
        }
        return outcome(since: before)
    }

    /// Takes the stretches of the lane it must not stop in. One that stands in one when they are taken is put at the nearer end of it, which
    /// is a jump, and then it has nothing it was playing with: a hole would be left across the camera.
    mutating func settle(lane: LaneContext) {
        keeper = LaneKeeper(lane)
        var shut = lane
        shut.closed += lane.crossing
        walkKeeper = LaneKeeper(shut)
        guard plan.from == plan.to, !(lane.crossing.isEmpty && lane.zones.isEmpty) else { return }
        let here = keeper.settled(plan.to)
        guard here != plan.to else { return }
        // (A hole that is closing is on the pose and no longer on the brain: it goes with the rest.)
        if hasProps || plan.prop != nil || stance != .standing {
            clearProps()
            queue = []
            scene = nil
            resumeStep = nil
            stance = .standing
            plan = Pose(motion: PenguinMove.stand.motion, facing: plan.facing, from: here, to: here, began: plan.began, duration: 0)
            return
        }
        plan.from = here
        plan.to = here
    }

    // MARK: Reacting

    /// What it drops what it is doing for. True when it did: there is only waking.
    private mutating func interruption(_ senses: CatSenses, now: TimeInterval) -> Bool {
        if move == .sleep, senses.idleSeconds < Self.wakeIdle {
            queue = [.stay(.stand, 1.5...2.5)]
            scene = nil
            startQueue(now: now)
            return true
        }
        return false
    }

    /// Whether it is looking at the pointer.
    private var isStaring: Bool { move == .lookTurn || move == .lookFlap }

    /// A penguin that has the pointer near turns to face it and flaps, and goes on when the pointer has gone, a moment later, and does not
    /// look for ever. One that is fishing pulls its line in first (and the hole closes), one that is lying gets up, and one that is asleep or
    /// tucked in does not look at all.
    private mutating func looking(_ senses: CatSenses, tuning: CatTuning, now: TimeInterval) -> Bool {
        let near = senses.pointer?.isNear ?? false
        if isStaring {
            if near { lastNear = now }
            let giveUp = now - frozenSince >= Self.freezeLimit
            if giveUp || (!near && now - lastNear >= Self.releaseDelay) {
                tired = giveUp && near
                release(now: now)
                return true
            }
            // Turned to face it, and then held, flapping, for as long as it takes.
            if now >= plan.end { plan = made(.lookFlap, now: now, duration: 2) }
            return true
        }
        guard near else {
            tired = false
            return false
        }
        let here = plan.position(at: now)
        // (One that is on its way to look, from its rod or its belly, is not told again.)
        guard !tired, now - lastFreezeEnd >= tuning.reactionCooldown, stance != .tucked, !queue.contains(.stare),
              keeper.settled(here) == here else { return false }
        if stance == .standing {
            freeze(at: here, now: now)
        } else {
            // From its belly or its rod: out of that first, and the rest of the scene is dropped.
            queue = wrapUp() + [.stare]
            scene = nil
            resumeStep = nil
            startQueue(now: now)
        }
        return true
    }

    private mutating func freeze(at here: Double, now: TimeInterval) {
        resumeStep = leftOfPlan(now: now)
        frozenSince = now
        lastNear = now
        plan = made(.lookTurn, now: now, duration: PenguinMove.lookTurn.passDuration, from: here)
    }

    /// Looks no more: turns back, and then what it was doing.
    private mutating func release(now: TimeInterval) {
        lastFreezeEnd = now
        if let resumeStep { queue.insert(resumeStep, at: 0) }
        resumeStep = nil
        plan = made(.lookBack, now: now, duration: PenguinMove.lookBack.passDuration)
    }

    /// What was left of a pose that goes round and round, to go on with when something has come in between: not of one on its belly or
    /// asleep, which is not gone back to.
    private func leftOfPlan(now: TimeInterval) -> PenguinStep? {
        guard plan.motion.loops, plan.from == plan.to, plan.end - now > 1, stance == .standing || stance == .fishing, move != .tucked,
              !isStaring else { return nil }
        let left = plan.end - now
        return .stay(move, left...left)
    }

    private func isCrossing(at now: TimeInterval) -> Bool {
        guard plan.from != plan.to else { return false }
        return keeper.isInCrossing(plan.position(at: now))
    }

    // MARK: Moving on

    /// The plan is over: the next step, or the next scene, or sleep.
    private mutating func advance(_ senses: CatSenses, tuning: CatTuning, now: TimeInterval) {
        if senses.idleSeconds >= tuning.sleepThreshold(hour: senses.hour) {
            // Down for the night in steps: the line in if it is fishing, up if it is lying, head tucked in, then asleep.
            let asleep = PenguinStep.stay(.sleep, Self.sleepChunk...Self.sleepChunk)
            if move == .sleep {
                plan = made(.sleep, now: now, duration: Self.sleepChunk)
            } else if queue.contains(asleep) {
                startQueue(now: now)
            } else {
                queue = wrapUp() + [asleep]
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
        // Nothing to do: stands.
        clearProps()
        stance = .standing
        plan = made(.stand, now: now, duration: 2)
    }

    private mutating func beginScene() {
        // The last scene took all it set out with it.
        if hasProps { strayProps += 1 }
        clearProps()
        if stance == .fishing { stance = .standing }
        let night = CatTuning.isNight(hour: senses.hour)
        var choices = PenguinScene.allCases.filter { $0 != lastScene && $0.weight(night: night) > 0 }
        if choices.isEmpty { choices = [.restStand] }
        let total = choices.reduce(0) { $0 + $1.weight(night: night) }
        var roll = Double.random(in: 0..<total, using: &generator)
        var picked = choices[0]
        for choice in choices {
            let weight = choice.weight(night: night)
            if roll < weight {
                picked = choice
                break
            }
            roll -= weight
        }
        scene = picked
        lastScene = picked
        sceneSerial += 1
        queue = picked.steps(using: &generator)
    }

    /// What it has to do to end what it is playing with, in order: the line in and the hole closed.
    private func wrapUp() -> [PenguinStep] {
        guard let hole else { return [] }
        switch hole.phase {
        case .occupied: return [.reel, .holeGoes]
        case .appearing, .waiting: return [.holeGoes]
        case .leaving: return []
        }
    }

    private mutating func clearProps() {
        hole = nil
        holeSpot = nil
    }

    // MARK: Plans

    /// A plan for `step`, from where the penguin is at `now`; nil for a step that takes no time or cannot be done. It gets up, lies down,
    /// tucks in or untucks first when the step needs it, and the step waits its turn; the line in first, whatever the step is.
    private mutating func begin(_ step: PenguinStep, now: TimeInterval) -> Pose? {
        var step = step
        // A walk or a glide is sent to a place the moment it begins, which is before it lies down for a glide: it faces the way it is going.
        switch step {
        case .walk(let place):
            guard let target = route(place, sliding: false, now: now) else { return nil }
            step = .walkTo(target)
        case .slide(let place):
            guard let target = route(place, sliding: true, now: now) else { return nil }
            step = .slideTo(target)
        default: break
        }
        if stance == .fishing, step.stance != .fishing {
            queue.insert(step, at: 0)
            queue.insert(.reel, at: 0)
            return nil
        }
        if step.stance != stance {
            if let hop = hop(to: step.stance) {
                queue.insert(step, at: 0)
                stance = hop.ends
                return made(hop.move, now: now, duration: hop.move.passDuration, facing: facingToward(step, now: now))
            }
            stance = step.stance
        }
        let planned: Pose?
        switch step {
        case .stay(let move, let seconds):
            planned = made(move, now: now, duration: Double.random(in: seconds, using: &generator))
        case .walk, .slide:
            planned = nil
        case .walkTo(let target):
            planned = go(to: target, sliding: false, now: now)
        case .slideTo(let target):
            planned = go(to: target, sliding: true, now: now)
        case .slip:
            planned = made(.slip, now: now, duration: PenguinMove.slip.passDuration)
        case .placeHole:
            planned = placeHole(now: now)
        case .cast:
            planned = cast(now: now)
        case .reel:
            planned = reel(now: now)
        case .holeGoes:
            planned = holeGoes(now: now)
        case .stare:
            planned = stare(now: now)
        }
        if planned != nil { stance = step.endStance }
        return planned
    }

    /// The move that takes the penguin one step nearer a stance, and the one it ends in; nil when it needs none.
    private func hop(to needed: PenguinMove.Stance) -> (move: PenguinMove, ends: PenguinMove.Stance)? {
        switch (stance, needed) {
        case (.standing, .lying): (.bellyDown, .lying)
        case (.lying, .standing), (.lying, .tucked), (.lying, .fishing): (.getUp, .standing)
        case (.standing, .tucked): (.tuck, .tucked)
        case (.tucked, .standing), (.tucked, .lying), (.tucked, .fishing): (.untuck, .standing)
        default: nil
        }
    }

    /// The way it faces for a move that is made on the way to `step`: towards where it is going.
    private func facingToward(_ step: PenguinStep, now: TimeInterval) -> Facing {
        let here = plan.position(at: now)
        switch step {
        case .walkTo(let target), .slideTo(let target): return abs(target - here) * travel >= 1 ? facing(target - here) : plan.facing
        default: return plan.facing
        }
    }

    /// The penguin doing `move` where it is, with whatever it has out (the hole).
    private mutating func made(
        _ move: PenguinMove, now: TimeInterval, duration: TimeInterval, facing: Facing? = nil, from: Double? = nil, to: Double? = nil,
        fpsScale: Double = 1
    ) -> Pose {
        let there = plan.position(at: now)
        // A penguin at its hole is not moved off the place it is at.
        let here = hasProps ? there : keeper.settled(there)
        var pose = Pose(
            motion: move.motion, facing: facing ?? plan.facing, from: from ?? here, to: to ?? from ?? here, began: now, duration: duration,
            fpsScale: fpsScale
        )
        pose.prop = nextProp(for: move)
        return pose
    }

    /// What it has out for the pose that is being made, and how far it has come: a hole opens in one pose and closes in one.
    private mutating func nextProp(for move: PenguinMove) -> PoseProp? {
        guard var current = hole else { return nil }
        let look: PenguinProp
        switch current.phase {
        case .appearing:
            look = .holeOpening
            current.phase = .waiting
            hole = current
        case .waiting: look = .holeStill
        case .occupied:
            switch move {
            case .bite: look = .holeChurning
            case .pull: look = .holeSplashing
            default: look = .holeRippling
            }
        case .leaving:
            look = .holeClosing
            hole = nil
        }
        return PoseProp(look: look.look, from: current.place, to: current.place, alsoAt: [current.home])
    }

    private func facing(_ direction: Double) -> Facing { direction > 0 ? .right : .left }

    // MARK: Waddling and gliding

    /// Where a walk or a glide sent to `place` goes, as a share of the lane, before the lane's rules have their say (`go`); nil for none.
    private mutating func route(_ place: PenguinPlace, sliding: Bool, now: TimeInterval) -> Double? {
        let here = plan.position(at: now)
        guard travel >= 1 else {
            queue = []
            return nil
        }
        let kept = sliding ? keeper : walkKeeper
        switch place {
        case .away(let pixels):
            // A waddle goes no further than the crossing; a glide may go through it.
            let reach = kept.reach(from: here)
            // (One that is lying down already goes on the way it faces: it cannot turn round on its belly.)
            var right = stance == .lying ? plan.facing == .right : (here <= 0.08 ? true : here >= 0.92 ? false : chance(0.5))
            let distance = Double.random(in: pixels, using: &generator)
            func aim() -> Double { right ? min(here + distance / travel, reach.upperBound) : max(here - distance / travel, reach.lowerBound) }
            var aimed = aim()
            if abs(aimed - here) * travel < 10 {
                // (No room that way: one on its belly stays where it is, rather than turn round.)
                if stance == .lying { return nil }
                right.toggle()
                aimed = aim()
            }
            return aimed
        case .farEdge:
            return here < 0.5 ? 1 - Self.edgeInset : Self.edgeInset
        case .fishSpot:
            guard let spot = fishSpot(from: here) else {
                queue = []
                return nil
            }
            holeSpot = spot
            return spot.start
        }
    }

    /// Waddles or glides to `target`, held to what the lane lets it do: out of the places it must not stop in, and no further than it can
    /// reach (a waddle: not through the crossing, a glide: not into what is closed). As quick as it is, whatever the Mac is doing, but for
    /// the waddle's quickening.
    private mutating func go(to target: Double, sliding: Bool, now: TimeInterval) -> Pose? {
        let here = plan.position(at: now)
        guard travel >= 1 else {
            queue = []
            return nil
        }
        let end = (sliding ? keeper : walkKeeper).destination(target, from: here)
        let covered = abs(end - here) * travel
        guard covered >= 1 else { return nil }
        let way = facing(end - here)
        if sliding {
            return made(.slide, now: now, duration: covered / PenguinMove.slide.speed, facing: way, from: here, to: end)
        }
        let quicker = quickening
        return made(
            .waddle, now: now, duration: covered / (PenguinMove.waddle.speed * quicker), facing: way, from: here, to: end, fpsScale: quicker
        )
    }

    // MARK: The hole

    /// Where there is room to open a hole in front of it (`PenguinMove.holeReach` away), nearest to `here`: the place it fishes from, and the
    /// way the hole is, which is the way it faces when it gets there if there is room for it so. Both the place and the hole are outside the
    /// crossing and out of the others' way, and the penguin can waddle there.
    private func fishSpot(from here: Double) -> (start: Double, direction: Double)? {
        guard travel >= 1 else { return nil }
        let span = PenguinMove.holeReach / travel
        let facingNow = plan.facing == .right ? 1.0 : -1.0
        let starts = [here] + stride(from: 0.0, through: 1.0, by: 0.05).filter { abs($0 - here) > 0.001 }.sorted { abs($0 - here) < abs($1 - here) }
        for start in starts {
            let arriving = start > here + 0.0005 ? 1.0 : (start < here - 0.0005 ? -1.0 : facingNow)
            for way in [arriving, -arriving] where fits(from: start, to: start + way * span, startingAt: here) { return (start, way) }
        }
        return nil
    }

    private func fits(from start: Double, to end: Double, startingAt here: Double) -> Bool {
        guard (0.0...1.0).contains(start), (0.0...1.0).contains(end), keeper.isFree(start), keeper.isFree(end),
              walkKeeper.destination(start, from: here) == start else { return false }
        let (low, high) = (min(start, end), max(start, end))
        if keeper.lane.crossing.contains(where: { high > $0.lowerBound && low < $0.upperBound }) { return false }
        return walkKeeper.reach(from: start).contains(end)
    }

    /// Stands and watches the ice crack open in front of it, a step and a bit away.
    private mutating func placeHole(now: TimeInterval) -> Pose? {
        let here = plan.position(at: now)
        guard travel >= 1, let spot = holeSpot ?? fishSpot(from: here) else {
            queue = []
            return nil
        }
        let span = PenguinMove.holeReach / travel
        for way in [spot.direction, -spot.direction] {
            let end = here + way * span
            guard fits(from: here, to: end, startingAt: here) else { continue }
            hole = Hole(place: end, home: here, phase: .appearing)
            return made(.stand, now: now, duration: PenguinProp.holeOpening.passDuration, facing: facing(way))
        }
        queue = []
        holeSpot = nil
        return nil
    }

    /// Puts the line in the hole.
    private mutating func cast(now: TimeInterval) -> Pose? {
        guard hole != nil else {
            queue = []
            return nil
        }
        hole?.phase = .occupied
        return made(.cast, now: now, duration: PenguinMove.cast.passDuration)
    }

    /// Takes the line in, and the hole stands empty.
    private mutating func reel(now: TimeInterval) -> Pose? {
        guard hole != nil else {
            stance = .standing
            return nil
        }
        let pose = made(.reel, now: now, duration: PenguinMove.reel.passDuration)
        hole?.phase = .waiting
        return pose
    }

    private mutating func holeGoes(now: TimeInterval) -> Pose? {
        guard hole != nil else { return nil }
        hole?.phase = .leaving
        return made(.stand, now: now, duration: PenguinProp.holeClosing.passDuration)
    }

    // MARK: Looking

    /// Turns to face the viewer where it stands.
    private mutating func stare(now: TimeInterval) -> Pose? {
        frozenSince = now
        lastNear = now
        resumeStep = nil
        return made(.lookTurn, now: now, duration: PenguinMove.lookTurn.passDuration)
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

nonisolated extension PenguinBrain: CharacterBrain {
    var pose: Pose { plan }
}
