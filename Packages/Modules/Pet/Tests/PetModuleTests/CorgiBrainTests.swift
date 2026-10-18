import Foundation
import Testing
@testable import PetModule

/// The corgi's brain driven by a clock the test holds: it is woken every quarter of a second, as the stage wakes it, with what it senses.
struct CorDrive {
    var brain: CorgiBrain
    var now: TimeInterval = 0
    var senses = CatSenses()
    var tuning = CatTuning()
    /// How far the corgi can walk, in pixels of its picture.
    var travel = 260.0
    var lane = LaneContext()

    /// Every pose that changed the picture, with the time it began.
    private(set) var history: [(at: TimeInterval, pose: Pose)] = []
    /// Every pose there was, extended or changed.
    private(set) var every: [Pose] = []
    private(set) var scenes: [CorgiScene] = []
    private(set) var spent: [CorgiMove: TimeInterval] = [:]
    private var serial = 0
    static let step = 0.25

    init(seed: UInt64 = 1, position: Double = 0.5, senses: CatSenses = CatSenses(), tuning: CatTuning = CatTuning(), travel: Double = 260) {
        brain = CorgiBrain(seed: seed, now: 0, position: position)
        self.senses = senses
        self.tuning = tuning
        self.travel = travel
    }

    var move: CorgiMove { brain.move }

    @discardableResult
    mutating func run(_ seconds: Double, each: (CorgiBrain) -> Void = { _ in }) -> BrainOutcome {
        var last = BrainOutcome.unchanged
        let end = now + seconds
        while now < end - 1e-9 {
            now += Self.step
            let outcome = brain.update(now: now, senses: senses, tuning: tuning, travel: travel, lane: lane)
            record(outcome)
            if outcome != .unchanged { last = outcome }
            if brain.sceneSerial != serial {
                serial = brain.sceneSerial
                if let scene = brain.scene { scenes.append(scene) }
            }
            spent[brain.move, default: 0] += Self.step
            each(brain)
        }
        return last
    }

    private mutating func record(_ outcome: BrainOutcome) {
        if outcome == .changed { history.append((now, brain.pose)) }
        if outcome != .unchanged { every.append(brain.pose) }
    }

    mutating func pet() {
        record(brain.pet(now: now))
    }

    mutating func resume() {
        brain.resume(now: now)
        history.append((now, brain.pose))
        every.append(brain.pose)
    }

    var moves: [CorgiMove] { history.map { CorgiMove($0.pose.motion) } }

    func share(of move: CorgiMove) -> Double {
        let total = spent.values.reduce(0, +)
        return total == 0 ? 0 : (spent[move] ?? 0) / total
    }

    /// What it has out, one entry for each picture it changed to.
    var trail: [(move: CorgiMove, prop: CorgiProp?)] {
        history.map { (CorgiMove($0.pose.motion), $0.pose.prop.map { CorgiProp($0.look) }) }
    }

    static func pointer(_ share: Double, near: Bool) -> PointerReading {
        PointerReading(share: share, isNear: near, isInRange: true)
    }

    /// The moves it has the ball in its mouth in.
    static let holding: Set<CorgiMove> = [.grab, .carry, .lower]
    /// The moves with nothing about them that has a ball out.
    static let withoutABall: Set<CorgiMove> = [.trot, .sitDown, .standUp, .sit, .begUp, .beg, .begDown, .lieDown, .getUp, .lie, .settle, .wake, .sleep]
}

