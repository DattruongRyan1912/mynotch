import Foundation
import Testing
@testable import PetModule

/// The frog's brain driven by a clock the test holds: it is woken every quarter of a second, as the stage wakes it, with what it senses.
struct FrDrive {
    var brain: FrogBrain
    var now: TimeInterval = 0
    var senses = CatSenses()
    var tuning = CatTuning()
    /// How far the frog can walk, in pixels of its picture.
    var travel = 260.0
    var lane = LaneContext()

    /// Every pose that changed the picture, with the time it began.
    private(set) var history: [(at: TimeInterval, pose: Pose)] = []
    /// Every pose there was, extended or changed.
    private(set) var every: [Pose] = []
    private(set) var scenes: [FrogScene] = []
    /// How many times it has begun to watch the pointer.
    private(set) var watchings = 0
    private var wasWatching = false
    private(set) var spent: [FrogMove: TimeInterval] = [:]
    private var serial = 0
    static let step = 0.25

    init(seed: UInt64 = 1, position: Double = 0.5, senses: CatSenses = CatSenses(), tuning: CatTuning = CatTuning(), travel: Double = 260) {
        brain = FrogBrain(seed: seed, now: 0, position: position)
        self.senses = senses
        self.tuning = tuning
        self.travel = travel
    }

    var move: FrogMove { brain.move }

    @discardableResult
    mutating func run(_ seconds: Double, each: (FrogBrain) -> Void = { _ in }) -> BrainOutcome {
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
            if brain.isWatching && !wasWatching { watchings += 1 }
            wasWatching = brain.isWatching
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

    var moves: [FrogMove] { history.map { FrogMove($0.pose.motion) } }

    func share(of move: FrogMove) -> Double {
        let total = spent.values.reduce(0, +)
        return total == 0 ? 0 : (spent[move] ?? 0) / total
    }

    /// What it has out, one entry for each picture it changed to.
    var trail: [(move: FrogMove, prop: FrogProp?)] {
        history.map { (FrogMove($0.pose.motion), $0.pose.prop.map { FrogProp($0.look) }) }
    }

    static func pointer(_ share: Double, near: Bool) -> PointerReading {
        PointerReading(share: share, isNear: near, isInRange: true)
    }

    /// The moves it is on the pad in, which always have the pad under them, rippling.
    static let onThePad: Set<FrogMove> = [.padSit, .padBlink, .padPuff, .padWatch, .padFlick, .padJump, .padSleep]
}

/// What a frog is allowed to have out after what it had out. A pad comes up beside a frog that sits (and watches it), is landed on by the
/// hop on to it, ripples under a frog that sits on it, is left by the hop off it, and goes down under a frog that sits; and then nothing. A
/// moth flies in and hovers under a frog that watches it, is held for the tongue under the one that shoots it out, and is gone with the
/// tongue coming in; or is frightened off under a frog that jumps. Nothing is ever left behind, and a frog that hops or sleeps on the bank has
/// no pad on it but the one it is leaving.
func frogPropProblems(_ trail: [(move: FrogMove, prop: FrogProp?)]) -> [String] {
    var problems: [String] = []
    for (index, entry) in trail.enumerated() {
        let previous = index > 0 ? trail[index - 1] : nil
        let before = previous?.prop
        if FrDrive.onThePad.contains(entry.move), entry.prop != .padRippling { problems.append("\(index): \(entry.move) with \(String(describing: entry.prop))") }
        if entry.move == .hopOn, entry.prop != .padLanding { problems.append("\(index): hops on with \(String(describing: entry.prop))") }
        if entry.move == .hopOff, entry.prop != .padLeaping { problems.append("\(index): hops off with \(String(describing: entry.prop))") }
        if [.hop, .sleep, .snapIn, .gulp].contains(entry.move), let prop = entry.prop { problems.append("\(index): \(entry.move) with \(prop)") }
        switch entry.prop {
        case .padAppearing?:
            // (After a pad that has gone down, or a moth that was frightened off, with nothing between them: the next scene wants the pad.)
            if entry.move != .sit || !(before == nil || before == .padSinking || (before == .moth && previous?.move == .jump)) {
                problems.append("\(index): the pad comes up under a \(entry.move) after \(String(describing: before))")
            }
        case .padStill?:
            if entry.move.stance != .ground || ![.padAppearing, .padStill, .padLeaping].contains(before) { problems.append("\(index): a pad lies by a \(entry.move) after \(String(describing: before))") }
        case .padLanding?:
            if entry.move != .hopOn || ![.padAppearing, .padStill].contains(before) { problems.append("\(index): landed on from \(String(describing: before)) by \(entry.move)") }
        case .padRippling?:
            if ![.padLanding, .padRippling].contains(before) { problems.append("\(index): the pad ripples after \(String(describing: before))") }
        case .padLeaping?:
            if ![.padRippling, .padLanding].contains(before) { problems.append("\(index): left from \(String(describing: before))") }
        case .padSinking?:
            if entry.move != .sit || ![.padStill, .padLeaping, .padAppearing].contains(before) { problems.append("\(index): the pad goes down under a \(entry.move) after \(String(describing: before))") }
        case .moth?:
            if ![.watch, .jump].contains(entry.move) { problems.append("\(index): a moth by a \(entry.move)") }
            if before != nil && before != .moth && before != .padSinking { problems.append("\(index): a moth after \(String(describing: before))") }
            if entry.move == .jump && before != .moth { problems.append("\(index): a moth frightened off that was not there") }
        case .mothHeld?:
            if entry.move != .snapOut || before != .moth { problems.append("\(index): a moth held under a \(entry.move) after \(String(describing: before))") }
        case nil:
            if let before, before != .padSinking {
                let caught = before == .mothHeld && entry.move == .snapIn
                let frightened = before == .moth && previous?.move == .jump
                if !caught && !frightened { problems.append("\(index): the \(before) is gone with no taking away (\(entry.move))") }
            }
        }
    }
    return problems
}

@Suite struct FrogBrainSceneTests {
    @Test func theSameSeedMakesTheSameDayAndAnotherSeedAnotherOne() {
        func day(seed: UInt64) -> [FrogMove] {
            var drive = FrDrive(seed: seed)
            drive.run(900)
            return drive.moves
        }
        #expect(day(seed: 3) == day(seed: 3))
        #expect(day(seed: 3) != day(seed: 4))
    }

