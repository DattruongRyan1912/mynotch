import Foundation
import Testing
@testable import PetModule

/// What the hamster does about what it senses, and what it does when something breaks into what it was doing.
@Suite struct HamsterSensesTests {
    func near(_ share: Double = 0.5) -> PointerReading { PointerReading(share: share, isNear: true, isInRange: true) }

    /// Runs until `condition` holds of the brain, for at most `limit` seconds.
    func run(_ drive: inout HamDrive, until condition: (HamsterBrain) -> Bool, limit: Double = 7200) {
        var spent = 0.0
        while spent < limit, !condition(drive.brain) {
            drive.run(1)
            spent += 1
        }
    }

    // MARK: The pointer

    @Test func aPointerNearMakesItFreezeWhereItIsUprightFacingTheViewerAndWhenItIsGoneItGoesOnAMomentLater() {
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(30 + Double(seed) * 3)
            let place = drive.brain.pose.position(at: drive.now)
            let moving = drive.brain.pose.from != drive.brain.pose.to
            drive.senses.pointer = near()
            drive.run(0.25)
            if drive.brain.stance == .curled || HamDrive.inTheWheel.contains(drive.move) && drive.move != .wheelWatch { continue }
            #expect(drive.move == .freeze || drive.move == .wheelWatch, "seed \(seed): \(drive.move)")
            let pose = drive.brain.pose
            #expect(pose.from == pose.to && abs(pose.to - place) < 1e-9 || moving, "it freezes where it is")
            #expect(pose.fpsScale == 1 && HamsterMove(pose.motion).fps <= 3)
            // It looks for as long as the pointer is there, and stays where it is.
            for _ in 0..<6 {
                drive.run(2)
                #expect(drive.move == .freeze && drive.brain.pose.from == pose.from && drive.brain.pose.to == pose.to, "seed \(seed): \(drive.move)")
            }
            drive.senses.pointer = nil
            drive.run(0.5)
            #expect(drive.move == .freeze, "a moment's grace: it does not go on at the first look")
            drive.run(1.5)
            #expect(drive.move != .freeze, "and then it goes on: \(drive.move)")
            return
        }
    }

    @Test func aPointerThatIsOnlyInSightDoesNothingToItAndOnlyNearMakesItLook() {
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.senses.pointer = PointerReading(share: 0.5, isNear: false, isInRange: true)
            drive.run(1200)
            #expect(!drive.moves.contains(.freeze) && !drive.moves.contains(.wheelWatch), "seed \(seed)")
            drive.senses.pointer = near()
            drive.run(60)
            #expect(drive.moves.contains(.freeze) || drive.moves.contains(.wheelWatch) || drive.scenes.last == .nap, "seed \(seed): it freezes")
        }
    }

    @Test func itFreezesInTheMiddleOfAScurryWhereItIsAndGoesOnWithItsSceneAfterwards() {
        var froze = 0
        for seed in 1...20 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.move == .scurry && $0.pose.from != $0.pose.to })
            drive.run(0.75)
            guard drive.move == .scurry else { continue }
            // Where it is when the next look finds the pointer there.
            let mid = drive.brain.pose.position(at: drive.now + HamDrive.step)
            drive.senses.pointer = near()
            drive.run(0.25)
            froze += 1
            #expect(drive.move == .freeze && abs(drive.brain.pose.to - mid) < 0.02, "seed \(seed): \(drive.move) at \(drive.brain.pose.to), it was at \(mid)")
            drive.senses.pointer = nil
            drive.run(60)
            #expect(hamsterPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        #expect(froze > 10)
    }

    @Test func inTheWheelItStopsRunningToLookWithTheWheelStillAndGoesOnRunningWhatWasLeftOfItWhenThePointerIsGone() {
        var checked = 0
        for seed in 1...16 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.3, hour: 14))
            run(&drive, until: { $0.move.runs && $0.pose.end - $0.pose.began > 8 })
            drive.run(2)
            guard drive.move.runs else { continue }
            let pace = drive.move
            let (place, wheel) = (drive.brain.pose.to, drive.brain.pose.prop)
            drive.senses.pointer = near()
            drive.run(0.25)
            checked += 1
            #expect(drive.move == .wheelWatch, "seed \(seed): \(drive.move)")
            #expect(drive.brain.pose.prop?.look == HamsterProp.wheelStill.look && drive.brain.pose.prop?.from == wheel?.from, "the wheel stands still")
            #expect(drive.brain.pose.to == place && drive.brain.stance == .wheel)
            drive.run(5)
            #expect(drive.move == .wheelWatch)
            drive.senses.pointer = nil
            drive.run(2)
            #expect(drive.move.runs || drive.move == .wheelSit || drive.move == .hopOut, "back to it: \(drive.move) (was \(pace))")
            drive.run(120)
            #expect(hamsterPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0, "\(hamsterPropProblems(drive.trail).prefix(3))")
        }
        #expect(checked > 8)
    }

    @Test func itDoesNotLookForEverAndNotAgainUntilThePointerHasBeenAwayAndNotMoreOftenThanTheCooldown() {
        var drive = HamDrive(seed: 2, senses: CatSenses(idleSeconds: 5, hour: 14))
        drive.senses.pointer = near()
        drive.run(1)
        #expect(drive.move == .freeze)
        drive.run(HamsterBrain.freezeLimit + 2)
        #expect(drive.move != .freeze, "it has looked as long as it will")
        let looks = drive.moves.filter { $0 == .freeze }.count
        drive.run(300)
        #expect(drive.moves.filter { $0 == .freeze }.count == looks, "a pointer that stays does not make it look again")
        // The pointer goes away and comes back: it looks again, once the cooldown is over.
        func staring(_ drive: HamDrive) -> Bool { [.freeze, .wheelWatch].contains(drive.move) }
        drive.senses.pointer = nil
        drive.run(1)
        drive.senses.pointer = near()
        drive.run(0.25)
        #expect(staring(drive), "\(drive.move)")
        drive.senses.pointer = nil
        drive.run(HamsterBrain.releaseDelay + 1)
        drive.senses.pointer = near()
        drive.run(0.25)
        #expect(!staring(drive), "not again within the cooldown, which is \(drive.tuning.reactionCooldown) s")
        drive.senses.pointer = nil
        drive.run(drive.tuning.reactionCooldown)
        drive.senses.pointer = near()
        drive.run(0.25)
        #expect(staring(drive), "\(drive.move)")
    }

    @Test func aPointerNeverBreaksIntoAHopTheWayInOrOutOrSittingDownAndTheSleeperIsNotWokenByIt() {
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            for _ in 0..<(4 * 60 * 90) {
                drive.senses.pointer = near()
                drive.run(0.25)
                if HamsterBrain.unbroken.contains(drive.move), drive.now < drive.brain.pose.end { continue }
            }
            for entry in drive.history.map(\.pose) where HamsterMove(entry.motion) == .freeze { #expect(entry.from == entry.to) }
            #expect(hamsterPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        var asleep = HamDrive(seed: 2, senses: CatSenses(idleSeconds: 1000, hour: 23))
        asleep.run(200)
        #expect(asleep.move == .sleep)
        asleep.senses.pointer = near()
        for _ in 0..<(4 * 40) {
            asleep.run(0.25)
            #expect(asleep.move == .sleep, "it is asleep: the pointer is nothing to it, not even for a moment")
        }
    }

    // MARK: A stroke

    @Test func aStrokeMakesAHappyHopWithAHeartAndTheDayGoesOnFromWhereItWas() {
        var drive = HamDrive(seed: 3, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&drive, until: { $0.move == .groom })
        #expect(drive.move == .groom)
        drive.run(1)
        let place = drive.brain.pose.from
        drive.pet()
        // From sitting up it hops at once; from four feet it sits up first.
        #expect(drive.move == .happy && drive.brain.pose.from == place && drive.brain.pose.to == place)
        #expect(HamsterArt.animation(for: .happy).frames.contains { $0.cells.contains("H") } && drive.brain.pose.duration == HamsterBrain.happyDuration)
        drive.run(HamsterBrain.happyDuration + 0.5)
        #expect(drive.move == .groom, "it goes back to washing: \(drive.move)")
        #expect(HamsterSpecies.shared.meowsWhenPetted == false, "the mew is the cat's")
    }

    @Test func fromAScurryAStrokeSitsItUpAndItHopsAndInTheWheelItHopsInTheWheelWithTheWheelStillAndRunsOnAfterIt() {
        var drive = HamDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&drive, until: { $0.move == .scurry })
        drive.run(0.5)
        drive.pet()
        #expect(drive.move == .sitDown, "\(drive.move)")
        drive.run(HamsterMove.sitDown.passDuration + 0.05)
        #expect(drive.move == .happy)

        var wheel = HamDrive(seed: 4, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.3, hour: 14))
        run(&wheel, until: { $0.move.runs && $0.pose.end - $0.pose.began > 6 })
        wheel.run(2)
        let (pace, tub) = (wheel.move, wheel.brain.pose.prop?.from)
        wheel.pet()
        #expect(wheel.move == .wheelHappy && wheel.brain.pose.prop?.look == HamsterProp.wheelStill.look && wheel.brain.pose.prop?.from == tub)
        #expect(wheel.brain.stance == .wheel)
        wheel.run(HamsterBrain.happyDuration + 0.5)
        #expect(wheel.move.runs || wheel.move == .hopOut, "and on running: \(wheel.move) (was \(pace))")
        wheel.run(120)
        #expect(hamsterPropProblems(wheel.trail).isEmpty && wheel.brain.strayProps == 0)
    }

    @Test func aStrokeWhileItHopsOrSitsDownOrCurlsIsNotTakenAndAStrokeOnAStareEndsTheStare() {
        var drive = HamDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 14))
        var skipped = 0
        for _ in 0..<(4 * 60 * 90) {
            drive.run(0.25)
            if HamsterBrain.unbroken.contains(drive.move), drive.now < drive.brain.pose.end {
                let before = drive.brain.pose
                let outcome = drive.brain.pet(now: drive.now)
                #expect(outcome == .unchanged && drive.brain.pose == before, "a stroke during \(drive.move)")
                skipped += 1
            }
        }
        #expect(skipped > 100)
        #expect(drive.brain.strayProps == 0)
        var staring = HamDrive(seed: 5, senses: CatSenses(idleSeconds: 5, hour: 14))
        staring.senses.pointer = near()
        staring.run(2)
        #expect(staring.move == .freeze)
        staring.pet()
        #expect(staring.move == .happy)
        staring.run(HamsterBrain.happyDuration + 0.5)
        #expect(staring.move != .freeze, "the stare is over: it is not looking, it was stroked: \(staring.move)")
        staring.run(60)
        #expect(!staring.brain.hasProps || hamsterPropProblems(staring.trail).isEmpty)
    }

    @Test func aStrokeWakesASleeperWhichUncurlsAndHopsForJoy() {
        var drive = HamDrive(seed: 2, senses: CatSenses(idleSeconds: 1000, hour: 23))
        drive.run(200)
        #expect(drive.move == .sleep)
        drive.senses.idleSeconds = 0
        drive.pet()
        #expect(drive.move == .uncurl, "\(drive.move)")
        drive.run(HamsterMove.uncurl.passDuration + 0.3)
        #expect(drive.move == .happy)
    }

    // MARK: Sleep

    @Test func awayForTheSleepTimeItComesOutOfTheWheelCurlsUpSleepsAndUncurlsWhenTheUserIsBack() {
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.3, hour: 14))
            // Wait until it is in the wheel, which is the hardest time to go to sleep.
            run(&drive, until: { $0.stance == .wheel && $0.move.runs })
            guard drive.brain.stance == .wheel else { continue }
            drive.senses.idleSeconds = 1000
            let from = drive.history.count
            drive.run(200)
            let moves = drive.history[from...].map { HamsterMove($0.pose.motion) }
            #expect(moves.contains(.hopOut) && moves.contains(.curl) && drive.move == .sleep, "seed \(seed): \(moves)")
            #expect(moves.firstIndex(of: .hopOut)! < moves.firstIndex(of: .curl)! && moves.firstIndex(of: .curl)! < moves.firstIndex(of: .sleep)!)
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil, "the wheel went with it")
            #expect(hamsterPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
            // The user is back: it uncurls.
            drive.senses.idleSeconds = 0
            drive.run(0.25)
            #expect(drive.move == .uncurl, "\(drive.move)")
            drive.run(5)
            #expect(drive.move != .sleep && drive.move != .uncurl)
        }
    }

    // MARK: Coming back and the lane

    @Test func backOnTheNotchItSitsWhereItWasWithNothingOutAndTheWheelDoesNotComeBack() {
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.3, hour: 14))
            run(&drive, until: { $0.stance == .wheel })
            guard drive.brain.stance == .wheel else { continue }
            drive.resume()
            let mark = drive.history.count - 1
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil && drive.move == .sit && drive.brain.stance == .seated)
            drive.run(3 * 3600)
            #expect(hamsterPropProblems(Array(drive.trail[mark...])).isEmpty && drive.brain.strayProps == 0)
        }
    }

    @Test func aLaneThatChangesUnderARunningHamsterTakesItsWheelAndMovesItOutOfTheWay() {
        var moved = 0
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.3, hour: 14))
            run(&drive, until: { $0.move.runs })
            guard drive.move.runs else { continue }
            let place = drive.brain.pose.from
            drive.lane = LaneContext(crossing: [(place - 0.05)...(place + 0.05)])
            drive.brain.settle(lane: drive.lane)
            moved += 1
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil, "no wheel left in the crossing")
            #expect(!(place - 0.05 + 1e-9...place + 0.05 - 1e-9).contains(drive.brain.pose.to))
            #expect(drive.brain.stance == .seated)
            let mark = drive.history.count
            drive.run(2 * 3600)
            #expect(hamsterPropProblems(Array(drive.trail[mark...])).isEmpty && drive.brain.strayProps == 0, "seed \(seed): \(hamsterPropProblems(Array(drive.trail[mark...])).prefix(3)) \(drive.trail[mark...].prefix(6).map { "\($0.move)/\(String(describing: $0.prop))" })")
        }
        #expect(moved >= 8)
    }

    @Test func itNeverStopsInTheCrossingOrInTheWayOfAnotherAndNeverGoesIntoWhatIsClosedThroughHours() {
        let crossing: ClosedRange<Double> = 0.4...0.6
        for load in [0.05, 0.6] {
            for seed in 1...8 as ClosedRange<UInt64> {
                var drive = HamDrive(seed: seed, position: 0.2, senses: CatSenses(idleSeconds: 5, cpuLoad: load, hour: 14), travel: 156)
                drive.lane = LaneContext(crossing: [crossing], zones: [0.8...0.95])
                drive.run(3 * 3600)
                for pose in drive.every {
                    if pose.from == pose.to {
                        #expect(!(crossing.lowerBound + 1e-9..<crossing.upperBound - 1e-9).contains(pose.to), "seed \(seed): a \(HamsterMove(pose.motion)) at \(pose.to)")
                        #expect(!(0.8 + 1e-9..<0.95 - 1e-9).contains(pose.to), "in the way of another at \(pose.to)")
                    }
                    if let prop = pose.prop, HamsterProp(prop.look).isWheel {
                        #expect(!(crossing.lowerBound + 1e-9..<crossing.upperBound - 1e-9).contains(prop.from), "a wheel in the camera at \(prop.from)")
                        #expect(!(0.8 + 1e-9..<0.95 - 1e-9).contains(prop.from), "a wheel in the way of another at \(prop.from)")
                    }
                    if [.hopIn, .hopOut].contains(HamsterMove(pose.motion)) {
                        let (low, high) = (min(pose.from, pose.to), max(pose.from, pose.to))
                        #expect(!(high > crossing.lowerBound && low < crossing.upperBound), "a hop through the camera")
                    }
                }
                #expect(hamsterPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
            }
        }
        var closed = HamDrive(seed: 3, position: 0.2, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 156)
        closed.lane = LaneContext(crossing: [crossing], closed: [crossing])
        closed.run(2 * 3600)
        for pose in closed.every { #expect(max(pose.from, pose.to) <= crossing.lowerBound + 1e-9, "it keeps out of the closed crossing: \(pose.from) to \(pose.to)") }
    }

    @Test func aLaneTooShortForAWheelHasNoneAndTheDayGoesOnAllTheSame() {
        var drive = HamDrive(seed: 5, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 20)
        drive.run(2 * 3600)
        #expect(drive.every.allSatisfy { pose in pose.prop.map { !HamsterProp($0.look).isWheel } ?? true }, "no wheel: there is no room to hop")
        #expect(drive.brain.strayProps == 0)
        #expect(drive.scenes.count > 100 && drive.moves.contains(.groom))
        var none = HamDrive(seed: 5, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 0)
        none.run(3600)
        #expect(none.every.allSatisfy { $0.prop == nil && $0.from == $0.to }, "no lane at all: nothing to walk or play on")
    }

    @Test func itHasNoBackToRideOnAndTakesPartInNoSceneWithAnother() {
        var drive = HamDrive(seed: 2, senses: CatSenses(idleSeconds: 5, hour: 14))
        drive.run(2 * 3600)
        for pose in drive.every { #expect(pose.perch == nil && !pose.raised) }
        #expect(drive.brain.jointScene == nil)
        let guest = JointInvite(scene: .catOnCapybara, role: .guest, partner: drive.brain.pose)
        #expect(!drive.brain.canJoin(guest, now: drive.now))
    }

    // MARK: Whatever interrupts

    @Test func throughAStormOfStrokesPointersSleepWakingAndLoadNothingIsLeftBehindAndItEndsWithNothingOut() {
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.2, hour: 14))
            var generator = SplitMix64(seed: seed &* 7919)
            for second in 0..<(3 * 3600) {
                let roll = Double.random(in: 0..<1, using: &generator)
                if roll < 0.02 { drive.pet() }
                if roll > 0.98 { drive.senses.pointer = HamDrive.pointer(Double.random(in: 0...1, using: &generator), near: roll > 0.985) }
                if roll > 0.5, roll < 0.52 { drive.senses.pointer = nil }
                if second % 700 == 0 { drive.senses.idleSeconds = second % 1400 == 0 ? 5 : 400 }
                if second % 3600 == 1800 { drive.senses.hour = (drive.senses.hour + 9) % 24 }
                if second % 30 == 0 { drive.senses.cpuLoad = Double.random(in: 0...1, using: &generator) }
                drive.senses.busyBurst = (second / 50) % 9 == 0 && drive.senses.cpuLoad > 0.5
                drive.run(1)
            }
            #expect(hamsterPropProblems(drive.trail).isEmpty, "seed \(seed): \(hamsterPropProblems(drive.trail).prefix(3))")
            #expect(drive.brain.strayProps == 0)
            // The user goes away for good: it ends what it was doing and sleeps, and has nothing out.
            drive.senses.pointer = nil
            drive.senses.busyBurst = false
            drive.senses.idleSeconds = 10_000
            drive.run(300)
            #expect(drive.move == .sleep && !drive.brain.hasProps && drive.brain.pose.prop == nil, "seed \(seed): \(drive.move)")
        }
    }
}
