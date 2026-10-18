import Foundation

/// What the hamster decides to do. A value that holds no timer and reads nothing, like the cat's and the capybara's: it is told the time
/// and what the hamster senses, and says whether the picture changed, so every rule of its day is a test with a made-up clock.
///
/// It is busy. What it does with its time is a handful of scenes (`HamsterScene`) picked at random by weights that depend on the time of
/// day and on the Mac, never the same one twice running: scurrying about, washing its face, stuffing seeds into its cheeks, curling up,
/// and, its signature, running in a wheel that pops up beside it. On top of that:
/// - **the Mac's load is the wheel's speed**: in the wheel it runs at the pace the load gives (`WheelPace`: a lazy jog, a jog, a run, a
///   sprint with lines streaming over its back), with a rest in between on a quiet Mac, and it follows the load up and down, never more
///   than once in `paceHold` seconds. A burst of work (`busyBurst`) sends it to the wheel at once, once. With the setting off it never
///   runs faster than a lazy jog. **Out of the wheel it is never in a hurry for any of it**: its walk is its walk;
/// - the pointer comes near: it freezes where it is, upright, and looks at it, and goes on when the pointer is gone. In the wheel it
///   stops running to look. It looks for no more than `freezeLimit` seconds, and not again until the pointer has gone away;
/// - a stroke makes it hop for joy (in the wheel, inside it), and then it goes on with what it was doing;
/// - the user has been away for the sleep time: it finishes what it is in, comes out of the wheel if it is in it, curls up and sleeps,
///   and uncurls when the user is back.
///
/// It has what it plays with only while the scene it is in calls for it: the wheel from the moment it pops up to the moment it has gone,
/// and the seeds until the last is stuffed in a cheek. Whatever interrupts a scene ends it first (`wrapUp`), and the props are a state of
/// this brain, so a wheel never stays behind.
nonisolated struct HamsterBrain: Sendable {
    typealias Outcome = BrainOutcome

    /// A user who has touched something this recently is at the Mac.
    static let wakeIdle: TimeInterval = 2
    static let sleepChunk: TimeInterval = 24
    /// A hop for joy, and a moment to be pleased with itself.
    static let happyDuration: TimeInterval = 1.2
    /// How near the end of the lane it goes when it goes to the end, as a share of it.
    static let edgeInset = 0.04
    /// The least time between one change of pace and the next: a picture is begun again at every change.
    static let paceHold: TimeInterval = 3
    /// How long it looks at the pointer, at the most, and how long after the pointer has gone it goes on looking.
    static let freezeLimit: TimeInterval = 15
    static let releaseDelay: TimeInterval = 0.9
    /// What it drops everything for is held to these moves: a stroke or a stare is not taken while it is hopping, sitting down or standing up,
    /// curling or uncurling.
    static let unbroken: Set<HamsterMove> = [.sitDown, .standUp, .curl, .uncurl, .hopIn, .hopOut, .happy, .wheelHappy]
    /// The load from which, or a burst, the Mac is busy enough for the wheel to be what it wants to do.
    static let busyFrom = 0.4

    /// The wheel: where it stands (a share of the lane: where the hamster is when it is in it), where it hops from and back to, and how far
    /// it has come.
    private struct Wheel {
        enum Phase { case appearing, waiting, occupied, leaving }
        var place: Double
        var home: Double
        var phase: Phase
    }

    private struct Seeds {
        var place: Double
        /// How many are still there to be picked up.
        var count: Int
    }

    private(set) var plan: Pose
    /// The scene it is in, nil while it does something that is not one: sleep, a stare at the pointer.
    private(set) var scene: HamsterScene?
    /// Rises with every scene begun, so a test sees one that repeats.
    private(set) var sceneSerial = 0
    /// How often a prop was found left over when a scene began and had to be cleared: never, which a test checks.
    private(set) var strayProps = 0
    /// How fast it runs when it runs: from the load, with a line to cross each way (`WheelPace`).
    private(set) var pace = WheelPace.lazy
    private var lastScene: HamsterScene?
    private var queue: [HamsterStep] = []
    private(set) var stance = HamsterMove.Stance.seated
    private var wheel: Wheel?
    private var seeds: Seeds?
    /// Where it hops into the wheel from and the way it faces to (1 right, -1 left), worked out when it walks there.
    private var wheelStart: (start: Double, direction: Double)?
    private var travel = 0.0
    private var keeper = LaneKeeper()
    private var effort = 0.0
    private var senses = CatSenses()
    private var generator: SplitMix64
    /// The burst it has heard of: it goes to the wheel for each once.
    private var burstHeard = false
    /// What it was in the middle of when it froze, to go on with: a run in the wheel, a groom.
    private var resumeStep: HamsterStep?
    private var frozenSince: TimeInterval = 0
    private var lastNear: TimeInterval = 0
    /// It has looked as long as it will, and does not look again until the pointer has gone away.
    private var tired = false
    private var lastFreezeEnd = -TimeInterval.infinity

    init(seed: UInt64, now: TimeInterval, position: Double = 0.5, facing: Facing = .left) {
        generator = SplitMix64(seed: seed)
        plan = Pose(motion: HamsterMove.sit.motion, facing: facing, from: position, to: position, began: now, duration: 2)
    }

    var move: HamsterMove { HamsterMove(plan.motion) }

    var isAsleep: Bool { move == .sleep }

    /// Whether it has a wheel or seeds out now.
    var hasProps: Bool { wheel != nil || seeds != nil }

    /// Where the hamster is at `now`.
    func position(at now: TimeInterval) -> Double { plan.position(at: now) }

    // MARK: From outside

    /// A stroke: a hop for joy, and then it goes on with what it was doing.
    mutating func pet(now: TimeInterval) -> Outcome {
        guard !isCrossing(at: now), !Self.unbroken.contains(move) else { return .unchanged }
        let before = plan
        var steps: [HamsterStep] = [.stay(stance == .wheel ? .wheelHappy : .happy, Self.happyDuration...Self.happyDuration)]
        if isStaring {
            // A stroke ends a stare, and what it was doing before it goes on.
            lastFreezeEnd = now
            if let resumeStep { steps.append(resumeStep) }
            resumeStep = nil
        } else if let left = leftOfPlan(now: now) {
            steps.append(left)
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
        stance = .seated
        resumeStep = nil
        burstHeard = false
        tired = false
        lastFreezeEnd = -.infinity
        plan = made(.sit, now: now, duration: 2)
    }

    /// Advances the hamster to `now`. `travel` is how far, in points of its picture's pixels, it can walk along the lane.
    mutating func update(now: TimeInterval, senses: CatSenses, tuning: CatTuning, travel: Double, lane: LaneContext) -> Outcome {
        let before = plan
        self.travel = travel
        self.senses = senses
        settle(lane: lane)
        let burst = tuning.reactsToBusyMachine && senses.busyBurst
        // With the reaction off a busy Mac and a quiet one are the same to it: nothing of the load is read.
        effort = tuning.reactsToBusyMachine ? min(max(burst ? max(senses.cpuLoad, WheelPace.sprint.risesAt) : senses.cpuLoad, 0), 1) : 0
        pace = WheelPace.pace(for: effort, from: pace)
        if !burst { burstHeard = false }
        let sticky = Self.unbroken.contains(move) && now < plan.end || isCrossing(at: now)
        if !sticky, interruption(senses, burst: burst, now: now) {
            // Done.
        } else if !sticky, looking(senses, tuning: tuning, now: now) {
            // Done.
        } else if !sticky, followsTheLoad(now: now) {
            // Done.
        } else if now >= plan.end {
            advance(senses, tuning: tuning, now: now)
        }
        return outcome(since: before)
    }

    /// Takes the stretches of the lane it must not stop in. One that stands in one when they are taken is put at the nearer end of it, which
    /// is a jump, and then it has nothing it was playing with: a wheel would be left across the camera.
    mutating func settle(lane: LaneContext) {
        keeper = LaneKeeper(lane)
        guard plan.from == plan.to, !(lane.crossing.isEmpty && lane.zones.isEmpty) else { return }
        let here = keeper.settled(plan.to)
        guard here != plan.to else { return }
        // (A wheel that is going is on the pose and no longer on the brain: it goes with the rest.)
        if hasProps || plan.prop != nil || stance != .seated {
            clearProps()
            queue = []
            scene = nil
            resumeStep = nil
            stance = .seated
            plan = Pose(motion: HamsterMove.sit.motion, facing: plan.facing, from: here, to: here, began: plan.began, duration: 0)
            return
        }
        plan.from = here
        plan.to = here
    }

    // MARK: Reacting

    /// What it drops what it is doing for. True when it did: waking, and a burst of work.
    private mutating func interruption(_ senses: CatSenses, burst: Bool, now: TimeInterval) -> Bool {
        if move == .sleep, senses.idleSeconds < Self.wakeIdle {
            queue = [.stay(.sit, 1.5...2.5)]
            scene = nil
            startQueue(now: now)
            return true
        }
        // A burst of work, which it hears of once: to the wheel, at once, if there is room for one. Not from sleep, not from a stare
        // (which has a way out of its own) and not in the middle of the wheel scene it is in.
        guard burst, !burstHeard, stance != .curled, !isStaring else { return false }
        burstHeard = true
        guard scene != .wheel, travel >= 1, soakSpot(from: plan.position(at: now)) != nil else { return false }
        queue = wrapUp() + HamsterScene.wheel.steps(using: &generator, busy: true, longer: 1)
        scene = .wheel
        lastScene = .wheel
        sceneSerial += 1
        startQueue(now: now)
        return true
    }

    /// Whether it is looking at the pointer.
    private var isStaring: Bool { move == .freeze || move == .wheelWatch }

    /// A hamster that has the pointer near freezes where it is, and looks at it: upright, ears up, and still, in the wheel too, where it
    /// stops running to look. It goes on when the pointer has gone, a moment later, and does not look for ever.
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
            // Held for as long as it takes.
            if now >= plan.end { plan = made(move, now: now, duration: 2) }
            return true
        }
        guard near else {
            tired = false
            return false
        }
        let here = plan.position(at: now)
        guard !tired, now - lastFreezeEnd >= tuning.reactionCooldown, stance != .curled, keeper.settled(here) == here else { return false }
        freeze(at: here, now: now)
        return true
    }

    private mutating func freeze(at here: Double, now: TimeInterval) {
        resumeStep = leftOfPlan(now: now)
        frozenSince = now
        lastNear = now
        if stance != .wheel { stance = .seated }
        plan = made(stance == .wheel ? .wheelWatch : .freeze, now: now, duration: 2, from: here)
    }

    /// Looks no more: a moment of sitting, and then what it was doing.
    private mutating func release(now: TimeInterval) {
        lastFreezeEnd = now
        if let resumeStep { queue.insert(resumeStep, at: 0) }
        resumeStep = nil
        plan = made(stance == .wheel ? .wheelSit : .sit, now: now, duration: 0.5)
    }

    /// What was left of a pose that goes round and round, to go on with when something has come in between.
    private func leftOfPlan(now: TimeInterval) -> HamsterStep? {
        guard plan.motion.loops, plan.from == plan.to, plan.end - now > 1, move != .sleep, !isStaring else { return nil }
        let left = plan.end - now
        return move.runs ? .run(left...left) : .stay(move, left...left)
    }

    /// In the wheel it runs at the pace of the Mac's load: when the load has gone over a line, a different pace, and a sitter sets off.
    private mutating func followsTheLoad(now: TimeInterval) -> Bool {
        guard stance == .wheel, plan.from == plan.to, now - plan.began >= Self.paceHold, plan.end - now > 0.5 else { return false }
        let left = plan.end - now
        if move.runs, WheelPace(move) != pace {
            plan = made(pace.move, now: now, duration: left)
            return true
        }
        // A sitter, in the wheel, sets off when the Mac is busy enough for more than a lazy jog.
        if move == .wheelSit, pace > .lazy {
            plan = made(pace.move, now: now, duration: max(left, 3))
            return true
        }
        return false
    }

    private func isCrossing(at now: TimeInterval) -> Bool {
        guard plan.from != plan.to else { return false }
        return keeper.isInCrossing(plan.position(at: now))
    }

    // MARK: Moving on

    /// The plan is over: the next step, or the next scene, or sleep.
    private mutating func advance(_ senses: CatSenses, tuning: CatTuning, now: TimeInterval) {
        if senses.idleSeconds >= tuning.sleepThreshold(hour: senses.hour) {
            // Down for the night in steps: out of the wheel if it is in it, curled up, then asleep.
            let asleep = HamsterStep.stay(.sleep, Self.sleepChunk...Self.sleepChunk)
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
        // Nothing to do: sits.
        clearProps()
        stance = .seated
        plan = made(.sit, now: now, duration: 2)
    }

    private mutating func beginScene() {
        // The last scene took all it set out with it.
        if hasProps { strayProps += 1 }
        clearProps()
        if stance == .wheel { stance = .seated }
        let night = CatTuning.isNight(hour: senses.hour)
        let busy = effort >= Self.busyFrom
        var choices = HamsterScene.allCases.filter { $0 != lastScene && $0.weight(night: night, busy: busy) > 0 }
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
        queue = picked.steps(using: &generator, busy: busy, longer: 1 + 0.6 * effort)
    }

    /// What it has to do to end what it is playing with, in order: out of the wheel and the wheel back. The seeds that lie there are simply
    /// taken away.
    private mutating func wrapUp() -> [HamsterStep] {
        var steps: [HamsterStep] = []
        if let wheel {
            switch wheel.phase {
            case .occupied: steps += [.hopOut, .wheelGoes]
            case .appearing, .waiting: steps.append(.wheelGoes)
            case .leaving: break
            }
        }
        seeds = nil
        return steps
    }

    private mutating func clearProps() {
        wheel = nil
        seeds = nil
        wheelStart = nil
    }

    // MARK: Plans

    /// A plan for `step`, from where the hamster is at `now`; nil for a step that takes no time or cannot be done. It sits down, stands up
    /// or uncurls first when the step needs it, and the step waits its turn; out of the wheel first, whatever the step is.
    private mutating func begin(_ step: HamsterStep, now: TimeInterval) -> Pose? {
        if stance == .wheel, step.stance != .wheel {
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
            planned = made(move, now: now, duration: Double.random(in: seconds, using: &generator))
        case .go(let place):
            planned = go(place, now: now)
        case .placeWheel:
            planned = placeWheel(now: now)
        case .hopIn:
            planned = hopIn(now: now)
        case .hopOut:
            planned = hopOut(now: now)
        case .wheelGoes:
            planned = wheelGoes(now: now)
        case .run(let seconds):
            planned = made(pace.move, now: now, duration: Double.random(in: seconds, using: &generator))
        case .placeSeeds:
            planned = placeSeeds(now: now)
        case .stuff(let number):
            planned = stuff(number, now: now)
        }
        if planned != nil { stance = step.endStance }
        return planned
    }

    /// The move that takes the hamster one step nearer a stance, and the one it ends in; nil when it needs none (it just is).
    private func hop(to needed: HamsterMove.Stance) -> (move: HamsterMove, ends: HamsterMove.Stance)? {
        switch (stance, needed) {
        case (.standing, .seated), (.standing, .curled): (.sitDown, .seated)
        case (.seated, .standing): (.standUp, .standing)
        case (.curled, .seated), (.curled, .standing): (.uncurl, .seated)
        case (.seated, .curled): (.curl, .curled)
        default: nil
        }
    }

    /// The hamster doing `move` where it is, with whatever it has out (the wheel, the seeds).
    private mutating func made(
        _ move: HamsterMove, now: TimeInterval, duration: TimeInterval, facing: Facing? = nil, from: Double? = nil, to: Double? = nil
    ) -> Pose {
        let there = plan.position(at: now)
        // A hamster in or by its wheel is not moved off the place it is at.
        let here = hasProps ? there : keeper.settled(there)
        var pose = Pose(
            motion: move.motion, facing: facing ?? plan.facing, from: from ?? here, to: to ?? from ?? here, began: now, duration: duration,
            fpsScale: 1
        )
        pose.prop = nextProp(for: move)
        return pose
    }

    /// What it has out for the pose that is being made, and how far it has come: a wheel comes up in one pose and goes in one.
    private mutating func nextProp(for move: HamsterMove) -> PoseProp? {
        if var current = wheel {
            let look: HamsterProp
            switch current.phase {
            case .appearing:
                look = .wheelAppearing
                current.phase = .waiting
                wheel = current
            case .waiting: look = .wheelStill
            case .occupied: look = move.runs ? pace.prop : .wheelStill
            case .leaving:
                look = .wheelGoing
                wheel = nil
            }
            return PoseProp(look: look.look, from: current.place, to: current.place, alsoAt: [current.home])
        }
        if let seeds {
            let look: HamsterProp = seeds.count >= 3 ? .seeds3 : (seeds.count == 2 ? .seeds2 : .seeds1)
            return PoseProp(look: look.look, from: seeds.place, to: seeds.place)
        }
        return nil
    }

    private func facing(_ direction: Double) -> Facing { direction > 0 ? .right : .left }

    private mutating func go(_ place: HamsterPlace, now: TimeInterval) -> Pose? {
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
        case .wheelStart:
            guard let spot = soakSpot(from: here) else {
                queue = []
                return nil
            }
            wheelStart = spot
            target = spot.start
        }
        target = keeper.destination(target, from: here)
        let covered = abs(target - here) * travel
        guard covered >= 1 else { return nil }
        // A walk is as quick as it is, whatever the Mac is doing.
        return made(
            .scurry, now: now, duration: covered / HamsterMove.scurry.speed, facing: target == here ? plan.facing : facing(target - here),
            from: here, to: target
        )
    }

    // MARK: The wheel

    /// Where there is room to hop into a wheel and out again, nearest to `here`: the place it hops from and the way it faces. Both the place
    /// and the wheel's are outside the crossing and out of the others' way, and the hop does not go through the camera.
    private func soakSpot(from here: Double) -> (start: Double, direction: Double)? {
        guard travel >= 1 else { return nil }
        let span = HamsterMove.hopSpan / travel
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

    /// Sits and watches the wheel pop up beside it, a hop in front of it.
    private mutating func placeWheel(now: TimeInterval) -> Pose? {
        let here = plan.position(at: now)
        guard let spot = wheelStart ?? soakSpot(from: here), travel >= 1 else {
            queue = []
            return nil
        }
        let end = here + spot.direction * HamsterMove.hopSpan / travel
        guard fits(from: here, to: end, startingAt: here) else {
            queue = []
            wheelStart = nil
            return nil
        }
        wheel = Wheel(place: end, home: here, phase: .appearing)
        return made(.sit, now: now, duration: HamsterProp.wheelAppearing.passDuration, facing: facing(spot.direction))
    }

    private mutating func hopIn(now: TimeInterval) -> Pose? {
        guard var current = wheel else {
            queue = []
            return nil
        }
        current.phase = .occupied
        wheel = current
        return made(.hopIn, now: now, duration: HamsterMove.hopIn.passDuration, from: plan.position(at: now), to: current.place)
    }

    /// Out of the wheel the way it came, backwards, and the wheel stands empty.
    private mutating func hopOut(now: TimeInterval) -> Pose? {
        guard wheel != nil, travel >= 1 else {
            queue = []
            wheel = nil
            return nil
        }
        let here = plan.position(at: now)
        let way = plan.facing == .right ? 1.0 : -1.0
        let out = min(max(here - way * HamsterMove.hopSpan / travel, 0), 1)
        let pose = made(.hopOut, now: now, duration: HamsterMove.hopOut.passDuration, from: here, to: out)
        wheel?.phase = .waiting
        return pose
    }

    private mutating func wheelGoes(now: TimeInterval) -> Pose? {
        guard wheel != nil else { return nil }
        wheel?.phase = .leaving
        return made(.sit, now: now, duration: HamsterProp.wheelGoing.passDuration)
    }

    // MARK: The seeds

    /// Sits while a pile of seeds is put down just in front of it, on the side it faces if there is room there and on the other if not.
    private mutating func placeSeeds(now: TimeInterval) -> Pose? {
        let here = plan.position(at: now)
        guard travel >= 1 else {
            queue = []
            return nil
        }
        let direction = plan.facing == .right ? 1.0 : -1.0
        for way in [direction, -direction] {
            let reach = way > 0 ? HamsterMove.seedReach.right : HamsterMove.seedReach.left
            let place = here + reach / travel
            guard (0.0...1.0).contains(place), keeper.isFree(place) else { continue }
            seeds = Seeds(place: place, count: 3)
            return made(.sit, now: now, duration: Double.random(in: 1.0...1.8, using: &generator), facing: facing(way))
        }
        queue = []
        return nil
    }

    /// The first, second or third seed from the pile into a cheek: the pile shows what is there when it reaches for it.
    private mutating func stuff(_ number: Int, now: TimeInterval) -> Pose? {
        guard seeds != nil else { return nil }
        let move: HamsterMove = number == 1 ? .stuffA : (number == 2 ? .stuffB : .stuffC)
        let pose = made(move, now: now, duration: move.passDuration)
        if let count = seeds?.count, count > 1 { seeds?.count = count - 1 } else { seeds = nil }
        return pose
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

nonisolated extension HamsterBrain: CharacterBrain {
    var pose: Pose { plan }
}
