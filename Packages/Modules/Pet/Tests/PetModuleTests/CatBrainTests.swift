import Foundation
import Testing
@testable import PetModule

/// A brain driven by a clock the test holds: it is woken every quarter of a second, as the stage wakes it, with what it senses.
struct Drive {
    var brain: CatBrain
    var now: TimeInterval = 0
    var senses = CatSenses()
    var tuning = CatTuning()
    /// How far the cat can walk, in points.
    var travel = 260.0

    struct Entry {
        let at: TimeInterval
        let plan: CatPlan
    }

    /// Every plan that changed the picture, with the time it began.
    private(set) var history: [Entry] = []
    /// The scenes begun, in order, with the time.
    private(set) var scenes: [CatScene] = []
    /// Seconds spent in each move.
    private(set) var spent: [CatMove: TimeInterval] = [:]
    private var serial = 0
    static let step = 0.25

    init(seed: UInt64 = 1, position: Double = 0.5, senses: CatSenses = CatSenses(), tuning: CatTuning = CatTuning(), travel: Double = 260) {
        brain = CatBrain(seed: seed, now: 0, position: position)
        self.senses = senses
        self.tuning = tuning
        self.travel = travel
    }

    var move: CatMove { brain.plan.move }

    @discardableResult
    mutating func run(_ seconds: Double) -> CatBrain.Outcome {
        var last = CatBrain.Outcome.unchanged
        let end = now + seconds
        while now < end - 1e-9 {
            now += Self.step
            let outcome = brain.update(now: now, senses: senses, tuning: tuning, travel: travel)
            if outcome == .changed { history.append(Entry(at: now, plan: brain.plan)) }
            if outcome != .unchanged { last = outcome }
            if brain.sceneSerial != serial {
                serial = brain.sceneSerial
                if let scene = brain.scene { scenes.append(scene) }
            }
            spent[brain.plan.move, default: 0] += Self.step
        }
        return last
    }

    var moves: [CatMove] { history.map(\.plan.move) }

    /// A stroke.
    mutating func pet() {
        if brain.pet(now: now) == .changed { history.append(Entry(at: now, plan: brain.plan)) }
    }

    func share(of move: CatMove) -> Double {
        let total = spent.values.reduce(0, +)
        return total == 0 ? 0 : (spent[move] ?? 0) / total
    }

    /// The pointer, at `share` of the lane: near, or only in sight.
    static func pointer(_ share: Double, near: Bool, above: Bool = true) -> PointerReading {
        PointerReading(share: share, isNear: near, isInRange: true, isAbove: above)
    }
}

/// A quarter of a second: one waking of the stage.
let wake = Drive.step

@Suite struct CatBrainSceneTests {
    @Test func theSameSeedMakesTheSameDayAndAnotherSeedAnotherOne() {
        func day(seed: UInt64) -> [CatMove] {
            var drive = Drive(seed: seed)
            drive.run(900)
            return drive.moves
        }
        #expect(day(seed: 3) == day(seed: 3))
        #expect(day(seed: 3) != day(seed: 4))
    }

    @Test func itNeverBeginsTheSameSceneTwiceRunning() {
        for hour in [14, 23] {
            for seed in 1...20 as ClosedRange<UInt64> {
                var drive = Drive(seed: seed, senses: CatSenses(idleSeconds: 60, hour: hour))
                drive.run(3600)
                #expect(drive.scenes.count > 100)
                for (before, after) in zip(drive.scenes, drive.scenes.dropFirst()) {
                    #expect(before != after, "seed \(seed) at \(hour): \(before) twice")
                }
            }
        }
    }

    @Test func byDayItPlaysEverySceneButNappingAndByNightItNaps() {
        var day = Set<CatScene>()
        var night = Set<CatScene>()
        for seed in 1...6 as ClosedRange<UInt64> {
            var daytime = Drive(seed: seed, senses: CatSenses(idleSeconds: 60, hour: 14))
            daytime.run(3600)
            day.formUnion(daytime.scenes)
            var overnight = Drive(seed: seed, senses: CatSenses(idleSeconds: 60, hour: 23))
            overnight.run(3600)
            night.formUnion(overnight.scenes)
        }
        let everyDay = Set(CatScene.allCases).subtracting([.nap, .pounceAtPointer, .fret])
        #expect(day == everyDay, "\(everyDay.subtracting(day))")
        #expect(!day.contains(.fret), "a quiet Mac does not make it sweat")
        #expect(night.contains(.nap))
        #expect(!day.contains(.nap))
    }

