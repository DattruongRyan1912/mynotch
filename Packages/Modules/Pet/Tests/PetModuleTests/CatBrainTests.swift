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
    var travel = 60.0
    /// Where on the lane nobody sees the cat.
    var blind: BlindSpan?
    /// Every plan that changed the picture, with the time it began.
    struct Entry {
        let at: TimeInterval
        let plan: CatPlan
    }

    private(set) var history: [Entry] = []
    /// Seconds spent in each pose.
    private(set) var spent: [CatPose: TimeInterval] = [:]
    static let step = 0.25

    init(
        seed: UInt64 = 1, position: Double = 0.5, senses: CatSenses = CatSenses(), tuning: CatTuning = CatTuning(), travel: Double = 60,
        blind: BlindSpan? = nil
    ) {
        brain = CatBrain(seed: seed, now: 0, position: position)
        self.senses = senses
        self.tuning = tuning
        self.travel = travel
        self.blind = blind
    }

    var pose: CatPose { brain.plan.pose }

    @discardableResult
    mutating func run(_ seconds: Double) -> CatBrain.Outcome {
        var last = CatBrain.Outcome.unchanged
        let end = now + seconds
        while now < end - 1e-9 {
            now += Self.step
            let outcome = brain.update(now: now, senses: senses, tuning: tuning, travel: travel, blind: blind)
            if outcome == .changed { history.append(Entry(at: now, plan: brain.plan)) }
            if outcome != .unchanged { last = outcome }
            spent[brain.plan.pose, default: 0] += Self.step
        }
        return last
    }

    func poses() -> [CatPose] { history.map(\.plan.pose) }

    func share(of pose: CatPose) -> Double {
        let total = spent.values.reduce(0, +)
        return total == 0 ? 0 : (spent[pose] ?? 0) / total
    }
}

@Suite struct CatBrainTests {
    // MARK: Whims

    @Test func theSameSeedMakesTheSameDayAndAnotherSeedAnotherOne() {
        func day(seed: UInt64) -> [CatPose] {
            var drive = Drive(seed: seed)
            drive.run(600)
            return drive.poses()
        }
        #expect(day(seed: 3) == day(seed: 3))
        #expect(day(seed: 3) != day(seed: 4))
    }

