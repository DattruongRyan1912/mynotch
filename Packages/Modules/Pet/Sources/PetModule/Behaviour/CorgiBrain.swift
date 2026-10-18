import Foundation

/// What the corgi decides to do. A value that holds no timer and reads nothing, like the others': it is told the time and what the corgi
/// senses, and says whether the picture changed, so every rule of its day is a test with a made-up clock.
///
/// It is hyperactive. What it does with its time is a handful of scenes (`CorgiScene`) picked at random by weights that depend on the time of
/// day, never the same one twice running: standing about, trotting, wiggling its rear, sitting, lying with its chin on its paws, napping on
/// its side, fetching a ball, and the zoomies. On top of that:
/// - **the Mac is busy: more zoomies.** Its frantic is a joyful one: nothing about it is stressed, it just runs about more, and for longer.
///   A burst of work (`busyBurst`) sends it off at once, once for each burst. With the setting off nothing of the load is read at all;
/// - the pointer comes near: it sits and begs, sitting up with its paws together, and goes on when the pointer has gone. It begs for no more
///   than `begLimit` seconds, and not again until the pointer has gone away. One with the ball out lets the ball be taken first;
/// - a stroke makes it spin for joy, and then it goes on with what it was doing;
/// - the user has been away for the sleep time: it finishes the step it is in, lets the ball be taken if it has one out, lies down and goes to
///   sleep on its side, and gets up when the user is back.
///
/// It has the ball only while the fetch scene calls for it: from the moment it falls in to the moment it has been taken up again. Whatever
/// interrupts a scene ends it first (`wrapUp`), and the props are a state of this brain, so a ball never stays behind. A corgi is never
/// sent through the camera but by a trot to the far end (`crossOver`): the zoomies and the fetch keep to one side of it.
nonisolated struct CorgiBrain: Sendable {
    typealias Outcome = BrainOutcome

    /// A user who has touched something this recently is at the Mac.
    static let wakeIdle: TimeInterval = 2
    static let sleepChunk: TimeInterval = 24
    /// A spin for joy, and a moment to be pleased with itself.
    static let spinDuration: TimeInterval = 1.2
    /// How near the end of the lane it goes when it goes to the end, as a share of it.
    static let edgeInset = 0.04
    /// How long it begs, at the most, and how long after the pointer has gone it goes on begging.
    static let begLimit: TimeInterval = 15
    static let releaseDelay: TimeInterval = 0.9
    /// The load from which the Mac is busy enough for more zoomies (as the cat's), and how busy a burst of work is, whatever the load.
    static let busyFrom = CatBrain.busyFrom
    static let burstBusyness = 0.8
    /// How far in front of the corgi, in pixels, the ball falls in (the middle of its picture is that much past the nose), and how far it
    /// rolls: from where the corgi stands to the middle of the ball's picture.
    static let tossStart = 17.0
    static let tossRoll: ClosedRange<Double> = 48...100
    /// What it rolls instead when there is not room for that: on the Mac's wings, which are little more than a ball's roll between the camera
    /// and the end of the lane, it is a short one.
    static let shorterRolls: [Double] = [64, 48, 40, 34, 30]
    /// What it drops everything for is held to these moves: a stroke or a begging is not taken while it is sitting down or getting up, lying
    /// down, settling, spinning, watching the ball come in, taking it up, carrying it or setting it down.
    static let unbroken: Set<CorgiMove> = [.sitDown, .standUp, .begUp, .begDown, .lieDown, .getUp, .settle, .wake, .spin, .watch, .grab, .carry, .lower]

    /// The ball: where it falls from and where it lies (a share of the lane, the left edge of its picture), where the corgi stood to watch it
    /// fall, which way it went, and how far it has come.
    private struct Ball {
        enum Phase { case tossing, lying, carried, dropping, leaving }
        var place: Double
        var start: Double
        var home: Double
        /// Where it will be set down, in front of the nose of the corgi that has come back: reserved with the rest.
        var setDown: Double
        var way: Double
        var phase: Phase
    }

    private(set) var plan: Pose
    /// The scene it is in, nil while it does something that is not one: sleep, begging.
    private(set) var scene: CorgiScene?
    /// Rises with every scene begun, so a test sees one that repeats.
    private(set) var sceneSerial = 0
    /// How often a prop was found left over when a scene began and had to be cleared: never, which a test checks.
    private(set) var strayProps = 0
    private var lastScene: CorgiScene?
    private var queue: [CorgiStep] = []
    private(set) var stance = CorgiMove.Stance.standing
    private var ball: Ball?
    private var travel = 0.0
    private var keeper = LaneKeeper()
    /// What the corgi keeps to when it runs about and fetches: the lane with the crossing shut. Only a trot goes through it.
    private var walkKeeper = LaneKeeper()
    private(set) var busyness = 0.0
    private var senses = CatSenses()
    private var generator: SplitMix64
    /// What it was in the middle of when it sat up to beg, to go on with: a wiggle.
    private var resumeStep: CorgiStep?
    private var begSince: TimeInterval = 0
    private var lastNear: TimeInterval = 0
    /// It has begged as long as it will, and does not beg again until the pointer has gone away.
    private var tired = false
    private var lastBegEnd = -TimeInterval.infinity
    /// The burst of work it has heard of: it goes off for each once.
    private var burstHeard = false

    init(seed: UInt64, now: TimeInterval, position: Double = 0.5, facing: Facing = .left) {
        generator = SplitMix64(seed: seed)
        plan = Pose(motion: CorgiMove.stand.motion, facing: facing, from: position, to: position, began: now, duration: 2)
    }

    var move: CorgiMove { CorgiMove(plan.motion) }

    var isAsleep: Bool { move == .sleep }

    /// Whether it has a ball out now.
    var hasProps: Bool { ball != nil }

    /// Where the corgi is at `now`.
    func position(at now: TimeInterval) -> Double { plan.position(at: now) }

    // MARK: From outside

    /// A stroke: a spin for joy, and then it goes on with what it was doing.
    mutating func pet(now: TimeInterval) -> Outcome {
        guard !isCrossing(at: now), !Self.unbroken.contains(move) else { return .unchanged }
        let before = plan
        var steps: [CorgiStep] = [.stay(.spin, Self.spinDuration...Self.spinDuration)]
        if isBegging {
            // A stroke ends the begging, and what it was doing before it goes on.
            lastBegEnd = now
            queue.removeAll { $0 == .beg }
            if let resumeStep { steps.append(resumeStep) }
            resumeStep = nil
        } else if ball != nil {
            // With the ball out, a stroke ends the fetch: the spin, and the ball is taken.
            queue = wrapUp()
            scene = nil
        } else if stance == .lying || stance == .asleep {
            // Down on the floor, it jumps up for joy and has had enough of that: what was left of the scene is not gone on with.
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
        ball = nil
        stance = .standing
        resumeStep = nil
        burstHeard = false
        tired = false
        lastBegEnd = -.infinity
        plan = made(.stand, now: now, duration: 2)
    }

    /// Advances the corgi to `now`. `travel` is how far, in points of its picture's pixels, it can walk along the lane.
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
        let sticky = Self.unbroken.contains(move) && now < plan.end || isCrossing(at: now)
        if !sticky, interruption(senses, burst: burst, now: now) {
            // Done.
        } else if !sticky, begging(senses, tuning: tuning, now: now) {
            // Done.
        } else if now >= plan.end {
            advance(senses, tuning: tuning, now: now)
        }
        return outcome(since: before)
    }

    /// Takes the stretches of the lane it must not stop in. One that stands in one when they are taken is put at the nearer end of it, which
    /// is a jump, and then it has nothing it was playing with: a ball would be left across the camera.
    mutating func settle(lane: LaneContext) {
        keeper = LaneKeeper(lane)
        var shut = lane
        shut.closed += lane.crossing
        walkKeeper = LaneKeeper(shut)
        guard plan.from == plan.to, !(lane.crossing.isEmpty && lane.zones.isEmpty) else { return }
        let here = keeper.settled(plan.to)
        guard here != plan.to else { return }
        // (A ball that is going is on the pose and no longer on the brain: it goes with the rest.)
        if hasProps || plan.prop != nil || stance != .standing {
            ball = nil
            queue = []
            scene = nil
            resumeStep = nil
            stance = .standing
            plan = Pose(motion: CorgiMove.stand.motion, facing: plan.facing, from: here, to: here, began: plan.began, duration: 0)
            return
        }
        plan.from = here
        plan.to = here
    }

    // MARK: Reacting

    /// What it drops what it is doing for. True when it did: waking, and a burst of work.
    private mutating func interruption(_ senses: CatSenses, burst: Bool, now: TimeInterval) -> Bool {
        if move == .sleep, senses.idleSeconds < Self.wakeIdle {
            queue = [.stay(.stand, 1.5...2.5)]
            scene = nil
            startQueue(now: now)
            return true
        }
        // A burst of work, which it hears of once: off it goes, at once, for the joy of it. Not from sleep, not from begging (which has a
        // way out of its own) and not in the middle of the zoomies it is in.
        guard burst, !burstHeard, stance != .asleep, !isBegging else { return false }
        burstHeard = true
        guard scene != .zoomies, travel >= 1 else { return false }
        queue = wrapUp() + CorgiScene.zoomies.steps(using: &generator, busyness: busyness)
        scene = .zoomies
        lastScene = .zoomies
        sceneSerial += 1
        resumeStep = nil
        startQueue(now: now)
        return true
    }

    /// Whether it is begging.
    private var isBegging: Bool { move == .begUp || move == .beg }

    /// A corgi that has the pointer near sits and begs, sitting up with its paws together, and goes on when the pointer has gone, a moment
    /// later, and does not beg for ever. One with the ball out lets it be taken first, one that is lying gets up, and one that is asleep
    /// does not beg at all.
    private mutating func begging(_ senses: CatSenses, tuning: CatTuning, now: TimeInterval) -> Bool {
        let near = senses.pointer?.isNear ?? false
        if isBegging {
            if near { lastNear = now }
            let giveUp = now - begSince >= Self.begLimit
            if giveUp || (!near && now - lastNear >= Self.releaseDelay) {
                tired = giveUp && near
                release(now: now)
                return true
            }
            // Sitting up, and held so, for as long as it takes.
            if now >= plan.end {
                if move == .begUp {
                    queue.removeAll { $0 == .beg }
                    begSince = now
                }
                plan = made(.beg, now: now, duration: 2)
            }
            return true
        }
        guard near else {
            tired = false
            // The pointer went before it had sat up: it does not beg for nothing.
            if queue.contains(.beg) { queue.removeAll { $0 == .beg } }
            return false
        }
        let here = plan.position(at: now)
        // (One that is on its way to beg, from the floor or from the ball, is not told again.)
        guard !tired, now - lastBegEnd >= tuning.reactionCooldown, stance != .asleep, !queue.contains(.beg), keeper.settled(here) == here else {
            return false
        }
        begSince = now
        lastNear = now
        if ball != nil {
            // The fetch is over: the ball is taken, and then it begs.
            queue = wrapUp() + [.beg]
            scene = nil
            resumeStep = nil
        } else {
            resumeStep = leftOfPlan(now: now)
            queue.insert(.beg, at: 0)
        }
        startQueue(now: now)
        return true
    }

    /// Begs no more: sits down, and then what it was doing.
    private mutating func release(now: TimeInterval) {
        lastBegEnd = now
        queue.removeAll { $0 == .beg }
        if let resumeStep { queue.insert(resumeStep, at: 0) }
        resumeStep = nil
        stance = .sitting
        plan = made(.begDown, now: now, duration: CorgiMove.begDown.passDuration)
    }

    /// What was left of a pose that goes round and round, to go on with when something has come in between: not of one that goes somewhere,
    /// or is lying or asleep, which is not gone back to.
    private func leftOfPlan(now: TimeInterval) -> CorgiStep? {
        guard plan.motion.loops, plan.from == plan.to, plan.end - now > 1, stance == .standing, ball == nil, !isBegging else { return nil }
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
            // Down for the night in steps: the ball taken if it is out, lying down, onto its side, then asleep.
            let asleep = CorgiStep.stay(.sleep, Self.sleepChunk...Self.sleepChunk)
            if move == .sleep {
                plan = made(.sleep, now: now, duration: Self.sleepChunk)
            } else if queue.contains(asleep) {
                startQueue(now: now)
            } else {
                queue = wrapUp() + [asleep]
                scene = nil
                resumeStep = nil
                startQueue(now: now)
            }
            return
        }
        startQueue(now: now)
    }

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
        // Nothing to do: stands.
        ball = nil
        stance = .standing
        plan = made(.stand, now: now, duration: 2)
    }

    private mutating func beginScene() {
        // The last scene took all it set out with it.
        if ball != nil { strayProps += 1 }
        ball = nil
        let night = CatTuning.isNight(hour: senses.hour)
        var choices = CorgiScene.allCases.filter { $0 != lastScene && $0.weight(night: night, busyness: busyness) > 0 }
        if choices.isEmpty { choices = [.restStand] }
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

    /// What it has to do to end what it is playing with, in order: the ball taken up (put down first if it is in its mouth).
    private func wrapUp() -> [CorgiStep] {
        guard let ball else { return [] }
        switch ball.phase {
        case .lying: return [.takeBall]
        case .carried: return [.lower, .drop, .takeBall]
        case .tossing, .dropping, .leaving: return []
        }
    }

    // MARK: Plans

    /// A plan for `step`, from where the corgi is at `now`; nil for a step that takes no time or cannot be done. It stands up, sits, lies down
    /// or gets up first when the step needs it, and the step waits its turn.
    private mutating func begin(_ step: CorgiStep, now: TimeInterval) -> Pose? {
        var step = step
        // A walk or a run is sent to a place the moment it begins, which is before it stands up: it faces the way it is going.
        switch step {
        case .walk(let place):
            guard let target = route(place, running: false, now: now) else { return nil }
            step = .walkTo(target)
        case .run(let place):
            guard let target = route(place, running: true, now: now) else { return nil }
            step = .runTo(target)
        default: break
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
        case .walk, .run:
            planned = nil
        case .walkTo(let target):
            planned = go(to: target, move: .trot, shut: false, now: now)
        case .runTo(let target):
            planned = go(to: target, move: .run, shut: true, now: now)
        case .toss:
            planned = toss(now: now)
        case .chase:
            planned = chase(now: now)
        case .grab:
            planned = grab(now: now)
        case .carryBack:
            planned = carryBack(now: now)
        case .lower:
            planned = lower(now: now)
        case .drop:
            planned = drop(now: now)
        case .takeBall:
            planned = takeBall(now: now)
        case .beg:
            planned = made(.beg, now: now, duration: 2)
        }
        return planned
    }

    /// The move that takes the corgi one step nearer a stance, and the one it ends in; nil when it needs none.
    private func hop(to needed: CorgiMove.Stance) -> (move: CorgiMove, ends: CorgiMove.Stance)? {
        switch (stance, needed) {
        case (.standing, .sitting), (.standing, .begging): (.sitDown, .sitting)
        case (.standing, .lying), (.standing, .asleep): (.lieDown, .lying)
        case (.sitting, .standing), (.sitting, .lying), (.sitting, .asleep): (.standUp, .standing)
        case (.sitting, .begging): (.begUp, .begging)
        case (.begging, .sitting), (.begging, .standing), (.begging, .lying), (.begging, .asleep): (.begDown, .sitting)
        case (.lying, .standing), (.lying, .sitting), (.lying, .begging): (.getUp, .standing)
        case (.lying, .asleep): (.settle, .asleep)
        case (.asleep, _): (.wake, .lying)
        default: nil
        }
    }

    /// The way it faces for a move that is made on the way to `step`: towards where it is going.
    private func facingToward(_ step: CorgiStep, now: TimeInterval) -> Facing {
        let here = plan.position(at: now)
        switch step {
        case .walkTo(let target), .runTo(let target): return abs(target - here) * travel >= 1 ? facing(target - here) : plan.facing
        default: return plan.facing
        }
    }

    /// The corgi doing `move` where it is, with whatever it has out (the ball).
    private mutating func made(
        _ move: CorgiMove, now: TimeInterval, duration: TimeInterval, facing: Facing? = nil, from: Double? = nil, to: Double? = nil
    ) -> Pose {
        let there = plan.position(at: now)
        // A corgi with its ball out is not moved off the place it is at.
        let here = hasProps ? there : keeper.settled(there)
        var pose = Pose(motion: move.motion, facing: facing ?? plan.facing, from: from ?? here, to: to ?? from ?? here, began: now, duration: duration)
        pose.prop = nextProp()
        return pose
    }

    /// What it has out for the pose that is being made, and how far it has come: the ball falls in with one pose, is set down with one and
    /// is taken up with one.
    private mutating func nextProp() -> PoseProp? {
        guard let current = ball else { return nil }
        let look: CorgiProp
        var from = current.place
        switch current.phase {
        case .tossing:
            look = .ballToss
            from = current.start
            ball?.phase = .lying
        case .lying: look = .ballRest
        case .carried: look = .ballHeld
        case .dropping:
            look = .ballDrop
            ball?.phase = .lying
        case .leaving:
            look = .ballUp
            ball = nil
        }
        return PoseProp(look: look.look, from: from, to: current.place, alsoAt: [current.home, current.setDown])
    }

    private func facing(_ direction: Double) -> Facing { direction > 0 ? .right : .left }

    private func sign(_ facing: Facing) -> Double { facing == .right ? 1 : -1 }

    // MARK: Trotting and running

    /// Where a trot or a run sent to `place` goes, as a share of the lane, before the lane's rules have their say (`go`); nil for none.
    private mutating func route(_ place: CorgiPlace, running: Bool, now: TimeInterval) -> Double? {
        let here = plan.position(at: now)
        guard travel >= 1 else {
            queue = []
            return nil
        }
        let kept = running ? walkKeeper : keeper
        switch place {
        case .away(let pixels):
            let reach = kept.reach(from: here)
            var right = here <= 0.08 ? true : here >= 0.92 ? false : chance(0.5)
            let distance = Double.random(in: pixels, using: &generator)
            func aim() -> Double { right ? min(here + distance / travel, reach.upperBound) : max(here - distance / travel, reach.lowerBound) }
            var aimed = aim()
            if abs(aimed - here) * travel < 10 {
                right.toggle()
                aimed = aim()
            }
            return aimed
        case .farEdge:
            return here < 0.5 ? 1 - Self.edgeInset : Self.edgeInset
        case .zoom:
            // Most of the way to the end of the stretch it can run in that it is farther from, and a leg that has no room to run is not run.
            let reach = kept.reach(from: here)
            let farther = here - reach.lowerBound > reach.upperBound - here ? reach.lowerBound : reach.upperBound
            let end = farther <= 0 ? Self.edgeInset : (farther >= 1 ? 1 - Self.edgeInset : farther)
            return here + (end - here) * Double.random(in: 0.75...1, using: &generator)
        case .fetchSpot:
            guard let spot = fetchSpot(from: here) else {
                queue = []
                return nil
            }
            return spot
        }
    }

    /// Trots or runs to `target`, held to what the lane lets it do: out of the places it must not stop in, and no further than it can reach.
    /// A run keeps to its side of the camera, a trot may go through it. As quick as the move is, whatever the Mac is doing.
    private mutating func go(to target: Double, move: CorgiMove, shut: Bool, now: TimeInterval) -> Pose? {
        let here = plan.position(at: now)
        guard travel >= 1 else {
            queue = []
            return nil
        }
        let end = (shut ? walkKeeper : keeper).destination(target, from: here)
        let covered = abs(end - here) * travel
        // A leg too short to be a leg is not run (the next step begins).
        guard covered >= (move == .run ? 6 : 1) else { return nil }
        return made(move, now: now, duration: covered / move.speed, facing: facing(end - here), from: here, to: end)
    }

    // MARK: The ball

    /// Where the ball goes if the corgi stands at `home` and faces `way` (1 right, -1 left) and the ball rolls `distance` pixels: where it
    /// falls, where it lies, and where the corgi stands to take it up. All of it, and the way between, is outside the crossing and out of the
    /// others' way, and the corgi can run there. (And where it is set down, which is the other side of where it stands.)
    private func ballRun(home: Double, way: Double, distance: Double, here: Double) -> (start: Double, place: Double, chaseTo: Double, setDown: Double)? {
        let start = home + way * Self.tossStart / travel
        let place = home + way * distance / travel
        let chaseTo = place - way * CorgiMove.ballReach / travel
        // It is set down in front of the nose of the corgi that has come back, which is the other way from where it was thrown.
        let setDown = home - way * CorgiMove.ballReach / travel
        let places = [home, start, place, chaseTo, setDown]
        guard places.allSatisfy({ (0.0...1.0).contains($0) }) else { return nil }
        // The corgi can stand where it is going to stand, and run to the ball, and none of the places is where another stands or will.
        guard walkKeeper.destination(home, from: here) == home, walkKeeper.reach(from: home).contains(chaseTo), places.allSatisfy(keeper.isFree) else { return nil }
        let (low, high) = (places.min() ?? home, places.max() ?? home)
        if keeper.lane.crossing.contains(where: { high > $0.lowerBound && low < $0.upperBound }) { return nil }
        return (start, place, chaseTo, setDown)
    }

    /// The place nearest to `here` where the ball can be fetched from: the corgi stands there, and the ball falls and rolls to one side.
    private mutating func fetchSpot(from here: Double) -> Double? {
        guard travel >= 1 else { return nil }
        let distance = Double.random(in: Self.tossRoll, using: &generator)
        let facingNow = sign(plan.facing)
        // (Not a place that is only a step away, which is a trot too short to be one.)
        let starts = [here] + stride(from: 0.0, through: 1.0, by: 0.02).filter { abs($0 - here) * travel >= 6 }.sorted { abs($0 - here) < abs($1 - here) }
        for start in starts {
            let arriving = start > here + 0.0005 ? 1.0 : (start < here - 0.0005 ? -1.0 : facingNow)
            for way in [arriving, -arriving] {
                for roll in [distance] + Self.shorterRolls where ballRun(home: start, way: way, distance: roll, here: here) != nil { return start }
            }
        }
        return nil
    }

    /// Stands and watches the ball fall in from above in front of it and bounce and roll away.
    private mutating func toss(now: TimeInterval) -> Pose? {
        let here = plan.position(at: now)
        guard travel >= 1 else {
            queue = []
            return nil
        }
        let distance = Double.random(in: Self.tossRoll, using: &generator)
        let facingNow = sign(plan.facing)
        for way in [facingNow, -facingNow] {
            for roll in [distance] + Self.shorterRolls {
                guard let run = ballRun(home: here, way: way, distance: roll, here: here) else { continue }
                ball = Ball(place: run.place, start: run.start, home: here, setDown: run.setDown, way: way, phase: .tossing)
                return made(.watch, now: now, duration: CorgiProp.ballToss.passDuration, facing: facing(way))
            }
        }
        // No room for it after all: the scene is over.
        queue = []
        return nil
    }

    /// Runs to the ball.
    private mutating func chase(now: TimeInterval) -> Pose? {
        guard let current = ball, current.phase == .lying else {
            queue = wrapUp()
            return nil
        }
        let here = plan.position(at: now)
        let target = current.place - current.way * CorgiMove.ballReach / travel
        let end = walkKeeper.destination(target, from: here)
        // It cannot get to the ball: the ball is taken, and that is the end of that.
        guard abs(end - target) * travel <= 0.75 else {
            queue = wrapUp()
            return nil
        }
        let covered = abs(end - here) * travel
        guard covered >= 1 else { return nil }
        return made(.run, now: now, duration: covered / CorgiMove.run.speed, facing: facing(end - here), from: here, to: end)
    }

    /// Takes the ball up in its mouth.
    private mutating func grab(now: TimeInterval) -> Pose? {
        guard ball?.phase == .lying else { return nil }
        ball?.phase = .carried
        // (The room it holds from here is the one the ball will be set down in.)
        if let setDown = ball?.setDown { ball?.place = setDown }
        return made(.grab, now: now, duration: CorgiMove.grab.passDuration)
    }

    /// Trots back to where it was with the ball.
    private mutating func carryBack(now: TimeInterval) -> Pose? {
        guard let current = ball, current.phase == .carried else { return nil }
        let here = plan.position(at: now)
        let end = walkKeeper.destination(current.home, from: here)
        let covered = abs(end - here) * travel
        guard covered >= 1 else { return nil }
        return made(.carry, now: now, duration: covered / CorgiMove.carry.speed, facing: facing(end - here), from: here, to: end)
    }

    /// Puts its head down to set the ball on the floor.
    private mutating func lower(now: TimeInterval) -> Pose? {
        guard ball?.phase == .carried else { return nil }
        return made(.lower, now: now, duration: CorgiMove.lower.passDuration)
    }

    /// The ball is set down where its nose is, and bounces a little.
    private mutating func drop(now: TimeInterval) -> Pose? {
        guard ball?.phase == .carried else { return nil }
        let here = plan.position(at: now)
        let way = sign(plan.facing)
        ball?.place = here + way * CorgiMove.ballReach / travel
        ball?.way = way
        ball?.phase = .dropping
        return made(.wiggle, now: now, duration: CorgiProp.ballDrop.passDuration)
    }

    /// The ball is taken up, out of sight, and the corgi watches it go.
    private mutating func takeBall(now: TimeInterval) -> Pose? {
        guard ball?.phase == .lying else {
            ball = nil
            return nil
        }
        ball?.phase = .leaving
        return made(.watch, now: now, duration: CorgiProp.ballUp.passDuration)
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

nonisolated extension CorgiBrain: CharacterBrain {
    var pose: Pose { plan }
}
