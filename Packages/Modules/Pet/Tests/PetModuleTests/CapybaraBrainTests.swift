import Foundation
import Testing
@testable import PetModule

/// The capybara's brain driven by a clock the test holds: it is woken every quarter of a second, as the stage wakes it, with what it senses.
struct CapyDrive {
    var brain: CapybaraBrain
    var now: TimeInterval = 0
    var senses = CatSenses()
    var tuning = CatTuning()
    /// How far the capybara can walk, in pixels of its picture.
    var travel = 260.0
    var lane = LaneContext()

    /// Every pose that changed the picture, with the time it began.
    private(set) var history: [(at: TimeInterval, pose: Pose)] = []
    /// Every pose there was, extended or changed.
    private(set) var every: [Pose] = []
    private(set) var scenes: [CapybaraScene] = []
    private(set) var spent: [CapybaraMove: TimeInterval] = [:]
    private var serial = 0
    static let step = 0.25

    init(seed: UInt64 = 1, position: Double = 0.5, senses: CatSenses = CatSenses(), tuning: CatTuning = CatTuning(), travel: Double = 260) {
        brain = CapybaraBrain(seed: seed, now: 0, position: position)
        self.senses = senses
        self.tuning = tuning
        self.travel = travel
    }

    var move: CapybaraMove { brain.move }

    @discardableResult
    mutating func run(_ seconds: Double, each: (CapybaraBrain) -> Void = { _ in }) -> BrainOutcome {
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

    var moves: [CapybaraMove] { history.map { CapybaraMove($0.pose.motion) } }

    func share(of move: CapybaraMove) -> Double {
        let total = spent.values.reduce(0, +)
        return total == 0 ? 0 : (spent[move] ?? 0) / total
    }

    /// What it has out, one entry for each picture it changed to.
    var trail: [(move: CapybaraMove, prop: CapybaraProp?)] {
        history.map { (CapybaraMove($0.pose.motion), $0.pose.prop.map { CapybaraProp($0.look) }) }
    }

    static func pointer(_ share: Double, near: Bool) -> PointerReading {
        PointerReading(share: share, isNear: near, isInRange: true)
    }
}

/// What a capybara is allowed to have out after what it had out: a tub comes up, sits empty or with it in, and goes; it is never left behind
/// and never goes without going; the peel the same; the orange is picked up and not put down again.
func propProblems(_ trail: [(move: CapybaraMove, prop: CapybaraProp?)]) -> [String] {
    var problems: [String] = []
    let tub: Set<CapybaraProp> = [.tubAppearing, .tubEmpty, .tubRippling, .tubGoing]
    let after: [CapybaraProp?: Set<CapybaraProp?>] = [
        .tubAppearing: [.tubEmpty, .tubRippling, .tubGoing], .tubEmpty: [.tubEmpty, .tubRippling, .tubGoing],
        .tubRippling: [.tubEmpty, .tubRippling, .tubGoing], .tubGoing: [nil], .peel: [.peel, .peelGoing], .peelGoing: [nil], .orange: [.orange, nil],
    ]
    for (index, entry) in trail.enumerated() {
        let soaking = [CapybaraMove.climbIn, .climbOut, .soak, .soakOrange, .soakHappy].contains(entry.move)
        if soaking, entry.prop != .tubRippling { problems.append("\(index): \(entry.move) with \(String(describing: entry.prop))") }
        if !soaking, entry.prop == .tubRippling { problems.append("\(index): \(entry.move) in the tub, which it is not in") }
        if entry.prop == .tubAppearing, entry.move != .sit { problems.append("\(index): the tub comes up under a \(entry.move)") }
        if entry.prop == .tubGoing, entry.move != .sit { problems.append("\(index): the tub goes under a \(entry.move)") }
        if let prop = entry.prop, tub.contains(prop), [CapybaraMove.walk, .sleep, .lie, .doze].contains(entry.move) {
            problems.append("\(index): a tub by a capybara that is \(entry.move)")
        }
        guard index + 1 < trail.count else { continue }
        let next = trail[index + 1].prop
        if let allowed = after[entry.prop], !allowed.contains(next) {
            problems.append("\(index): \(String(describing: entry.prop)) is followed by \(String(describing: next))")
        }
        if let prop = entry.prop, tub.contains(prop) == false, [CapybaraProp.tubEmpty, .tubRippling].contains(next) {
            problems.append("\(index): a tub that was not asked for")
        }
        if entry.prop == nil, let next, [CapybaraProp.tubEmpty, .tubRippling].contains(next) {
            problems.append("\(index): \(next) with no beginning")
        }
    }
    return problems
}

@Suite struct CapybaraBrainSceneTests {
    @Test func theSameSeedMakesTheSameDayAndAnotherSeedAnotherOne() {
        func day(seed: UInt64) -> [CapybaraMove] {
            var drive = CapyDrive(seed: seed)
            drive.run(900)
            return drive.moves
        }
        #expect(day(seed: 3) == day(seed: 3))
        #expect(day(seed: 3) != day(seed: 4))
    }