    @Test func overADayAndANightItShowsEveryMoveItHas() {
        var seen = Set<CatMove>()
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = Drive(seed: seed, tuning: CatTuning(sleepAfter: 120))
            for minute in 0..<60 {
                drive.senses.idleSeconds = [14: 400, 11: 60, 12: 60, 13: 60, 8: 20, 9: 20, 10: 20][minute % 15] ?? 5
                drive.senses.cpuLoad = minute % 11 == 5 || minute % 11 == 6 ? 0.9 : 0.05
                drive.senses.busyBurst = minute % 11 == 5
                drive.senses.audioPlaying = minute % 13 == 7
                drive.senses.hour = minute < 30 ? 14 : 23
                drive.senses.pointer = minute % 9 == 3 ? Drive.pointer(0.6, near: minute % 18 == 3) : nil
                if minute % 20 == 4 { drive.pet() }
                drive.run(60)
            }
            seen.formUnion(drive.moves)
        }
        let missing = Set(CatMove.allCases).subtracting(seen)
        #expect(missing.isEmpty, "never shown: \(missing)")
    }

    @Test func aCatThatSitsOnForAnotherSitIsStillTheSamePictureSoNothingIsRedrawn() {
        // A lane too short to walk on: it sits, and the sit after a sit is not a new picture.
        var drive = Drive(seed: 1, travel: 0)
        var sawExtended = false
        for _ in 0..<800 where drive.run(wake) == .extended { sawExtended = true }
        #expect(sawExtended)
    }

    // MARK: Standing up and sitting down

    @Test func itOnlyChangesHowItIsByGettingUpSittingDownOrLyingDown() {
        for seed in 1...12 as ClosedRange<UInt64> {
            var drive = Drive(seed: seed, senses: CatSenses(idleSeconds: 60, hour: 23))
            drive.run(1800)
            let plans = drive.history.map(\.plan)
            for (before, after) in zip(plans, plans.dropFirst()) {
                guard let was = before.move.stance, let now = after.move.stance, was != now else { continue }
                let hop: [CatMove] = [.standUp, .sitDown, .lieDown]
                #expect(
                    hop.contains(after.move) || (was == .lying && now == .seated),
                    "seed \(seed): \(before.move) to \(after.move) without getting up or down"
                )
            }
        }
    }

    @Test func aWalkBeginsWithTheCatOnItsFeet() {
        var drive = Drive(seed: 2)
        drive.run(1200)
        let plans = drive.history.map(\.plan)
        #expect(plans.contains { $0.move == .walk })
        for (before, after) in zip(plans, plans.dropFirst()) where after.move == .walk {
            #expect(before.move.stance == .standing || before.move == .peek, "\(before.move) then a walk")
        }
        #expect(plans.contains { $0.move == .standUp } && plans.contains { $0.move == .sitDown })
    }

    // MARK: Walking

    @Test func itNeverLeavesTheLaneAndEachPlanBeginsWhereTheLastOneEnded() {
        for seed in 1...12 as ClosedRange<UInt64> {
            var drive = Drive(seed: seed, position: 0.95)
            drive.run(1800)
            var place = 0.95
            for entry in drive.history {
                let plan = entry.plan
                #expect((0.0...1.0).contains(plan.from) && (0.0...1.0).contains(plan.to), "seed \(seed): \(plan)")
                #expect(abs(plan.from - place) < 1e-9, "seed \(seed) at \(entry.at): \(plan.move) starts at \(plan.from), not \(place)")
                place = plan.to
            }
            let goes = drive.history.map(\.plan).filter { $0.move == .walk }
            #expect(goes.contains { $0.facing == .left } && goes.contains { $0.facing == .right })
            for walk in goes { #expect(walk.facing == (walk.to > walk.from ? .right : .left)) }
        }
    }

    @Test func aWalkTakesTheTimeItTakesAtTheMovesOwnPace() {
        var drive = Drive(seed: 2)
        drive.run(2400)
        let goes = drive.history.map(\.plan).filter { [CatMove.walk, .trot].contains($0.move) }
        #expect(goes.count > 20)
        for plan in goes {
            let distance = abs(plan.to - plan.from) * 260
            #expect(abs(plan.duration - distance / plan.move.speed) < 1e-9, "\(plan.move)")
            #expect(distance >= 1)
        }
        #expect(CatMove.walk.speed == 24)
        #expect(CatMove.trot.speed == 48)
    }

    @Test func aLaneTooShortToWalkOnHasTheCatStayWhereItIs() {
        var drive = Drive(seed: 2, travel: 0)
        drive.run(1200)
        #expect(!drive.moves.contains(.walk) && !drive.moves.contains(.trot))
        for entry in drive.history where entry.plan.move != .pounce { #expect(entry.plan.from == entry.plan.to) }
    }

    @Test func itIsWhereThePlanSaysAtEveryMomentOfAWalkAndOfAPounce() {
        let plan = CatPlan(move: .walk, facing: .right, from: 0.2, to: 0.8, began: 10, duration: 5)
        #expect(plan.position(at: 10) == 0.2)
        #expect(abs(plan.position(at: 12.5) - 0.5) < 1e-12)
        #expect(plan.position(at: 15) == 0.8)
        #expect(plan.position(at: 99) == 0.8)
        #expect(plan.position(at: 0) == 0.2)
        var pounce = CatPlan(move: .pounce, facing: .right, from: 0.2, to: 0.6, began: 0, duration: 8, delay: 0.5)
        #expect(pounce.position(at: 3.9) == 0.2, "crouching")
        #expect(abs(pounce.position(at: 6) - 0.4) < 1e-12)
        #expect(pounce.position(at: 8) == 0.6)
        pounce.delay = 0
        #expect(abs(pounce.position(at: 4) - 0.4) < 1e-12)
        let still = CatPlan(move: .sit, facing: .left, from: 0.4, to: 0.4, began: 0, duration: 3)
        #expect(still.position(at: 1) == 0.4)
    }

    // MARK: Sleeping

    @Test func itYawnsLiesDownAndSleepsOnlyOnceTheUserHasBeenAwayForTheTimeTheyChose() {
        for minutes in [2.0, 5, 10] {
            var drive = Drive(seed: 1, tuning: CatTuning(sleepAfter: minutes * 60))
            drive.senses.idleSeconds = minutes * 60 - 1
            drive.run(120)
            #expect(!drive.moves.contains(.sleep), "\(minutes) min: not yet")
            drive.senses.idleSeconds = minutes * 60
            drive.run(40)
            let moves = drive.moves
            let yawn = moves.lastIndex(of: .yawn)
            let down = moves.lastIndex(of: .lieDown)
            let sleep = moves.firstIndex(of: .sleep)
            #expect(sleep != nil, "\(minutes) min")
            if let yawn, let down, let sleep { #expect(yawn < down && down < sleep, "a yawn, getting down, then sleep") }
            #expect(drive.move == .sleep)
        }
    }

    @Test func aCatThatSleepsOnAsleepWithoutAnythingToRedraw() {
        var drive = Drive(seed: 1, tuning: CatTuning(sleepAfter: 120))
        drive.senses.idleSeconds = 500
        drive.run(30)
        #expect(drive.move == .sleep)
        let sleeps = drive.moves.filter { $0 == .sleep }.count
        #expect(drive.run(200) == .extended)
        #expect(drive.moves.filter { $0 == .sleep }.count == sleeps, "no new picture while it sleeps")
        #expect(drive.move == .sleep)
    }

    @Test func atNightItNodsOffInAThirdOfTheTime() {
        #expect(CatTuning(sleepAfter: 300).sleepThreshold(hour: 12) == 300)
        #expect(CatTuning(sleepAfter: 300).sleepThreshold(hour: 23) == 90)
        #expect(CatTuning(sleepAfter: 300).sleepThreshold(hour: 3) == 90)
        #expect(CatTuning(sleepAfter: 600).sleepThreshold(hour: 22) == 180)
        #expect(CatTuning(sleepAfter: 60).sleepThreshold(hour: 23) == 30, "never sooner than half a minute")
        var day = Drive(seed: 1, senses: CatSenses(idleSeconds: 100, hour: 12))
        day.run(60)
        #expect(day.move != .sleep)
        var night = Drive(seed: 1, senses: CatSenses(idleSeconds: 100, hour: 23))
        night.run(60)
        #expect(night.move == .sleep)
    }

    @Test func nightStartsAtTenAndEndsAtSix() {
        #expect((0..<24).filter { CatTuning.isNight(hour: $0) } == [0, 1, 2, 3, 4, 5, 22, 23])
    }

    @Test func atNightItWalksLessAndLiesDownMoreThanByDay() {
        var day = Drive(seed: 9, senses: CatSenses(idleSeconds: 60, hour: 14))
        var night = Drive(seed: 9, senses: CatSenses(idleSeconds: 60, hour: 23))
        day.run(3600)
        night.run(3600)
        let walking: (Drive) -> Double = { $0.share(of: .walk) + $0.share(of: .trot) + $0.share(of: .chase) }
        #expect(walking(night) < walking(day) * 0.6, "night \(walking(night)) day \(walking(day))")
        #expect(night.share(of: .loaf) > 0.1)
        #expect(day.share(of: .loaf) == 0 && day.share(of: .lieDown) == 0, "a cat naps only at night")
    }

    @Test func aCatDoesNotNapWhileTheUserIsStillAtTheMachine() {
        var drive = Drive(seed: 9, senses: CatSenses(idleSeconds: 3, hour: 23))
        drive.run(3600)
        #expect(!drive.scenes.contains(.nap))
    }

    @Test func itWakesWithAYawnWhenTheUserIsBack() {
        var drive = Drive(seed: 1, tuning: CatTuning(sleepAfter: 120))
        drive.senses.idleSeconds = 500
        drive.run(30)
        #expect(drive.move == .sleep)
        drive.senses.idleSeconds = 0.5
        drive.run(wake)
        #expect(drive.move == .yawn)
        drive.run(5)
        #expect(drive.move != .sleep && drive.move != .yawn)
    }

    // MARK: The pointer

    @Test func whenThePointerComesCloseAnAwakeCatPouncesOrJumps() {
        var pounced = 0
        var jumped = 0
        for seed in 1...30 as ClosedRange<UInt64> {
            var drive = Drive(seed: seed)
            drive.run(5)
            drive.senses.pointer = Drive.pointer(0.8, near: true)
            drive.run(wake)
            switch drive.move {
            case .pounce: pounced += 1
            case .startled: jumped += 1
            default: Issue.record("seed \(seed): \(drive.move)")
            }
        }
        #expect(pounced > jumped && jumped > 0, "mostly a pounce: \(pounced) against \(jumped)")
    }

    @Test func aSleepingCatIsStartledAndNeverPounces() {
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = Drive(seed: seed, tuning: CatTuning(sleepAfter: 120))
            drive.senses.idleSeconds = 500
            drive.run(30)
            #expect(drive.move == .sleep)
            drive.senses.pointer = Drive.pointer(0.4, near: true)
            drive.run(wake)
            #expect(drive.move == .startled, "seed \(seed)")
        }
    }

    @Test func aPounceLandsTowardsThePointerNoFartherThanACatCanLeap() throws {
        var landed = 0
        for seed in 1...30 as ClosedRange<UInt64> {
            var drive = Drive(seed: seed, position: 0.2)
            drive.run(5)
            drive.senses.pointer = Drive.pointer(0.9, near: true)
            drive.run(wake)
            guard drive.move == .pounce else { continue }
            landed += 1
            let plan = drive.brain.plan
            #expect(plan.facing == .right)
            #expect(plan.to > plan.from)
            #expect((plan.to - plan.from) * 260 <= CatBrain.longestPounce + 1e-9)
            #expect(abs(plan.delay - 5.0 / 8) < 1e-9, "a crouch, a wiggle, and then the leap")
            #expect(abs(plan.duration - CatMove.pounce.passDuration) < 1e-9)
        }
        #expect(landed > 10)
    }

    @Test func aPounceToThePointerNearbyLandsAtThePointer() {
        for seed in 1...30 as ClosedRange<UInt64> {
            var drive = Drive(seed: seed, position: 0.5)
            drive.run(5)
            let share = drive.brain.position(at: drive.now) + 0.1
            drive.senses.pointer = Drive.pointer(share, near: true)
            drive.run(wake)
            guard drive.move == .pounce else { continue }
            #expect(abs(drive.brain.plan.to - min(share, 1)) < 1e-9, "as far as the lane goes")
        }
    }

    @Test func aPouncingCatIsLeftToFinishAndSitsAfterwards() {
        var drive = Drive(seed: 1)
        drive.run(5)
        drive.senses.pointer = Drive.pointer(0.9, near: true)
        drive.senses.cpuLoad = 0.9
        drive.senses.busyBurst = true
        drive.senses.audioPlaying = true
        drive.run(wake)
        guard drive.move == .pounce || drive.move == .startled else {
            Issue.record("it did neither: \(drive.move)")
            return
        }
        let reaction = drive.move
        drive.run(0.4)
        #expect(drive.move == reaction, "not taken from it by a busy machine or music")
        drive.run(CatMove.pounce.passDuration + 1)
        #expect(drive.move == .frantic, "and then the machine is still in its burst")
    }

    @Test func itReactsOnceAndNotAgainWithinTheCooldown() {
        func reactions(_ drive: Drive) -> Int { drive.moves.filter { $0 == .pounce || $0 == .startled }.count }
        var drive = Drive(seed: 4)
        drive.run(5)
        drive.senses.pointer = Drive.pointer(0.8, near: true)
        drive.run(wake)
        #expect(reactions(drive) == 1)
        // Staying near is not coming near again.
        drive.run(3)
        #expect(reactions(drive) == 1)
        // Going and coming back too soon is not either.
        drive.senses.pointer = nil
        drive.run(1)
        drive.senses.pointer = Drive.pointer(0.8, near: true)
        drive.run(wake)
        #expect(reactions(drive) == 1, "too soon after the last")
        drive.senses.pointer = nil
        drive.run(CatBrain.reactionCooldown)
        drive.senses.pointer = Drive.pointer(0.8, near: true)
        drive.run(wake)
        #expect(reactions(drive) == 2)
    }

    @Test func aCatThatCameBackOntoTheNotchWithThePointerAlreadyThereDoesNotReact() {
        var drive = Drive(seed: 1)
        drive.run(5)
        drive.brain.resume(now: drive.now)
        drive.senses.pointer = Drive.pointer(0.5, near: true)
        drive.run(wake)
        #expect(drive.move != .pounce && drive.move != .startled, "the pointer it last saw is not news; it only looks")
    }

    // MARK: Looking

    @Test func aSittingCatLooksAtThePointerAndGoesBackToItsSceneWhenItIsGone() {
        var drive = Drive(seed: 1, position: 0.5)
        drive.run(0.5)
        #expect(drive.move == .sit)
        drive.senses.pointer = Drive.pointer(0.1, near: false, above: false)
        drive.run(wake)
        #expect(drive.move == .lookLeft)
        drive.senses.pointer = Drive.pointer(0.9, near: false, above: false)
        drive.run(wake)
        #expect(drive.move == .lookRight)
        drive.senses.pointer = Drive.pointer(0.5, near: false, above: true)
        drive.run(wake)
        #expect(drive.move == .lookUp, "over its head")
        drive.senses.pointer = nil
        drive.run(wake)
        #expect(drive.move == .sit)
    }

    @Test func aCatThatIsWalkingOrGroomingIsNotDistractedByThePointerUntilItIsDone() {
        let busy: [CatMove] = [.walk, .trot, .groom, .scratch, .stretch, .pounce, .yarn, .chase, .yawn, .lieDown, .loaf]
        let looks: [CatMove] = [.lookLeft, .lookRight, .lookUp]
        var drifted = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = Drive(seed: seed)
            drive.senses.pointer = Drive.pointer(0.9, near: false)
            for _ in 0..<(400 * 4) {
                let before = drive.brain.plan
                drive.run(wake)
                let after = drive.brain.plan
                // A look takes the place of something that was not over only when that was a sit, a blink or a swish of the tail.
                if busy.contains(before.move), looks.contains(after.move), drive.now < before.end - 1e-9 {
                    drifted += 1
                    Issue.record("seed \(seed): a \(before.move) given up for a look at \(drive.now)")
                }
            }
            #expect(Set(drive.moves).isSuperset(of: [.walk, .groom]), "seed \(seed): it does what it does with the pointer in sight")
            #expect(drive.moves.contains { looks.contains($0) }, "and looks when it sits")
        }
        #expect(drifted == 0)
    }

    // MARK: Processors and music

    @Test func inABurstOfLoadItRunsFranticallyAndDoesNotStopToSit() {
        var drive = Drive(seed: 1, senses: CatSenses(cpuLoad: 0.9, busyBurst: true))
        drive.run(BusyWatch.longestBurst)
        #expect(drive.move == .frantic)
        let others = Set(drive.moves).subtracting([.frantic])
        #expect(others.isEmpty, "\(others)")
    }

    @Test func aHighLoadThatIsNoBurstDoesNotMakeItRunAtAllAndEveryOtherSceneStillPlays() {
        for load in [0.65, 0.9, 1.0] {
            var drive = Drive(seed: 3, senses: CatSenses(idleSeconds: 60, cpuLoad: load, hour: 14))
            drive.run(3600)
            #expect(!drive.moves.contains(.frantic), "at \(load)")
            let missing = Set(CatScene.allCases).subtracting([.nap, .pounceAtPointer]).subtracting(drive.scenes)
            #expect(missing.isEmpty, "at \(load) an hour of scenes lacks \(missing)")
        }
    }

    @Test func theBusierTheProcessorsInABurstTheFasterItRunsAndTheFasterItsFramesPlay() throws {
        func run(load: Double) throws -> CatPlan {
            var drive = Drive(seed: 1, position: 0, senses: CatSenses(cpuLoad: load, busyBurst: true))
            drive.run(5)
            return try #require(drive.history.first { $0.plan.move == .frantic }?.plan)
        }
        let gentle = try run(load: BusyWatch.floor)
        let hard = try run(load: 1.0)
        let speed: (CatPlan) -> Double = { abs($0.to - $0.from) * 260 / $0.duration }
        #expect(speed(hard) > speed(gentle))
        #expect(hard.fpsScale > gentle.fpsScale && gentle.fpsScale >= 1)
        #expect(abs(hard.fpsScale - (1 + CatBrain.runFrameBoost)) < 1e-9)
        #expect(hard.to == 1 && hard.from == 0, "across the lane to the end that is farther off")
    }

    @Test func itRunsBackAndForthAlongTheLaneForAsLongAsTheBurstLasts() {
        var drive = Drive(seed: 1, position: 0, senses: CatSenses(cpuLoad: 0.9, busyBurst: true))
        drive.run(40)
        let runs = drive.history.map(\.plan).filter { $0.move == .frantic }
        #expect(runs.count >= 3)
        #expect(runs.contains { $0.facing == .right } && runs.contains { $0.facing == .left })
    }

    @Test func whenTheBurstIsOverItStopsAtOnceSitsAndGoesBackToItsScenes() {
        var drive = Drive(seed: 1, senses: CatSenses(cpuLoad: 0.9, busyBurst: true))
        drive.run(5)
        #expect(drive.move == .frantic)
        // The load is as high as ever: a burst is over when the burst says so, not when the load drops.
        drive.senses.busyBurst = false
        drive.run(wake)
        #expect(drive.move == .sitDown || drive.move == .sit, "calming down: it sits")
        drive.run(600)
        #expect(!drive.history.filter { $0.at > 6 }.contains { $0.plan.move == .frantic }, "and does not run again")
        #expect(Set(drive.scenes).count >= 5, "it is back to what it does with its day")
    }

    @Test func aLoadThatIsNoBurstAtAnyLevelNeverMakesItRun() {
        for load in [0, 0.35, BusyWatch.floor, 0.95] {
            var drive = Drive(seed: 1, senses: CatSenses(cpuLoad: load))
            drive.run(1200)
            #expect(!drive.moves.contains(.frantic), "at \(load)")
        }
    }

    @Test func aBusyMacQuickensTheWalksAPartOfTheWayAndANormalOneDoesNot() throws {
        func walks(load: Double, reacts: Bool = true) -> [CatPlan] {
            var drive = Drive(
                seed: 2, senses: CatSenses(idleSeconds: 60, cpuLoad: load, hour: 14), tuning: CatTuning(reactsToBusyMachine: reacts)
            )
            drive.run(1800)
            return drive.history.map(\.plan).filter { [CatMove.walk, .trot].contains($0.move) }
        }
        let quiet = walks(load: 0.3)
        let busy = walks(load: 1.0)
        let half = walks(load: (CatBrain.busyFrom + 1) / 2)
        #expect(!quiet.isEmpty && !busy.isEmpty && !half.isEmpty)
        #expect(quiet.allSatisfy { $0.fpsScale == 1 }, "an ordinary load changes nothing")
        #expect(busy.allSatisfy { abs($0.fpsScale - (1 + CatBrain.busyBoost)) < 1e-9 }, "a full load quickens them by the most there is")
        #expect(half.allSatisfy { $0.fpsScale > 1 && $0.fpsScale < 1 + CatBrain.busyBoost }, "and half of it by half")
        #expect(CatBrain.busyBoost <= 0.25, "a little, not a run")
        // A quicker walk is quicker: the same distance in less time.
        let speed: (CatPlan) -> Double = { abs($0.to - $0.from) * 260 / $0.duration / $0.move.speed }
        #expect(busy.allSatisfy { abs(speed($0) - (1 + CatBrain.busyBoost)) < 0.02 })
        #expect(walks(load: 1.0, reacts: false).allSatisfy { $0.fpsScale == 1 }, "unless the user has turned the reaction off")
    }

    @Test func aBusyMacBringsOnTheSweatSceneAndAQuietOneNeverDoes() {
        for seed in 1...4 as ClosedRange<UInt64> {
            var busy = Drive(seed: seed, senses: CatSenses(idleSeconds: 60, cpuLoad: 0.9, hour: 14))
            busy.run(1800)
            #expect(busy.scenes.contains(.fret), "seed \(seed)")
            #expect(busy.moves.contains(.sweat), "seed \(seed)")
            var quiet = Drive(seed: seed, senses: CatSenses(idleSeconds: 60, cpuLoad: 0.3, hour: 14))
            quiet.run(1800)
            #expect(!quiet.scenes.contains(.fret) && !quiet.moves.contains(.sweat), "seed \(seed)")
        }
    }

    @Test func theSweatSceneIsAShareOfTheDayAndNotAllOfIt() {
        var busy = Drive(seed: 5, senses: CatSenses(idleSeconds: 60, cpuLoad: 1.0, hour: 14))
        busy.run(3600)
        let fretting = Double(busy.scenes.filter { $0 == .fret }.count) / Double(busy.scenes.count)
        #expect(fretting > 0.03 && fretting < 0.2, "\(fretting) of the scenes")
    }

    @Test func withTheReactionOffABurstAndAHighLoadChangeNothing() {
        var drive = Drive(
            seed: 1, senses: CatSenses(idleSeconds: 60, cpuLoad: 1.0, busyBurst: true, hour: 14), tuning: CatTuning(reactsToBusyMachine: false)
        )
        drive.run(3600)
        #expect(!drive.moves.contains(.frantic))
        #expect(!drive.scenes.contains(.fret) && !drive.moves.contains(.sweat))
        let missing = Set(CatScene.allCases).subtracting([.nap, .pounceAtPointer, .fret]).subtracting(drive.scenes)
        #expect(missing.isEmpty, "\(missing)")
    }

    @Test func aLaneTooShortToRunAlongHasTheCatRunOnTheSpot() throws {
        var drive = Drive(seed: 1, senses: CatSenses(cpuLoad: 0.9, busyBurst: true), travel: 0)
        drive.run(10)
        let run = try #require(drive.history.last { $0.plan.move == .frantic }?.plan)
        #expect(run.from == run.to)
        #expect(run.duration >= CatBrain.shortestRun)
    }

    @Test func aBusyMachineWakesASleepingCatToRunAndItCalmsDownWhenItIsQuietAgain() {
        var drive = Drive(seed: 1, tuning: CatTuning(sleepAfter: 120))
        drive.senses.idleSeconds = 500
        drive.run(30)
        #expect(drive.move == .sleep)
        drive.senses.cpuLoad = 0.8
        drive.senses.busyBurst = true
        drive.run(wake)
        #expect(drive.move == .frantic)
        drive.senses.cpuLoad = 0.05
        drive.senses.busyBurst = false
        drive.run(wake)
        #expect(drive.move != .frantic)
    }

    @Test func itDancesWhileSoundPlaysAndStopsWhenItDoes() {
        var drive = Drive(seed: 1)
        drive.run(5)
        drive.senses.audioPlaying = true
        drive.run(wake)
        #expect(drive.move == .dance)
        drive.run(60)
        #expect(drive.move == .dance)
        drive.senses.audioPlaying = false
        drive.run(wake)
        #expect(drive.move == .sit)
    }

    @Test func itDancesInPlace() throws {
        var drive = Drive(seed: 1, position: 0.3, senses: CatSenses(audioPlaying: true))
        drive.run(10)
        let dance = try #require(drive.history.first { $0.plan.move == .dance }?.plan)
        #expect(dance.from == dance.to)
    }

    @Test func aBusyMachineBeatsMusicAndAJumpBeatsBoth() {
        var drive = Drive(seed: 1, senses: CatSenses(cpuLoad: 0.9, busyBurst: true, audioPlaying: true))
        drive.run(10)
        #expect(drive.move == .frantic)
        drive.senses.pointer = Drive.pointer(0.9, near: true)
        drive.run(wake)
        #expect(drive.move == .pounce || drive.move == .startled)
        drive.run(CatMove.pounce.passDuration + 0.5)
        #expect(drive.move == .frantic)
    }

    @Test func musicWakesASleepingCatToo() {
        var drive = Drive(seed: 1, tuning: CatTuning(sleepAfter: 120))
        drive.senses.idleSeconds = 500
        drive.run(30)
        drive.senses.audioPlaying = true
        drive.run(wake)
        #expect(drive.move == .dance)
    }

    // MARK: Petting

    @Test func aStrokePurrsWhereverTheCatIsAndWhateverItWasDoing() {
        var drive = Drive(seed: 1, tuning: CatTuning(sleepAfter: 120))
        drive.senses.idleSeconds = 500
        drive.run(30)
        #expect(drive.move == .sleep)
        #expect(drive.brain.pet(now: drive.now) == .changed)
        #expect(drive.move == .purr)
        #expect(drive.brain.plan.duration == CatBrain.purrDuration)
        #expect(drive.brain.plan.from == drive.brain.plan.to)
    }

    @Test func aPurrIsNotCutShortByTheMachineGettingBusyOrByMusic() {
        var drive = Drive(seed: 1)
        drive.run(3)
        _ = drive.brain.pet(now: drive.now)
        drive.senses.cpuLoad = 0.9
        drive.senses.busyBurst = true
        drive.senses.audioPlaying = true
        drive.run(1)
        #expect(drive.move == .purr)
        drive.run(CatBrain.purrDuration)
        #expect(drive.move == .frantic)
    }

    @Test func strokingAgainWhilePurringIsTheSamePicture() {
        var brain = CatBrain(seed: 1, now: 0)
        #expect(brain.pet(now: 1) == .changed)
        #expect(brain.pet(now: 2) == .extended)
    }
}


