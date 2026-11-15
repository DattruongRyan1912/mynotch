import Foundation
import Testing
@testable import PetModule

/// The penguin's brain driven by a clock the test holds: it is woken every quarter of a second, as the stage wakes it, with what it senses.
struct PenDrive {
    var brain: PenguinBrain
    var now: TimeInterval = 0
    var senses = CatSenses()
    var tuning = CatTuning()
    /// How far the penguin can walk, in pixels of its picture.
    var travel = 260.0
    var lane = LaneContext()

    /// Every pose that changed the picture, with the time it began.
    private(set) var history: [(at: TimeInterval, pose: Pose)] = []
    /// Every pose there was, extended or changed.
    private(set) var every: [Pose] = []
    private(set) var scenes: [PenguinScene] = []
    private(set) var spent: [PenguinMove: TimeInterval] = [:]
    private var serial = 0
    static let step = 0.25

    init(seed: UInt64 = 1, position: Double = 0.5, senses: CatSenses = CatSenses(), tuning: CatTuning = CatTuning(), travel: Double = 260) {
        brain = PenguinBrain(seed: seed, now: 0, position: position)
        self.senses = senses
        self.tuning = tuning
        self.travel = travel
    }

    var move: PenguinMove { brain.move }

    @discardableResult
    mutating func run(_ seconds: Double, each: (PenguinBrain) -> Void = { _ in }) -> BrainOutcome {
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

    var moves: [PenguinMove] { history.map { PenguinMove($0.pose.motion) } }

    func share(of move: PenguinMove) -> Double {
        let total = spent.values.reduce(0, +)
        return total == 0 ? 0 : (spent[move] ?? 0) / total
    }

    /// What it has out, one entry for each picture it changed to.
    var trail: [(move: PenguinMove, prop: PenguinProp?)] {
        history.map { (PenguinMove($0.pose.motion), $0.pose.prop.map { PenguinProp($0.look) }) }
    }

    static func pointer(_ share: Double, near: Bool) -> PointerReading {
        PointerReading(share: share, isNear: near, isInRange: true)
    }

    /// The moves it is fishing in, which are all with the line in the hole.
    static let fishing: Set<PenguinMove> = [.cast, .fish, .bite, .pull, .gulp, .fishHappy, .reel]
    /// The moves with nothing about them that has a hole out.
    static let withoutAHole: Set<PenguinMove> = [.waddle, .slide, .bellyDown, .lie, .slip, .dazed, .getUp, .tuck, .tucked, .sleep, .untuck, .flap]
}

/// What a penguin is allowed to have out after what it had out: a hole opens (under a standing penguin), stands, takes the line in and
/// ripples, is stirred up when a fish bites and splashes when it comes out, and closes (under a standing penguin), and then nothing; it is
/// never left behind and never goes without going; and a penguin that fishes always has a hole, and one that is on its belly never.
func penguinPropProblems(_ trail: [(move: PenguinMove, prop: PenguinProp?)]) -> [String] {
    var problems: [String] = []
    let water: Set<PenguinProp?> = [.holeRippling, .holeChurning, .holeSplashing]
    let after: [PenguinProp?: Set<PenguinProp?>] = [
        .holeOpening: water.union([.holeStill, .holeClosing]), .holeStill: water.union([.holeStill, .holeClosing]),
        .holeRippling: water.union([.holeStill, .holeClosing]), .holeChurning: water.union([.holeStill, .holeClosing]),
        .holeSplashing: water.union([.holeStill, .holeClosing]), .holeClosing: [nil],
    ]
    let wanted: [PenguinMove: PenguinProp] = [.bite: .holeChurning, .pull: .holeSplashing]
    for (index, entry) in trail.enumerated() {
        if PenDrive.fishing.contains(entry.move) {
            let expected = wanted[entry.move] ?? .holeRippling
            if entry.prop != expected { problems.append("\(index): \(entry.move) with \(String(describing: entry.prop))") }
        } else if let prop = entry.prop, water.contains(prop) {
            problems.append("\(index): \(entry.move) with the line in \(prop)")
        }
        if entry.prop != nil, PenDrive.withoutAHole.contains(entry.move) { problems.append("\(index): a hole by a penguin that is \(entry.move)") }
        if entry.prop == .holeOpening, entry.move != .stand { problems.append("\(index): the hole opens under a \(entry.move)") }
        if entry.prop == .holeClosing, entry.move != .stand { problems.append("\(index): the hole closes under a \(entry.move)") }
        guard index + 1 < trail.count else { continue }
        let next = trail[index + 1].prop
        if let allowed = after[entry.prop], !allowed.contains(next) {
            problems.append("\(index): \(String(describing: entry.prop)) is followed by \(String(describing: next))")
        }
        if let next, entry.prop == nil, next != .holeOpening { problems.append("\(index): \(next) with no beginning") }
    }
    return problems
}

@Suite struct PenguinBrainSceneTests {
    @Test func theSameSeedMakesTheSameDayAndAnotherSeedAnotherOne() {
        func day(seed: UInt64) -> [PenguinMove] {
            var drive = PenDrive(seed: seed)
            drive.run(900)
            return drive.moves
        }
        #expect(day(seed: 3) == day(seed: 3))
        #expect(day(seed: 3) != day(seed: 4))
    }