/// What a corgi is allowed to have out after what it had out: a ball falls in (under a corgi that watches it), lies (while the corgi runs to
/// it, or wiggles over it, or spins for joy over it), is taken up in its mouth (and is then a picture with nothing in it, which holds the room
/// it will be set down in, while it grabs it, trots with it and puts its head down), is set down (under a wiggling corgi that has just put its
/// head down), lies, and is taken up (under a corgi that watches it go), and then nothing; it is never left behind and never goes without
/// going; and a corgi that sits, lies, sleeps or begs has none.
func corgiPropProblems(_ trail: [(move: CorgiMove, prop: CorgiProp?)]) -> [String] {
    var problems: [String] = []
    for (index, entry) in trail.enumerated() {
        let previous = index > 0 ? trail[index - 1] : nil
        if CorDrive.withoutABall.contains(entry.move), entry.prop != nil { problems.append("\(index): a ball by a corgi that is \(entry.move)") }
        if CorDrive.holding.contains(entry.move), entry.prop != .ballHeld { problems.append("\(index): not holding the ball it has in its mouth: \(entry.move) with \(String(describing: entry.prop))") }
        switch entry.prop {
        case .ballToss?:
            if entry.move != .watch { problems.append("\(index): the ball falls in under a \(entry.move)") }
            if previous?.prop != nil { problems.append("\(index): a ball falls in while there is one") }
        case .ballUp?:
            if entry.move != .watch { problems.append("\(index): the ball is taken up under a \(entry.move)") }
            if ![.ballRest, .ballDrop, .ballToss].contains(previous?.prop) { problems.append("\(index): taken up from \(String(describing: previous?.prop))") }
        case .ballDrop?:
            if entry.move != .wiggle || previous?.move != .lower { problems.append("\(index): set down under a \(entry.move) after \(String(describing: previous?.move))") }
        case .ballRest?:
            if ![.run, .wiggle, .stand, .blink, .spin].contains(entry.move) { problems.append("\(index): a ball lies by a corgi that is \(entry.move)") }
            if ![.ballToss, .ballRest, .ballDrop].contains(previous?.prop) { problems.append("\(index): a ball lies with no beginning: after \(String(describing: previous?.prop))") }
        case .ballHeld?:
            if !CorDrive.holding.contains(entry.move) { problems.append("\(index): the ball is in its mouth in a \(entry.move)") }
            if ![.ballRest, .ballHeld].contains(previous?.prop) { problems.append("\(index): taken up from \(String(describing: previous?.prop))") }
            if previous?.prop == .ballRest, entry.move != .grab { problems.append("\(index): taken up by \(entry.move)") }
        case nil:
            if let before = previous?.prop, before != .ballUp { problems.append("\(index): the \(before) ball is gone with no taking up (\(entry.move))") }
        }
        if entry.move == .run, let prop = entry.prop, prop != .ballRest { problems.append("\(index): running with \(prop)") }
    }
    return problems
}

@Suite struct CorgiBrainSceneTests {
    @Test func theSameSeedMakesTheSameDayAndAnotherSeedAnotherOne() {
        func day(seed: UInt64) -> [CorgiMove] {
            var drive = CorDrive(seed: seed)
            drive.run(900)
            return drive.moves
        }
        #expect(day(seed: 3) == day(seed: 3))
        #expect(day(seed: 3) != day(seed: 4))
    }