    @Test func aCatWithNothingToDoSitsBlinksWandersGroomsAndYawns() {
        var drive = Drive(seed: 11)
        drive.run(1200)
        let seen = Set(drive.poses())
        for pose in [CatPose.sit, .blink, .walk, .lick, .yawn] { #expect(seen.contains(pose), "\(pose)") }
        // And none of what needs a reason.
        for pose in [CatPose.run, .dance, .sleep, .startled, .purr] { #expect(!seen.contains(pose), "\(pose)") }
    }

    @Test func itBlinksForAMomentAndGoesBackToWhatItWasDoing() {
        var drive = Drive(seed: 11)
        drive.run(1200)
        let blinks = drive.history.filter { $0.plan.pose == .blink }
        #expect(!blinks.isEmpty)
        for blink in blinks { #expect(blink.plan.duration == CatBrain.blinkDuration) }
    }

    @Test func aCatThatSitsOnForAnotherSitIsStillTheSamePictureSoNothingIsRedrawn() {
        var brain = CatBrain(seed: 1, now: 0)
        // Longer than any sit, with nothing else: the plan ends, and a new one that looks like it may begin.
        var outcomes: [CatBrain.Outcome] = []
        var now = 0.0
        while now < 200 {
            now += 0.25
            let outcome = brain.update(now: now, senses: CatSenses(), tuning: CatTuning(), travel: 0)
            if outcome != .unchanged { outcomes.append(outcome) }
        }
        #expect(outcomes.contains(.extended), "a second sit after a sit, and the lane being too short to walk")
        #expect(outcomes.contains(.changed))
    }

    // MARK: Walking

    @Test func itNeverWalksOutOfItsLaneAndTurnsRoundAtTheEnds() {
        for seed in 1...20 as ClosedRange<UInt64> {
            var drive = Drive(seed: seed, position: 0.95)
            drive.run(2000)
            for entry in drive.history {
                let plan = entry.plan
                #expect((0.0...1.0).contains(plan.from) && (0.0...1.0).contains(plan.to), "seed \(seed): \(plan)")
            }
            let walks = drive.history.map(\.plan).filter { $0.pose == .walk }
            #expect(walks.contains { $0.facing == .left } && walks.contains { $0.facing == .right }, "seed \(seed) goes both ways")
            for walk in walks { #expect(walk.facing == (walk.to > walk.from ? .right : .left)) }
        }
    }

    @Test func aWalkTakesTheTimeItTakesAtTheWalkingPace() {
        var drive = Drive(seed: 2, travel: 60)
        drive.run(1200)
        let walks = drive.history.map(\.plan).filter { $0.pose == .walk }
        #expect(walks.count > 5)
        for walk in walks {
            let distance = abs(walk.to - walk.from) * 60
            #expect(abs(walk.duration - distance / CatBrain.walkSpeed) < 1e-9)
            #expect(distance >= 1)
        }
    }

    @Test func aWalkStartsWhereTheLastPlanLeftTheCat() {
        var drive = Drive(seed: 5)
        drive.run(1200)
        var place = 0.5
        for entry in drive.history {
            #expect(abs(entry.plan.from - place) < 1e-9, "at \(entry.at)")
            place = entry.plan.to
        }
    }

    @Test func aLaneTooShortToWalkOnHasTheCatSitInsteadOfWalking() {
        var drive = Drive(seed: 2, travel: 0)
        drive.run(1200)
        #expect(!drive.poses().contains(.walk))
        #expect(drive.share(of: .sit) > 0.3)
    }

    @Test func itIsWhereThePlanSaysAtEveryMomentOfAWalk() {
        let plan = CatPlan(pose: .walk, facing: .right, from: 0.2, to: 0.8, began: 10, duration: 5)
        #expect(plan.position(at: 10) == 0.2)
        #expect(abs(plan.position(at: 12.5) - 0.5) < 1e-12)
        #expect(plan.position(at: 15) == 0.8)
        #expect(plan.position(at: 99) == 0.8)
        #expect(plan.position(at: 0) == 0.2)
        let still = CatPlan(pose: .sit, facing: .left, from: 0.4, to: 0.4, began: 0, duration: 3)
        #expect(still.position(at: 1) == 0.4)
    }

    // MARK: Sleeping

    @Test func itYawnsAndFallsAsleepOnlyOnceTheUserHasBeenAwayForTheTimeTheyChose() {
        for minutes in [2.0, 5, 10] {
            var drive = Drive(seed: 1, tuning: CatTuning(sleepAfter: minutes * 60))
            drive.senses.idleSeconds = minutes * 60 - 1
            drive.run(120)
            #expect(!drive.poses().contains(.sleep), "\(minutes) min: not yet")
            #expect(!drive.poses().contains(.yawn) || drive.poses().last != .sleep)
            drive.senses.idleSeconds = minutes * 60
            drive.run(30)
            let poses = drive.poses()
            let yawn = poses.lastIndex(of: .yawn)
            let sleep = poses.firstIndex(of: .sleep)
            #expect(sleep != nil, "\(minutes) min")
            if let yawn, let sleep { #expect(yawn < sleep, "a yawn first") }
            #expect(drive.pose == .sleep)
        }
    }

    @Test func aCatThatSleepsOnAsleepWithoutAnythingToRedraw() {
        var drive = Drive(seed: 1, tuning: CatTuning(sleepAfter: 120))
        drive.senses.idleSeconds = 500
        drive.run(10)
        #expect(drive.pose == .sleep)
        let sleeps = drive.poses().filter { $0 == .sleep }.count
        #expect(drive.run(200) == .extended)
        #expect(drive.poses().filter { $0 == .sleep }.count == sleeps, "no new picture while it sleeps")
        #expect(drive.pose == .sleep)
    }

    @Test func atNightItNodsOffInAThirdOfTheTime() {
        #expect(CatTuning(sleepAfter: 300).sleepThreshold(hour: 12) == 300)
        #expect(CatTuning(sleepAfter: 300).sleepThreshold(hour: 23) == 90)
        #expect(CatTuning(sleepAfter: 300).sleepThreshold(hour: 3) == 90)
        #expect(CatTuning(sleepAfter: 600).sleepThreshold(hour: 22) == 180)
        // Never sooner than half a minute.
        #expect(CatTuning(sleepAfter: 60).sleepThreshold(hour: 23) == 30)
        var day = Drive(seed: 1, senses: CatSenses(idleSeconds: 100, hour: 12))
        day.run(60)
        #expect(day.pose != .sleep)
        var night = Drive(seed: 1, senses: CatSenses(idleSeconds: 100, hour: 23))
        night.run(60)
        #expect(night.pose == .sleep)
    }

    @Test func nightStartsAtTenAndEndsAtSix() {
        let night = (0..<24).filter { CatTuning.isNight(hour: $0) }
        #expect(night == [0, 1, 2, 3, 4, 5, 22, 23])
    }

    @Test func atNightItWalksLessAndSleepsMoreThanByDay() {
        var day = Drive(seed: 9, senses: CatSenses(idleSeconds: 60, hour: 14))
        var night = Drive(seed: 9, senses: CatSenses(idleSeconds: 60, hour: 23))
        day.run(3600)
        night.run(3600)
        #expect(night.share(of: .walk) < day.share(of: .walk) * 0.6, "night \(night.share(of: .walk)) day \(day.share(of: .walk))")
        #expect(night.share(of: .sleep) > 0.15)
        #expect(day.share(of: .sleep) == 0, "a cat naps only at night")
    }

    @Test func aCatDoesNotNapWhileTheUserIsStillAtTheMachine() {
        var drive = Drive(seed: 9, senses: CatSenses(idleSeconds: 3, hour: 23))
        drive.run(3600)
        #expect(!drive.poses().contains(.sleep))
    }

    @Test func itWakesWithAYawnWhenTheUserIsBack() {
        var drive = Drive(seed: 1, tuning: CatTuning(sleepAfter: 120))
        drive.senses.idleSeconds = 500
        drive.run(10)
        #expect(drive.pose == .sleep)
        drive.senses.idleSeconds = 0.5
        drive.run(CatDrive.quarter)
        #expect(drive.pose == .yawn)
        drive.run(5)
        #expect(drive.pose != .sleep && drive.pose != .yawn)
    }

    // MARK: Pointer

    @Test func whenThePointerComesCloseItJumpsOnce() {
        var drive = Drive(seed: 1)
        drive.run(5)
        drive.senses.pointerNear = true
        drive.run(CatDrive.quarter)
        #expect(drive.pose == .startled)
        #expect(drive.brain.plan.duration == CatBrain.startleDuration)
        // Staying near is not coming near again.
        drive.run(30)
        #expect(drive.poses().filter { $0 == .startled }.count == 1)
    }

    @Test func itJumpsAgainWhenThePointerComesBackButNotWithinTheCooldown() {
        var drive = Drive(seed: 1)
        drive.run(5)
        drive.senses.pointerNear = true
        drive.run(CatDrive.quarter)
        drive.senses.pointerNear = false
        drive.run(1)
        drive.senses.pointerNear = true
        drive.run(CatDrive.quarter)
        #expect(drive.poses().filter { $0 == .startled }.count == 1, "too soon after the last jump")
        drive.senses.pointerNear = false
        drive.run(CatBrain.startleCooldown)
        drive.senses.pointerNear = true
        drive.run(CatDrive.quarter)
        #expect(drive.poses().filter { $0 == .startled }.count == 2)
    }

    @Test func aSleepingCatWakesWithAStartledJump() {
        var drive = Drive(seed: 1, tuning: CatTuning(sleepAfter: 120))
        drive.senses.idleSeconds = 500
        drive.run(10)
        #expect(drive.pose == .sleep)
        drive.senses.pointerNear = true
        drive.run(CatDrive.quarter)
        #expect(drive.pose == .startled)
    }

    @Test func aCatThatCameBackOntoTheNotchWithThePointerAlreadyThereDoesNotJump() {
        var drive = Drive(seed: 1)
        drive.run(5)
        drive.brain.resume(now: drive.now)
        drive.senses.pointerNear = true
        drive.run(CatDrive.quarter)
        #expect(drive.pose != .startled)
        #expect(drive.brain.plan.pose == .sit)
    }

    // MARK: Processors

    @Test func whenTheProcessorsAreBusyItRunsAndDoesNotStopToSit() {
        var drive = Drive(seed: 1, senses: CatSenses(cpuLoad: 0.9))
        drive.run(120)
        #expect(drive.pose == .run)
        let others = Set(drive.poses()).subtracting([.run])
        #expect(others.isEmpty, "\(others)")
    }

    @Test func theBusierTheProcessorsTheFasterItRunsAndTheFasterItsFramesPlay() throws {
        func run(load: Double) throws -> CatPlan {
            var drive = Drive(seed: 1, position: 0, senses: CatSenses(cpuLoad: load))
            drive.run(5)
            return try #require(drive.history.last { $0.plan.pose == .run }?.plan)
        }
        let gentle = try run(load: 0.4)
        let hard = try run(load: 1.0)
        let speed: (CatPlan) -> Double = { abs($0.to - $0.from) * 60 / $0.duration }
        #expect(speed(hard) > speed(gentle))
        #expect(hard.fpsScale > gentle.fpsScale)
        #expect(gentle.fpsScale >= 1)
        #expect(abs(hard.fpsScale - (1 + CatBrain.runFrameBoost)) < 1e-9)
        // A run goes across the lane to the end that is farther off.
        #expect(hard.to == 1 && hard.from == 0)
    }

    @Test func itRunsBackAndForthAlongTheLane() {
        var drive = Drive(seed: 1, position: 0, senses: CatSenses(cpuLoad: 0.9))
        drive.run(30)
        let runs = drive.history.map(\.plan).filter { $0.pose == .run }
        #expect(runs.count >= 3)
        #expect(runs.contains { $0.facing == .right } && runs.contains { $0.facing == .left })
    }

    @Test func aQuietMachineNeverMakesItRunAndTheLoadItStopsAtIsLowerThanTheOneItStartsAt() {
        var calm = Drive(seed: 1, senses: CatSenses(cpuLoad: CatBrain.runOn - 0.01))
        calm.run(1200)
        #expect(!calm.poses().contains(.run))

        // Running at a load between the two keeps running, and a load below the lower one calms it at once.
        var drive = Drive(seed: 1, senses: CatSenses(cpuLoad: 0.9))
        drive.run(5)
        drive.senses.cpuLoad = (CatBrain.runOn + CatBrain.runOff) / 2
        drive.run(10)
        #expect(drive.pose == .run)
        drive.senses.cpuLoad = CatBrain.runOff - 0.01
        drive.run(CatDrive.quarter)
        #expect(drive.pose == .sit)
    }

    @Test func aLaneTooShortToRunAlongHasTheCatRunOnTheSpot() throws {
        var drive = Drive(seed: 1, senses: CatSenses(cpuLoad: 0.9), travel: 0)
        drive.run(10)
        let run = try #require(drive.history.last { $0.plan.pose == .run }?.plan)
        #expect(run.from == run.to)
        #expect(run.duration >= CatBrain.shortestRun)
    }

    @Test func aBusyMachineWakesASleepingCatToRunAndItCalmsDownWhenItIsQuietAgain() {
        var drive = Drive(seed: 1, tuning: CatTuning(sleepAfter: 120))
        drive.senses.idleSeconds = 500
        drive.run(10)
        #expect(drive.pose == .sleep)
        drive.senses.cpuLoad = 0.8
        drive.run(CatDrive.quarter)
        #expect(drive.pose == .run)
        drive.senses.cpuLoad = 0.05
        drive.run(CatDrive.quarter)
        #expect(drive.pose != .run)
    }

    // MARK: Music

    @Test func itDancesWhileSoundPlaysAndStopsWhenItDoes() {
        var drive = Drive(seed: 1)
        drive.run(5)
        drive.senses.audioPlaying = true
        drive.run(CatDrive.quarter)
        #expect(drive.pose == .dance)
        drive.run(60)
        #expect(drive.pose == .dance)
        drive.senses.audioPlaying = false
        drive.run(CatDrive.quarter)
        #expect(drive.pose == .sit)
    }

    @Test func itDancesInPlace() throws {
        var drive = Drive(seed: 1, position: 0.3, senses: CatSenses(audioPlaying: true))
        drive.run(10)
        let dance = try #require(drive.history.first { $0.plan.pose == .dance }?.plan)
        #expect(dance.from == dance.to)
    }

    @Test func aBusyMachineBeatsMusicAndAJumpBeatsBoth() {
        var drive = Drive(seed: 1, senses: CatSenses(cpuLoad: 0.9, audioPlaying: true))
        drive.run(10)
        #expect(drive.pose == .run)
        drive.senses.pointerNear = true
        drive.run(CatDrive.quarter)
        #expect(drive.pose == .startled)
        // Until the jump is over, and then back to what it was.
        drive.run(CatBrain.startleDuration + 0.5)
        #expect(drive.pose == .run)
    }

    @Test func musicWakesASleepingCatToo() {
        var drive = Drive(seed: 1, tuning: CatTuning(sleepAfter: 120))
        drive.senses.idleSeconds = 500
        drive.run(10)
        drive.senses.audioPlaying = true
        drive.run(CatDrive.quarter)
        #expect(drive.pose == .dance)
    }

    // MARK: Petting

    @Test func aStrokePurrsWhereverTheCatIsAndWhateverItWasDoing() {
        var drive = Drive(seed: 1, tuning: CatTuning(sleepAfter: 120))
        drive.senses.idleSeconds = 500
        drive.run(10)
        #expect(drive.pose == .sleep)
        #expect(drive.brain.pet(now: drive.now) == .changed)
        #expect(drive.pose == .purr)
        #expect(drive.brain.plan.duration == CatBrain.purrDuration)
        #expect(drive.brain.plan.from == drive.brain.plan.to)
    }

    @Test func aPurrIsNotCutShortByTheMachineGettingBusyOrByMusic() {
        var drive = Drive(seed: 1)
        drive.run(3)
        _ = drive.brain.pet(now: drive.now)
        drive.senses.cpuLoad = 0.9
        drive.senses.audioPlaying = true
        drive.run(1)
        #expect(drive.pose == .purr)
        drive.run(CatBrain.purrDuration)
        #expect(drive.pose == .run)
    }

    @Test func strokingAgainWhilePurringIsTheSamePicture() {
        var brain = CatBrain(seed: 1, now: 0)
        #expect(brain.pet(now: 1) == .changed)
        #expect(brain.pet(now: 2) == .extended)
    }
}

@Suite struct CatBrainBlindSpanTests {
    static let blind = BlindSpan(low: 0.2, high: 0.8)

    /// A day of a cat with a stretch of lane nobody sees: busy and quiet machines, long silences, music and the user's return.
    func day(seed: UInt64, position: Double = 0.05) -> Drive {
        var drive = Drive(seed: seed, position: position, tuning: CatTuning(sleepAfter: 120), travel: 250, blind: Self.blind)
        for minute in 0..<20 {
            drive.senses.cpuLoad = minute % 7 == 3 ? 0.9 : 0.05
            drive.senses.idleSeconds = minute % 5 == 4 ? 400 : 5
            drive.senses.audioPlaying = minute % 6 == 5
            drive.senses.hour = minute < 10 ? 14 : 23
            drive.senses.pointerNear = minute % 4 == 2
            drive.run(60)
        }
        return drive
    }

    @Test func theCatNeverStopsWhereNobodyCanSeeItWhatItIsDoing() {
        for seed in 1...12 as ClosedRange<UInt64> {
            let drive = day(seed: seed)
            #expect(drive.history.count > 50)
            // A jump where the cat happens to be when the pointer comes is a moment, and the next waking has it dash out of there.
            for entry in drive.history where entry.plan.pose != .startled {
                let plan = entry.plan
                #expect(!Self.blind.contains(plan.to), "seed \(seed) at \(entry.at): a \(plan.pose) that ends at \(plan.to)")
                if plan.from == plan.to {
                    #expect(!Self.blind.contains(plan.from), "seed \(seed) at \(entry.at): a \(plan.pose) begins at \(plan.from)")
                }
            }
        }
    }

    @Test func aWalkThatWouldGoIntoTheBlindStretchGoesAcrossItAtTheCrossingSpeed() {
        var crossings = 0
        for seed in 1...12 as ClosedRange<UInt64> {
            let drive = day(seed: seed)
            for entry in drive.history where entry.plan.from != entry.plan.to && Self.blind.meets(from: entry.plan.from, to: entry.plan.to) {
                let plan = entry.plan
                #expect(plan.pose == .run, "\(plan.pose) across the blind stretch")
                crossings += 1
                #expect(abs(plan.duration - max(abs(plan.to - plan.from) * 250 / CatBrain.crossingSpeed, 0.3)) < 1e-9
                    || plan.fpsScale > 1, "at the crossing speed, or harder if the machine is busy")
            }
        }
        #expect(crossings > 20)
    }

    @Test func itIsInBothPartsOfTheLaneAndNotOnlyInOne() {
        var left = false
        var right = false
        for seed in 1...6 as ClosedRange<UInt64> {
            for entry in day(seed: seed, position: 0.9).history {
                if entry.plan.to <= Self.blind.low { left = true }
                if entry.plan.to >= Self.blind.high { right = true }
            }
        }
        #expect(left && right)
    }

    @Test func aCatThatIsToSitDownInTheBlindStretchDashesOutOfItFirst() throws {
        // Interrupted in the middle of a run across: asked to sit, it is in the middle of the stretch.
        var drive = Drive(seed: 1, position: 0, senses: CatSenses(cpuLoad: 0.9), travel: 250, blind: Self.blind)
        drive.run(1.5)
        #expect(drive.pose == .run)
        #expect(Self.blind.contains(drive.brain.position(at: drive.now)), "it is behind the camera")
        drive.senses.cpuLoad = 0.05
        drive.run(Drive.step)
        let plan = drive.brain.plan
        #expect(plan.pose == .run, "not a sit: out of there first")
        #expect(!Self.blind.contains(plan.to))
    }

    @Test func aCatThatIsStillInTheBlindStretchWhenThePlaceIsLearntOfLeavesAtOnce() {
        var drive = Drive(seed: 1, position: 0.5, travel: 250)
        drive.run(1)
        #expect(drive.pose == .sit)
        drive.blind = Self.blind
        drive.run(Drive.step)
        #expect(drive.pose == .run)
        #expect(!Self.blind.contains(drive.brain.plan.to))
    }

    @Test func aCatThatComesBackOntoTheNotchIsNotBehindTheCamera() {
        var drive = Drive(seed: 1, position: 0, senses: CatSenses(cpuLoad: 0.9), travel: 250, blind: Self.blind)
        drive.run(1.5)
        let before = drive.brain.position(at: drive.now)
        #expect(Self.blind.contains(before))
        drive.brain.resume(now: drive.now, blind: Self.blind)
        let after = drive.brain.plan
        #expect(!Self.blind.contains(after.from))
        #expect(after.pose == .sit)
        #expect(after.from == Self.blind.nearestEdge(to: before))
    }

    @Test func theSpanKnowsItsEdgesAndWhatMeetsIt() {
        let span = BlindSpan(low: 0.2, high: 0.8)
        #expect(span.contains(0.5) && !span.contains(0.2) && !span.contains(0.8) && !span.contains(0.1) && !span.contains(0.9))
        #expect(span.meets(from: 0.1, to: 0.9))
        #expect(span.meets(from: 0.9, to: 0.1))
        #expect(span.meets(from: 0.1, to: 0.5))
        #expect(span.meets(from: 0.5, to: 0.5))
        #expect(!span.meets(from: 0.0, to: 0.2))
        #expect(!span.meets(from: 0.8, to: 1.0))
        #expect(!span.meets(from: 0.3, to: 0.3) == false)
        #expect(span.nearestEdge(to: 0.4) == 0.2)
        #expect(span.nearestEdge(to: 0.6) == 0.8)
    }
}

/// Time the brain's callers wait before looking again: one wake of the stage.
enum CatDrive {
    static let quarter = Drive.step
}