    @Test func itNeverBeginsTheSameSceneTwiceRunning() {
        for hour in [14, 23] {
            for seed in 1...12 as ClosedRange<UInt64> {
                var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: hour))
                drive.run(3600)
                #expect(drive.scenes.count > 40, "\(drive.scenes.count)")
                for (before, after) in zip(drive.scenes, drive.scenes.dropFirst()) { #expect(before != after, "seed \(seed) at \(hour): \(before) twice") }
            }
        }
    }

    @Test func everySceneComesUpTheGlideIsAFifthOfThemAndAtNightItNapsMoreAndFishesLess() {
        var counts: [PenguinScene: Int] = [:]
        var day = 0.0, night = 0.0
        var gliding = 0, all = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var daytime = PenguinDrive.day(seed: seed, hour: 14)
            daytime.run(3 * 3600)
            var overnight = PenguinDrive.day(seed: seed, hour: 23)
            overnight.run(3 * 3600)
            for scene in daytime.scenes { counts[scene, default: 0] += 1 }
            gliding += daytime.scenes.filter { $0 == .slideAbout || $0 == .crossOver }.count
            all += daytime.scenes.count
            day += [PenguinMove.tucked, .sleep].reduce(0) { $0 + daytime.share(of: $1) }
            night += [PenguinMove.tucked, .sleep].reduce(0) { $0 + overnight.share(of: $1) }
        }
        #expect(Set(counts.keys) == Set(PenguinScene.allCases), "\(Set(PenguinScene.allCases).subtracting(counts.keys))")
        #expect(night > day * 1.2, "more standing with its head tucked in at night: \(night / 8) against \(day / 8)")
        #expect(Double(gliding) / Double(all) > 0.15, "lying down and going is what it does: \(gliding) of \(all)")
        // The same idle time that is not enough by day is by night: the threshold is shorter then.
        var byDay = PenDrive(seed: 2, senses: CatSenses(idleSeconds: 120, hour: 14))
        var byNight = PenDrive(seed: 2, senses: CatSenses(idleSeconds: 120, hour: 23))
        byDay.run(300)
        byNight.run(300)
        #expect(byDay.share(of: .sleep) == 0 && byNight.share(of: .sleep) > 0.3)
    }

    // MARK: The waddle and the slide

    @Test func theSlideIsTheSameQuickGlideAtAnyLoadAndTheWaddleQuickensWithTheMacByNoMoreThanHalfAgainAndNothingIsFrantic() {
        var biggest = 0.0
        for load in [0.05, 0.5, 0.7, 0.9, 1.0] {
            for burst in [false, true] {
                for seed in 1...5 as ClosedRange<UInt64> {
                    var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: load, busyBurst: burst, hour: 14))
                    drive.run(2 * 3600)
                    var glides = 0, waddles = 0
                    for pose in drive.every {
                        let move = PenguinMove(pose.motion)
                        let speed = abs(pose.to - pose.from) * drive.travel / pose.duration
                        if move == .slide, pose.from != pose.to {
                            glides += 1
                            #expect(abs(speed - PenguinMove.slide.speed) < 1e-6, "a glide of \(speed) points a second")
                            #expect(pose.fpsScale == 1)
                        } else if move == .waddle, pose.from != pose.to {
                            waddles += 1
                            let wanted = pose.fpsScale * PenguinMove.waddle.speed
                            #expect(abs(speed - wanted) < 1e-6, "a waddle of \(speed) points a second at \(pose.fpsScale)")
                            #expect(pose.fpsScale >= 1 && pose.fpsScale <= 1 + PenguinMove.busyBoost + 1e-9)
                            #expect(PenguinMove.waddle.fps * pose.fpsScale <= 12 + 1e-9, "its frames are not in a hurry")
                            biggest = max(biggest, pose.fpsScale)
                            if load <= PenguinBrain.busyFrom && !burst { #expect(pose.fpsScale == 1, "a Mac that is not busy does not quicken it") }
                        } else {
                            #expect(pose.fpsScale == 1 && pose.delay == 0, "no quickening: \(move)")
                        }
                        #expect(speed <= PenguinMove.slide.speed + 1e-6, "nothing is quicker than the glide")
                    }
                    #expect(glides > 10 && waddles > 10, "load \(load): \(glides) glides, \(waddles) waddles")
                }
            }
        }
        #expect(abs(biggest - 1.5) < 1e-6, "a Mac at full tilt has it waddle half as fast again: \(biggest)")
        #expect(PenguinMove.slide.speed >= 2 * PenguinMove.waddle.speed * (1 + PenguinMove.busyBoost), "a glide is always the way to go quickly")
    }

    @Test func theBusierTheMacTheFasterItWaddlesAndABurstOfWorkQuickensItAndWithTheReactionOffNothingChanges() {
        func waddleSpeed(load: Double, burst: Bool = false, reacts: Bool = true) -> Double {
            var drive = PenDrive(seed: 4, senses: CatSenses(idleSeconds: 5, cpuLoad: load, busyBurst: burst, hour: 14))
            drive.tuning.reactsToBusyMachine = reacts
            drive.run(3600)
            let speeds = drive.every.filter { PenguinMove($0.motion) == .waddle && $0.from != $0.to }.map { abs($0.to - $0.from) * drive.travel / $0.duration }
            return speeds.reduce(0, +) / Double(max(speeds.count, 1))
        }
        let (quiet, edge, busy, flat) = (waddleSpeed(load: 0.05), waddleSpeed(load: 0.6), waddleSpeed(load: 0.8), waddleSpeed(load: 1.0))
        #expect(abs(quiet - 16) < 1e-6 && abs(edge - 16) < 1e-6, "quiet \(quiet), at the line \(edge)")
        #expect(busy > edge * 1.2 && flat > busy && abs(flat - 24) < 1e-6, "\(edge), \(busy), \(flat)")
        let bursting = waddleSpeed(load: 0.05, burst: true)
        #expect(bursting > 16 * 1.3 && bursting <= 24 + 1e-6, "a burst quickens it: \(bursting)")
        #expect(abs(waddleSpeed(load: 1.0, burst: true, reacts: false) - 16) < 1e-6, "with the reaction off a busy Mac is a quiet one")
        var off = PenDrive(seed: 3, senses: CatSenses(idleSeconds: 5, cpuLoad: 1, busyBurst: true, hour: 14))
        off.tuning.reactsToBusyMachine = false
        var calm = PenDrive(seed: 3, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.05, hour: 14))
        off.run(3600)
        calm.run(3600)
        #expect(off.moves == calm.moves && off.history.map(\.pose) == calm.history.map(\.pose), "with the reaction off a busy Mac changes nothing")
    }

    @Test func aMacThatIsBusyChangesHowFastItWaddlesButNotWhatItDoes() {
        // The same seed on a quiet and a busy Mac: the same scenes in the same order, only the waddles take a different time.
        var quiet = PenDrive(seed: 6, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.05, hour: 14))
        var busy = PenDrive(seed: 6, senses: CatSenses(idleSeconds: 5, cpuLoad: 1, hour: 14))
        quiet.run(600)
        busy.run(600)
        let first = min(quiet.scenes.count, busy.scenes.count, 4)
        #expect(first >= 3 && Array(quiet.scenes.prefix(first)) == Array(busy.scenes.prefix(first)))
        #expect(quiet.every.contains { PenguinMove($0.motion) == .waddle } && busy.every.contains { PenguinMove($0.motion) == .waddle })
    }

    // MARK: Gliding

    @Test func aGlideIsLyingDownGlidingLyingStillAndGettingUpAndItFacesTheWayItGoes() {
        var glides = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 300)
            drive.run(2 * 3600)
            let poses = drive.history.map(\.pose)
            for (index, pose) in poses.enumerated() where PenguinMove(pose.motion) == .slide && pose.from != pose.to {
                guard index >= 1 else { continue }
                glides += 1
                // It lies down first, unless it is lying down already (a second glide, from where the first left it, the way it faces).
                let before = poses[index - 1], down = PenguinMove(before.motion)
                #expect(down == .bellyDown || down == .lie, "it lies down first: \(down)")
                #expect(before.from == before.to && abs(before.to - pose.from) < 1e-9 && before.facing == pose.facing, "in the place it glides from, facing the way")
                #expect((pose.to > pose.from) == (pose.facing == .right), "it faces the way it goes")
                let next = poses[(index + 1)...].prefix(4).map { PenguinMove($0.motion) }
                #expect(next.first == .lie || next.first == .slide, "it stays lying where it stopped: \(next)")
                if next.first == .lie {
                    let after = poses[index + 1]
                    #expect(after.from == after.to && abs(after.to - pose.to) < 1e-9)
                    #expect(next.contains(.getUp), "and gets up: \(next)")
                }
            }
            // It is never flat on its belly without a reason, and never stands up from one without getting up.
            for (before, after) in zip(poses, poses.dropFirst()) {
                let (a, b) = (PenguinMove(before.motion), PenguinMove(after.motion))
                if b == .lie { #expect([.slide, .bellyDown, .lie, .slip, .dazed].contains(a), "\(a) then lying") }
                if [.stand, .blink, .flap, .waddle, .tuck].contains(b) { #expect(![.lie, .slide, .dazed, .slip, .bellyDown].contains(a), "\(a) then \(b) with no getting up") }
            }
        }
        #expect(glides > 30, "\(glides)")
    }

    @Test func aSlipIsAWaddleAFallInOnePlaceAStarryLieAndAGetUpAndItIsAMishapNotAHabit() {
        var slips = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(3 * 3600)
            let poses = drive.history.map(\.pose)
            for (index, pose) in poses.enumerated() where PenguinMove(pose.motion) == .slip {
                slips += 1
                #expect(pose.from == pose.to, "it falls where it stands")
                #expect(PenguinMove(poses[index - 1].motion) != .bellyDown && PenguinMove(poses[index - 1].motion) != .slide)
                let next = poses[(index + 1)...].prefix(3).map { PenguinMove($0.motion) }
                #expect(next == [.dazed, .getUp, .stand], "\(next)")
            }
        }
        #expect(slips > 8, "\(slips)")
        var all = 0, falls = 0
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(3 * 3600)
            all += drive.scenes.count
            falls += drive.scenes.filter { $0 == .slip }.count
        }
        #expect(Double(falls) / Double(all) < 0.12, "a mishap: \(falls) of \(all)")
    }

    // MARK: The camera

    @Test func itNeverStopsInTheCrossingOrInTheWayOfAnotherAndOnlyAGlideGoesThroughTheCrossingAndNothingGoesIntoWhatIsClosed() {
        let crossing: ClosedRange<Double> = 0.4...0.6
        var through = 0, waddles = 0
        for load in [0.05, 0.9] {
            for seed in 1...8 as ClosedRange<UInt64> {
                var drive = PenDrive(seed: seed, position: 0.2, senses: CatSenses(idleSeconds: 5, cpuLoad: load, hour: 14), travel: 156)
                drive.lane = LaneContext(crossing: [crossing], zones: [0.8...0.95])
                drive.run(3 * 3600)
                for pose in drive.every {
                    let move = PenguinMove(pose.motion)
                    if pose.from == pose.to {
                        #expect(!(crossing.lowerBound + 1e-9..<crossing.upperBound - 1e-9).contains(pose.to), "seed \(seed): a \(move) at \(pose.to)")
                        #expect(!(0.8 + 1e-9..<0.95 - 1e-9).contains(pose.to), "in the way of another at \(pose.to)")
                    }
                    let (low, high) = (min(pose.from, pose.to), max(pose.from, pose.to))
                    if high > crossing.lowerBound && low < crossing.upperBound {
                        through += 1
                        #expect(move == .slide, "seed \(seed): a \(move) goes through the crossing, from \(pose.from) to \(pose.to)")
                    } else if move == .waddle, pose.from != pose.to {
                        waddles += 1
                    }
                    if let prop = pose.prop {
                        #expect(!(crossing.lowerBound + 1e-9..<crossing.upperBound - 1e-9).contains(prop.from), "a hole in the camera at \(prop.from)")
                        #expect(!(0.8 + 1e-9..<0.95 - 1e-9).contains(prop.from), "a hole in the way of another at \(prop.from)")
                    }
                }
                #expect(penguinPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
            }
        }
        #expect(through >= 20 && waddles > 100, "it went through the camera on its belly \(through) times, and waddled \(waddles) legs")
        var closed = PenDrive(seed: 3, position: 0.2, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 156)
        closed.lane = LaneContext(crossing: [crossing], closed: [crossing])
        closed.run(2 * 3600)
        for pose in closed.every { #expect(max(pose.from, pose.to) <= crossing.lowerBound + 1e-9, "it keeps out of the closed crossing: \(pose.from) to \(pose.to)") }
    }

    @Test func aWaddleNeverGoesThroughTheCrossingEvenWhenItIsTheOnlyWayItCouldGoAndTheLongGlideToTheFarEndDoes() {
        // On a lane that is all crossing but its ends, the far end is across it: only a glide gets there.
        var crossings = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, position: 0.1, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 200)
            drive.lane = LaneContext(crossing: [0.25...0.75])
            drive.run(3 * 3600)
            let stands = drive.every.filter { $0.from == $0.to }.map(\.to)
            #expect(stands.contains { $0 < 0.25 } && stands.contains { $0 > 0.75 }, "it is on both sides now and then")
            for pose in drive.every where pose.from != pose.to && min(pose.from, pose.to) < 0.75 && max(pose.from, pose.to) > 0.25 {
                crossings += 1
                #expect(PenguinMove(pose.motion) == .slide)
            }
        }
        #expect(crossings >= 6, "\(crossings)")
    }

    // MARK: What it fishes in

    @Test func whatItHasOutStartsAndEndsInOrderThroughHoursOfDaysAndMacs() {
        var seen: Set<PenguinProp> = []
        for load in [0.03, 0.5, 0.9] {
            for hour in [14, 23] {
                for seed in 1...6 as ClosedRange<UInt64> {
                    var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: load, hour: hour))
                    drive.run(3 * 3600)
                    #expect(penguinPropProblems(drive.trail).isEmpty, "seed \(seed) at \(hour), load \(load): \(penguinPropProblems(drive.trail).prefix(4))")
                    #expect(drive.brain.strayProps == 0, "nothing left over when a scene began")
                    seen.formUnion(drive.trail.compactMap(\.prop))
                }
            }
        }
        #expect(seen == Set(PenguinProp.allCases), "\(Set(PenguinProp.allCases).subtracting(seen))")
    }

    /// The fishing scenes cut out of a run: every picture from the hole opening to the hole's closing.
    func fishingScenes(_ drive: PenDrive) -> [[(move: PenguinMove, prop: PenguinProp?)]] {
        var found: [[(move: PenguinMove, prop: PenguinProp?)]] = []
        var current: [(move: PenguinMove, prop: PenguinProp?)]?
        for entry in drive.trail {
            if entry.prop == .holeOpening { current = [entry] } else if current != nil { current?.append(entry) }
            if entry.prop == .holeClosing, let finished = current {
                found.append(finished)
                current = nil
            }
        }
        return found
    }

    @Test func aFishingSceneIsTheHoleOpeningTheLineGoingInWaitingNowAndThenAFishAndTheLineComingInAndTheHoleClosing() {
        var scenes = 0, caught = 0, empty = 0, twice = 0
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(3 * 3600)
            for stretch in fishingScenes(drive) {
                scenes += 1
                let moves = stretch.map(\.move)
                #expect(moves.first == .stand && moves.last == .stand, "it stands to watch the hole open and close: \(moves)")
                guard let cast = moves.firstIndex(of: .cast), let reel = moves.lastIndex(of: .reel) else {
                    #expect(Bool(false), "a line in and out: \(moves)")
                    continue
                }
                #expect(cast < reel)
                #expect(moves[..<cast].allSatisfy { $0 == .stand }, "the hole stands empty until the line goes in: \(moves)")
                #expect(moves[(cast + 1)..<reel].allSatisfy { PenDrive.fishing.contains($0) }, "while the line is in it fishes: \(moves)")
                #expect(moves[(reel + 1)...].allSatisfy { $0 == .stand }, "and stands to watch it close")
                #expect(moves.contains(.fish))
                let bites = moves.indices.filter { moves[$0] == .pull }
                for pull in bites {
                    #expect(moves[pull - 1] == .bite && moves[pull + 1] == .gulp, "a bite, the fish pulled out, swallowed: \(moves)")
                }
                if bites.isEmpty { empty += 1 } else { caught += 1 }
                if bites.count > 1 { twice += 1 }
                #expect(bites.count <= 2)
            }
        }
        #expect(scenes > 25, "\(scenes)")
        #expect(caught > 5 && empty > 5, "now and then a fish, and often not: \(caught) with, \(empty) without, \(twice) with two")
        #expect(Double(caught) / Double(scenes) > 0.3 && Double(caught) / Double(scenes) < 0.85, "\(caught) of \(scenes)")
    }

    @Test func theHoleIsAStepAndABitInFrontOfItOnTheSideItFacesAndItDoesNotMoveWhileItFishesAndItsPlaceIsReservedWithTheHole() {
        var checked = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 300)
            drive.run(3 * 3600)
            var place: Double?, home: Double?, facing: Facing?
            for entry in drive.history.map(\.pose) {
                let move = PenguinMove(entry.motion)
                guard let prop = entry.prop else {
                    place = nil
                    continue
                }
                let step = PenguinMove.holeReach / 300
                if place == nil {
                    place = prop.from
                    home = entry.from
                    facing = entry.facing
                    #expect(PenguinProp(prop.look) == .holeOpening && move == .stand, "it begins under a standing penguin")
                }
                #expect(entry.from == entry.to && entry.from == home, "it stays where it stands: \(move)")
                #expect(prop.from == place && prop.to == place, "and the hole stays where it is")
                #expect(abs(abs(prop.from - entry.from) - step) < 1e-9, "a hole's reach away: \(abs(prop.from - entry.from) * 300)")
                #expect((prop.from > entry.from) == (entry.facing == .right) && entry.facing == facing, "on the side it faces, and it faces it throughout")
                #expect(prop.alsoAt == [entry.from], "the place it stands is reserved with the hole")
                #expect((0.0...1.0).contains(prop.from) && prop.look.occupies)
                // Another character is told not to stop at the hole or where the penguin stands while it is out.
                let lane = LaneRules.context(for: 1, poses: [entry, nil], crossing: [], separation: 0.05, now: entry.began)
                #expect(lane.zones.contains { $0.contains(prop.from) } && lane.zones.contains { $0.contains(entry.from) })
                checked += 1
            }
        }
        #expect(checked > 150, "\(checked)")
    }

    @Test func aLaneTooShortForAHoleHasNoneAndTheDayGoesOnAllTheSame() {
        var drive = PenDrive(seed: 5, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 8)
        drive.run(2 * 3600)
        #expect(drive.every.allSatisfy { $0.prop == nil }, "no hole: there is no room to open one")
        #expect(drive.brain.strayProps == 0)
        #expect(drive.scenes.count > 100 && drive.moves.contains(.flap) && drive.moves.contains(.lookTurn) == false)
        var none = PenDrive(seed: 5, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 0)
        none.run(3600)
        #expect(none.every.allSatisfy { $0.prop == nil && $0.from == $0.to }, "no lane at all: nothing to walk or play on")
    }

    @Test func itHasNoBackToRideOnAndTakesPartInNoSceneWithAnother() {
        var drive = PenDrive(seed: 2, senses: CatSenses(idleSeconds: 5, hour: 14))
        drive.run(2 * 3600)
        for pose in drive.every { #expect(pose.perch == nil && !pose.raised) }
        #expect(drive.brain.jointScene == nil)
        let guest = JointInvite(scene: .catOnCapybara, role: .guest, partner: drive.brain.pose)
        #expect(!drive.brain.canJoin(guest, now: drive.now))
    }
}

/// A driver for a day of a given hour.
enum PenguinDrive {
    static func day(seed: UInt64, hour: Int) -> PenDrive { PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: hour)) }
}