    @Test func itNeverBeginsTheSameSceneTwiceRunning() {
        for hour in [14, 23] {
            for seed in 1...12 as ClosedRange<UInt64> {
                var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: hour))
                drive.run(3600)
                #expect(drive.scenes.count > 40, "\(drive.scenes.count)")
                for (before, after) in zip(drive.scenes, drive.scenes.dropFirst()) { #expect(before != after, "seed \(seed) at \(hour): \(before) twice") }
            }
        }
    }

    @Test func everySceneComesUpAtNightItNapsMoreAndFetchesLessAndTheSleepTimeIsShorterThen() {
        var counts: [CorgiScene: Int] = [:]
        var day = 0.0, night = 0.0
        var fetches = (day: 0, night: 0)
        for seed in 1...8 as ClosedRange<UInt64> {
            var daytime = CorgiDrive.day(seed: seed, hour: 14)
            daytime.run(3 * 3600)
            var overnight = CorgiDrive.day(seed: seed, hour: 23)
            overnight.run(3 * 3600)
            for scene in daytime.scenes { counts[scene, default: 0] += 1 }
            fetches.day += daytime.scenes.filter { $0 == .fetch }.count
            fetches.night += overnight.scenes.filter { $0 == .fetch }.count
            day += [CorgiMove.sleep, .lie].reduce(0) { $0 + daytime.share(of: $1) }
            night += [CorgiMove.sleep, .lie].reduce(0) { $0 + overnight.share(of: $1) }
        }
        #expect(Set(counts.keys) == Set(CorgiScene.allCases), "\(Set(CorgiScene.allCases).subtracting(counts.keys))")
        #expect(night > day * 1.2, "more lying down and sleeping at night: \(night / 8) against \(day / 8)")
        #expect(fetches.day > fetches.night, "more fetching by day: \(fetches)")
        // The same idle time that is not enough by day is by night: the threshold is shorter then.
        var byDay = CorDrive(seed: 2, senses: CatSenses(idleSeconds: 120, hour: 14))
        var byNight = CorDrive(seed: 2, senses: CatSenses(idleSeconds: 120, hour: 23))
        byDay.run(300)
        byNight.run(300)
        // (A nap on its side is a scene of the day too, and is shorter than a sleep that goes on until the user is back.)
        func slept(_ drive: CorDrive) -> Int { drive.every.filter { CorgiMove($0.motion) == .sleep && $0.duration == CorgiBrain.sleepChunk }.count }
        #expect(slept(byDay) == 0 && slept(byNight) > 5, "\(slept(byDay)) by day, \(slept(byNight)) by night")
    }

    // MARK: Trotting and running

    @Test func aTrotAndTheTrotHomeWithTheBallAreTheSamePaceAndARunIsTheRunsAtAnyLoadAndNothingIsQuickenedForTheMac() {
        for load in [0.05, 0.5, 0.9, 1.0] {
            for burst in [false, true] {
                for seed in 1...4 as ClosedRange<UInt64> {
                    var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: load, busyBurst: burst, hour: 14))
                    drive.run(2 * 3600)
                    var kinds: Set<CorgiMove> = []
                    for pose in drive.every where pose.from != pose.to {
                        let move = CorgiMove(pose.motion)
                        let speed = abs(pose.to - pose.from) * drive.travel / pose.duration
                        kinds.insert(move)
                        #expect([CorgiMove.trot, .run, .carry].contains(move), "\(move) goes somewhere")
                        #expect(abs(speed - move.speed) < 1e-6, "\(move) at \(speed) points a second, not \(move.speed)")
                        #expect(pose.fpsScale == 1 && pose.delay == 0, "no quickening: \(move)")
                        #expect(speed <= CorgiMove.run.speed + 1e-6, "nothing is quicker than the run")
                    }
                    #expect(kinds == [.trot, .run, .carry], "load \(load) burst \(burst) seed \(seed): \(kinds)")
                }
            }
        }
    }

    @Test func theBusierTheMacTheMoreItRunsAboutForJoyAndABurstOfWorkSendsItOffAtOnceAndWithTheReactionOffNothingChanges() {
        func zoomies(load: Double, burst: Bool = false, reacts: Bool = true) -> (scenes: Double, time: Double, legs: Double) {
            var scenes = 0, all = 0, legs = 0
            var time = 0.0
            for seed in 1...8 as ClosedRange<UInt64> {
                var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: load, busyBurst: burst, hour: 14))
                drive.tuning.reactsToBusyMachine = reacts
                drive.run(3 * 3600)
                scenes += drive.scenes.filter { $0 == .zoomies }.count
                all += drive.scenes.count
                time += drive.share(of: .run)
                legs += drive.history.filter { CorgiMove($0.pose.motion) == .run && $0.pose.from != $0.pose.to && $0.pose.prop == nil }.count
            }
            return (Double(scenes) / Double(all), time / 8, Double(legs) / Double(max(scenes, 1)))
        }
        let (quiet, edge, busy, flat) = (zoomies(load: 0.05), zoomies(load: 0.6), zoomies(load: 0.8), zoomies(load: 1.0))
        #expect(quiet.scenes > 0.06 && quiet.scenes < 0.2, "a part of its day, quiet: \(quiet)")
        #expect(abs(edge.scenes - quiet.scenes) < 0.03, "the line is where it starts: \(edge) against \(quiet)")
        #expect(busy.scenes > quiet.scenes * 1.8 && flat.scenes > busy.scenes, "more of them the busier it is: \(quiet.scenes), \(busy.scenes), \(flat.scenes)")
        #expect(flat.scenes > 0.3 && flat.time > quiet.time * 1.8, "and more of its time: \(quiet.time) against \(flat.time)")
        #expect(flat.legs > quiet.legs * 1.4, "and longer: \(quiet.legs) legs against \(flat.legs)")
        let bursting = zoomies(load: 0.05, burst: true)
        #expect(bursting.scenes > quiet.scenes * 1.5, "a burst counts as a busy Mac: \(bursting) against \(quiet)")
        let off = zoomies(load: 1.0, burst: true, reacts: false)
        #expect(abs(off.scenes - quiet.scenes) < 1e-9 && abs(off.time - quiet.time) < 1e-9, "with the reaction off a busy Mac is a quiet one")
        var calm = CorDrive(seed: 3, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.05, hour: 14))
        var same = CorDrive(seed: 3, senses: CatSenses(idleSeconds: 5, cpuLoad: 1, busyBurst: true, hour: 14))
        same.tuning.reactsToBusyMachine = false
        calm.run(3600)
        same.run(3600)
        #expect(calm.moves == same.moves && calm.history.map(\.pose) == same.history.map(\.pose), "with the reaction off a busy Mac changes nothing")
    }

    @Test func aBurstOfWorkSendsItOffToRunAboutAtOnceAndOnlyOnceForTheBurst() {
        var checked = 0
        for seed in 1...40 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(40 + Double(seed) * 3)
            guard drive.brain.stance == .standing, drive.brain.scene != .zoomies, !drive.brain.hasProps, !CorgiBrain.unbroken.contains(drive.move) else { continue }
            let scenes = drive.scenes.count
            drive.senses.busyBurst = true
            drive.run(0.25)
            #expect(drive.brain.scene == .zoomies && drive.scenes.count == scenes + 1, "seed \(seed): \(String(describing: drive.brain.scene))")
            #expect(drive.move == .run, "and it is off: \(drive.move)")
            // The burst goes on for forty seconds: it did not go off again and again for it.
            drive.run(40)
            #expect(drive.scenes.count <= scenes + 6, "seed \(seed): \(drive.scenes.count - scenes) scenes in the burst")
            checked += 1
            // A burst is heard of once, so another one is heard of again.
            drive.senses.busyBurst = false
            drive.run(60)
            // (Not while it is in the zoomies already, which a burst is not heard of in.)
            guard drive.brain.scene != .zoomies, drive.brain.stance != .asleep else { continue }
            drive.senses.busyBurst = true
            drive.run(2)
            #expect(drive.brain.scene == .zoomies || drive.brain.stance == .asleep, "seed \(seed): the next burst: \(String(describing: drive.brain.scene))")
            #expect(corgiPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        #expect(checked >= 8, "\(checked)")
    }

    @Test func theZoomiesGoBackAndForthFastWithAWiggleAtTheEndAndKeepToOneSideOfTheCamera() {
        var scenes = 0, legs = 0, opposite = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, position: 0.2, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 200)
            drive.lane = LaneContext(crossing: [0.45...0.55])
            drive.run(3 * 3600)
            let poses = drive.history.map(\.pose)
            var index = 0
            while index < poses.count {
                guard CorgiMove(poses[index].motion) == .run, poses[index].prop == nil, poses[index].from != poses[index].to else {
                    index += 1
                    continue
                }
                var runs: [Pose] = []
                while index < poses.count, CorgiMove(poses[index].motion) == .run, poses[index].prop == nil {
                    runs.append(poses[index])
                    index += 1
                }
                guard runs.count >= 2 else { continue }
                scenes += 1
                for pose in runs {
                    legs += 1
                    #expect(max(pose.from, pose.to) <= 0.45 + 1e-9 || min(pose.from, pose.to) >= 0.55 - 1e-9, "a run through the camera: \(pose.from) to \(pose.to)")
                    #expect((pose.to > pose.from) == (pose.facing == .right), "it faces the way it runs")
                }
                for (a, b) in zip(runs, runs.dropFirst()) where (a.to > a.from) != (b.to > b.from) { opposite += 1 }
                // (Unless the hours ended in the middle of it.)
                if index < poses.count { #expect([.wiggle, .stand].contains(CorgiMove(poses[index].motion)), "it ends with a wiggle: \(CorgiMove(poses[index].motion))") }
            }
        }
        #expect(scenes > 20 && legs > 60, "\(scenes) scenes, \(legs) legs")
        // On a lane with the camera in the middle, a run stays on its side, so it does not always go back: but mostly it does.
        #expect(Double(opposite) / Double(max(legs - scenes, 1)) > 0.5, "\(opposite) of \(legs - scenes) turned round")
    }

    // MARK: The camera

    @Test func itNeverStopsInTheCrossingOrInTheWayOfAnotherAndOnlyATrotGoesThroughTheCrossingAndNothingGoesIntoWhatIsClosed() {
        let crossing: ClosedRange<Double> = 0.4...0.6
        var through = 0, others = 0
        for load in [0.05, 0.9] {
            for seed in 1...8 as ClosedRange<UInt64> {
                var drive = CorDrive(seed: seed, position: 0.2, senses: CatSenses(idleSeconds: 5, cpuLoad: load, hour: 14), travel: 156)
                drive.lane = LaneContext(crossing: [crossing], zones: [0.8...0.95])
                drive.run(3 * 3600)
                for pose in drive.every {
                    let move = CorgiMove(pose.motion)
                    if pose.from == pose.to {
                        #expect(!(crossing.lowerBound + 1e-9..<crossing.upperBound - 1e-9).contains(pose.to), "seed \(seed): a \(move) at \(pose.to)")
                        #expect(!(0.8 + 1e-9..<0.95 - 1e-9).contains(pose.to), "in the way of another at \(pose.to)")
                    }
                    let (low, high) = (min(pose.from, pose.to), max(pose.from, pose.to))
                    if high > crossing.lowerBound && low < crossing.upperBound {
                        through += 1
                        #expect(move == .trot, "seed \(seed): a \(move) goes through the crossing, from \(pose.from) to \(pose.to)")
                    } else if pose.from != pose.to {
                        others += 1
                    }
                    if let prop = pose.prop {
                        for place in [prop.from, prop.to] + prop.alsoAt {
                            #expect(!(crossing.lowerBound + 1e-9..<crossing.upperBound - 1e-9).contains(place), "a ball in the camera at \(place)")
                            #expect(!(0.8 + 1e-9..<0.95 - 1e-9).contains(place), "a ball in the way of another at \(place)")
                        }
                    }
                }
                #expect(corgiPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
            }
        }
        #expect(through >= 20 && others > 200, "it went through the camera at a trot \(through) times, and went about on one side \(others) legs")
        var closed = CorDrive(seed: 3, position: 0.2, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 156)
        closed.lane = LaneContext(crossing: [crossing], closed: [crossing])
        closed.run(2 * 3600)
        for pose in closed.every { #expect(max(pose.from, pose.to) <= crossing.lowerBound + 1e-9, "it keeps out of the closed crossing: \(pose.from) to \(pose.to)") }
    }

    @Test func aRunNeverGoesThroughTheCrossingEvenWhenItIsTheOnlyWayItCouldGoAndTheTrotToTheFarEndDoes() {
        var crossings = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, position: 0.1, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 200)
            drive.lane = LaneContext(crossing: [0.25...0.75])
            drive.run(3 * 3600)
            let stands = drive.every.filter { $0.from == $0.to }.map(\.to)
            #expect(stands.contains { $0 < 0.25 } && stands.contains { $0 > 0.75 }, "it is on both sides now and then")
            for pose in drive.every where pose.from != pose.to && min(pose.from, pose.to) < 0.75 && max(pose.from, pose.to) > 0.25 {
                crossings += 1
                #expect(CorgiMove(pose.motion) == .trot)
            }
        }
        #expect(crossings >= 6, "\(crossings)")
    }

    // MARK: The ball

    @Test func whatItHasOutStartsAndEndsInOrderThroughHoursOfDaysAndMacs() {
        var seen: Set<CorgiProp> = []
        for load in [0.03, 0.5, 0.9] {
            for hour in [14, 23] {
                for seed in 1...6 as ClosedRange<UInt64> {
                    var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: load, hour: hour))
                    drive.run(3 * 3600)
                    #expect(corgiPropProblems(drive.trail).isEmpty, "seed \(seed) at \(hour), load \(load): \(corgiPropProblems(drive.trail).prefix(4))")
                    #expect(drive.brain.strayProps == 0, "nothing left over when a scene began")
                    seen.formUnion(drive.trail.compactMap(\.prop))
                }
            }
        }
        #expect(seen == Set(CorgiProp.allCases), "\(Set(CorgiProp.allCases).subtracting(seen))")
    }

    /// The fetching scenes cut out of a run: every pose from the ball falling in to the ball being taken up, with the poses of each.
    func rounds(_ drive: CorDrive) -> [[Pose]] {
        var found: [[Pose]] = []
        var current: [Pose]?
        for entry in drive.history.map(\.pose) {
            let prop = entry.prop.map { CorgiProp($0.look) }
            if prop == .ballToss { current = [entry] } else if current != nil { current?.append(entry) }
            if prop == .ballUp, let finished = current {
                found.append(finished)
                current = nil
            }
        }
        return found
    }

    @Test func aRoundOfFetchIsTheBallFallingWatchingItRunningAfterItTakingItUpTrottingBackSettingItDownAndItBeingTakenUp() throws {
        var rounds = 0
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 300)
            drive.run(3 * 3600)
            for round in self.rounds(drive) {
                rounds += 1
                let moves = round.map { CorgiMove($0.motion) }
                #expect(Array(moves.prefix(5)) == [.watch, .run, .grab, .carry, .lower], "\(moves)")
                #expect(Array(moves.suffix(2)) == [.wiggle, .watch] || Array(moves.suffix(3)) == [.wiggle, .wiggle, .watch], "\(moves)")
                let (toss, chase, grab, carry, lower) = (round[0], round[1], round[2], round[3], round[4])
                let drop = round[5]
                let ball = try #require(toss.prop)
                let way = toss.facing == .right ? 1.0 : -1.0
                let home = toss.from
                #expect(toss.from == toss.to && toss.duration == CorgiProp.ballToss.passDuration, "it stands and watches for as long as the ball takes")
                #expect(abs(ball.from - (home + way * CorgiBrain.tossStart / 300)) < 1e-9, "the ball falls in a little way in front of its nose")
                let rolled = (ball.to - home) * way * 300
                #expect(CorgiBrain.tossRoll.contains(rolled) || CorgiBrain.shorterRolls.contains { abs(rolled - $0) < 1e-6 }, "and rolls \(rolled) pixels")
                #expect(ball.alsoAt.count == 2 && ball.alsoAt[0] == home && abs(ball.alsoAt[1] - (home - way * CorgiMove.ballReach / 300)) < 1e-9 && ball.look.occupies,
                        "the place it stands and the place the ball is set down are reserved with the ball")
                // The run: from where it stood to where its nose is over the ball, facing the ball, with the ball lying.
                let there = ball.to - way * CorgiMove.ballReach / 300
                #expect(chase.from == home && abs(chase.to - there) < 1e-9 && chase.facing == toss.facing, "it runs to the ball")
                #expect(chase.prop?.from == ball.to && chase.prop?.to == ball.to && chase.prop.map { CorgiProp($0.look) } == .ballRest)
                // Takes it up where it is; the ball is in its mouth (and so is on no picture of its own), and it trots back to where it began.
                #expect(grab.from == grab.to && abs(grab.to - chase.to) < 1e-9)
                #expect(abs(carry.from - grab.to) < 1e-9 && abs(carry.to - home) < 1e-9, "back to where it began: \(carry.to) and \(home)")
                #expect((carry.to > carry.from) == (carry.facing == .right) && carry.facing != toss.facing)
                #expect(lower.from == lower.to && abs(lower.to - home) < 1e-9)
                // What it has in its mouth is a picture with nothing in it, which holds the room it is set down in.
                for pose in [grab, carry, lower] {
                    let held = try #require(pose.prop)
                    #expect(CorgiProp(held.look) == .ballHeld && held.from == held.to && held.alsoAt == ball.alsoAt && abs(held.to - ball.alsoAt[1]) < 1e-9, "\(CorgiMove(pose.motion))")
                }
                // It sets it down in front of its nose, where the ball's own picture has it.
                let down = try #require(drop.prop)
                #expect(CorgiProp(down.look) == .ballDrop && abs(down.from - (home - way * CorgiMove.ballReach / 300)) < 1e-9 && down.from == down.to, "set down in front of its nose")
                #expect(drop.duration == CorgiProp.ballDrop.passDuration && down.alsoAt == ball.alsoAt)
                let last = try #require(round.last?.prop)
                #expect(CorgiProp(last.look) == .ballUp && last.from == down.from && round.last?.duration == CorgiProp.ballUp.passDuration)
                for pose in round { #expect(pose.prop.map { (0.0...1.0).contains($0.from) && (0.0...1.0).contains($0.to) } ?? true, "the ball is on the lane") }
            }
        }
        #expect(rounds > 25, "\(rounds)")
    }

    @Test func aFetchSceneIsOneRoundOrNowAndThenTwoAndTheBallIsTakenUpBeforeTheNextSceneBegins() {
        var scenes = 0, double = 0
        for seed in 1...12 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(3 * 3600)
            var inScene = 0
            var count = 0
            for entry in drive.trail {
                if entry.prop == .ballToss { count += 1 }
                if entry.prop == .ballUp { inScene += 1 }
            }
            scenes += drive.scenes.filter { $0 == .fetch }.count
            double += drive.trail.filter { $0.prop == .ballToss }.count
            // (The hours may end with the ball out, and then it is the one that has not been taken up.)
            #expect(count - inScene == (drive.brain.hasProps ? 1 : 0), "every ball that fell was taken up: \(count) against \(inScene)")
            #expect(drive.brain.strayProps == 0)
        }
        #expect(scenes > 25 && double > scenes, "\(scenes) scenes, \(double) rounds: now and then it is thrown twice")
        #expect(double < scenes * 2 - scenes / 4, "and mostly not: \(scenes) scenes, \(double) rounds")
    }

    @Test func aLaneTooShortForTheBallHasNoneAndTheDayGoesOnAllTheSame() {
        var drive = CorDrive(seed: 5, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 8)
        drive.run(2 * 3600)
        #expect(drive.every.allSatisfy { $0.prop == nil }, "no ball: there is no room to throw one")
        #expect(drive.brain.strayProps == 0)
        #expect(drive.scenes.count > 100 && drive.moves.contains(.wiggle) && drive.moves.contains(.spin) == false)
        var none = CorDrive(seed: 5, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 0)
        none.run(3600)
        #expect(none.every.allSatisfy { $0.prop == nil && $0.from == $0.to }, "no lane at all: nothing to walk or play on")
    }

    @Test func itNeverHasTheBallWhereAnotherCharacterStandsOrWillStandAndTheNotStoppingZonesAreKept() {
        var checked = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, position: 0.1, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 300)
            drive.lane = LaneContext(crossing: [0.45...0.55], zones: [0.2...0.34, 0.8...0.9])
            drive.run(3 * 3600)
            for pose in drive.every {
                guard let prop = pose.prop else { continue }
                checked += 1
                for place in [prop.from, prop.to, pose.from, pose.to] {
                    #expect(!(0.45 + 1e-9..<0.55 - 1e-9).contains(place), "in the camera at \(place)")
                }
                for place in [prop.to] + (pose.from == pose.to ? [pose.to] : []) {
                    #expect(!(0.2 + 1e-9..<0.34 - 1e-9).contains(place) && !(0.8 + 1e-9..<0.9 - 1e-9).contains(place), "in the way of another at \(place)")
                }
            }
            #expect(corgiPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        #expect(checked > 150, "\(checked)")
    }

    @Test func itHasNoBackToSitOnAndTakesPartInNoSceneWithAnother() {
        var drive = CorDrive(seed: 2, senses: CatSenses(idleSeconds: 5, hour: 14))
        drive.run(2 * 3600)
        for pose in drive.every { #expect(pose.perch == nil && !pose.raised) }
        #expect(drive.brain.jointScene == nil)
        let guest = JointInvite(scene: .catOnCapybara, role: .guest, partner: drive.brain.pose)
        #expect(!drive.brain.canJoin(guest, now: drive.now))
    }
}

/// A driver for a day of a given hour.
enum CorgiDrive {
    static func day(seed: UInt64, hour: Int) -> CorDrive { CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: hour)) }
}