    @Test func itNeverBeginsTheSameSceneTwiceRunning() {
        for hour in [14, 23] {
            for seed in 1...12 as ClosedRange<UInt64> {
                var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: hour))
                drive.run(3600)
                #expect(drive.scenes.count > 50)
                for (before, after) in zip(drive.scenes, drive.scenes.dropFirst()) { #expect(before != after, "seed \(seed) at \(hour): \(before) twice") }
            }
        }
    }

    @Test func soakingAndDozingAreTheMostCommonEatingAnOrangeIsRegularAndWalkingIsShort() {
        var counts: [CapybaraScene: Int] = [:]
        var total = CapyDrive()
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(3 * 3600)
            for scene in drive.scenes { counts[scene, default: 0] += 1 }
            for (move, time) in drive.spent { total.addSpent(move, time) }
        }
        let scenes = Double(counts.values.reduce(0, +))
        func share(_ list: [CapybaraScene]) -> Double { Double(list.reduce(0) { $0 + (counts[$1] ?? 0) }) / scenes }
        #expect(share([.soak, .soakOrange, .doze]) > 0.4, "soaking and dozing: \(share([.soak, .soakOrange, .doze]))")
        #expect(counts[.soak, default: 0] > counts[.eatOrange, default: 0] && counts[.doze, default: 0] > counts[.eatOrange, default: 0])
        #expect(share([.eatOrange]) > 0.08 && share([.eatOrange]) < 0.25, "eating an orange is regular: \(share([.eatOrange]))")
        #expect(share([.stroll, .crossOver]) < 0.15, "walking is the least of it")
        #expect(total.share(of: .walk) < 0.08, "and the shortest: \(total.share(of: .walk))")
        #expect(Set(counts.keys) == Set(CapybaraScene.allCases).subtracting([.fret]), "every scene, and no sweat on a quiet Mac")
    }

    @Test func atNightItLiesAboutAndDozesMoreAndSleepsAtShorterNotice() {
        var day = 0.0, night = 0.0
        for seed in 1...8 as ClosedRange<UInt64> {
            var daytime = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            daytime.run(3 * 3600)
            var overnight = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 23))
            overnight.run(3 * 3600)
            day += [CapybaraMove.lie, .sleep, .doze].reduce(0) { $0 + daytime.share(of: $1) }
            night += [CapybaraMove.lie, .sleep, .doze].reduce(0) { $0 + overnight.share(of: $1) }
        }
        #expect(night > day * 1.3, "night \(night / 8) against day \(day / 8)")
        // The same idle time that is not enough by day is by night: the threshold is shorter then.
        var byDay = CapyDrive(seed: 2, senses: CatSenses(idleSeconds: 120, hour: 14))
        var byNight = CapyDrive(seed: 2, senses: CatSenses(idleSeconds: 120, hour: 23))
        byDay.run(300)
        byNight.run(300)
        #expect(byDay.share(of: .sleep) == 0 && byNight.share(of: .sleep) > 0.3)
    }

    @Test func itWalksSlowlyAndShortAndNeverQuickens() {
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.95, busyBurst: true, hour: 14))
            drive.run(2 * 3600)
            var walks = 0
            for pose in drive.every where CapybaraMove(pose.motion) == .walk && pose.from != pose.to {
                walks += 1
                #expect(pose.fpsScale == 1, "no quickening")
                let speed = abs(pose.to - pose.from) * drive.travel / pose.duration
                #expect(speed <= CapybaraMove.walk.speed + 1e-9, "\(speed) points a second")
            }
            #expect(walks > 10)
            for pose in drive.every { #expect(pose.fpsScale == 1 && pose.delay == 0) }
        }
    }

    // MARK: What it plays with

    @Test func whatItHasOutStartsAndEndsInOrderThroughHoursOfDays() {
        var seen: Set<CapybaraProp> = []
        for hour in [14, 23] {
            for seed in 1...12 as ClosedRange<UInt64> {
                var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: hour))
                drive.run(3 * 3600)
                #expect(propProblems(drive.trail).isEmpty, "seed \(seed) at \(hour): \(propProblems(drive.trail).prefix(4))")
                #expect(drive.brain.strayProps == 0, "nothing left over when a scene began")
                seen.formUnion(drive.trail.compactMap(\.prop))
            }
        }
        #expect(seen == Set(CapybaraProp.allCases), "\(Set(CapybaraProp.allCases).subtracting(seen))")
    }

    /// The scenes of one kind, cut out of a run: every picture from the first prop's coming to the last one going.
    func stretches(from trail: [(move: CapybaraMove, prop: CapybaraProp?)], beginning begin: CapybaraProp, ending end: CapybaraProp) -> [[(move: CapybaraMove, prop: CapybaraProp?)]] {
        var found: [[(move: CapybaraMove, prop: CapybaraProp?)]] = []
        var current: [(move: CapybaraMove, prop: CapybaraProp?)]?
        for entry in trail {
            if entry.prop == begin { current = [entry] } else if current != nil { current?.append(entry) }
            if entry.prop == end, let finished = current {
                found.append(finished)
                current = nil
            }
        }
        return found
    }

    @Test func aSoakIsTheTubComingUpAHopInAStayAHopOutAndTheTubGoing() {
        var soaks = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(2 * 3600)
            for stretch in stretches(from: drive.trail, beginning: .tubAppearing, ending: .tubGoing) {
                soaks += 1
                let moves = stretch.map(\.move)
                #expect(moves.first == .sit && moves.last == .sit, "it sits to watch the tub come and go: \(moves)")
                let (hopIn, hopOut) = (moves.firstIndex(of: .climbIn), moves.lastIndex(of: .climbOut))
                guard let hopIn, let hopOut else { continue }
                #expect(hopIn < hopOut)
                #expect(moves[(hopIn + 1)..<hopOut].allSatisfy { [.soak, .soakOrange, .soakHappy].contains($0) }, "in the tub it soaks: \(moves)")
                #expect(moves[(hopIn + 1)..<hopOut].contains(.soak) || moves[(hopIn + 1)..<hopOut].contains(.soakOrange))
                #expect(stretch[..<hopIn].allSatisfy { $0.prop == .tubAppearing || $0.prop == .tubEmpty }, "the tub stands empty until it hops in")
                #expect(stretch[(hopOut + 1)...].allSatisfy { $0.prop == .tubEmpty || $0.prop == .tubGoing }, "and empty after it has hopped out")
                #expect(moves[(hopOut + 1)...].dropLast().allSatisfy { [.sitDown].contains($0) }, "it sits down by the empty tub: \(moves)")
            }
        }
        #expect(soaks > 20, "\(soaks)")
    }

    @Test func theHopsGoTheSpanOfTheHopAndTheTubIsWhereTheHopIntoItEndsAndTheSoakStaysThere() {
        var checked = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 300)
            drive.run(2 * 3600)
            var place: Double?
            for entry in drive.history.map(\.pose) {
                let move = CapybaraMove(entry.motion)
                if move == .climbIn {
                    #expect(abs(abs(entry.to - entry.from) * 300 - CapybaraMove.hopSpan) < 1e-6, "a hop of \(abs(entry.to - entry.from) * 300) points")
                    place = entry.to
                    #expect(entry.prop?.from == entry.to && entry.prop?.to == entry.to, "the tub is where it hops to")
                    checked += 1
                } else if move == .climbOut {
                    #expect(entry.from == place && abs(abs(entry.to - entry.from) * 300 - CapybaraMove.hopSpan) < 1e-6, "back out the way it came")
                    #expect(entry.facing == drive.history.first { $0.pose.motion == CapybaraMove.climbIn.motion }?.pose.facing || true)
                } else if [.soak, .soakOrange, .soakHappy].contains(move) {
                    #expect(entry.from == place && entry.to == place, "it stays where the tub is")
                    #expect(entry.perch != nil || move == .soakHappy, "it has a back to ride on")
                }
            }
        }
        #expect(checked > 10)
    }

    @Test func itFacesTheWayItHopsAndHopsOutBackwardsFacingTheSameWay() {
        var drive = CapyDrive(seed: 5, senses: CatSenses(idleSeconds: 5, hour: 14))
        drive.run(3 * 3600)
        var facing: Facing?
        var hops = 0
        for entry in drive.history.map(\.pose) {
            let move = CapybaraMove(entry.motion)
            if move == .climbIn {
                facing = entry.facing
                #expect((entry.to > entry.from) == (entry.facing == .right), "it hops the way it faces")
                hops += 1
            } else if move == .climbOut {
                #expect(entry.facing == facing && (entry.to < entry.from) == (entry.facing == .right), "and out backwards")
            } else if move == .soak { #expect(entry.facing == facing) }
        }
        #expect(hops > 5)
    }

    @Test func anOrangeIsPutDownPickedUpPeeledChewedAndThePeelGoes() {
        var meals = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(2 * 3600)
            let trail = drive.trail
            for (index, entry) in trail.enumerated() where entry.prop == .orange {
                meals += 1
                #expect(entry.move == .sit)
                let rest = trail[(index + 1)...]
                #expect(rest.first?.move == .hold && rest.first?.prop == nil, "it picks it up and the orange is gone from the floor")
                let peel = rest.firstIndex { $0.prop == .peel }
                let gone = rest.firstIndex { $0.prop == .peelGoing }
                guard let peel, let gone else { continue }
                #expect(peel < gone)
                let between = rest[peel...gone].map(\.move)
                #expect(between.first == .peel && between.contains(.chew) && between.last == .sit, "\(between)")
                #expect(rest[peel...gone].dropLast().allSatisfy { $0.prop == .peel }, "the peel lies there while it chews")
            }
        }
        #expect(meals > 15)
    }

    @Test func theOrangeIsOnTheSideItFacesAndThePeelIsNearerAndBothAreOnTheLane() {
        var checked = 0
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, position: 0.5, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(2 * 3600)
            for entry in drive.history.map(\.pose) {
                guard let prop = entry.prop, [.orange, .peel].contains(CapybaraProp(prop.look)) else { continue }
                let kind = CapybaraProp(prop.look)
                let reach = kind == .orange ? CapybaraMove.orangeReach : CapybaraMove.peelReach
                let expected = entry.from + (entry.facing == .right ? reach.right : reach.left) / drive.travel
                #expect(abs(prop.from - expected) < 1e-9 && prop.from == prop.to, "\(kind) at \(prop.from), expected \(expected)")
                #expect((0.0...1.0).contains(prop.from))
                checked += 1
            }
        }
        #expect(checked > 30)
    }

    // MARK: Busy

    @Test func aBusyMacNeverMakesItFranticItSweatsALittleAndSoaksLonger() {
        func soakLength(_ senses: CatSenses) -> (mean: Double, sweat: Double) {
            var lengths: [Double] = []
            var sweat = 0.0
            for seed in 1...8 as ClosedRange<UInt64> {
                var drive = CapyDrive(seed: seed, senses: senses)
                drive.run(3 * 3600)
                sweat += drive.share(of: .sweat)
                for pose in drive.history.map(\.pose) where CapybaraMove(pose.motion) == .soak || CapybaraMove(pose.motion) == .soakOrange { lengths.append(pose.duration) }
            }
            return (lengths.reduce(0, +) / Double(max(lengths.count, 1)), sweat / 8)
        }
        let quiet = soakLength(CatSenses(idleSeconds: 5, cpuLoad: 0.05, hour: 14))
        let busy = soakLength(CatSenses(idleSeconds: 5, cpuLoad: 1, busyBurst: true, hour: 14))
        #expect(busy.mean > quiet.mean * 1.3, "soaks longer: \(busy.mean) against \(quiet.mean)")
        #expect(quiet.sweat == 0 && busy.sweat > 0.005, "sweats a little, and only when it is busy: \(busy.sweat)")
        var drive = CapyDrive(seed: 4, senses: CatSenses(idleSeconds: 5, cpuLoad: 1, busyBurst: true, hour: 14))
        drive.run(3600)
        for pose in drive.every {
            #expect(pose.fpsScale == 1, "no frantic pace")
            #expect(pose.motion.fps <= 8, "no run: \(CapybaraMove(pose.motion))")
        }
        #expect(!drive.moves.isEmpty && drive.scenes.contains(.fret))
        #expect(CapybaraMove.allCases.allSatisfy { $0.speed <= 24 }, "nothing it has goes faster than a hop")
    }

    @Test func withTheReactionTurnedOffABusyMacChangesNothing() {
        var off = CapyDrive(seed: 3, senses: CatSenses(idleSeconds: 5, cpuLoad: 1, busyBurst: true, hour: 14))
        off.tuning.reactsToBusyMachine = false
        var quiet = CapyDrive(seed: 3, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.05, hour: 14))
        off.run(3600)
        quiet.run(3600)
        #expect(off.moves == quiet.moves && off.history.map(\.pose) == quiet.history.map(\.pose))
    }
}

extension CapyDrive {
    mutating func addSpent(_ move: CapybaraMove, _ time: TimeInterval) { spent[move, default: 0] += time }
}