/// The scenes with something in them: a moth, a ball of yarn, a place to hide.
@Suite struct CatBrainPlayTests {
    /// A day of the cat with nothing else to do, from a few seeds.
    static func plans(seeds: ClosedRange<UInt64> = 1...12, hour: Int = 14) -> [[CatPlan]] {
        seeds.map { seed in
            var drive = Drive(seed: seed, senses: CatSenses(idleSeconds: 60, hour: hour))
            drive.run(3600)
            return drive.history.map(\.plan)
        }
    }

    @Test func aMothComesInAtOneEndAndTheCatRunsAfterItToTheOtherWhereItGetsAway() {
        var chases = 0
        for plans in Self.plans() {
            for (index, plan) in plans.enumerated() where plan.prop?.kind == .moth {
                chases += 1
                let moth = plan.prop!
                #expect(plan.move == .chase)
                let right = plan.to > plan.from
                #expect(plan.facing == (right ? .right : .left))
                // The moth is ahead of the cat the whole way and leaves the strip at the far end.
                #expect(right ? moth.from > plan.from : moth.from < plan.from, "ahead at the start")
                #expect(abs(moth.from - plan.from) <= CatBrain.mothLead + 1e-9)
                #expect(right ? moth.to > 1 : moth.to < 0, "it flies off the strip")
                #expect(plan.to == (right ? 1 - CatBrain.edgeInset : CatBrain.edgeInset), "the cat stops short of the end")
                let duration = abs(plan.to - plan.from) * 260 / CatMove.chase.speed
                #expect(abs(plan.duration - max(duration, 1.5)) < 1e-9)
                // It begins from the end the cat is nearer, and what it does after is sit proudly, its tail swishing.
                #expect(plan.from <= 0.2 || plan.from >= 0.8, "from near an end: \(plan.from)")
                // (The last scene of the run may have been cut off.)
                if let after = plans.dropFirst(index + 1).first(where: { $0.move != .sitDown }) { #expect(after.move == .tailSwish) }
            }
        }
        #expect(chases >= 5)
    }

    @Test func theMothIsOnlyThereForTheChase() {
        for plans in Self.plans() {
            let withMoth = plans.filter { $0.prop?.kind == .moth }
            #expect(withMoth.allSatisfy { $0.move == .chase })
        }
    }

    @Test func aBallOfYarnIsWalkedUpToBattedRolledAndWalkedUpToAgain() {
        var scenes = 0
        for plans in Self.plans() {
            var index = 0
            while index < plans.count {
                guard plans[index].prop?.kind == .yarn else {
                    index += 1
                    continue
                }
                // One scene: every plan up to the first without the ball.
                var scene: [CatPlan] = []
                while index < plans.count, plans[index].prop?.kind == .yarn {
                    scene.append(plans[index])
                    index += 1
                }
                // The last scene of the run may have been cut off.
                guard index < plans.count else { break }
                scenes += 1
                let bats = scene.filter { $0.move == .yarn }
                #expect(bats.count == 3, "three bats")
                for bat in bats {
                    let ball = bat.prop!
                    #expect(ball.from != ball.to, "it rolls")
                    #expect(bat.from == bat.to, "the cat stands to bat")
                    #expect(bat.facing == (ball.to > ball.from ? .right : .left), "facing the way it rolls")
                    #expect(abs(abs(ball.from - bat.from) - CatBrain.playGap) < 0.01, "close to it: \(abs(ball.from - bat.from))")
                    #expect(abs(ball.to - ball.from) - CatBrain.rollLength < 1e-9)
                    #expect((0.0...1.0).contains(ball.to))
                }
                // Between bats the ball lies where the last one left it, and the next bat is where it lay.
                for (before, after) in zip(bats, bats.dropFirst()) {
                    #expect(abs(after.prop!.from - before.prop!.to) < 1e-9)
                }
                for plan in scene where plan.move != .yarn {
                    #expect(plan.prop!.from == plan.prop!.to, "lying still while the cat walks")
                }
                // And the plan after the scene has no ball.
                #expect(plans[index].prop == nil)
            }
        }
        #expect(scenes >= 5)
    }

    @Test func aCatThatPeeksDucksOutOfSightAndComesUpTwice() {
        var seen = 0
        for plans in Self.plans() {
            for (index, plan) in plans.enumerated() where plan.move == .peek && (index == 0 || plans[index - 1].move != .peek) {
                seen += 1
                #expect(plans[index + 1].move == .peek, "twice")
                #expect(plans[index + 1].from == plan.from, "in the same place")
                #expect(abs(plan.from - 0.5) < 0.01, "in the middle of the strip, under the notch's middle")
                #expect(plans[index - 1].move == .trot || abs(plans[index - 1].to - 0.5) < 0.01, "after running there")
            }
        }
        #expect(seen >= 5)
    }

    @Test func aNapIsLyingDownALoafAndAStretch() {
        var naps = 0
        for plans in Self.plans(hour: 23) {
            for (index, plan) in plans.enumerated() where plan.move == .lieDown && index + 3 < plans.count && plans[index + 1].move == .loaf {
                naps += 1
                #expect(plan.duration == CatMove.lieDown.passDuration)
                #expect(plans[index + 1].duration >= 8 && plans[index + 1].duration <= 16)
                // Up again from the loaf, and a stretch.
                #expect(plans[index + 2].move == .standUp)
                #expect(plans[index + 3].move == .stretch)
            }
        }
        #expect(naps >= 5)
    }

    @Test func movesThatArePlayedOnceAreAlwaysAPictureToStartOver() {
        for move in CatMove.allCases where !move.loops {
            let plan = CatPlan(move: move, facing: .left, from: 0.4, to: 0.4, began: 0, duration: 1)
            var later = plan
            later.began = 5
            #expect(!plan.looksLike(later), "\(move) twice")
        }
        let sit = CatPlan(move: .sit, facing: .left, from: 0.4, to: 0.4, began: 0, duration: 1)
        var longer = sit
        longer.duration = 5
        #expect(sit.looksLike(longer))
    }

    @Test func theMovesTimingsMatchTheirPicturesAndWhatTheBrainCountsOn() {
        for move in CatMove.allCases {
            #expect(move.frameCount > 0 && move.fps > 0)
            #expect(move.passDuration == Double(move.frameCount) / move.fps)
            #expect(move.speed == move.advance * move.fps)
        }
        #expect(CatMove.allCases.filter { $0.advance > 0 } == [.walk, .trot, .frantic, .chase])
    }
}
