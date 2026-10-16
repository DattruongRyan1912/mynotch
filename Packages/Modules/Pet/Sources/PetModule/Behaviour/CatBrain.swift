import Foundation

/// What the cat decides to do. A value that holds no timer and reads nothing: it is told the time and what the cat senses, and says
/// whether the picture changed, so every rule of its day is a test with a made-up clock.
///
/// Its rules, most urgent first:
/// - the pointer comes close to the notch: a startled jump (not more often than every `startleCooldown` seconds);
/// - a petting or a jump is finished before anything else;
/// - the processors are busy: it runs, harder the busier they are, whatever else is going on;
/// - the Mac plays sound: it dances;
/// - the user has been away for the sleep time: a yawn, then sleep, which ends with a yawn when the user is back;
/// - otherwise it sits, blinks, wanders, grooms and yawns at random, and at night it does less of the walking and more of the sleeping.
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

    static let startleCooldown: TimeInterval = 6
    /// The processors' load at which the cat starts to run, and the lower one at which it stops.
    static let runOn = 0.35
    static let runOff = 0.2
    /// How fast the cat walks, in points a second; a run starts at `runSpeed` and goes up to `runSpeed + runBoost`.
    static let walkSpeed = 12.0
    static let runSpeed = 36.0
    static let runBoost = 44.0
    /// The most a run speeds the frames up by.
    static let runFrameBoost = 0.6
    /// A user who has touched something this recently is at the Mac.
    static let wakeIdle: TimeInterval = 2
    /// A cat does not nap while the user is still at it.
    static let napMinimumIdle: TimeInterval = 10
    static let sleepChunk: TimeInterval = 20
    static let danceChunk: TimeInterval = 4
    static let purrDuration: TimeInterval = 2.6
    static let startleDuration: TimeInterval = 0.6
    static let yawnDuration: TimeInterval = 1.3
    static let lickDuration: TimeInterval = 2.4
    static let blinkDuration: TimeInterval = 0.3
    /// The longest a run goes on for in one plan when it has no distance to cover (a lane too short to cross).
    static let shortestRun: TimeInterval = 1

    /// How fast it dashes across the stretch of its lane where nobody can see it, in points a second.
    static let crossingSpeed = 60.0

    private(set) var plan: CatPlan
    /// Where on its lane the cat cannot be seen, as of the last time it was told (nil for a lane that has no such place).
    private var blind: BlindSpan?
    private var generator: SplitMix64
    private var pointerWasNear = false
    private var lastStartle = -TimeInterval.infinity

    init(seed: UInt64, now: TimeInterval, position: Double = 1, facing: Facing = .left) {
        generator = SplitMix64(seed: seed)
        plan = CatPlan(pose: .sit, facing: facing, from: position, to: position, began: now, duration: 2)
    }

    /// Where the cat is at `now`.
    func position(at now: TimeInterval) -> Double { plan.position(at: now) }

    /// A stroke: purring, with hearts.
    mutating func pet(now: TimeInterval) -> Outcome {
        let before = plan
        plan = still(.purr, now: now, duration: Self.purrDuration)
        return outcome(since: before)
    }

    /// The cat is back on the notch after being out of sight: where it was, sitting, and the pointer it last saw is not news. A cat that was
    /// in the middle of crossing behind the camera is on the edge of it when it comes back: nobody saw it get there.
    mutating func resume(now: TimeInterval, blind: BlindSpan? = nil) {
        self.blind = blind
        var place = plan.position(at: now)
        if let blind, blind.contains(place) { place = blind.nearestEdge(to: place) }
        plan = CatPlan(pose: .sit, facing: plan.facing, from: place, to: place, began: now, duration: 2)
        pointerWasNear = true
    }

    /// Advances the cat to `now`. `travel` is how far, in points, the cat can walk along the lane it is on.
    mutating func update(now: TimeInterval, senses: CatSenses, tuning: CatTuning, travel: Double, blind: BlindSpan? = nil) -> Outcome {
        let before = plan
        self.blind = blind
        let pointerArrived = senses.pointerNear && !pointerWasNear
        pointerWasNear = senses.pointerNear

        if pointerArrived, now - lastStartle >= Self.startleCooldown, plan.pose != .startled {
            lastStartle = now
            plan = still(.startled, now: now, duration: Self.startleDuration)
        } else if let out = leaving(now: now, travel: travel) {
            plan = out
        } else if let interrupt = interruption(senses: senses) {
            plan = begin(interrupt, now: now, senses: senses, tuning: tuning, travel: travel)
        } else if now >= plan.end {
            plan = begin(next(now: now, senses: senses, tuning: tuning), now: now, senses: senses, tuning: tuning, travel: travel)
        }
        return outcome(since: before)
    }

    // MARK: Deciding

    /// What the cat drops what it is doing for, or nil.
    private func interruption(senses: CatSenses) -> CatPose? {
        if plan.pose == .startled || plan.pose == .purr { return nil }
        let running = plan.pose == .run
        if running ? senses.cpuLoad >= Self.runOff : senses.cpuLoad >= Self.runOn { return running ? nil : .run }
        if running { return .sit }
        if senses.audioPlaying { return plan.pose == .dance ? nil : .dance }
        if plan.pose == .dance { return .sit }
        if plan.pose == .sleep, senses.idleSeconds < Self.wakeIdle { return .yawn }
        return nil
    }

    /// What the cat does when it is done with what it was doing.
    private mutating func next(now: TimeInterval, senses: CatSenses, tuning: CatTuning) -> CatPose {
        // A run that is going stops at the lower load, as it does mid-plan, so the pace does not flicker at the border.
        if senses.cpuLoad >= (plan.pose == .run ? Self.runOff : Self.runOn) { return .run }
        if senses.audioPlaying { return .dance }
        if senses.idleSeconds >= tuning.sleepThreshold(hour: senses.hour) {
            // Down for the night in two steps: a yawn, then sleep.
            return plan.pose == .sleep || plan.pose == .yawn ? .sleep : .yawn
        }
        if plan.pose == .sit, chance(0.4) { return .blink }
        return calm(senses: senses)
    }

    /// The cat's idle whims, weighted by the time of day.
    private mutating func calm(senses: CatSenses) -> CatPose {
        let night = CatTuning.isNight(hour: senses.hour)
        let table: [(CatPose, Double)] = night
            ? [(.sit, 40), (.walk, 10), (.lick, 10), (.yawn, 14), (.sleep, 26)]
            : [(.sit, 32), (.walk, 34), (.lick, 14), (.yawn, 6)]
        var pick = weighted(table)
        if pick == plan.pose, pick != .sit { pick = weighted(table) }
        // A nap is for a cat that has the notch to itself.
        if pick == .sleep, senses.idleSeconds < Self.napMinimumIdle { return .sit }
        return pick
    }

    private mutating func weighted(_ table: [(CatPose, Double)]) -> CatPose {
        let total = table.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total, using: &generator)
        for (pose, weight) in table {
            if roll < weight { return pose }
            roll -= weight
        }
        return table[0].0
    }

    private mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &generator) < probability
    }

    // MARK: Planning

    /// A plan for `pose` from where the cat is at `now`. A cat that is to stop where nobody can see it dashes out of there first.
    private mutating func begin(_ pose: CatPose, now: TimeInterval, senses: CatSenses, tuning: CatTuning, travel: Double) -> CatPlan {
        let planned = makePlan(for: pose, now: now, senses: senses, tuning: tuning, travel: travel)
        return hidden(planned) ? dash(to: blind?.nearestEdge(to: planned.to) ?? planned.to, now: now, travel: travel) : planned
    }

    /// Whether `plan` has the cat stay where it cannot be seen.
    private func hidden(_ plan: CatPlan) -> Bool {
        guard let blind else { return false }
        return plan.from == plan.to && blind.contains(plan.to)
    }

    /// The way out for a cat that is standing still in the blind stretch, which the lane may have only just got to know about.
    private mutating func leaving(now: TimeInterval, travel: Double) -> CatPlan? {
        guard let blind, travel >= 1, hidden(plan) else { return nil }
        return dash(to: blind.nearestEdge(to: plan.position(at: now)), now: now, travel: travel)
    }

    /// A run from where the cat is to `target`, at the pace of one that has somewhere to be.
    private func dash(to target: Double, now: TimeInterval, travel: Double) -> CatPlan {
        let here = plan.position(at: now)
        let covered = abs(target - here) * max(travel, 0)
        return CatPlan(
            pose: .run, facing: target == here ? plan.facing : (target > here ? .right : .left), from: here, to: target, began: now,
            duration: max(covered / Self.crossingSpeed, 0.3)
        )
    }

    private mutating func makePlan(for pose: CatPose, now: TimeInterval, senses: CatSenses, tuning: CatTuning, travel: Double) -> CatPlan {
        switch pose {
        case .walk: return wander(now: now, travel: travel)
        case .run: return run(now: now, load: senses.cpuLoad, travel: travel)
        case .sit: return still(.sit, now: now, duration: Double.random(in: 2.5...6, using: &generator))
        case .blink: return still(.blink, now: now, duration: Self.blinkDuration)
        case .lick: return still(.lick, now: now, duration: Self.lickDuration)
        case .yawn: return still(.yawn, now: now, duration: Self.yawnDuration)
        case .sleep:
            // A nap is short; sleeping through the user's absence goes on in chunks, which a host sees as one sleep.
            let asleepForGood = senses.idleSeconds >= tuning.sleepThreshold(hour: senses.hour)
            return still(.sleep, now: now, duration: asleepForGood ? Self.sleepChunk : Double.random(in: 25...50, using: &generator))
        case .startled: return still(.startled, now: now, duration: Self.startleDuration)
        case .dance: return still(.dance, now: now, duration: Self.danceChunk)
        case .purr: return still(.purr, now: now, duration: Self.purrDuration)
        }
    }

    /// `pose` where the cat is, facing the way it faced.
    private func still(_ pose: CatPose, now: TimeInterval, duration: TimeInterval) -> CatPlan {
        let here = plan.position(at: now)
        return CatPlan(pose: pose, facing: plan.facing, from: here, to: here, began: now, duration: duration)
    }

    /// A few steps one way or the other, turning round at the ends of the lane.
    private mutating func wander(now: TimeInterval, travel: Double) -> CatPlan {
        let here = plan.position(at: now)
        guard travel >= 1 else { return still(.sit, now: now, duration: Double.random(in: 2.5...6, using: &generator)) }
        var toTheRight = here <= 0.05 ? true : here >= 0.95 ? false : chance(0.5)
        let distance = Double.random(in: 14...44, using: &generator)
        func target() -> Double { toTheRight ? min(here + distance / travel, 1) : max(here - distance / travel, 0) }
        var to = target()
        // Too little room that way: turn round.
        if abs(to - here) * travel < 6 {
            toTheRight.toggle()
            to = target()
        }
        // A walk that would go into the blind stretch goes across it instead, the whole way, and quickly.
        if let blind, blind.meets(from: here, to: to) {
            return dash(to: toTheRight ? blind.high : blind.low, now: now, travel: travel)
        }
        let covered = abs(to - here) * travel
        guard covered >= 1 else { return still(.sit, now: now, duration: Double.random(in: 2.5...6, using: &generator)) }
        return CatPlan(
            pose: .walk, facing: to > here ? .right : .left, from: here, to: to, began: now, duration: covered / Self.walkSpeed
        )
    }

    /// Across the lane to the end that is farther off, harder the busier the processors are. A lane too short to run along has the cat
    /// run on the spot, as a runner on a treadmill does.
    private func run(now: TimeInterval, load: Double, travel: Double) -> CatPlan {
        let here = plan.position(at: now)
        let strength = min(max((load - Self.runOn) / (1 - Self.runOn), 0), 1)
        let to = here < 0.5 ? 1.0 : 0.0
        let covered = abs(to - here) * max(travel, 0)
        let speed = Self.runSpeed + Self.runBoost * strength
        let moves = covered >= 1
        return CatPlan(
            pose: .run, facing: moves ? (to > here ? .right : .left) : plan.facing, from: here, to: moves ? to : here, began: now,
            duration: max(covered / speed, Self.shortestRun), fpsScale: 1 + Self.runFrameBoost * strength
        )
    }

    private func outcome(since before: CatPlan) -> Outcome {
        if plan == before { return .unchanged }
        return plan.looksLike(before) ? .extended : .changed
    }
}
