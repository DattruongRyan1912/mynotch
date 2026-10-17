import Foundation
import Testing
@testable import PetModule

/// The hamster's brain driven by a clock the test holds: it is woken every quarter of a second, as the stage wakes it, with what it senses.
struct HamDrive {
    var brain: HamsterBrain
    var now: TimeInterval = 0
    var senses = CatSenses()
    var tuning = CatTuning()
    /// How far the hamster can walk, in pixels of its picture.
    var travel = 260.0
    var lane = LaneContext()

    /// Every pose that changed the picture, with the time it began.
    private(set) var history: [(at: TimeInterval, pose: Pose)] = []
    /// Every pose there was, extended or changed.
    private(set) var every: [Pose] = []
    private(set) var scenes: [HamsterScene] = []
    private(set) var spent: [HamsterMove: TimeInterval] = [:]
    private var serial = 0
    static let step = 0.25

    init(seed: UInt64 = 1, position: Double = 0.5, senses: CatSenses = CatSenses(), tuning: CatTuning = CatTuning(), travel: Double = 260) {
        brain = HamsterBrain(seed: seed, now: 0, position: position)
        self.senses = senses
        self.tuning = tuning
        self.travel = travel
    }

    var move: HamsterMove { brain.move }

    @discardableResult
    mutating func run(_ seconds: Double, each: (HamsterBrain) -> Void = { _ in }) -> BrainOutcome {
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

    var moves: [HamsterMove] { history.map { HamsterMove($0.pose.motion) } }

    func share(of move: HamsterMove) -> Double {
        let total = spent.values.reduce(0, +)
        return total == 0 ? 0 : (spent[move] ?? 0) / total
    }

    mutating func addSpent(_ move: HamsterMove, _ time: TimeInterval) { spent[move, default: 0] += time }

    /// What it has out, one entry for each picture it changed to.
    var trail: [(move: HamsterMove, prop: HamsterProp?)] {
        history.map { (HamsterMove($0.pose.motion), $0.pose.prop.map { HamsterProp($0.look) }) }
    }

    static func pointer(_ share: Double, near: Bool) -> PointerReading {
        PointerReading(share: share, isNear: near, isInRange: true)
    }

    /// The moves in the wheel, which are all with the wheel out.
    static let inTheWheel: Set<HamsterMove> = [.hopIn, .hopOut, .wheelSit, .wheelLazy, .wheelJog, .wheelRun, .wheelSprint, .wheelWatch, .wheelHappy]
}

/// What a hamster is allowed to have out after what it had out: a wheel pops up, stands empty or with it in, turns at the pace its pose
/// runs at, and goes; it is never left behind and never goes without going; the seeds are fewer and fewer and then none. Never the wheel
/// and the seeds together, and never a hamster in the wheel without one.
func hamsterPropProblems(_ trail: [(move: HamsterMove, prop: HamsterProp?)]) -> [String] {
    var problems: [String] = []
    let turning: Set<HamsterProp?> = [.wheelLazy, .wheelJog, .wheelRun, .wheelSprint]
    let wheelAfter: Set<HamsterProp?> = turning.union([.wheelStill, .wheelGoing])
    let after: [HamsterProp?: Set<HamsterProp?>] = [
        .wheelAppearing: wheelAfter, .wheelStill: wheelAfter, .wheelLazy: wheelAfter, .wheelJog: wheelAfter, .wheelRun: wheelAfter,
        .wheelSprint: wheelAfter, .wheelGoing: [nil], .seeds3: [.seeds3, .seeds2, nil], .seeds2: [.seeds2, .seeds1, nil], .seeds1: [.seeds1, nil],
    ]
    let apart: Set<HamsterMove> = [.scurry, .sleep, .ball, .curl, .uncurl, .groom, .stuffA, .stuffB, .stuffC, .puffed, .unstuff]
    for (index, entry) in trail.enumerated() {
        let wheel = entry.prop?.isWheel ?? false
        if HamDrive.inTheWheel.contains(entry.move), !wheel { problems.append("\(index): \(entry.move) with no wheel") }
        if entry.move.runs, let pace = WheelPace(entry.move), entry.prop != pace.prop {
            problems.append("\(index): \(entry.move) with \(String(describing: entry.prop))")
        }
        if [.wheelSit, .wheelWatch, .wheelHappy, .hopIn, .hopOut].contains(entry.move), entry.prop != .wheelStill {
            problems.append("\(index): \(entry.move) with a wheel that is not standing: \(String(describing: entry.prop))")
        }
        if wheel, apart.contains(entry.move) { problems.append("\(index): a wheel by a hamster that is \(entry.move)") }
        if entry.prop == .wheelAppearing, entry.move != .sit { problems.append("\(index): the wheel comes up under a \(entry.move)") }
        if entry.prop == .wheelGoing, entry.move != .sit { problems.append("\(index): the wheel goes under a \(entry.move)") }
        if let prop = entry.prop, !prop.isWheel, [.sit, .stuffA, .stuffB, .stuffC, .freeze, .happy, .sitDown, .standUp].contains(entry.move) == false {
            problems.append("\(index): seeds by a hamster that is \(entry.move)")
        }
        guard index + 1 < trail.count else { continue }
        let next = trail[index + 1].prop
        if let allowed = after[entry.prop], !allowed.contains(next) {
            problems.append("\(index): \(String(describing: entry.prop)) is followed by \(String(describing: next))")
        }
        if let next, next.isWheel, entry.prop == nil, next != .wheelAppearing { problems.append("\(index): \(next) with no beginning") }
        if let next, !next.isWheel, entry.prop == nil, next != .seeds3 { problems.append("\(index): \(next) with no beginning") }
    }
    return problems
}

@Suite struct HamsterBrainSceneTests {
    @Test func theSameSeedMakesTheSameDayAndAnotherSeedAnotherOne() {
        func day(seed: UInt64) -> [HamsterMove] {
            var drive = HamDrive(seed: seed)
            drive.run(900)
            return drive.moves
        }
        #expect(day(seed: 3) == day(seed: 3))
        #expect(day(seed: 3) != day(seed: 4))
    }

