import Foundation

/// What the cat decides to do. A value that holds no timer and reads nothing: it is told the time and what the cat senses, and says
/// whether the picture changed, so every rule of its day is a test with a made-up clock.
///
/// What it does with its time is a string of small scenes (`CatScene`): a walk and a sit, a groom, a moth to chase, a ball of yarn. Each
/// is picked at random, by weights that depend on the time of day, never the same one twice running; each is a few steps; getting up and
/// sitting down between steps that need it is the brain's own business. On top of that, most urgent first:
/// - the pointer comes close to the strip: a pounce at it, or, for a sleeper or now and then, a startled jump (not more often than every
///   `reactionCooldown` seconds);
/// - a petting, a jump and a pounce are finished before anything else;
/// - the Mac is busy by its own standards (`BusyWatch`: a burst, now and then and not for long): it runs frantically, harder the busier the
///   processors are, whatever else is going on. A load that is merely high is not that, and only quickens its walks and brings on the sweat;
/// - the Mac plays sound: it dances;
/// - the user has been away for the sleep time: a yawn, then sleep, which ends with a yawn when the user is back;
/// - the pointer is within sight and it is sitting: it looks at it.
nonisolated struct CatBrain: Sendable {
    /// What an update did to the cat's plan.
    enum Outcome: Equatable {
        /// Nothing came due.
        case unchanged
        /// A new plan that looks like the one before it (a cat that goes on sleeping): a host has nothing to redraw.
        case extended
        /// A different picture: a host starts the new animation.
        case changed
    }

    static let reactionCooldown: TimeInterval = 8
    /// The chance that a pointer coming close makes a cat that is awake pounce, and not jump.
    static let pounceChance = 0.7
    /// The most a run speeds the frames up by.
    static let runFrameBoost = 0.5
    /// The load from which a Mac is busy enough to bother the cat a little (the walks quicken, it sweats), outside any burst: busyness is
    /// nothing at this and everything at a full load.
    static let busyFrom = 0.6
    /// The most a busy Mac quickens the walks and trots by.
    static let busyBoost = 0.25
    /// A user who has touched something this recently is at the Mac.
    static let wakeIdle: TimeInterval = 2
    /// A cat does not nap while the user is still at it.
    static let napMinimumIdle: TimeInterval = 10
    static let sleepChunk: TimeInterval = 20
    static let danceChunk: TimeInterval = 4
    static let purrDuration: TimeInterval = 2.6
    static let startleDuration: TimeInterval = 0.9
    static let lookChunk: TimeInterval = 1.5
    /// How far from the pointer's own place a pounce can land, in points.
    static let longestPounce = 70.0
    /// How near the end of the lane a cat goes when it goes to the end, as a share of it.
    static let edgeInset = 0.04
    /// The room between the cat and what it plays with, as a share of the lane.
    static let playGap = 0.085
    /// The most a moth leads the cat by, as a share of the lane.
    static let mothLead = 0.08
    static let shortestRun: TimeInterval = 1
    /// How far the ball rolls at a bat, as a share of the lane.
    static let rollLength = 0.12

    private(set) var plan: CatPlan
    /// The scene it is in, nil while it does something that is not one: a reaction, sleep, a dance, a run.
    private(set) var scene: CatScene?
    /// Rises with every scene begun, so a test sees one that repeats.
    private(set) var sceneSerial = 0
    private var lastScene: CatScene?
    private var queue: [Step] = []
    private var stance = CatMove.Stance.seated
    /// Where the ball of yarn lies, as a share of the lane, and which way the cat rolls it (1 to the right, -1 to the left): the way there is
    /// room for three bats.
    private var ball: Double?
    private var rolling = 1.0
    private var travel = 0.0
    /// How much the Mac's load bothers the cat, 0 to 1, as of the last update: 0 when the user has turned the reaction off.
    private var busyness = 0.0
    private var generator: SplitMix64
    private var pointerWasNear = false
    private var lastReaction = -TimeInterval.infinity

    init(seed: UInt64, now: TimeInterval, position: Double = 0.5, facing: Facing = .left) {
        generator = SplitMix64(seed: seed)
        plan = CatPlan(move: .sit, facing: facing, from: position, to: position, began: now, duration: 2)
    }

    /// Where the cat is at `now`.
    func position(at now: TimeInterval) -> Double { plan.position(at: now) }

    var isAsleep: Bool { plan.move == .sleep }

    /// A stroke: purring, with hearts.
    mutating func pet(now: TimeInterval) -> Outcome {
        let before = plan
        interrupt(with: [])
        plan = made(.purr, now: now, duration: Self.purrDuration)
        stance = .seated
        return outcome(since: before)
    }

    /// The cat is back on the notch after being out of sight: where it was, sitting, and the pointer it last saw is not news.
    mutating func resume(now: TimeInterval) {
        interrupt(with: [])
        stance = .seated
        plan = made(.sit, now: now, duration: 2)
        pointerWasNear = true
    }

    /// Advances the cat to `now`. `travel` is how far, in points, the cat can walk along the lane it is on.
    mutating func update(now: TimeInterval, senses: CatSenses, tuning: CatTuning, travel: Double) -> Outcome {
        let before = plan
        self.travel = travel
        busyness = tuning.reactsToBusyMachine ? min(max((senses.cpuLoad - Self.busyFrom) / (1 - Self.busyFrom), 0), 1) : 0
        pointer = senses.pointer
        let arrived = senses.pointerNear && !pointerWasNear
        pointerWasNear = senses.pointerNear
        let sticky = [CatMove.startled, .purr, .pounce].contains(plan.move) && now < plan.end

        if arrived, !sticky, now - lastReaction >= Self.reactionCooldown {
            lastReaction = now
            react(senses, now: now)
        } else if !sticky, interruption(senses, tuning: tuning, now: now) {
            // Done.
        } else if !sticky, looking(senses, now: now) {
            // Done.
        } else if now >= plan.end {
            advance(senses, tuning: tuning, now: now)
        }
        return outcome(since: before)
    }

    /// Whether the cat is to run: the Mac is in a burst and the user wants the cat to mind.
    private func bursting(_ senses: CatSenses, _ tuning: CatTuning) -> Bool {
        tuning.reactsToBusyMachine && senses.busyBurst
    }

    // MARK: Reacting

    /// The pointer came close: a sleeper is startled; one that is awake pounces, or sometimes jumps.
    private mutating func react(_ senses: CatSenses, now: TimeInterval) {
        if plan.move == .sleep || plan.move == .loaf || !chance(Self.pounceChance) {
            interrupt(with: [.startle])
        } else {
            interrupt(with: CatScene.pounceAtPointer.steps(using: &generator))
            scene = .pounceAtPointer
            lastScene = .pounceAtPointer
            sceneSerial += 1
        }
        startQueue(now: now, senses: senses)
    }

    /// Where the pointer is, as of the last update: for a pounce.
    private var pointer: PointerReading?

    /// What the cat drops what it is doing for. True when it did.
    private mutating func interruption(_ senses: CatSenses, tuning: CatTuning, now: TimeInterval) -> Bool {
        let running = plan.move == .frantic
        if bursting(senses, tuning) {
            guard !running else { return false }
            interrupt(with: [])
            plan = frantic(now: now, load: senses.cpuLoad)
            stance = .standing
            return true
        }
        if running {
            interrupt(with: [.stay(.sit, 1...1)])
            startQueue(now: now, senses: senses)
            return true
        }
        if senses.audioPlaying {
            guard plan.move != .dance else { return false }
            interrupt(with: [.stay(.dance, Self.danceChunk...Self.danceChunk)])
            startQueue(now: now, senses: senses)
            return true
        }
        if plan.move == .dance {
            interrupt(with: [.stay(.sit, 1.5...2.5)])
            startQueue(now: now, senses: senses)
            return true
        }
        if plan.move == .sleep, senses.idleSeconds < Self.wakeIdle {
            interrupt(with: [.once(.yawn)])
            startQueue(now: now, senses: senses)
            return true
        }
        return false
    }

    /// A cat that is sitting and has the pointer in sight looks at it, and goes on with what it was doing when it is gone.
    private mutating func looking(_ senses: CatSenses, now: TimeInterval) -> Bool {
        let lookable: [CatMove] = [.sit, .blink, .tailSwish, .lookLeft, .lookRight, .lookUp]
        guard lookable.contains(plan.move), stance == .seated else { return false }
        let isLooking = [CatMove.lookLeft, .lookRight, .lookUp].contains(plan.move)
        guard let pointer = senses.pointer, pointer.isInRange else {
            // It has gone: back to what the scene was.
            guard isLooking else { return false }
            plan = made(.sit, now: now, duration: Double.random(in: 0.8...1.5, using: &generator))
            return true
        }
        let wanted = lookMove(for: pointer, at: plan.position(at: now))
        guard wanted != plan.move else { return false }
        plan = made(wanted, now: now, duration: Self.lookChunk)
        return true
    }

    /// Which way the head goes: up for a pointer over it, else to the side it is on.
    private func lookMove(for pointer: PointerReading, at position: Double) -> CatMove {
        let apart = (pointer.share - position) * travel
        if abs(apart) < 24, pointer.isAbove { return .lookUp }
        return apart < 0 ? .lookLeft : .lookRight
    }

    // MARK: Moving on

    /// The plan is over: the next step, or the next scene, or sleep, or what the cat is made to do.
    private mutating func advance(_ senses: CatSenses, tuning: CatTuning, now: TimeInterval) {
        if bursting(senses, tuning) {
            plan = frantic(now: now, load: senses.cpuLoad)
            stance = .standing
            return
        }
        if senses.audioPlaying {
            plan = made(.dance, now: now, duration: Self.danceChunk)
            stance = .seated
            return
        }
        if senses.idleSeconds >= tuning.sleepThreshold(hour: senses.hour) {
            // Down for the night in steps: a yawn, then sleep.
            let asleep = Step.stay(.sleep, Self.sleepChunk...Self.sleepChunk)
            if plan.move == .sleep {
                plan = made(.sleep, now: now, duration: Self.sleepChunk)
            } else if queue.contains(asleep) {
                startQueue(now: now, senses: senses)
            } else {
                interrupt(with: [.once(.yawn), asleep])
                startQueue(now: now, senses: senses)
            }
            return
        }
        startQueue(now: now, senses: senses)
    }

    /// Begins the next step of the scene, which is the first of a new scene when there is none left.
    private mutating func startQueue(now: TimeInterval, senses: CatSenses) {
        for _ in 0..<12 {
            if queue.isEmpty { beginScene(senses) }
            guard !queue.isEmpty else { break }
            let step = queue.removeFirst()
            if let planned = begin(step, now: now, senses: senses) {
                plan = planned
                return
            }
        }
        // Nothing to do: sits.
        plan = made(.sit, now: now, duration: 2)
    }

    private mutating func beginScene(_ senses: CatSenses) {
        let night = CatTuning.isNight(hour: senses.hour)
        let busy = busyness > 0
        var choices = CatScene.allCases.filter { $0 != lastScene && $0.weight(night: night, busy: busy) > 0 }
        if senses.idleSeconds < Self.napMinimumIdle { choices.removeAll { $0 == .nap } }
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
        ball = nil
        queue = picked.steps(using: &generator)
    }

    /// Drops what is going on and takes up `steps`, clearing the scene and what it played with.
    private mutating func interrupt(with steps: [Step]) {
        queue = steps
        ball = nil
        scene = nil
    }

    // MARK: Plans

    /// A plan for `step`, from where the cat is at `now`; nil for a step that takes no time or has nothing to do. The cat gets up or sits
    /// down first when the step needs it, and the step waits its turn.
    private mutating func begin(_ step: Step, now: TimeInterval, senses: CatSenses) -> CatPlan? {
        if let needed = step.stance, needed != stance {
            let cut = step == .startle || step == .pounce
            if !cut, let hop = hop(to: needed) {
                queue.insert(step, at: 0)
                stance = hop.ends
                return withBall(made(hop.move, now: now, duration: hop.move.passDuration))
            }
            stance = needed
        }
        let planned: CatPlan?
        switch step {
        case .stay(let move, let seconds):
            planned = made(move, now: now, duration: Double.random(in: seconds, using: &generator))
        case .once(let move):
            planned = made(move, now: now, duration: move.passDuration)
        case .go(let move, let place):
            planned = go(move, to: place, now: now)
        case .chaseMoth:
            planned = chaseMoth(now: now)
        case .placeBall:
            placeBall(now: now)
            planned = nil
        case .batBall:
            planned = batBall(now: now)
        case .pounce:
            planned = pounce(now: now)
        case .startle:
            planned = made(.startled, now: now, duration: Self.startleDuration)
        }
        return planned.map(withBall)
    }

    /// The move that takes the cat one step nearer a stance, and the one it ends in; nil when it needs none (it just is).
    private func hop(to needed: CatMove.Stance) -> (move: CatMove, ends: CatMove.Stance)? {
        switch (stance, needed) {
        case (.standing, .seated), (.standing, .lying): (.sitDown, .seated)
        case (.seated, .standing), (.lying, .standing): (.standUp, .standing)
        case (.seated, .lying): (.lieDown, .lying)
        default: nil
        }
    }

    /// The cat doing `move` where it is.
    private func made(_ move: CatMove, now: TimeInterval, duration: TimeInterval) -> CatPlan {
        let here = plan.position(at: now)
        return CatPlan(move: move, facing: plan.facing, from: here, to: here, began: now, duration: duration)
    }

    private func withBall(_ planned: CatPlan) -> CatPlan {
        guard planned.prop == nil, let ball else { return planned }
        var result = planned
        result.prop = CatProp(kind: .yarn, from: ball, to: ball)
        return result
    }

    private func facing(from here: Double, to target: Double) -> Facing {
        target == here ? plan.facing : (target > here ? .right : .left)
    }

    private mutating func go(_ move: CatMove, to place: Place, now: TimeInterval) -> CatPlan? {
        let here = plan.position(at: now)
        guard travel >= 1 else { return nil }
        let target: Double
        switch place {
        case .away(let points):
            var right = here <= 0.08 ? true : here >= 0.92 ? false : chance(0.5)
            let distance = Double.random(in: points, using: &generator)
            func aim() -> Double { right ? min(here + distance / travel, 1) : max(here - distance / travel, 0) }
            var aimed = aim()
            if abs(aimed - here) * travel < 10 {
                right.toggle()
                aimed = aim()
            }
            target = aimed
        case .nearEdge: target = here < 0.5 ? Self.edgeInset : 1 - Self.edgeInset
        case .farEdge: target = here < 0.5 ? 1 - Self.edgeInset : Self.edgeInset
        case .centre: target = 0.5
        case .besideBall:
            guard let ball else { return nil }
            target = min(max(ball - rolling * Self.playGap, 0), 1)
        }
        let covered = abs(target - here) * travel
        guard covered >= 1 else { return nil }
        // A busy Mac quickens a walk a little: the frames and the pace together.
        let quickening = 1 + Self.busyBoost * busyness
        return CatPlan(
            move: move, facing: facing(from: here, to: target), from: here, to: target, began: now,
            duration: covered / (move.speed * quickening), fpsScale: quickening
        )
    }

    /// The cat runs the length of the strip after a moth that is always a little ahead and, at the end, gets away.
    private func chaseMoth(now: TimeInterval) -> CatPlan? {
        guard travel >= 1 else { return nil }
        let here = plan.position(at: now)
        let right = here < 0.5
        let catEnd = right ? 1 - Self.edgeInset : Self.edgeInset
        let covered = max(abs(catEnd - here) * travel, 1)
        let lead = right ? Self.mothLead : -Self.mothLead
        var chasing = CatPlan(
            move: .chase, facing: right ? .right : .left, from: here, to: catEnd, began: now, duration: max(covered / CatMove.chase.speed, 1.5)
        )
        chasing.prop = CatProp(kind: .moth, from: here + lead, to: right ? 1.2 : -0.2)
        return chasing
    }

    /// The ball goes down a little way off, on the side of the cat that has more room, and room for three bats of `rollLength` each.
    private mutating func placeBall(now: TimeInterval) {
        let here = plan.position(at: now)
        rolling = here < 0.5 ? 1 : -1
        let distance = Double.random(in: 0.18...0.3, using: &generator)
        let room = 3 * Self.rollLength + 0.06
        ball = rolling > 0 ? min(max(here + distance, 0.15), 1 - room) : min(max(here - distance, room), 0.85)
    }

    /// A bat at the ball, and it rolls on a way.
    private mutating func batBall(now: TimeInterval) -> CatPlan? {
        guard let resting = ball else { return nil }
        let rolled = min(max(resting + rolling * Self.rollLength, 0.06), 0.94)
        ball = rolled
        var batting = made(.yarn, now: now, duration: 1.6)
        batting.facing = rolling > 0 ? .right : .left
        batting.prop = CatProp(kind: .yarn, from: resting, to: rolled)
        return batting
    }

    /// A pounce towards where the pointer was, as far as the lane and a cat's leap allow, from a crouch that takes most of the time.
    private mutating func pounce(now: TimeInterval) -> CatPlan {
        let here = plan.position(at: now)
        var target = here
        if let pointer, travel >= 1 {
            let leap = min(max((pointer.share - here) * travel, -Self.longestPounce), Self.longestPounce) / travel
            target = min(max(here + leap, 0), 1)
        }
        var pouncing = made(.pounce, now: now, duration: CatMove.pounce.passDuration)
        pouncing.to = target
        pouncing.facing = facing(from: here, to: target)
        pouncing.delay = 5.0 / Double(CatMove.pounce.frameCount)
        return pouncing
    }

    /// Running for its life, from one end of the lane to the other and back, harder the busier the processors are.
    private func frantic(now: TimeInterval, load: Double) -> CatPlan {
        let here = plan.position(at: now)
        let strength = min(max((load - BusyWatch.floor) / (1 - BusyWatch.floor), 0), 1)
        let scale = 1 + Self.runFrameBoost * strength
        let target = here < 0.5 ? 1.0 : 0.0
        let covered = abs(target - here) * max(travel, 0)
        let moves = covered >= 1
        return CatPlan(
            move: .frantic, facing: moves ? (target > here ? .right : .left) : plan.facing, from: here, to: moves ? target : here,
            began: now, duration: max(covered / (CatMove.frantic.speed * scale), Self.shortestRun), fpsScale: scale
        )
    }

    private mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &generator) < probability
    }

    private func outcome(since before: CatPlan) -> Outcome {
        if plan == before { return .unchanged }
        return plan.looksLike(before) ? .extended : .changed
    }
}
