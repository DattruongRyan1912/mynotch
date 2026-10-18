import Foundation

/// What the frog decides to do. A value that holds no timer and reads nothing, like the others': it is told the time and what the frog
/// senses, and says whether the picture changed, so every rule of its day is a test with a made-up clock.
///
/// It is lazy, and likes to lie in wait. What it does with its time is a handful of scenes (`FrogScene`) picked at random by weights that
/// depend on the time of day, never the same one twice running: sitting, puffing its throat, hopping about, sitting on a lily pad that comes
/// up out of the water beside it, dozing on the pad, and, its signature, catching a moth with its tongue. On top of that:
/// - **the Mac is busy: it hops more often.** A frog that hops more is not a frog that hops faster: every hop is the same hop at any load,
///   there are only more of them, with less rest between. A burst of work (`busyBurst`) sends it hopping at once, once for each burst. With
///   the setting off nothing of the load is read at all;
/// - the pointer comes near: it turns to it, sits up with its eyes on it like a fly, and now and then flicks its tongue out towards it, and
///   goes on when the pointer has gone. It watches for no more than `watchLimit` seconds, and not again until the pointer has gone away;
/// - a stroke makes it hop in place for joy, and then it goes on with what it was doing;
/// - the user has been away for the sleep time: it finishes the step it is in, goes to the lily pad (which comes up for it, if there is
///   room) and sleeps there with its eyes shut, and when the user is back it wakes, hops off and the pad goes down.
///
/// It has what it plays with only while the scene it is in calls for it: the pad from the moment it comes up to the moment it has gone, the
/// moth from the moment it flies in to the moment the tongue has it. Whatever interrupts a scene ends it first (`wrapUp`), and the props are
/// a state of this brain, so a pad never stays behind. A leg of hops can go through the camera (it is one walk, as the cat's is), but the
/// pad, the hop on to it and the moth's way in are never in the camera or across it.
nonisolated struct FrogBrain: Sendable {
    typealias Outcome = BrainOutcome

    /// A user who has touched something this recently is at the Mac.
    static let wakeIdle: TimeInterval = 2
    static let sleepChunk: TimeInterval = 24
    /// How near the end of the lane it goes when it goes to the end, as a share of it.
    static let edgeInset = 0.04
    /// How long it watches the pointer, at the most, and how long after the pointer has gone it goes on watching.
    static let watchLimit: TimeInterval = 15
    static let releaseDelay: TimeInterval = 0.9
    /// How long it is between one flick of the tongue at the pointer and the next.
    static let flickGap: ClosedRange<Double> = 1.5...4
    /// The load from which the Mac is busy enough for more hopping (as the cat's), and how busy a burst of work is, whatever the load.
    static let busyFrom = CatBrain.busyFrom
    static let burstBusyness = 0.8
    /// How fast a moth flies in, in points a second, and how far outside the ends of the lane (in points) it starts and goes to.
    static let mothSpeed = 50.0
    static let mothOutside = (left: 20.0, right: 40.0)
    /// What it drops everything for is held to these moves: a stroke, the pointer or a burst of work is not taken while it hops on to the pad
    /// or off it, jumps for joy, shoots its tongue at a moth, takes it in or swallows it.
    static let unbroken: Set<FrogMove> = [.hopOn, .hopOff, .jump, .padJump, .snapOut, .snapIn, .gulp]
    /// What the pointer and a burst of work wait for, as a stroke does not: a blink, a puff, a flick of the tongue, and a leg of hops, which
    /// is not broken off in the air.
    static let holds: Set<FrogMove> = [.blink, .padBlink, .puff, .padPuff, .flick, .padFlick]

    /// The lily pad: where it floats (a share of the lane: where the frog is when it is on it), where the frog hops from and back to, and how
    /// far it has come.
    private struct Pad {
        enum Phase { case appearing, waiting, occupied, leaving }
        var place: Double
        var home: Double
        var phase: Phase
    }

    /// The moth: where it flies in from, where it hovers (the tip of the tongue), and how far it has come.
    private struct Moth {
        enum Phase { case coming, hovering, held, leaving }
        var place: Double
        var entry: Double
        /// Where it was when a stroke sent it off, which is where it flies away from.
        var from = 0.0
        var phase: Phase
    }

    private(set) var plan: Pose
    /// The scene it is in, nil while it does something that is not one: sleep, watching the pointer.
    private(set) var scene: FrogScene?
    /// Rises with every scene begun, so a test sees one that repeats.
    private(set) var sceneSerial = 0
    /// How often a prop was found left over when a scene began and had to be cleared: never, which a test checks.
    private(set) var strayProps = 0
    private var lastScene: FrogScene?
    private var queue: [FrogStep] = []
    private(set) var stance = FrogMove.Stance.ground
    private var pad: Pad?
    private var moth: Moth?
    /// Where the next step puts the pad and the way it faces to, worked out when it hops there; and the side the moth comes from.
    private var padStart: (start: Double, direction: Double)?
    private var mothWay: Double?
    private var travel = 0.0
    private var keeper = LaneKeeper()
    private(set) var busyness = 0.0
    private var senses = CatSenses()
    private var generator: SplitMix64
    /// What it was in the middle of when it turned to the pointer, to go on with: a sit.
    private var resumeStep: FrogStep?
    private var watching = false
    private var lookWay = 1.0
    private var watchSince: TimeInterval = 0
    private var lastNear: TimeInterval = 0
    private var nextFlick: TimeInterval = 0
    /// It has watched as long as it will, and does not watch again until the pointer has gone away.
    private var tired = false
    private var lastWatchEnd = -TimeInterval.infinity
    /// The burst of work it has heard of: it goes off for each once.
    private var burstHeard = false
    /// It is on its way to sleep, which takes a few steps: to the pad, up, on it.
    private var sleeping = false

    init(seed: UInt64, now: TimeInterval, position: Double = 0.5, facing: Facing = .left) {
        generator = SplitMix64(seed: seed)
        plan = Pose(motion: FrogMove.sit.motion, facing: facing, from: position, to: position, began: now, duration: 2)
    }

    var move: FrogMove { FrogMove(plan.motion) }

    var isAsleep: Bool { move == .sleep || move == .padSleep }

    /// Whether it has a pad or a moth out now.
    var hasProps: Bool { pad != nil || moth != nil }

    /// Whether it is watching the pointer.
    var isWatching: Bool { watching }

    /// Where the frog is at `now`.
    func position(at now: TimeInterval) -> Double { plan.position(at: now) }

    // MARK: From outside

    /// A stroke: a hop in place for joy, and then it goes on with what it was doing.
    mutating func pet(now: TimeInterval) -> Outcome {
        guard !isCrossing(at: now), !Self.unbroken.contains(move) else { return .unchanged }
        let before = plan
        var steps: [FrogStep] = [.stay(stance == .pad ? .padJump : .jump, FrogMove.jump.passDuration...FrogMove.jump.passDuration)]
        if watching {
            // A stroke ends the watching, and what it was doing before it goes on.
            watching = false
            lastWatchEnd = now
            queue.removeAll { $0 == .look }
            if let resumeStep { steps.append(resumeStep) }
            resumeStep = nil
        } else if var flying = moth {
            // The moth is frightened off, from where it is: the rest of the hunt is not gone on with.
            flying.from = mothPlace(at: now) ?? flying.place
            flying.phase = .leaving
            moth = flying
            queue = []
            scene = nil
        } else if isAsleep || sleeping {
            // Awake, it has had enough of sleeping: it hops off the pad if it is on one, and the scene it was in is not gone back to.
            sleeping = false
            queue = wrapUp()
            scene = nil
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
        stance = .ground
        resumeStep = nil
        watching = false
        sleeping = false
        burstHeard = false
        tired = false
        lastWatchEnd = -.infinity
        plan = made(.sit, now: now, duration: 2)
    }

    /// Advances the frog to `now`. `travel` is how far, in points of its picture's pixels, it can walk along the lane.
    mutating func update(now: TimeInterval, senses: CatSenses, tuning: CatTuning, travel: Double, lane: LaneContext) -> Outcome {
        let before = plan
        self.travel = travel
        self.senses = senses
        settle(lane: lane)
        // With the reaction off a busy Mac and a quiet one are the same to it: nothing of the load is read.
        let burst = tuning.reactsToBusyMachine && senses.busyBurst
        busyness = tuning.reactsToBusyMachine ? min(max((senses.cpuLoad - Self.busyFrom) / (1 - Self.busyFrom), 0), 1) : 0
        if burst { busyness = max(busyness, Self.burstBusyness) }
        if !burst { burstHeard = false }
        // What it does not drop: a move that is not to be broken, a leg of hops in the air, the camera, the moth.
        let sticky = isSticky(now: now)
        if !sticky, interruption(senses, burst: burst, now: now) {
            // Done.
        } else if !sticky, pointerWatching(senses, tuning: tuning, now: now) {
            // Done.
        } else if now >= plan.end {
            advance(senses, tuning: tuning, now: now)
        }
        return outcome(since: before)
    }

    /// Takes the stretches of the lane it must not stop in. One that stands in one when they are taken is put at the nearer end of it, which
    /// is a jump, and then it has nothing it was playing with: a pad would be left across the camera.
    mutating func settle(lane: LaneContext) {
        keeper = LaneKeeper(lane)
        guard plan.from == plan.to, !(lane.crossing.isEmpty && lane.zones.isEmpty) else { return }
        let here = keeper.settled(plan.to)
        guard here != plan.to else { return }
        // (A prop that is going is on the pose and no longer on the brain: it goes with the rest.)
        if hasProps || plan.prop != nil || stance != .ground || isAsleep {
            clearProps()
            queue = []
            scene = nil
            resumeStep = nil
            watching = false
            sleeping = false
            stance = .ground
            plan = Pose(motion: FrogMove.sit.motion, facing: plan.facing, from: here, to: here, began: plan.began, duration: 0)
            return
        }
        plan.from = here
        plan.to = here
    }

    // MARK: Reacting

    private func isSticky(now: TimeInterval) -> Bool {
        if now < plan.end {
            if Self.unbroken.contains(move) || Self.holds.contains(move) { return true }
            if move == .hop, plan.from != plan.to { return true }
        }
        return moth != nil || isCrossing(at: now)
    }

    /// What it drops what it is doing for. True when it did: waking, and a burst of work.
    private mutating func interruption(_ senses: CatSenses, burst: Bool, now: TimeInterval) -> Bool {
        if (isAsleep || sleeping) && senses.idleSeconds < Self.wakeIdle {
            wake(now: now)
            return true
        }
        // A burst of work, which it hears of once: off it hops, at once. Not from sleep, not while it watches the pointer (which has a way out
        // of its own) and not in the middle of the hops it is in.
        guard burst, !burstHeard, !isAsleep, !sleeping, !watching, moth == nil else { return false }
        burstHeard = true
        guard scene != .hopAbout, travel >= 1 else { return false }
        queue = wrapUp() + FrogScene.hopAbout.steps(using: &generator, busyness: busyness)
        scene = .hopAbout
        lastScene = .hopAbout
        sceneSerial += 1
        resumeStep = nil
        startQueue(now: now)
        return true
    }

    /// The user is back: it wakes with its eyes open, hops off the pad if it is on one and the pad goes down; one that was only on its way to
    /// sleep does not go on to.
    private mutating func wake(now: TimeInterval) {
        let wasAsleep = isAsleep
        sleeping = false
        queue = (wasAsleep ? [.stay(stance == .pad ? .padSit : .sit, 1.5...2.5)] : []) + wrapUp()
        scene = nil
        startQueue(now: now)
    }

    /// A frog that has the pointer near turns to it, sits up with its eyes on it, and now and then flicks its tongue out towards it, and
    /// goes on when the pointer has gone, a moment later, and does not watch for ever. One that is asleep or has a moth to catch does not.
    private mutating func pointerWatching(_ senses: CatSenses, tuning: CatTuning, now: TimeInterval) -> Bool {
        let near = senses.pointer?.isNear ?? false
        if watching {
            if near { lastNear = now }
            let giveUp = now - watchSince >= Self.watchLimit
            if giveUp || (!near && now - lastNear >= Self.releaseDelay) {
                tired = giveUp && near
                release(now: now)
                return true
            }
            if now >= plan.end { nextWatchPicture(now: now) }
            return true
        }
        guard near else {
            tired = false
            // The pointer went before it had turned: it does not watch for nothing.
            if queue.contains(.look) { queue.removeAll { $0 == .look } }
            return false
        }
        let here = plan.position(at: now)
        guard !tired, now - lastWatchEnd >= tuning.reactionCooldown, !isAsleep, !sleeping, moth == nil, !queue.contains(.look),
              keeper.settled(here) == here else { return false }
        watchSince = now
        lastNear = now
        nextFlick = now + Double.random(in: Self.flickGap, using: &generator)
        lookWay = way(towards: senses.pointer?.share, from: here) ?? sign(plan.facing)
        resumeStep = leftOfPlan(now: now)
        queue.insert(.look, at: 0)
        startQueue(now: now)
        return true
    }

    /// The side of the frog the pointer is on, 1 right and -1 left; nil when it is too near the middle of it to say.
    private func way(towards share: Double?, from here: Double) -> Double? {
        guard let share, travel >= 1 else { return nil }
        let middle = here + (CatField.pictureSize.width / 2) / travel
        guard abs(share - middle) * travel >= 6 else { return nil }
        return share > middle ? 1 : -1
    }

    /// The next picture of the watching: the eyes on the pointer, and the tongue now and then, towards it.
    private mutating func nextWatchPicture(now: TimeInterval) {
        let (watch, flick): (FrogMove, FrogMove) = stance == .pad ? (.padWatch, .padFlick) : (.watch, .flick)
        let here = plan.position(at: now)
        let facing = facing(way(towards: senses.pointer?.share, from: here) ?? sign(plan.facing))
        if move == flick {
            nextFlick = now + Double.random(in: Self.flickGap, using: &generator)
        } else if now >= nextFlick {
            plan = made(flick, now: now, duration: flick.passDuration, facing: facing)
            return
        }
        plan = made(watch, now: now, duration: max(min(nextFlick - now, 2), 0.25), facing: facing)
    }

    /// Watches no more: and what it was doing goes on.
    private mutating func release(now: TimeInterval) {
        watching = false
        lastWatchEnd = now
        queue.removeAll { $0 == .look }
        if let resumeStep { queue.insert(resumeStep, at: 0) }
        resumeStep = nil
        startQueue(now: now)
    }

    /// What was left of a pose that goes round and round, to go on with when something has come in between: not of one that goes somewhere,
    /// or is asleep, which is not gone back to.
    private func leftOfPlan(now: TimeInterval) -> FrogStep? {
        guard plan.motion.loops, plan.from == plan.to, plan.end - now > 1, moth == nil, !watching, !isAsleep else { return nil }
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
        // (Not away for as long as sleep takes any more, though the user has not touched anything very lately: it wakes as it does for that.)
        if (isAsleep || sleeping) && senses.idleSeconds < tuning.sleepThreshold(hour: senses.hour) {
            wake(now: now)
            return
        }
        if senses.idleSeconds >= tuning.sleepThreshold(hour: senses.hour) {
            if isAsleep {
                plan = made(move, now: now, duration: Self.sleepChunk)
                return
            }
            if sleeping {
                startQueue(now: now)
                return
            }
            if beginSleep(now: now) { return }
        }
        startQueue(now: now)
    }

    /// Down for the night in steps: to the pad, which comes up for it, on to it, asleep there; or, with no room for a pad, asleep where it
    /// is. A moth that is out is caught first, and a pad that is coming or going is gone on with.
    private mutating func beginSleep(now: TimeInterval) -> Bool {
        guard moth == nil else { return false }
        let asleep = FrogStep.stay(.padSleep, Self.sleepChunk...Self.sleepChunk)
        switch pad?.phase {
        case .occupied?:
            queue = [asleep]
        case nil:
            queue = padSpot(from: plan.position(at: now)) == nil ? [groundSleep] : [.walk(.padSpot), .placePad, .hopOn, asleep]
        default:
            return false
        }
        scene = nil
        resumeStep = nil
        watching = false
        sleeping = true
        startQueue(now: now)
        return true
    }

    private var groundSleep: FrogStep { .stay(.sleep, Self.sleepChunk...Self.sleepChunk) }

    /// Begins the next step of the scene, which is the first of a new scene when there is none left.
    private mutating func startQueue(now: TimeInterval) {
        for _ in 0..<16 {
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
        stance = .ground
        plan = made(.sit, now: now, duration: 2)
    }

    private mutating func beginScene() {
        // The last scene took all it set out with it.
        if hasProps { strayProps += 1 }
        clearProps()
        let night = CatTuning.isNight(hour: senses.hour)
        var choices = FrogScene.allCases.filter { $0 != lastScene && $0.weight(night: night, busyness: busyness) > 0 }
        if choices.isEmpty { choices = [.restSit] }
        let total = choices.reduce(0) { $0 + $1.weight(night: night, busyness: busyness) }
        var roll = Double.random(in: 0..<total, using: &generator)
        var picked = choices[0]
        for choice in choices {
            let weight = choice.weight(night: night, busyness: busyness)
            if roll < weight {
                picked = choice
                break
            }
            roll -= weight
        }
        scene = picked
        lastScene = picked
        sceneSerial += 1
        queue = picked.steps(using: &generator, busyness: busyness)
    }

    /// What it has to do to end what it is playing with, in order: off the pad, and the pad down.
    private func wrapUp() -> [FrogStep] {
        guard let pad else { return [] }
        switch pad.phase {
        case .occupied: return [.hopOff, .padSinks]
        case .appearing, .waiting: return [.padSinks]
        case .leaving: return []
        }
    }

    private mutating func clearProps() {
        pad = nil
        moth = nil
        padStart = nil
        mothWay = nil
    }

    // MARK: Plans

    /// A plan for `step`, from where the frog is at `now`; nil for a step that takes no time or cannot be done. It hops off the pad first when
    /// the step is not on it, whatever the step is, and the pad goes down after.
    private mutating func begin(_ step: FrogStep, now: TimeInterval) -> Pose? {
        var step = step
        if case .walk(let place) = step {
            guard let target = route(place, now: now) else { return nil }
            step = .walkTo(target)
        }
        if let needed = step.stance, needed != stance {
            if stance == .pad {
                queue.insert(step, at: 0)
                if pad != nil { queue.insert(.padSinks, at: 0) }
                queue.insert(.hopOff, at: 0)
                return nil
            }
            stance = needed
        }
        let planned: Pose?
        switch step {
        case .stay(let move, let seconds):
            planned = made(move, now: now, duration: Double.random(in: seconds, using: &generator))
        case .walk:
            planned = nil
        case .walkTo(let target):
            planned = hop(to: target, now: now)
        case .placePad:
            planned = placePad(now: now)
        case .hopOn:
            planned = hopOn(now: now)
        case .hopOff:
            planned = hopOff(now: now)
        case .padSinks:
            planned = padSinks(now: now)
        case .mothComes:
            planned = mothComes(now: now)
        case .mothHovers(let seconds):
            planned = mothHovers(seconds, now: now)
        case .snap:
            planned = snap(now: now)
        case .reel:
            planned = reel(now: now)
        case .look:
            watching = true
            planned = made(stance == .pad ? .padWatch : .watch, now: now, duration: 2, facing: facing(lookWay))
        }
        if planned != nil, let ends = step.endStance { stance = ends }
        return planned
    }

    /// The frog doing `move` where it is, with whatever it has out (the pad, the moth).
    private mutating func made(
        _ move: FrogMove, now: TimeInterval, duration: TimeInterval, facing: Facing? = nil, from: Double? = nil, to: Double? = nil
    ) -> Pose {
        let there = plan.position(at: now)
        // A frog with its pad out is not moved off the place it is at.
        let here = pad != nil ? there : keeper.settled(there)
        var pose = Pose(motion: move.motion, facing: facing ?? plan.facing, from: from ?? here, to: to ?? from ?? here, began: now, duration: duration)
        pose.prop = nextProp(for: move)
        return pose
    }

    /// What it has out for the pose that is being made, and how far it has come: the pad comes up in one pose and goes down in one; the moth
    /// flies in in one, hovers in the next and is gone with the pose that takes it.
    private mutating func nextProp(for move: FrogMove) -> PoseProp? {
        if var current = pad {
            let look: FrogProp
            switch current.phase {
            case .appearing:
                look = .padAppearing
                current.phase = .waiting
                pad = current
            case .waiting: look = .padStill
            case .occupied: look = move == .hopOn ? .padLanding : (move == .hopOff ? .padLeaping : .padRippling)
            case .leaving:
                look = .padSinking
                pad = nil
            }
            return PoseProp(look: look.look, from: current.place, to: current.place, alsoAt: [current.home])
        }
        if var current = moth {
            switch current.phase {
            case .coming:
                current.phase = .hovering
                moth = current
                return PoseProp(look: FrogProp.moth.look, from: current.entry, to: current.place)
            case .hovering:
                return PoseProp(look: FrogProp.moth.look, from: current.place, to: current.place)
            case .held:
                return PoseProp(look: FrogProp.mothHeld.look, from: current.place, to: current.place)
            case .leaving:
                moth = nil
                return PoseProp(look: FrogProp.moth.look, from: current.from, to: current.entry)
            }
        }
        return nil
    }

    private func facing(_ direction: Double) -> Facing { direction > 0 ? .right : .left }

    private func sign(_ facing: Facing) -> Double { facing == .right ? 1 : -1 }

    // MARK: Hopping

    /// Where a hop sent to `place` goes, as a share of the lane, before the lane's rules have their say (`hop(to:)`); nil for none.
    private mutating func route(_ place: FrogPlace, now: TimeInterval) -> Double? {
        let here = plan.position(at: now)
        guard travel >= 1 else {
            queue = []
            return nil
        }
        switch place {
        case .away(let pixels):
            let reach = keeper.reach(from: here)
            var right = here <= 0.08 ? true : here >= 0.92 ? false : chance(0.5)
            let distance = Double.random(in: pixels, using: &generator)
            func aim() -> Double { right ? min(here + distance / travel, reach.upperBound) : max(here - distance / travel, reach.lowerBound) }
            var aimed = aim()
            if abs(aimed - here) * travel < FrogMove.hopLength / 2 {
                right.toggle()
                aimed = aim()
            }
            return aimed
        case .farEdge:
            return here < 0.5 ? 1 - Self.edgeInset : Self.edgeInset
        case .padSpot:
            guard let spot = padSpot(from: here) else {
                failedSpot()
                return nil
            }
            padStart = spot
            return spot.start
        case .mothSpot:
            guard let spot = mothSpot(from: here) else {
                failedSpot()
                return nil
            }
            mothWay = spot.way
            return spot.start
        }
    }

    /// There is no room for what it was going to do: the scene is over, and a frog that was on its way to sleep sleeps where it is.
    private mutating func failedSpot() {
        queue = sleeping ? [groundSleep] : []
    }

    /// Hops to `target`, held to what the lane lets it do: out of the places it must not stop in, no further than it can reach, and a whole
    /// number of hops, so that the leg ends on a landing. As quick as the hop is, whatever the Mac is doing.
    private mutating func hop(to target: Double, now: TimeInterval) -> Pose? {
        let here = plan.position(at: now)
        guard travel >= 1 else {
            queue = []
            return nil
        }
        let end = wholeHops(from: here, to: keeper.destination(target, from: here))
        // A leg too short to be a hop is not hopped (the next step begins).
        guard abs(end - here) * travel >= FrogMove.hopLength / 2 else { return nil }
        let covered = abs(end - here) * travel
        return made(.hop, now: now, duration: covered / FrogMove.hop.speed, facing: facing(end - here), from: here, to: end)
    }

    /// `end` moved to the nearest place a whole number of hops from `here` that the frog may stop in, if there is one.
    private func wholeHops(from here: Double, to end: Double) -> Double {
        let length = FrogMove.hopLength
        let hops = (abs(end - here) * travel / length).rounded()
        guard hops >= 1 else { return end }
        let direction = end > here ? 1.0 : -1.0
        for count in [hops, hops - 1, hops + 1] where count >= 1 {
            let candidate = here + direction * count * length / travel
            if (0.0...1.0).contains(candidate), keeper.destination(candidate, from: here) == candidate, isFree(candidate) { return candidate }
        }
        return end
    }

    /// Whether a character may stop at `place` (and so a pad may float or a moth hunt be from there): it is in none of the stretches the lane
    /// keeps clear. A lane so crowded that there is nowhere free to go leaves a character where it is, which is no place for a pad, so this
    /// asks for a free one and not whether `settled` gave the place back.
    private func isFree(_ place: Double) -> Bool {
        !(keeper.lane.crossing + keeper.lane.zones).contains { place > $0.lowerBound && place < $0.upperBound }
    }

    /// The places a hop can end at from `here`, nearest first: a whole number of hops either way.
    private func hopPlaces(from here: Double) -> [Double] {
        let step = FrogMove.hopLength / travel
        guard step > 0 else { return [here] }
        var places = [here]
        for count in 1...max(Int(1 / step) + 1, 1) {
            places += [here + Double(count) * step, here - Double(count) * step]
        }
        return places.filter { (0.0...1.0).contains($0) }
    }

    // MARK: The lily pad

    /// Where there is room to put a pad, and to hop on to it and off it, nearest to `here`: the place it hops from, and the way it faces to.
    /// Both the place and the pad's are outside the crossing and free of the others (and of what they have out), and the hop does not go
    /// through the camera.
    private func padSpot(from here: Double) -> (start: Double, direction: Double)? {
        guard travel >= 1 else { return nil }
        let span = FrogMove.hopSpan / travel
        let direction = plan.facing == .right ? 1.0 : -1.0
        for start in hopPlaces(from: here) {
            for way in [direction, -direction] where fits(from: start, to: start + way * span, startingAt: here) { return (start, way) }
        }
        return nil
    }

    private func fits(from start: Double, to end: Double, startingAt here: Double) -> Bool {
        guard (0.0...1.0).contains(start), (0.0...1.0).contains(end), isFree(start), isFree(end),
              keeper.destination(start, from: here) == start else { return false }
        let (low, high) = (min(start, end), max(start, end))
        if keeper.lane.crossing.contains(where: { high > $0.lowerBound && low < $0.upperBound }) { return false }
        return keeper.reach(from: start).contains(end)
    }

    /// Sits and watches the pad come up out of the water beside it, a hop in front of it.
    private mutating func placePad(now: TimeInterval) -> Pose? {
        let here = plan.position(at: now)
        guard travel >= 1, let spot = padStart ?? padSpot(from: here) else {
            failedSpot()
            return nil
        }
        let end = here + spot.direction * FrogMove.hopSpan / travel
        guard fits(from: here, to: end, startingAt: here) else {
            padStart = nil
            failedSpot()
            return nil
        }
        pad = Pad(place: end, home: here, phase: .appearing)
        padStart = nil
        return made(.sit, now: now, duration: FrogProp.padAppearing.passDuration, facing: facing(spot.direction))
    }

    private mutating func hopOn(now: TimeInterval) -> Pose? {
        guard var current = pad, current.phase == .waiting else {
            queue = []
            return nil
        }
        current.phase = .occupied
        pad = current
        let here = plan.position(at: now)
        return made(.hopOn, now: now, duration: FrogMove.hopOn.passDuration, facing: facing(current.place - here), from: here, to: current.place)
    }

    /// Off the pad the way it came, and the pad stands empty.
    private mutating func hopOff(now: TimeInterval) -> Pose? {
        guard let current = pad, current.phase == .occupied else {
            stance = .ground
            return nil
        }
        let here = plan.position(at: now)
        let pose = made(.hopOff, now: now, duration: FrogMove.hopOff.passDuration, facing: facing(current.home - here), from: here, to: current.home)
        pad?.phase = .waiting
        return pose
    }

    private mutating func padSinks(now: TimeInterval) -> Pose? {
        guard pad != nil else { return nil }
        pad?.phase = .leaving
        return made(.sit, now: now, duration: FrogProp.padSinking.passDuration)
    }

    // MARK: The moth

    /// Where a moth hovers if the frog sits at `start` facing `way` (1 right, -1 left): at the tip of its tongue, and where it comes in from,
    /// the end of the lane on that side. The moth's whole way is outside the crossing, and the frog's place is free.
    private func mothRun(start: Double, way: Double) -> (place: Double, entry: Double)? {
        let place = start + (way > 0 ? FrogMove.mothReach.right : FrogMove.mothReach.left) / travel
        let entry = way > 0 ? 1 + Self.mothOutside.right / travel : -Self.mothOutside.left / travel
        guard (0.0...1.0).contains(start), (0.0...1.0).contains(place), isFree(start) else { return nil }
        let (low, high) = (min(entry, place), max(entry, place))
        if keeper.lane.crossing.contains(where: { high > $0.lowerBound && low < $0.upperBound }) { return nil }
        return (place, entry)
    }

    /// The place nearest to `here` where a moth can be hunted from, and the side it comes from.
    private func mothSpot(from here: Double) -> (start: Double, way: Double)? {
        guard travel >= 1 else { return nil }
        let facingNow = sign(plan.facing)
        for start in hopPlaces(from: here) where keeper.destination(start, from: here) == start {
            let arriving = start > here + 0.0005 ? 1.0 : (start < here - 0.0005 ? -1.0 : facingNow)
            for way in [arriving, -arriving] where mothRun(start: start, way: way) != nil { return (start, way) }
        }
        return nil
    }

    /// Where the moth is at `now`, if the pose shows one.
    private func mothPlace(at now: TimeInterval) -> Double? {
        guard let prop = plan.prop, FrogProp(prop.look).isMoth else { return nil }
        guard plan.duration > 0 else { return prop.to }
        let progress = min(max((now - plan.began) / plan.duration, 0), 1)
        return prop.from + (prop.to - prop.from) * progress
    }

    /// Sits up and watches a moth fly in from the end of the lane.
    private mutating func mothComes(now: TimeInterval) -> Pose? {
        let here = plan.position(at: now)
        guard travel >= 1 else {
            queue = []
            return nil
        }
        let preferred = mothWay ?? sign(plan.facing)
        for way in [preferred, -preferred] {
            guard let run = mothRun(start: here, way: way) else { continue }
            moth = Moth(place: run.place, entry: run.entry, phase: .coming)
            let flight = max(abs(run.place - run.entry) * travel / Self.mothSpeed, 1)
            return made(.watch, now: now, duration: flight, facing: facing(way))
        }
        // No room for it after all: the scene is over.
        queue = []
        return nil
    }

    /// Watches it hover.
    private mutating func mothHovers(_ seconds: ClosedRange<Double>, now: TimeInterval) -> Pose? {
        guard moth?.phase == .hovering else { return nil }
        return made(.watch, now: now, duration: Double.random(in: seconds, using: &generator))
    }

    /// Shoots its tongue out at it.
    private mutating func snap(now: TimeInterval) -> Pose? {
        guard moth?.phase == .hovering else { return nil }
        moth?.phase = .held
        return made(.snapOut, now: now, duration: FrogMove.snapOut.passDuration)
    }

    /// Takes the tongue in with the moth on it: the moth is gone.
    private mutating func reel(now: TimeInterval) -> Pose? {
        guard moth?.phase == .held else {
            moth = nil
            return nil
        }
        moth = nil
        return made(.snapIn, now: now, duration: FrogMove.snapIn.passDuration)
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

nonisolated extension FrogBrain: CharacterBrain {
    var pose: Pose { plan }
}