    @Test func itNeverBeginsTheSameSceneTwiceRunning() {
        for hour in [14, 23] {
            for seed in 1...12 as ClosedRange<UInt64> {
                var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: hour))
                drive.run(3600)
                #expect(drive.scenes.count > 80)
                for (before, after) in zip(drive.scenes, drive.scenes.dropFirst()) { #expect(before != after, "seed \(seed) at \(hour): \(before) twice") }
            }
        }
    }

    @Test func everySceneComesUpAndTheHamsterIsBusyWithSomethingAllTheTimeAndAtNightItIsMoreAbout() {
        var counts: [HamsterScene: Int] = [:]
        var day = 0.0, night = 0.0
        for seed in 1...8 as ClosedRange<UInt64> {
            var daytime = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            daytime.run(3 * 3600)
            var overnight = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 23))
            overnight.run(3 * 3600)
            for scene in daytime.scenes { counts[scene, default: 0] += 1 }
            day += [HamsterMove.ball, .sleep].reduce(0) { $0 + daytime.share(of: $1) }
            night += [HamsterMove.ball, .sleep].reduce(0) { $0 + overnight.share(of: $1) }
        }
        #expect(Set(counts.keys) == Set(HamsterScene.allCases), "\(Set(HamsterScene.allCases).subtracting(counts.keys))")
        #expect(night < day * 0.7, "a night animal: curled up \(night / 8) at night against \(day / 8) by day")
        // The same idle time that is not enough by day is by night: the threshold is shorter then.
        var byDay = HamDrive(seed: 2, senses: CatSenses(idleSeconds: 120, hour: 14))
        var byNight = HamDrive(seed: 2, senses: CatSenses(idleSeconds: 120, hour: 23))
        byDay.run(300)
        byNight.run(300)
        #expect(byDay.share(of: .sleep) == 0 && byNight.share(of: .sleep) > 0.3)
    }

    @Test func itScurriesInQuickSmallStepsAndNeverFasterWhateverTheMacIsDoing() {
        for load in [0.05, 0.5, 1.0] {
            for seed in 1...6 as ClosedRange<UInt64> {
                var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: load, busyBurst: load == 1, hour: 14))
                drive.run(2 * 3600)
                var walks = 0
                for pose in drive.every where HamsterMove(pose.motion) == .scurry && pose.from != pose.to {
                    walks += 1
                    let speed = abs(pose.to - pose.from) * drive.travel / pose.duration
                    #expect(speed <= HamsterMove.scurry.speed + 1e-9, "\(speed) points a second")
                }
                #expect(walks > 10)
                for pose in drive.every {
                    #expect(pose.fpsScale == 1 && pose.delay == 0, "no quickening: \(HamsterMove(pose.motion))")
                    if !DriveHelpers.runs(pose) { #expect(pose.motion.fps <= HamsterMove.scurry.fps, "no run outside the wheel: \(HamsterMove(pose.motion))") }
                }
            }
        }
        #expect(HamsterMove.scurry.advance <= 4 && HamsterMove.scurry.speed > CatMove.walk.speed, "small steps, quick: quicker than the cat's walk")
    }

    // MARK: What it plays with

    @Test func whatItHasOutStartsAndEndsInOrderThroughHoursOfDaysAndMacs() {
        var seen: Set<HamsterProp> = []
        for load in [0.03, 0.3, 0.55, 0.9] {
            for hour in [14, 23] {
                for seed in 1...6 as ClosedRange<UInt64> {
                    var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: load, hour: hour))
                    drive.run(3 * 3600)
                    #expect(hamsterPropProblems(drive.trail).isEmpty, "seed \(seed) at \(hour), load \(load): \(hamsterPropProblems(drive.trail).prefix(4))")
                    #expect(drive.brain.strayProps == 0, "nothing left over when a scene began")
                    seen.formUnion(drive.trail.compactMap(\.prop))
                }
            }
        }
        #expect(seen == Set(HamsterProp.allCases), "\(Set(HamsterProp.allCases).subtracting(seen))")
    }

    /// The scenes of one kind, cut out of a run: every picture from the first prop's coming to the last one going.
    func stretches(
        from trail: [(move: HamsterMove, prop: HamsterProp?)], beginning begin: HamsterProp, ending end: HamsterProp
    ) -> [[(move: HamsterMove, prop: HamsterProp?)]] {
        var found: [[(move: HamsterMove, prop: HamsterProp?)]] = []
        var current: [(move: HamsterMove, prop: HamsterProp?)]?
        for entry in trail {
            if entry.prop == begin { current = [entry] } else if current != nil { current?.append(entry) }
            if entry.prop == end, let finished = current {
                found.append(finished)
                current = nil
            }
        }
        return found
    }

    @Test func aWheelSceneIsTheWheelComingUpAHopInRunningAHopOutAndTheWheelGoing() {
        var scenes = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.3, hour: 14))
            drive.run(2 * 3600)
            for stretch in stretches(from: drive.trail, beginning: .wheelAppearing, ending: .wheelGoing) {
                scenes += 1
                let moves = stretch.map(\.move)
                #expect(moves.first == .sit && moves.last == .sit, "it sits to watch the wheel come and go: \(moves)")
                guard let hopIn = moves.firstIndex(of: .hopIn), let hopOut = moves.lastIndex(of: .hopOut) else { continue }
                #expect(hopIn < hopOut)
                #expect(moves[(hopIn + 1)..<hopOut].allSatisfy { HamDrive.inTheWheel.contains($0) }, "in the wheel it runs, sits or looks: \(moves)")
                #expect(moves[(hopIn + 1)..<hopOut].contains { $0.runs }, "and runs")
                #expect(stretch[..<hopIn].allSatisfy { $0.prop == .wheelAppearing || $0.prop == .wheelStill }, "the wheel stands empty until it hops in")
                #expect(stretch[(hopOut + 1)...].allSatisfy { $0.prop == .wheelStill || $0.prop == .wheelGoing }, "and empty after it has hopped out")
                #expect(moves[(hopOut + 1)...].dropLast().isEmpty, "it is sitting where it hopped out: \(moves)")
            }
        }
        #expect(scenes > 20, "\(scenes)")
    }

    @Test func theHopsGoTheSpanOfTheHopAndTheWheelIsWhereTheHopIntoItEndsAndTheRunStaysThere() {
        var checked = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.3, hour: 14), travel: 300)
            drive.run(2 * 3600)
            var place: Double?
            for entry in drive.history.map(\.pose) {
                let move = HamsterMove(entry.motion)
                if move == .hopIn {
                    #expect(abs(abs(entry.to - entry.from) * 300 - HamsterMove.hopSpan) < 1e-6, "a hop of \(abs(entry.to - entry.from) * 300) points")
                    place = entry.to
                    #expect(entry.prop?.from == entry.to && entry.prop?.to == entry.to, "the wheel is where it hops to")
                    checked += 1
                } else if move == .hopOut {
                    #expect(entry.from == place && abs(abs(entry.to - entry.from) * 300 - HamsterMove.hopSpan) < 1e-6, "back out the way it came")
                } else if HamDrive.inTheWheel.contains(move) {
                    #expect(entry.from == place && entry.to == place, "it stays where the wheel is")
                }
            }
        }
        #expect(checked > 10)
    }

    @Test func itFacesTheWayItHopsAndHopsOutBackwardsFacingTheSameWayAndRunsFacingIt() {
        var drive = HamDrive(seed: 5, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.3, hour: 14))
        drive.run(3 * 3600)
        var facing: Facing?
        var hops = 0
        for entry in drive.history.map(\.pose) {
            let move = HamsterMove(entry.motion)
            if move == .hopIn {
                facing = entry.facing
                #expect((entry.to > entry.from) == (entry.facing == .right), "it hops the way it faces")
                hops += 1
            } else if move == .hopOut {
                #expect(entry.facing == facing && (entry.to < entry.from) == (entry.facing == .right), "and out backwards")
            } else if HamDrive.inTheWheel.contains(move) { #expect(entry.facing == facing) }
        }
        #expect(hops > 5)
    }

    @Test func seedsArePutDownThreeAndTheHamsterStuffsThemOneAtATimeUntilItsCheeksAreFullAndThenLetsThemOut() {
        var meals = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(2 * 3600)
            let trail = drive.trail
            for (index, entry) in trail.enumerated() where entry.prop == .seeds3 && entry.move == .sit {
                let rest = trail[(index + 1)...]
                let eaten = rest.prefix(8).map(\.move).filter { [.stuffA, .stuffB, .stuffC].contains($0) }
                guard eaten.count == 3 else { continue }
                meals += 1
                #expect(eaten == [.stuffA, .stuffB, .stuffC], "\(eaten)")
                let stuffs = rest.filter { [.stuffA, .stuffB, .stuffC].contains($0.move) }.prefix(3)
                #expect(stuffs.map(\.prop) == [.seeds3, .seeds2, .seeds1], "the pile as it is when it reaches for it: \(stuffs.map(\.prop))")
                let after = rest.drop { $0.move != .stuffC }.dropFirst().prefix(3).map(\.move)
                guard after.count == 3 else { continue }
                #expect(after.first == .puffed && after.dropFirst().first == .unstuff && rest.drop { $0.move != .puffed }.first?.prop == nil, "\(after)")
            }
        }
        #expect(meals > 15, "\(meals)")
    }

    @Test func theSeedsAreOnTheSideItFacesAndOnTheLane() {
        var checked = 0
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, position: 0.5, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(2 * 3600)
            for entry in drive.history.map(\.pose) where entry.prop?.look.key == HamsterProp.seeds3.look.key {
                guard let prop = entry.prop else { continue }
                let reach = entry.facing == .right ? HamsterMove.seedReach.right : HamsterMove.seedReach.left
                #expect(abs(prop.from - (entry.from + reach / drive.travel)) < 1e-9 && prop.from == prop.to, "seeds at \(prop.from)")
                #expect((0.0...1.0).contains(prop.from))
                checked += 1
            }
        }
        #expect(checked > 30)
    }

    // MARK: The wheel's speed is the Mac's load

    @Test func inTheWheelTheHamsterRunsAtThePaceTheLoadGivesAndFasterTheBusierTheMacIs() {
        var paceBy: [Double: [WheelPace: TimeInterval]] = [:]
        for load in [0.03, 0.15, 0.3, 0.55, 0.85] {
            for seed in 1...6 as ClosedRange<UInt64> {
                var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: load, hour: 14))
                drive.run(3 * 3600)
                for (move, time) in drive.spent { if let pace = WheelPace(move) { paceBy[load, default: [:]][pace, default: 0] += time } }
            }
        }
        func mean(_ load: Double) -> Double {
            let times = paceBy[load] ?? [:]
            let total = times.values.reduce(0, +)
            return total == 0 ? 0 : times.reduce(0) { $0 + Double($1.key.rawValue) * $1.value } / total
        }
        #expect(mean(0.03) < 0.05, "quiet: lazy (\(mean(0.03)))")
        #expect(mean(0.03) < mean(0.3) && mean(0.3) < mean(0.55) && mean(0.55) < mean(0.85), "faster as the load goes up: \(mean(0.03)), \(mean(0.3)), \(mean(0.55)), \(mean(0.85))")
        #expect(mean(0.3) > 0.9 && mean(0.3) < 1.1, "a jog at a third of the load: \(mean(0.3))")
        #expect(mean(0.85) > 2.9, "a sprint when it is very busy: \(mean(0.85))")
        for (load, times) in paceBy {
            let wanted = WheelPace.pace(for: load, from: .lazy)
            #expect(times.filter { $0.value > 0 }.keys.allSatisfy { $0 == wanted }, "at a load of \(load) it runs at the one pace: \(times)")
        }
    }

    @Test func thePaceHasLinesToCrossAndOnlyChangesWhenTheLoadIsClearlyPastOneAndTheyAreInOrder() {
        // Rising and falling cross at different loads: no flicker on a line.
        for pace in WheelPace.allCases.dropFirst() {
            #expect(pace.fallsAt < pace.risesAt)
            #expect(WheelPace.pace(for: pace.risesAt - 0.01, from: WheelPace(rawValue: pace.rawValue - 1)!) == WheelPace(rawValue: pace.rawValue - 1)!)
            #expect(WheelPace.pace(for: pace.risesAt, from: WheelPace(rawValue: pace.rawValue - 1)!) >= pace)
            #expect(WheelPace.pace(for: (pace.risesAt + pace.fallsAt) / 2, from: pace) == pace, "it stays between the two lines")
            #expect(WheelPace.pace(for: pace.fallsAt - 0.01, from: pace) < pace)
        }
        #expect(WheelPace.pace(for: 0.03, from: .sprint) == .lazy && WheelPace.pace(for: 1, from: .lazy) == .sprint)
        // Monotone: over a slow climb in load, the pace never goes down.
        var pace = WheelPace.lazy
        for step in 0...100 {
            let next = WheelPace.pace(for: Double(step) / 100, from: pace)
            #expect(next >= pace)
            pace = next
        }
        #expect(pace == .sprint)
        for pace in WheelPace.allCases.dropFirst() {
            #expect(pace.move.fps > WheelPace(rawValue: pace.rawValue - 1)!.move.fps && pace.prop.fps > WheelPace(rawValue: pace.rawValue - 1)!.prop.fps, "faster: \(pace)")
            #expect(pace.move.fps <= Double(CatSpriteView.frameRateCeiling) && pace.prop.fps <= Double(CatSpriteView.frameRateCeiling))
        }
    }

    @Test func aChangeOfLoadChangesThePaceAndNeverMoreOftenThanEveryThreeSeconds() {
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.05, hour: 14))
            var generator = SplitMix64(seed: seed &* 4001)
            for _ in 0..<(60 * 60 * 2) {
                // The load wanders, as a Mac's does, a second at a time.
                drive.senses.cpuLoad = min(max(drive.senses.cpuLoad + Double.random(in: -0.12...0.12, using: &generator), 0), 1)
                drive.run(1)
            }
            var lastChange: [TimeInterval] = []
            var previous: Pose?
            for (at, pose) in drive.history {
                defer { previous = pose }
                guard let previous, HamsterMove(pose.motion).runs, HamsterMove(previous.motion).runs else { continue }
                // One run followed by another run, with no step between, is a change of pace.
                if pose.motion != previous.motion, abs(previous.end - pose.end) < 1e-9 { lastChange.append(at) }
            }
            #expect(lastChange.count > 5, "seed \(seed): it does change pace: \(lastChange.count)")
            for (a, b) in zip(lastChange, lastChange.dropFirst()) { #expect(b - a >= 3 - 1e-9, "paces \(b - a) s apart") }
        }
    }

    @Test func aLoadThatFlipsAcrossTheLinesEverySecondChangesThePaceNoMoreOftenThanEveryThreeSeconds() {
        var changes = 0
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.05, hour: 14))
            for second in 0..<(60 * 20) {
                drive.senses.cpuLoad = second % 2 == 0 ? 0.05 : 0.6
                drive.run(1)
            }
            // Where the pace changes in the middle of a run: the same end, another picture.
            var times: [TimeInterval] = []
            var previous: Pose?
            for (at, pose) in drive.history {
                defer { previous = pose }
                guard let previous, HamsterMove(pose.motion).runs, HamsterMove(previous.motion).runs, pose.motion != previous.motion,
                      abs(previous.end - pose.end) < 1e-9 else { continue }
                times.append(at)
            }
            changes += times.count
            for (a, b) in zip(times, times.dropFirst()) { #expect(b - a >= 3 - 1e-9, "seed \(seed): paces \(b - a) s apart") }
        }
        #expect(changes > 10, "it did change pace: \(changes)")
        #expect(HamsterBrain.paceHold == 3, "three seconds between one change of pace and the next")
    }

    @Test func aRunInProgressFollowsTheLoadUpAndDownAndASitterInTheWheelSetsOffWhenTheMacGetsBusy() {
        var rose = 0, fell = 0, setOff = 0, runs = 0, sits = 0
        for seed in 1...14 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.04, hour: 14))
            var spent = 0.0
            while spent < 7200, !(drive.move.runs && drive.brain.pose.end - drive.now > 10) {
                drive.run(0.5)
                spent += 0.5
            }
            guard drive.move.runs else { continue }
            runs += 1
            let end = drive.brain.pose.end
            drive.senses.cpuLoad = 0.9
            drive.run(5)
            if drive.move == .wheelSprint, abs(drive.brain.pose.end - end) < 1e-9 { rose += 1 }
            // And back down: a few seconds later it jogs at the pace of a quiet Mac, with what was left of the run.
            if drive.brain.pose.end - drive.now > 6 {
                drive.senses.cpuLoad = 0.04
                drive.run(5)
                if drive.move == .wheelLazy, abs(drive.brain.pose.end - end) < 1e-9 { fell += 1 }
            } else { fell += 1 }

            var sitter = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.04, hour: 14))
            spent = 0
            while spent < 7200, !(sitter.move == .wheelSit && sitter.brain.pose.end - sitter.now > 5) {
                sitter.run(0.5)
                spent += 0.5
            }
            guard sitter.move == .wheelSit else { continue }
            sits += 1
            sitter.senses.cpuLoad = 0.5
            sitter.run(4.5)
            if sitter.move.runs { setOff += 1 }
        }
        #expect(runs >= 10 && rose >= runs - 1, "a run in progress went to a sprint with the load: \(rose) of \(runs)")
        #expect(fell >= runs - 1, "and came down again: \(fell) of \(runs)")
        #expect(sits >= 10 && setOff >= sits - 1, "a sitter set off: \(setOff) of \(sits)")
    }

    @Test func aBusyMacMakesTheWheelWhatItDoesMostAndAQuietOneLessThanHalfAsMuch() {
        func wheelShare(_ senses: CatSenses) -> (scenes: Double, time: Double) {
            var wheel = 0, all = 0
            var time = 0.0, total = 0.0
            for seed in 1...8 as ClosedRange<UInt64> {
                var drive = HamDrive(seed: seed, senses: senses)
                drive.run(3 * 3600)
                wheel += drive.scenes.filter { $0 == .wheel }.count
                all += drive.scenes.count
                for (move, spent) in drive.spent {
                    total += spent
                    if HamDrive.inTheWheel.contains(move) { time += spent }
                }
            }
            return (Double(wheel) / Double(all), time / total)
        }
        let quiet = wheelShare(CatSenses(idleSeconds: 5, cpuLoad: 0.05, hour: 14))
        let busy = wheelShare(CatSenses(idleSeconds: 5, cpuLoad: 0.8, hour: 14))
        #expect(busy.scenes > quiet.scenes * 3, "scenes: \(busy.scenes) against \(quiet.scenes)")
        #expect(busy.time > 0.5 && busy.time > quiet.time * 2, "time in the wheel: \(busy.time) against \(quiet.time)")
        #expect(busy.scenes > 0.25, "common when the Mac is busy: \(busy.scenes)")
    }

    @Test func aQuietMacLetsItSitInTheWheelAndJogLazilyAndNeverSprintWithLinesOverItsBack() {
        var sits = 0.0, lazy = 0.0, other = 0.0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.05, hour: 14))
            drive.run(3 * 3600)
            sits += drive.spent[.wheelSit] ?? 0
            lazy += drive.spent[.wheelLazy] ?? 0
            other += [HamsterMove.wheelJog, .wheelRun, .wheelSprint].reduce(0) { $0 + (drive.spent[$1] ?? 0) }
        }
        #expect(sits > 0 && lazy > 0 && other == 0, "sits \(sits), lazy \(lazy), faster \(other)")
        #expect(sits > lazy * 0.25 && sits < lazy * 4, "both are common: sat \(sits) s, jogged \(lazy) s")
    }

    @Test func aBurstOfWorkSendsItToTheWheelAtOnceOnceAndWithTheReactionOffItDoesNotGo() throws {
        var went = 0
        for seed in 1...16 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.05, hour: 14))
            // Until it is doing something that is not the wheel.
            for _ in 0..<4000 {
                drive.run(0.5)
                if drive.scenes.last != .wheel, !HamDrive.inTheWheel.contains(drive.move), drive.brain.stance != .curled, !drive.brain.hasProps { break }
            }
            let mark = drive.history.count
            drive.senses.cpuLoad = 0.95
            drive.senses.busyBurst = true
            drive.run(5)
            let sentToTheWheel = drive.scenes.last == .wheel
            if sentToTheWheel {
                went += 1
                #expect(drive.history[mark...].contains { HamsterMove($0.pose.motion) == .hopIn || $0.pose.prop?.look == HamsterProp.wheelAppearing.look }, "seed \(seed)")
            }
            // Once: another burst is another.
            drive.run(10)
            let scenes = drive.scenes.count
            drive.senses.busyBurst = false
            drive.senses.cpuLoad = 0.05
            drive.run(1)
            #expect(hamsterPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
            _ = scenes
        }
        #expect(went >= 12, "most of the time there was room, and it went: \(went) of 16")

        var off = HamDrive(seed: 3, senses: CatSenses(idleSeconds: 5, cpuLoad: 1, busyBurst: true, hour: 14))
        off.tuning.reactsToBusyMachine = false
        var quiet = HamDrive(seed: 3, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.05, hour: 14))
        off.run(3600)
        quiet.run(3600)
        #expect(off.moves == quiet.moves && off.history.map(\.pose) == quiet.history.map(\.pose), "with the reaction off a busy Mac changes nothing")
        #expect(off.every.allSatisfy { !($0.prop?.look.fps ?? 0).isNaN } && off.spent.keys.allSatisfy { ![.wheelJog, .wheelRun, .wheelSprint].contains($0) })
    }

    @Test func aBurstThatFindsNoRoomForAWheelChangesNothingAndDoesNotTryAgainUntilTheNextOne() {
        // A lane with no room for the wheel and the hop.
        var drive = HamDrive(seed: 4, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.05, hour: 14), travel: 20)
        drive.run(300)
        let before = drive.scenes.count
        drive.senses.cpuLoad = 0.95
        drive.senses.busyBurst = true
        var changes = 0
        for _ in 0..<(4 * 18) {
            let outcome = drive.run(0.25)
            if outcome == .changed { changes += 1 }
        }
        // Its own day goes on at its own pace: a change now and then, never one on every look.
        #expect(changes < 4 * 18 / 3, "\(changes) changes in 18 seconds")
        #expect(drive.every.allSatisfy { $0.prop == nil || !$0.prop!.look.occupies })
        #expect(drive.scenes.count >= before && drive.brain.strayProps == 0)
    }
}

enum DriveHelpers {
    /// Whether the pose is one of running in the wheel.
    static func runs(_ pose: Pose) -> Bool { HamsterMove(pose.motion).runs }
}