    @Test func itNeverBeginsTheSameSceneTwiceRunning() {
        for hour in [14, 23] {
            for seed in 1...12 as ClosedRange<UInt64> {
                var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: hour))
                drive.run(3600)
                #expect(drive.scenes.count > 40, "\(drive.scenes.count)")
                for (before, after) in zip(drive.scenes, drive.scenes.dropFirst()) { #expect(before != after, "seed \(seed) at \(hour): \(before) twice") }
            }
        }
    }

    @Test func everySceneComesUpAtNightItNapsAndHuntsMoreAndTheSleepTimeIsShorterThen() {
        var counts: [FrogScene: Int] = [:]
        var naps = (day: 0, night: 0)
        var dozing = (day: 0, night: 0)
        var (huntsDay, huntsNight) = (0, 0)
        for seed in 1...8 as ClosedRange<UInt64> {
            var daytime = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            daytime.run(3 * 3600)
            var overnight = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 23))
            overnight.run(3 * 3600)
            for scene in daytime.scenes { counts[scene, default: 0] += 1 }
            naps.day += daytime.scenes.filter { $0 == .nap }.count
            naps.night += overnight.scenes.filter { $0 == .nap }.count
            huntsDay += daytime.scenes.filter { $0 == .mothCatch }.count
            huntsNight += overnight.scenes.filter { $0 == .mothCatch }.count
            dozing.day += Int(daytime.share(of: .padSleep) * 1000)
            dozing.night += Int(overnight.share(of: .padSleep) * 1000)
        }
        #expect(Set(counts.keys) == Set(FrogScene.allCases), "\(Set(FrogScene.allCases).subtracting(counts.keys))")
        #expect(Double(naps.night) > Double(naps.day) * 1.5, "more napping at night: \(naps.night) against \(naps.day)")
        #expect(Double(dozing.night) > Double(dozing.day) * 1.5, "more of its time asleep on the pad at night: \(dozing.night) against \(dozing.day)")
        #expect(huntsNight > huntsDay, "more moths at night: \(huntsNight) against \(huntsDay)")
        // The same idle time that is not enough by day is by night: the threshold is shorter then.
        var byDay = FrDrive(seed: 2, senses: CatSenses(idleSeconds: 120, hour: 14))
        var byNight = FrDrive(seed: 2, senses: CatSenses(idleSeconds: 120, hour: 23))
        byDay.run(300)
        byNight.run(300)
        // (A doze on the pad is a scene of the day too, and is shorter than a sleep that goes on until the user is back.)
        func slept(_ drive: FrDrive) -> Int { drive.every.filter { [.sleep, .padSleep].contains(FrogMove($0.motion)) && $0.duration == FrogBrain.sleepChunk }.count }
        #expect(slept(byDay) == 0 && slept(byNight) > 5, "\(slept(byDay)) by day, \(slept(byNight)) by night")
    }

    // MARK: Hopping

    @Test func aHopIsTheSameHopAtAnyLoadAndAWholeNumberOfThemAndNothingIsQuickenedForTheMac() {
        for load in [0.05, 0.5, 0.9, 1.0] {
            for burst in [false, true] {
                for seed in 1...4 as ClosedRange<UInt64> {
                    var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: load, busyBurst: burst, hour: 14))
                    drive.run(2 * 3600)
                    var kinds: Set<FrogMove> = []
                    var (legs, whole) = (0, 0)
                    for pose in drive.every where pose.from != pose.to {
                        let move = FrogMove(pose.motion)
                        let covered = abs(pose.to - pose.from) * drive.travel
                        kinds.insert(move)
                        #expect([FrogMove.hop, .hopOn, .hopOff].contains(move), "\(move) goes somewhere")
                        #expect(pose.fpsScale == 1 && pose.delay == 0, "no quickening: \(move)")
                        if move == .hop {
                            #expect(abs(covered / pose.duration - FrogMove.hop.speed) < 1e-6, "a hop at \(covered / pose.duration) points a second, not \(FrogMove.hop.speed)")
                            legs += 1
                            if abs(covered / FrogMove.hopLength - (covered / FrogMove.hopLength).rounded()) < 1e-6 { whole += 1 }
                        } else {
                            #expect(abs(covered - FrogMove.hopSpan) < 1e-6 && abs(pose.duration - move.passDuration) < 1e-9, "\(move): \(covered) points in \(pose.duration) s")
                        }
                    }
                    #expect(kinds == [.hop, .hopOn, .hopOff], "load \(load) burst \(burst) seed \(seed): \(kinds)")
                    #expect(legs > 50 && Double(whole) / Double(legs) > 0.97, "\(whole) of \(legs) legs end on a landing")
                }
            }
        }
    }

    @Test func aLegOfHopsIsAWholeNumberOfHopsWhichIsWhatMakesItEndOnALanding() {
        #expect(FrogMove.hopLength == FrogMove.hop.advance * Double(FrogMove.hop.frameCount) && FrogMove.hopLength == 18)
        #expect(FrogMove.hopSpan == FrogMove.hopOn.passDuration * 32 && FrogMove.hopSpan / Double(FrogMove.hopOn.frameCount) <= Double(CatField.leastEndError))
        // Whatever it is sent to, a leg is a whole number of hops long: the lane has its say about where it stops, and a leg is rounded to what
        // the lane allows.
        var (legs, whole) = (0, 0)
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, position: 0.3, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 237)
            drive.lane = LaneContext(crossing: [0.45...0.55], zones: [0.8...0.95])
            drive.run(3 * 3600)
            for pose in drive.every where FrogMove(pose.motion) == .hop {
                legs += 1
                let hops = abs(pose.to - pose.from) * 237 / FrogMove.hopLength
                if abs(hops - hops.rounded()) < 1e-6 { whole += 1 }
            }
        }
        // (A few end where the lane stops them, against the edge of what another stands in, which is not a whole number of hops from anywhere.)
        #expect(legs > 300 && Double(whole) / Double(legs) > 0.95, "\(whole) of \(legs)")
    }

    @Test func theBusierTheMacTheMoreItHopsAboutAndABurstOfWorkSendsItHoppingAtOnceAndWithTheReactionOffNothingChanges() {
        func hopping(load: Double, burst: Bool = false, reacts: Bool = true) -> (scenes: Double, time: Double, legs: Double) {
            var scenes = 0, all = 0, legs = 0
            var time = 0.0
            for seed in 1...8 as ClosedRange<UInt64> {
                var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: load, busyBurst: burst, hour: 14))
                drive.tuning.reactsToBusyMachine = reacts
                drive.run(3 * 3600)
                scenes += drive.scenes.filter { $0 == .hopAbout }.count
                all += drive.scenes.count
                time += drive.share(of: .hop)
                legs += drive.history.filter { FrogMove($0.pose.motion) == .hop }.count
            }
            return (Double(scenes) / Double(all), time / 8, Double(legs) / 8)
        }
        let (quiet, edge, busy, flat) = (hopping(load: 0.05), hopping(load: 0.6), hopping(load: 0.8), hopping(load: 1.0))
        #expect(quiet.scenes > 0.04 && quiet.scenes < 0.2, "a part of its day, quiet: \(quiet)")
        #expect(abs(edge.scenes - quiet.scenes) < 0.03, "the line is where it starts: \(edge) against \(quiet)")
        #expect(busy.scenes > quiet.scenes * 1.8 && flat.scenes > busy.scenes, "more of them the busier it is: \(quiet.scenes), \(busy.scenes), \(flat.scenes)")
        #expect(flat.time > quiet.time * 1.8, "and more of its time hopping: \(quiet.time) against \(flat.time)")
        #expect(flat.legs > quiet.legs * 1.8, "and more legs of hops: \(quiet.legs) against \(flat.legs)")
        let bursting = hopping(load: 0.05, burst: true)
        #expect(bursting.scenes > quiet.scenes * 1.5, "a burst counts as a busy Mac: \(bursting) against \(quiet)")
        let off = hopping(load: 1.0, burst: true, reacts: false)
        #expect(abs(off.scenes - quiet.scenes) < 1e-9 && abs(off.time - quiet.time) < 1e-9, "with the reaction off a busy Mac is a quiet one")
        var calm = FrDrive(seed: 3, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.05, hour: 14))
        var same = FrDrive(seed: 3, senses: CatSenses(idleSeconds: 5, cpuLoad: 1, busyBurst: true, hour: 14))
        same.tuning.reactsToBusyMachine = false
        calm.run(3600)
        same.run(3600)
        #expect(calm.moves == same.moves && calm.history.map(\.pose) == same.history.map(\.pose), "with the reaction off a busy Mac changes nothing")
    }

    @Test func aBusyMacHasLessRestBetweenHopsAndNeverAQuickerHop() {
        func rest(load: Double) -> Double {
            var (total, count) = (0.0, 0)
            for seed in 1...8 as ClosedRange<UInt64> {
                var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: load, hour: 14))
                drive.run(3 * 3600)
                let poses = drive.history.map(\.pose)
                for (before, after) in zip(poses, poses.dropFirst()) where FrogMove(before.motion) == .hop && FrogMove(after.motion) == .sit {
                    total += after.duration
                    count += 1
                }
                for pose in drive.every { #expect(pose.fpsScale == 1 && FrogMove(pose.motion).fps <= FrogMove.snapOut.fps) }
            }
            return total / Double(max(count, 1))
        }
        let (quiet, busy) = (rest(load: 0.05), rest(load: 1.0))
        #expect(busy < quiet * 0.75, "rests of \(busy) s when busy and \(quiet) s when quiet")
    }

    @Test func aBurstOfWorkSendsItHoppingAtOnceAndOnlyOnceForTheBurst() {
        /// Standing about with nothing out and nothing under way: where a burst finds it most of the time.
        func free(_ brain: FrogBrain) -> Bool {
            brain.stance == .ground && brain.scene != .hopAbout && !brain.hasProps && !FrogBrain.unbroken.contains(brain.move)
                && !FrogBrain.holds.contains(brain.move) && !(brain.move == .hop && brain.pose.from != brain.pose.to) && !brain.isAsleep
        }
        var checked = 0
        for seed in 1...60 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(40 + Double(seed) * 3)
            guard free(drive.brain) else { continue }
            let scenes = drive.scenes.count
            drive.senses.busyBurst = true
            drive.run(0.25)
            #expect(drive.brain.scene == .hopAbout && drive.scenes.count == scenes + 1, "seed \(seed): \(String(describing: drive.brain.scene))")
            #expect(drive.move == .hop || drive.move == .sit, "and it is off: \(drive.move)")
            // The burst goes on for forty seconds: it did not go off again and again for it.
            drive.run(40)
            #expect(drive.scenes.count <= scenes + 6, "seed \(seed): \(drive.scenes.count - scenes) scenes in the burst")
            checked += 1
            // A burst is heard of once, so another one is heard of again.
            drive.senses.busyBurst = false
            drive.run(60)
            var waited = 0.0
            while waited < 120, !free(drive.brain) {
                drive.run(0.25)
                waited += 0.25
            }
            guard free(drive.brain) else { continue }
            drive.senses.busyBurst = true
            drive.run(0.25)
            #expect(drive.brain.scene == .hopAbout, "seed \(seed): the next burst: \(String(describing: drive.brain.scene))")
            #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        #expect(checked >= 8, "\(checked)")
    }

    // MARK: The camera

    @Test func itNeverStopsInTheCrossingOrInTheWayOfAnotherAndNothingGoesIntoWhatIsClosedAndNeitherPadNorMothIsInTheCamera() {
        let crossing: ClosedRange<Double> = 0.4...0.6
        var (through, others, props) = (0, 0, 0)
        for load in [0.05, 0.9] {
            for seed in 1...8 as ClosedRange<UInt64> {
                var drive = FrDrive(seed: seed, position: 0.2, senses: CatSenses(idleSeconds: 5, cpuLoad: load, hour: 14), travel: 156)
                drive.lane = LaneContext(crossing: [crossing], zones: [0.8...0.95])
                drive.run(3 * 3600)
                for pose in drive.every {
                    let move = FrogMove(pose.motion)
                    if pose.from == pose.to {
                        #expect(!(crossing.lowerBound + 1e-9..<crossing.upperBound - 1e-9).contains(pose.to), "seed \(seed): a \(move) at \(pose.to)")
                        #expect(!(0.8 + 1e-9..<0.95 - 1e-9).contains(pose.to), "in the way of another at \(pose.to)")
                    }
                    let (low, high) = (min(pose.from, pose.to), max(pose.from, pose.to))
                    if high > crossing.lowerBound && low < crossing.upperBound {
                        through += 1
                        #expect(move == .hop, "seed \(seed): a \(move) goes through the crossing, from \(pose.from) to \(pose.to)")
                    } else if pose.from != pose.to {
                        others += 1
                    }
                    if let prop = pose.prop {
                        props += 1
                        let places = [prop.from, prop.to] + prop.alsoAt
                        let (propLow, propHigh) = (places.min() ?? 0, places.max() ?? 0)
                        #expect(!(propHigh > crossing.lowerBound && propLow < crossing.upperBound), "seed \(seed): a prop in the camera or across it, \(propLow) to \(propHigh)")
                        if FrogProp(prop.look).isPad {
                            for place in [prop.to] + prop.alsoAt { #expect(!(0.8 + 1e-9..<0.95 - 1e-9).contains(place), "a pad in the way of another at \(place)") }
                        }
                    }
                }
                #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
            }
        }
        #expect(through >= 20 && others > 200 && props > 300, "it went through the camera \(through) times, and went about on one side \(others) legs, with \(props) poses with a prop")
        var closed = FrDrive(seed: 3, position: 0.2, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 156)
        closed.lane = LaneContext(crossing: [crossing], closed: [crossing])
        closed.run(2 * 3600)
        for pose in closed.every { #expect(max(pose.from, pose.to) <= crossing.lowerBound + 1e-9, "it keeps out of the closed crossing: \(pose.from) to \(pose.to)") }
    }

    @Test func aLegOfHopsGoesThroughTheCrossingWhenTheFarEndIsTheOnlyWayItCouldGo() {
        var crossings = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, position: 0.1, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 200)
            drive.lane = LaneContext(crossing: [0.25...0.75])
            drive.run(3 * 3600)
            let stands = drive.every.filter { $0.from == $0.to }.map(\.to)
            #expect(stands.contains { $0 < 0.25 } && stands.contains { $0 > 0.75 }, "it is on both sides now and then")
            for pose in drive.every where pose.from != pose.to && min(pose.from, pose.to) < 0.75 && max(pose.from, pose.to) > 0.25 {
                crossings += 1
                #expect(FrogMove(pose.motion) == .hop)
            }
        }
        #expect(crossings >= 6, "\(crossings)")
    }

    @Test func theHopOnToAPadIsNeverAcrossACameraThatIsNarrowerThanTheHopItself() {
        // (The real camera's crossing is wider than the hop on to the pad, so it cannot be straddled: this is the rule on its own. A hop of
        // twenty-four points would otherwise begin on one side of a crossing of twelve and end on the other.)
        var pads = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, position: 0.2, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 300)
            drive.lane = LaneContext(crossing: [0.47...0.51])
            drive.run(3 * 3600)
            for pose in drive.every where [.hopOn, .hopOff].contains(FrogMove(pose.motion)) {
                pads += 1
                let (low, high) = (min(pose.from, pose.to), max(pose.from, pose.to))
                #expect(!(high > 0.47 && low < 0.51), "seed \(seed): a hop on or off from \(pose.from) to \(pose.to) across the camera")
            }
            #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        #expect(pads > 100, "\(pads)")
    }

    // MARK: The lily pad

    @Test func whatItHasOutStartsAndEndsInOrderThroughHoursOfDaysAndMacs() {
        var seen: Set<FrogProp> = []
        for load in [0.03, 0.5, 0.9] {
            for hour in [14, 23] {
                for seed in 1...6 as ClosedRange<UInt64> {
                    var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: load, hour: hour))
                    drive.run(3 * 3600)
                    #expect(frogPropProblems(drive.trail).isEmpty, "seed \(seed) at \(hour), load \(load): \(frogPropProblems(drive.trail).prefix(4))")
                    #expect(drive.brain.strayProps == 0, "nothing left over when a scene began")
                    seen.formUnion(drive.trail.compactMap(\.prop))
                }
            }
        }
        // (A pad that lies with nobody on it is only seen when something comes between its coming up and the hop on: the pointer.)
        #expect(seen == Set(FrogProp.allCases).subtracting([.padStill]), "\(Set(FrogProp.allCases).subtracting(seen))")
    }

    /// The scenes with a pad cut out of a run: every pose from the pad coming up to the pad having gone down.
    func padRounds(_ drive: FrDrive) -> [[Pose]] {
        var found: [[Pose]] = []
        var current: [Pose]?
        for entry in drive.history.map(\.pose) {
            let prop = entry.prop.map { FrogProp($0.look) }
            if prop == .padAppearing { current = [entry] } else if current != nil { current?.append(entry) }
            if prop == .padSinking, let finished = current {
                found.append(finished)
                current = nil
            }
        }
        return found
    }

    @Test func aPadRoundIsThePadComingUpTheHopOnSittingOnItTheHopOffAndThePadGoingDownAllWithinTheLane() throws {
        var rounds = 0
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 300)
            drive.run(3 * 3600)
            for round in padRounds(drive) {
                rounds += 1
                let moves = round.map { FrogMove($0.motion) }
                #expect(moves.first == .sit && moves[1] == .hopOn && Array(moves.suffix(2)) == [.hopOff, .sit], "\(moves)")
                let (coming, on, off, sinking) = (round[0], round[1], round[round.count - 2], round[round.count - 1])
                let (rising, landing) = (try #require(coming.prop), try #require(on.prop))
                let home = coming.from
                let way = coming.facing == .right ? 1.0 : -1.0
                let place = home + way * FrogMove.hopSpan / 300
                #expect(coming.from == coming.to && coming.duration == FrogProp.padAppearing.passDuration, "it sits and watches for as long as the pad takes")
                #expect(abs(rising.from - place) < 1e-9 && rising.from == rising.to && rising.look.occupies, "the pad is a hop in front of it")
                #expect(rising.alsoAt == [home], "and the place it hops from is room that nobody else stops in")
                #expect(on.from == home && abs(on.to - place) < 1e-9 && on.facing == coming.facing && abs(on.duration - FrogMove.hopOn.passDuration) < 1e-9, "it hops on")
                #expect(FrogProp(landing.look) == .padLanding && abs(landing.to - place) < 1e-9 && landing.alsoAt == [home])
                // Whatever it does on the pad is on the pad: the pad is where it is, and it does not go anywhere.
                for pose in round[2..<(round.count - 2)] {
                    let move = FrogMove(pose.motion)
                    #expect(move.stance == .pad && pose.from == pose.to && abs(pose.to - place) < 1e-9, "\(move) on the pad")
                    #expect(pose.prop.map { FrogProp($0.look) == .padRippling && abs($0.to - place) < 1e-9 && $0.alsoAt == [home] } ?? false)
                }
                #expect(abs(off.from - place) < 1e-9 && abs(off.to - home) < 1e-9 && off.facing != coming.facing && abs(off.duration - FrogMove.hopOff.passDuration) < 1e-9, "it hops off the way it came")
                #expect(off.prop.map { FrogProp($0.look) } == .padLeaping)
                #expect(sinking.from == home && sinking.to == home && sinking.duration == FrogProp.padSinking.passDuration)
                #expect(sinking.prop.map { FrogProp($0.look) } == .padSinking && abs((sinking.prop?.to ?? 0) - place) < 1e-9)
                for pose in round { #expect(pose.prop.map { (0.0...1.0).contains($0.from) && (0.0...1.0).contains($0.to) } ?? true, "the pad is on the lane") }
            }
        }
        #expect(rounds > 40, "\(rounds)")
    }

    @Test func aNapIsADozeOnThePadWithItsEyesShutAndAMoreOfItAtNight() {
        var dozes = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 23))
            drive.run(3 * 3600)
            for round in padRounds(drive) where round.contains(where: { FrogMove($0.motion) == .padSleep }) {
                dozes += 1
                let moves = round.map { FrogMove($0.motion) }
                let at = moves.firstIndex(of: .padSleep)!
                #expect(moves[at - 1] == .padSit && moves[at + 1] == .padSit && moves[1] == .hopOn, "\(moves)")
                #expect(round[at].duration >= 10, "a good while: \(round[at].duration)")
                #expect(FrogArt.animation(for: .padSleep).frames.allSatisfy { $0.cells.contains("Z") })
            }
        }
        #expect(dozes > 15, "\(dozes)")
    }

    // MARK: The moth

    /// The moth hunts cut out of a run: every pose from the moth coming in to the tongue taking it in.
    func hunts(_ drive: FrDrive) -> [[Pose]] {
        var found: [[Pose]] = []
        var current: [Pose]?
        for entry in drive.history.map(\.pose) {
            let prop = entry.prop.map { FrogProp($0.look) }
            if prop == .moth, current == nil, FrogMove(entry.motion) == .watch { current = [entry] } else if current != nil { current?.append(entry) }
            if FrogMove(entry.motion) == .snapIn, let finished = current {
                found.append(finished)
                current = nil
            }
            if FrogMove(entry.motion) == .jump { current = nil }
        }
        return found
    }

    @Test func aHuntIsTheMothFlyingInFromTheEndOfTheLaneHoveringAtTheTipOfItsTongueTheTongueGoingOutAndTheMothBeingGone() throws {
        var hunts = 0
        for crossing in [nil, 0.4...0.6 as ClosedRange<Double>?] {
            for seed in 1...8 as ClosedRange<UInt64> {
                var drive = FrDrive(seed: seed, position: 0.2, senses: CatSenses(idleSeconds: 5, hour: 23), travel: 300)
                if let crossing { drive.lane = LaneContext(crossing: [crossing]) }
                drive.run(3 * 3600)
                for hunt in self.hunts(drive) {
                    hunts += 1
                    let moves = hunt.map { FrogMove($0.motion) }
                    #expect(moves == [.watch, .watch, .snapOut, .snapIn], "\(moves)")
                    let (flying, hovering, snapping, reeling) = (hunt[0], hunt[1], hunt[2], hunt[3])
                    let moth = try #require(flying.prop)
                    let way = flying.facing == .right ? 1.0 : -1.0
                    let reach = way > 0 ? FrogMove.mothReach.right : FrogMove.mothReach.left
                    let place = flying.from + reach / 300
                    #expect(flying.from == flying.to && FrogProp(moth.look) == .moth && moth.look.flutters && !moth.look.occupies, "it sits and watches it come")
                    #expect(abs(moth.to - place) < 1e-9, "to the tip of its tongue: \(moth.to) and \(place)")
                    // It comes in from outside the lane, at the end of it that the frog faces, and the moth is not across the camera.
                    #expect(way > 0 ? moth.from > 1 : moth.from < 0, "from outside the lane: \(moth.from)")
                    if let crossing { #expect(max(moth.from, moth.to) <= crossing.lowerBound || min(moth.from, moth.to) >= crossing.upperBound, "the moth's way is on one side of the camera") }
                    let speed = abs(moth.to - moth.from) * 300 / flying.duration
                    #expect(speed <= FrogBrain.mothSpeed + 1e-6 && flying.duration >= 1, "a moth flies at \(speed)")
                    #expect(hovering.from == hovering.to && hovering.facing == flying.facing && hovering.prop?.from == place && hovering.prop?.to == place)
                    #expect(snapping.prop.map { FrogProp($0.look) } == .mothHeld && snapping.prop?.look.flutters == false && snapping.prop?.from == place)
                    #expect(snapping.duration == FrogMove.snapOut.passDuration && snapping.from == snapping.to && snapping.facing == flying.facing)
                    #expect(reeling.prop == nil && reeling.duration == FrogMove.snapIn.passDuration, "the moth is gone")
                    #expect(hovering.duration >= 1.5 && hovering.duration <= 3.5)
                }
            }
        }
        #expect(hunts > 40, "\(hunts)")
    }

    @Test func aHuntIsFollowedByAGulpAndNowAndThenThereIsASecondMoth() {
        var (scenes, doubles, gulps) = (0, 0, 0)
        for seed in 1...12 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 23))
            drive.run(3 * 3600)
            let moves = drive.moves
            for (index, move) in moves.enumerated() where move == .snapIn {
                #expect(index + 1 < moves.count ? moves[index + 1] == .gulp : true, "the gulp")
                gulps += 1
            }
            scenes += drive.scenes.filter { $0 == .mothCatch }.count
            doubles += moves.filter { $0 == .snapIn }.count
            #expect(drive.brain.strayProps == 0)
        }
        #expect(scenes > 25 && doubles > scenes && gulps == doubles, "\(scenes) scenes, \(doubles) moths")
        #expect(doubles < scenes * 2 - scenes / 4, "and mostly one: \(scenes) scenes, \(doubles) moths")
    }

    // MARK: No room

    @Test func aLaneTooShortForAPadOrAMothHasNoneAndTheDayGoesOnAllTheSame() {
        var drive = FrDrive(seed: 5, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 8)
        drive.run(2 * 3600)
        #expect(drive.every.allSatisfy { $0.prop.map { FrogProp($0.look).isMoth } ?? true }, "no pad: there is no room for the hop on to it (a moth is not in the way of anything)")
        #expect(drive.brain.strayProps == 0)
        #expect(drive.scenes.count > 100 && !drive.moves.contains(.hopOn))
        var none = FrDrive(seed: 5, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 0)
        none.run(3600)
        #expect(none.every.allSatisfy { $0.prop == nil && $0.from == $0.to }, "no lane at all: nothing to hop on or to hunt")
    }

    @Test func inALaneSoCrowdedThatNothingIsFreeItHasNoPadAndNoMothAndTheDayGoesOnAllTheSame() {
        // Two characters' zones that touch and so are joined, and cover the whole lane: `LaneKeeper.settled` has nowhere to send a place and gives
        // it back, which is no place for a pad, so it asks whether a place is free and not whether it was given back.
        var props = 0, scenes = 0
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, position: 0.3, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 237)
            drive.lane = LaneContext(zones: [-0.01...0.61, 0.6...1.2])
            drive.run(3 * 3600)
            props += drive.every.filter { $0.prop != nil }.count
            scenes += drive.scenes.count
            #expect(drive.brain.strayProps == 0)
        }
        #expect(props == 0 && scenes > 300, "\(props) poses with a prop in \(scenes) scenes")
        // And with a stretch that is free, there is a pad and a moth.
        var free = FrDrive(seed: 3, position: 0.3, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 237)
        free.lane = LaneContext(zones: [0.8...1.2])
        free.run(3 * 3600)
        #expect(free.every.contains { $0.prop.map { FrogProp($0.look).isMoth } == false } && free.every.contains { $0.prop.map { FrogProp($0.look).isMoth } == true })
    }

    @Test func itNeverHasThePadWhereAnotherCharacterStandsOrWillStandAndTheNotStoppingZonesAreKept() {
        var checked = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, position: 0.1, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 300)
            drive.lane = LaneContext(crossing: [0.45...0.55], zones: [0.2...0.34, 0.8...0.9])
            drive.run(3 * 3600)
            for pose in drive.every {
                guard let prop = pose.prop, FrogProp(prop.look).isPad else { continue }
                checked += 1
                for place in [prop.from, prop.to, pose.from, pose.to] {
                    #expect(!(0.45 + 1e-9..<0.55 - 1e-9).contains(place), "in the camera at \(place)")
                }
                for place in [prop.to] + prop.alsoAt {
                    #expect(!(0.2 + 1e-9..<0.34 - 1e-9).contains(place) && !(0.8 + 1e-9..<0.9 - 1e-9).contains(place), "in the way of another at \(place)")
                }
            }
            #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        #expect(checked > 150, "\(checked)")
    }

    @Test func itHasNoBackToSitOnAndTakesPartInNoSceneWithAnother() {
        var drive = FrDrive(seed: 2, senses: CatSenses(idleSeconds: 5, hour: 14))
        drive.run(2 * 3600)
        for pose in drive.every { #expect(pose.perch == nil && !pose.raised) }
        #expect(drive.brain.jointScene == nil)
        let guest = JointInvite(scene: .catOnCapybara, role: .guest, partner: drive.brain.pose)
        #expect(!drive.brain.canJoin(guest, now: drive.now))
    }
}
