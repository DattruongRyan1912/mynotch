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
    typealias Outcome = BrainOutcome

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
    /// What the lane it shares asks of it: the crossing it goes through and never stops in, the places others stand, the stretch it may not
    /// go into (see `LaneKeeper`).
    private var keeper = LaneKeeper()
    /// How much the Mac's load bothers the cat, 0 to 1, as of the last update: 0 when the user has turned the reaction off.
    private var busyness = 0.0
    private var generator: SplitMix64
    private var pointerWasNear = false
    private var lastReaction = -TimeInterval.infinity
    /// The joint scene it is playing the guest in, if it is (see `CatJoint`).
    private var joint: CatJoint?
    /// What it last sensed, for what it does when a joint scene ends between two updates.
    private var lastSenses = CatSenses()

    init(seed: UInt64, now: TimeInterval, position: Double = 0.5, facing: Facing = .left) {
        generator = SplitMix64(seed: seed)
        plan = CatPlan(move: .sit, facing: facing, from: position, to: position, began: now, duration: 2)
    }

    /// Where the cat is at `now`.
    func position(at now: TimeInterval) -> Double { plan.position(at: now) }

    var isAsleep: Bool { plan.move == .sleep }

    /// A stroke: purring, with hearts.
    mutating func pet(now: TimeInterval) -> Outcome {
        // A cat that is going through a portal is not to be stopped in it, and one that is on the capybara comes off it first.
        guard !isCrossing(at: now), joint == nil else { return .unchanged }
        let before = plan
        interrupt(with: [])
        plan = made(.purr, now: now, duration: Self.purrDuration)
        stance = .seated
        return outcome(since: before)
    }

    /// The cat is back on the notch after being out of sight: where it was, sitting, and the pointer it last saw is not news.
    mutating func resume(now: TimeInterval) {
        joint = nil
        interrupt(with: [])
        stance = .seated
        plan = made(.sit, now: now, duration: 2)
        pointerWasNear = true
    }

    /// Advances the cat to `now`. `travel` is how far, in points, the cat can walk along the lane it is on.
    mutating func update(
        now: TimeInterval, senses: CatSenses, tuning: CatTuning, travel: Double, gaps: [ClosedRange<Double>] = []
    ) -> Outcome {
        update(now: now, senses: senses, tuning: tuning, travel: travel, lane: LaneContext(crossing: gaps))
    }

    /// The same, in a lane that other characters share (see `LaneContext`).
    mutating func update(now: TimeInterval, senses: CatSenses, tuning: CatTuning, travel: Double, lane: LaneContext) -> Outcome {
        let before = plan
        self.travel = travel
        lastSenses = senses
        settle(lane: lane)
        if joint != nil { return updateJoint(now: now, lane: lane, before: before) }
        busyness = tuning.reactsToBusyMachine ? min(max((senses.cpuLoad - Self.busyFrom) / (1 - Self.busyFrom), 0), 1) : 0
        pointer = senses.pointer
        let arrived = senses.pointerNear && !pointerWasNear
        pointerWasNear = senses.pointerNear
        // A petting, a jump and a pounce are finished first, and so is a walk through a portal.
        let sticky = [CatMove.startled, .purr, .pounce].contains(plan.move) && now < plan.end || isCrossing(at: now)

        if arrived, !sticky, now - lastReaction >= tuning.reactionCooldown {
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

    /// Takes the stretches of the lane the cat must not stop in. A cat that stands in one when they are taken (the views it plays in have
    /// changed under it) is put at the nearer end of it, which is a jump, and made only then.
    mutating func settle(gaps: [ClosedRange<Double>]) {
        settle(lane: LaneContext(crossing: gaps))
    }

    /// The same, for a lane that other characters share: where they stand is a place it does not stop in either, and it may be told not to
    /// go into a stretch at all.
    mutating func settle(lane: LaneContext) {
        keeper = LaneKeeper(lane)
        // A cat on the capybara's back, or going to it, is where the scene puts it.
        guard joint == nil, plan.from == plan.to, !(lane.crossing.isEmpty && lane.zones.isEmpty) else { return }
        let here = keeper.settled(plan.to)
        guard here != plan.to else { return }
        plan.from = here
        plan.to = here
    }

    /// Whether the cat is in the middle of a walk through a stretch it must not stop in.
    private func isCrossing(at now: TimeInterval) -> Bool {
        guard plan.from != plan.to else { return false }
        return keeper.isInCrossing(plan.position(at: now))
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
        let here = keeper.settled(plan.position(at: now))
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
        var target: Double
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
        target = keeper.destination(target, from: here)
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
        let catEnd = keeper.endOfLane(right ? 1 - Self.edgeInset : Self.edgeInset, from: here)
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
        ball = keeper.destination(rolling > 0 ? min(max(here + distance, 0.15), 1 - room) : min(max(here - distance, room), 0.85), from: here)
    }

    /// A bat at the ball, and it rolls on a way.
    private mutating func batBall(now: TimeInterval) -> CatPlan? {
        guard let resting = ball else { return nil }
        let rolled = keeper.settled(min(max(resting + rolling * Self.rollLength, 0.06), 0.94))
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
            target = keeper.destination(min(max(here + leap, 0), 1), from: here)
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
        let target = keeper.endOfLane(here < 0.5 ? 1.0 : 0.0, from: here)
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

// MARK: Sitting on the capybara

/// The cat's part in a joint scene as the guest: it walks to the host's rump side, hops onto its back, sits or loafs there for a while,
/// hops off and walks a little way off, and nothing it senses (the pointer, the Mac's load, sound, being away) takes it off before that.
/// Where it goes is worked out from the host's pose, which the stage hands it at every update, and a host that is not where it was, or is
/// gone, ends the scene.
nonisolated struct CatJoint: Sendable {
    enum Phase: Equatable, Sendable {
        /// Walking to where it hops from.
        case approach
        case hopOn
        /// On its back, sitting or lying like a loaf.
        case perched(loaf: Bool)
        /// Off again, and walking out of the capybara's way: these two need nobody, and the end of the second is the end of the scene for
        /// the cat.
        case hopOff
        case walkOff
    }

    var scene: JointScene.ID
    var phase: Phase
    /// Where it hops from, where it sits, and where it walks to when it is off again (shares of the lane, its left foot), and which way
    /// it hops on (1 right, -1 left).
    var launch: Double
    var seat: Double
    var exit: Double
    var direction: Double
    /// Where the host was when the scene began: it holds still, so a host that is not there is a reason to come down.
    var host: Double
    /// Whether it lies down for part of the time on the back.
    var loafs: Bool
}

nonisolated extension CatMove {
    /// How far from the capybara, in pixels, the cat is out of its way: a picture and a little air, which is the room that two characters
    /// that are not playing together leave each other (`CatField.separation`), and a pixel more.
    static let clearance = Double(CatField.pictureSize.width + CatField.apart) + 1
}

nonisolated extension CatBrain {
    /// The moves it is in a state to leave for a joint scene: it is awake and doing nothing it cannot be taken from.
    private static let calm: Set<CatMove> = [.sit, .blink, .tailSwish, .groom, .scratch, .lookLeft, .lookRight, .lookUp, .yawn, .walk, .trot, .stretch, .loaf]

    var jointScene: JointScene.ID? { joint?.scene }

    /// Where it goes when it is done with the capybara, while it is in a scene.
    var jointExit: Double? { joint?.exit }

    /// Where it would hop from, sit and walk to on `partner`, which has a back to give: nil when there is no room (the lane, the camera,
    /// the way). It comes from the capybara's rump, which is behind the way it faces, and hops forward onto it; when it has hopped off
    /// it walks out of the capybara's way, which it must have the room for, or it would be moved out of it with a jump when the scene is
    /// over.
    private func seating(
        on partner: Pose, now: TimeInterval, keeper: LaneKeeper
    ) -> (launch: Double, seat: Double, exit: Double, direction: Double, host: Double)? {
        guard travel >= 40, let perch = partner.perch, perch.spot == .back else { return nil }
        let host = partner.position(at: now)
        let seat = host + perch.dx / travel
        let direction = partner.facing == .right ? 1.0 : -1.0
        let launch = seat - direction * CatMove.hopSpan / travel
        // It walks out to where it is out of the room of all that the capybara has, which is more than its own when it has its tub out: the
        // place it hops into the tub from is behind it, where the cat comes from.
        let places = JointRoom(host: partner, now: now, travel: travel, keeper: keeper).places
        let clear = CatMove.clearance / travel
        let exit = direction > 0 ? (places.min() ?? host) - clear : (places.max() ?? host) + clear
        let here = plan.position(at: now)
        guard (0.0...1.0).contains(seat), (0.0...1.0).contains(launch), (0.0...1.0).contains(exit),
              keeper.destination(launch, from: here) == launch, keeper.settled(seat) == seat, keeper.settled(exit) == exit,
              keeper.reach(from: launch).contains(exit) else { return nil }
        let (low, high) = (min(exit, seat), max(exit, seat))
        if keeper.lane.crossing.contains(where: { high > $0.lowerBound && low < $0.upperBound }) { return nil }
        return (launch, seat, exit, direction, host)
    }

    func canJoin(_ invite: JointInvite, now: TimeInterval) -> Bool {
        guard invite.role == .guest, invite.scene == .catOnCapybara, joint == nil, busyness == 0, Self.calm.contains(plan.move),
              !isCrossing(at: now) else { return false }
        // The room is judged as it will be once the scene has begun, with the host's own place no longer in the way.
        return seating(on: invite.partner, now: now, keeper: LaneKeeper(invite.lane)) != nil
    }

    mutating func join(_ invite: JointInvite, now: TimeInterval) {
        let lane = LaneKeeper(invite.lane)
        guard let place = seating(on: invite.partner, now: now, keeper: lane) else { return }
        keeper = lane
        interrupt(with: [])
        stance = .standing
        joint = CatJoint(
            scene: invite.scene, phase: .approach, launch: place.launch, seat: place.seat, exit: place.exit, direction: place.direction,
            host: place.host, loafs: chance(0.6)
        )
        plan = approach(now: now)
        if plan.duration == 0 { advanceJoint(now: now) }
    }

    /// The cat is done with the scene, wherever it is in it: one that is on the capybara hops off, one that is going to it goes the way it
    /// is going and then about its day (out of the capybara's way, if it is in it), and one that is hopping off finishes the hop.
    mutating func leaveJoint(now: TimeInterval) -> Outcome {
        guard let current = joint else { return .unchanged }
        let before = plan
        switch current.phase {
        case .approach:
            let here = plan.position(at: now)
            if abs(here - current.host) * travel < CatMove.clearance { walkOff(now: now) } else { finishJoint(now: now) }
        case .hopOn, .perched:
            hopOff(now: now)
        case .hopOff, .walkOff:
            break
        }
        return outcome(since: before)
    }

    /// An update of a cat that is in a scene: nothing it senses matters, only the host and the time.
    fileprivate mutating func updateJoint(now: TimeInterval, lane: LaneContext, before: CatPlan) -> Outcome {
        guard let current = joint else { return .unchanged }
        if current.phase != .hopOff, current.phase != .walkOff {
            // The host is where it was and still gives its back to ride on; if not, down it comes.
            let hostHolds = lane.joint.map { sight in
                sight.scene == current.scene && sight.role == .guest && sight.partner.perch?.spot == .back
                    && abs(sight.partner.position(at: now) - current.host) < 1e-9
            } ?? false
            if !hostHolds {
                _ = leaveJoint(now: now)
                return outcome(since: before)
            }
        }
        if now >= plan.end { advanceJoint(now: now) }
        return outcome(since: before)
    }

    /// The walk to where it hops from; no time at all when it is there.
    private func approach(now: TimeInterval) -> CatPlan {
        guard let current = joint else { return plan }
        let here = plan.position(at: now)
        let covered = abs(current.launch - here) * travel
        guard covered >= 1 else { return CatPlan(move: .sit, facing: current.direction > 0 ? .right : .left, from: here, to: here, began: now, duration: 0) }
        return CatPlan(
            move: .walk, facing: current.launch > here ? .right : .left, from: here, to: current.launch, began: now, duration: covered / CatMove.walk.speed
        )
    }

    /// The next part of the scene, as the one before it is over.
    private mutating func advanceJoint(now: TimeInterval) {
        guard var current = joint else { return }
        let facing: Facing = current.direction > 0 ? .right : .left
        switch current.phase {
        case .approach:
            current.phase = .hopOn
            joint = current
            plan = CatPlan(
                move: .hopOn, facing: facing, from: current.launch, to: current.seat, began: now, duration: CatMove.hopOn.passDuration
            )
        case .hopOn:
            let loaf = current.loafs && chance(0.5)
            current.phase = .perched(loaf: loaf)
            joint = current
            plan = CatPlan(
                move: loaf ? .perchLoaf : .perch, facing: facing, from: current.seat, to: current.seat, began: now,
                duration: Double.random(in: 6...11, using: &generator)
            )
        case .perched(let loaf):
            if current.loafs, !loaf {
                current.phase = .perched(loaf: true)
                joint = current
                plan = CatPlan(
                    move: .perchLoaf, facing: facing, from: current.seat, to: current.seat, began: now, duration: Double.random(in: 7...13, using: &generator)
                )
            } else if exitIsFree(now: now) {
                hopOff(now: now)
            } else {
                // Nowhere to go once it is down (another has come to stand there, or is on its way through the camera): it stays where it
                // is a little longer, which the director puts an end to if it goes on.
                plan = CatPlan(move: plan.move, facing: facing, from: current.seat, to: current.seat, began: now, duration: 2)
            }
        case .hopOff:
            walkOff(now: now)
        case .walkOff:
            finishJoint(now: now)
        }
    }

    /// Off the back to where it hopped from, facing the way it goes.
    private mutating func hopOff(now: TimeInterval) {
        guard var current = joint else { return }
        let here = plan.position(at: now)
        current.phase = .hopOff
        joint = current
        plan = CatPlan(
            move: .hopOff, facing: current.launch >= here ? .right : .left, from: here, to: current.launch, began: now, duration: CatMove.hopOff.passDuration
        )
    }

    /// Whether there is a place to walk to when it is off the capybara's back, out of the way of everyone, the capybara too.
    private func exitIsFree(now: TimeInterval) -> Bool {
        guard let current = joint else { return true }
        let room = CatMove.clearance / travel
        var lane = keeper.lane
        lane.zones.append((current.host - room)...(current.host + room))
        let keeper = LaneKeeper(lane)
        let target = keeper.destination(current.exit, from: current.launch)
        return keeper.settled(target) == target && abs(target - current.host) * travel >= CatMove.clearance - 1e-6
    }

    /// A few steps to where it is out of the capybara's way; the end of the scene when it already is.
    private mutating func walkOff(now: TimeInterval) {
        guard var current = joint else { return }
        let here = plan.position(at: now)
        // To where it is out of the way of everyone, the capybara too, whose room the scene did not ask of it: the way out may be past
        // the other side of it, or short of where the cat first meant, if another stands there now.
        var lane = keeper.lane
        let room = CatMove.clearance / travel
        lane.zones.append((current.host - room)...(current.host + room))
        let target = LaneKeeper(lane).destination(current.exit, from: here)
        let covered = abs(target - here) * travel
        guard covered >= 1 else {
            finishJoint(now: now)
            return
        }
        current.phase = .walkOff
        joint = current
        plan = CatPlan(
            move: .walk, facing: target > here ? .right : .left, from: here, to: target, began: now, duration: covered / CatMove.walk.speed
        )
    }

    /// The scene is over and the day goes on, from where the cat stands.
    private mutating func finishJoint(now: TimeInterval) {
        joint = nil
        stance = .standing
        interrupt(with: [])
        startQueue(now: now, senses: lastSenses)
    }
}
