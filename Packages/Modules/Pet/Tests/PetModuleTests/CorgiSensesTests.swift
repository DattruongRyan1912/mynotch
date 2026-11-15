import Foundation
import Testing
@testable import PetModule

/// What the corgi does about what it senses, and what it does when something breaks into what it was doing.
@Suite struct CorgiSensesTests {
    func near(_ share: Double = 0.5) -> PointerReading { PointerReading(share: share, isNear: true, isInRange: true) }

    /// Runs until `condition` holds of the brain, for at most `limit` seconds.
    func run(_ drive: inout CorDrive, until condition: (CorgiBrain) -> Bool, limit: Double = 7200) {
        var spent = 0.0
        while spent < limit, !condition(drive.brain) {
            drive.run(0.5)
            spent += 0.5
        }
    }

    static let begging: Set<CorgiMove> = [.begUp, .beg]

    /// Standing about with nothing out and nothing under way: where a pointer finds it most of the time.
    static func standingAbout(_ brain: CorgiBrain) -> Bool {
        brain.move == .stand && brain.stance == .standing && !brain.hasProps
    }

    static func free(_ brain: CorgiBrain) -> Bool {
        brain.stance == .standing && !brain.hasProps && !CorgiBrain.unbroken.contains(brain.move)
    }

    // MARK: The pointer

    @Test func aPointerNearMakesItSitDownAndSitUpToBegWhereItStandsAndWhenItIsGoneItSitsDownAMomentLater() {
        var checked = 0
        for seed in 1...12 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: Self.standingAbout)
            guard Self.standingAbout(drive.brain) else { continue }
            let place = drive.brain.pose.position(at: drive.now)
            drive.senses.pointer = near()
            drive.run(0.25)
            #expect(drive.move == .sitDown, "seed \(seed): \(drive.move)")
            let pose = drive.brain.pose
            #expect(abs(pose.to - place) < 0.03 && pose.from == pose.to, "it sits where it is")
            #expect(pose.fpsScale == 1 && !pose.motion.loops)
            drive.run(CorgiMove.sitDown.passDuration + 0.1)
            #expect(drive.move == .begUp, "and sits up: \(drive.move)")
            drive.run(CorgiMove.begUp.passDuration + 0.25)
            #expect(drive.move == .beg, "with its paws together: \(drive.move)")
            // It begs for as long as the pointer is there (within the limit), and stays where it is.
            for _ in 0..<5 {
                drive.run(2)
                #expect(drive.move == .beg && drive.brain.pose.from == pose.from && drive.brain.pose.to == pose.to, "seed \(seed): \(drive.move)")
            }
            drive.senses.pointer = nil
            drive.run(0.5)
            #expect(drive.move == .beg, "a moment's grace: it does not sit down at the first look")
            drive.run(0.75)
            #expect(drive.move == .begDown, "and then it sits down: \(drive.move)")
            drive.run(CorgiMove.begDown.passDuration + 0.5)
            #expect(!Self.begging.contains(drive.move) && drive.move != .begDown, "and goes on: \(drive.move)")
            #expect(corgiPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
            checked += 1
        }
        #expect(checked >= 6, "\(checked)")
    }

    @Test func aPointerThatIsOnlyInSightDoesNothingToItAndOnlyNearMakesItBeg() {
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.senses.pointer = PointerReading(share: 0.5, isNear: false, isInRange: true)
            drive.run(1200)
            #expect(!drive.moves.contains(.begUp) && !drive.moves.contains(.beg), "seed \(seed)")
            drive.senses.pointer = near()
            drive.run(120)
            #expect(drive.moves.contains(.begUp) || drive.scenes.last == .nap, "seed \(seed): it begs")
        }
    }

    @Test func itSitsInTheMiddleOfATrotWhereItIsAndGoesOnWithItsDayAfterwards() {
        var begged = 0
        for seed in 1...20 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.move == .trot && $0.pose.from != $0.pose.to })
            drive.run(0.75)
            guard drive.move == .trot else { continue }
            let mid = drive.brain.pose.position(at: drive.now + CorDrive.step)
            drive.senses.pointer = near()
            drive.run(0.25)
            begged += 1
            #expect(drive.move == .sitDown && abs(drive.brain.pose.to - mid) < 0.02, "seed \(seed): \(drive.move) at \(drive.brain.pose.to), it was at \(mid)")
            drive.senses.pointer = nil
            drive.run(60)
            #expect(corgiPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        #expect(begged > 10)
    }

    @Test func inTheMiddleOfTheZoomiesItStopsWhereItIsToBegAndRunsOnWhenThePointerHasGone() {
        var checked = 0
        for seed in 1...30 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.scene == .zoomies && $0.move == .run && $0.pose.prop == nil })
            guard drive.brain.scene == .zoomies, drive.move == .run else { continue }
            drive.run(0.25)
            guard drive.move == .run else { continue }
            drive.senses.pointer = near()
            drive.run(0.25)
            #expect(drive.move == .sitDown, "seed \(seed): \(drive.move)")
            drive.run(3)
            drive.senses.pointer = nil
            drive.run(8)
            checked += 1
            #expect(corgiPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        #expect(checked > 10, "\(checked)")
    }

    @Test func withTheBallOutItLetsTheBallBeTakenBeforeItSitsUpAndWithItInItsMouthItSetsItDownFirstAndNothingIsLeftOut() {
        var chased = 0, carried = 0
        for seed in 1...16 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.move == .run && $0.pose.prop != nil })
            guard drive.move == .run, drive.brain.pose.prop != nil else { continue }
            let mark = drive.history.count
            drive.senses.pointer = near()
            drive.run(4)
            let moves = drive.history[mark...].map { CorgiMove($0.pose.motion) }
            chased += 1
            #expect(Array(moves.prefix(4)) == [.watch, .sitDown, .begUp, .beg], "seed \(seed): \(moves)")
            #expect(drive.history[mark].pose.prop.map { CorgiProp($0.look) } == .ballUp, "the ball is taken up first")
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil && drive.move == .beg, "nothing out while it begs: \(drive.move)")
            drive.senses.pointer = nil
            drive.run(60)
            #expect(corgiPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0, "\(corgiPropProblems(drive.trail).prefix(3))")

            var holding = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&holding, until: { $0.move == .carry })
            guard holding.move == .carry else { continue }
            let begun = holding.history.count
            holding.senses.pointer = near()
            holding.run(12)
            let after = holding.history[begun...].map { CorgiMove($0.pose.motion) }
            carried += 1
            // The trot home is not broken into, the ball is set down and taken up, and then it begs.
            #expect(Array(after.prefix(5)) == [.lower, .wiggle, .watch, .sitDown, .begUp], "seed \(seed): \(after)")
            #expect(after.contains(.beg) && !holding.brain.hasProps)
            #expect(corgiPropProblems(holding.trail).isEmpty && holding.brain.strayProps == 0, "\(corgiPropProblems(holding.trail).prefix(3))")
        }
        #expect(chased > 8 && carried > 8, "\(chased), \(carried)")
    }

    @Test func fromTheFloorItGetsUpFirstAndAsleepOrNappingItDoesNotBegAtAll() {
        var checked = 0
        for seed in 1...16 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.move == .lie && $0.stance == .lying })
            guard drive.move == .lie else { continue }
            let mark = drive.history.count
            drive.senses.pointer = near()
            drive.run(4)
            let moves = drive.history[mark...].map { CorgiMove($0.pose.motion) }
            checked += 1
            #expect(Array(moves.prefix(4)) == [.getUp, .sitDown, .begUp, .beg], "\(moves)")
        }
        #expect(checked > 8)
        var asleep = CorDrive(seed: 2, senses: CatSenses(idleSeconds: 1000, hour: 23))
        asleep.run(200)
        #expect(asleep.move == .sleep)
        asleep.senses.pointer = near()
        for _ in 0..<(4 * 40) {
            asleep.run(0.25)
            #expect(asleep.move == .sleep, "it is asleep: the pointer is nothing to it, not even for a moment")
        }
        var napping = CorDrive(seed: 3, senses: CatSenses(idleSeconds: 5, hour: 23))
        run(&napping, until: { $0.move == .sleep && $0.pose.end - $0.pose.began > 8 })
        #expect(napping.move == .sleep)
        napping.senses.pointer = near()
        napping.run(4)
        #expect(napping.move == .sleep, "a corgi that is asleep does not beg: \(napping.move)")
    }

    @Test func itDoesNotBegForEverAndNotAgainUntilThePointerHasBeenAwayAndNotMoreOftenThanTheCooldown() {
        var drive = CorDrive(seed: 2, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&drive, until: Self.standingAbout)
        drive.senses.pointer = near()
        drive.run(1)
        #expect(Self.begging.contains(drive.move) || drive.move == .sitDown, "\(drive.move)")
        drive.run(CorgiBrain.begLimit + 3)
        #expect(!Self.begging.contains(drive.move), "it has begged as long as it will: \(drive.move)")
        let begs = drive.moves.filter { $0 == .begUp }.count
        drive.run(300)
        #expect(drive.moves.filter { $0 == .begUp }.count == begs, "a pointer that stays does not make it beg again")
        func begUps(_ drive: CorDrive) -> Int { drive.moves.filter { $0 == .begUp }.count }
        // The pointer goes away and comes back: it begs again, once the cooldown is over.
        drive.senses.pointer = nil
        drive.run(1)
        run(&drive, until: Self.free)
        var count = begUps(drive)
        drive.senses.pointer = near()
        drive.run(3)
        #expect(begUps(drive) == count + 1, "it begs again")
        drive.senses.pointer = nil
        drive.run(CorgiBrain.releaseDelay + 1.5)
        count = begUps(drive)
        drive.senses.pointer = near()
        drive.run(1)
        #expect(begUps(drive) == count, "not again within the cooldown, which is \(drive.tuning.reactionCooldown) s")
        drive.senses.pointer = nil
        drive.run(drive.tuning.reactionCooldown + 4)
        count = begUps(drive)
        drive.senses.pointer = near()
        drive.run(3)
        #expect(begUps(drive) == count + 1, "and when it is over it begs")
    }

    @Test func aPointerNeverBreaksIntoSittingDownGettingUpLyingDownSpinningWatchingTheBallOrCarryingItAndAnythingItBegsFromIsGoneOnFrom() {
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            // The pointer comes and goes: near for two seconds in every fourteen, which is more than the cooldown apart, so that it is
            // heard of again and again, in whatever the corgi is in the middle of.
            for tick in 0..<(4 * 60 * 90) {
                drive.senses.pointer = (tick + Int(seed) * 7) % (4 * 14) < 4 * 2 ? near() : nil
                drive.run(0.25)
            }
            let poses = drive.history.map(\.pose)
            for (before, after) in zip(poses, poses.dropFirst()) where CorgiBrain.unbroken.contains(CorgiMove(before.motion)) {
                #expect(after.began >= before.end - 1e-9, "seed \(seed): \(CorgiMove(before.motion)) was cut short by \(CorgiMove(after.motion))")
            }
            for entry in poses where CorgiMove(entry.motion) == .beg { #expect(entry.from == entry.to) }
            #expect(drive.moves.filter { $0 == .begUp }.count > 100, "it begged again and again: \(drive.moves.filter { $0 == .begUp }.count)")
            #expect(corgiPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
    }

    // MARK: A stroke

    @Test func aStrokeMakesAHappySpinWithAHeartAndTheDayGoesOnFromWhereItWas() {
        var drive = CorDrive(seed: 3, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&drive, until: { $0.move == .wiggle && $0.pose.end - $0.pose.began > 2.5 && Self.free($0) })
        #expect(drive.move == .wiggle)
        drive.run(0.5)
        let place = drive.brain.pose.from
        drive.pet()
        #expect(drive.move == .spin && drive.brain.pose.from == place && drive.brain.pose.to == place)
        #expect(CorgiArt.animation(for: .spin).frames.contains { $0.cells.contains("H") })
        #expect(drive.brain.pose.duration == CorgiBrain.spinDuration)
        drive.run(CorgiBrain.spinDuration + 0.5)
        #expect(drive.move == .wiggle, "it goes back to wiggling: \(drive.move)")
        #expect(CorgiSpecies.shared.meowsWhenPetted == false, "the mew is the cat's")
    }

    @Test func fromATrotAStrokeStopsItWhereItIsAndItSpinsAndFromSittingItStandsUpFirstAndFromTheFloorItGetsUpFirstAndDropsWhatWasLeftOfTheScene() {
        var drive = CorDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&drive, until: { $0.move == .trot && $0.pose.from != $0.pose.to })
        drive.run(0.75)
        let mid = drive.brain.pose.position(at: drive.now)
        drive.pet()
        #expect(drive.move == .spin && abs(drive.brain.pose.to - mid) < 1e-9 && drive.brain.pose.from == drive.brain.pose.to, "\(drive.move)")

        var sitting = CorDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&sitting, until: { $0.move == .sit && $0.stance == .sitting })
        #expect(sitting.move == .sit)
        let seat = sitting.brain.pose.from
        sitting.pet()
        #expect(sitting.move == .standUp, "\(sitting.move)")
        sitting.run(CorgiMove.standUp.passDuration + 0.05)
        #expect(sitting.move == .spin && sitting.brain.pose.from == seat)

        var lying = CorDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&lying, until: { $0.move == .lie && $0.stance == .lying })
        #expect(lying.move == .lie)
        let place = lying.brain.pose.from
        let scene = lying.brain.sceneSerial
        lying.pet()
        #expect(lying.move == .getUp, "\(lying.move)")
        lying.run(CorgiMove.getUp.passDuration + 0.05)
        #expect(lying.move == .spin && lying.brain.pose.from == place)
        lying.run(CorgiBrain.spinDuration + 0.3)
        #expect(lying.brain.sceneSerial > scene, "a new scene: what was left of the old one was dropped")
    }

    @Test func aStrokeOnABeggingCorgiEndsTheBegAndItSitsDownAndStandsUpAndSpinsAndDoesNotBegAgainAtOnce() {
        var checked = 0
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: Self.standingAbout)
            guard Self.standingAbout(drive.brain) else { continue }
            drive.senses.pointer = near()
            run(&drive, until: { $0.move == .beg })
            guard drive.move == .beg else { continue }
            let mark = drive.history.count
            drive.pet()
            drive.run(5)
            let moves = drive.history[mark...].map { CorgiMove($0.pose.motion) }
            checked += 1
            #expect(Array(moves.prefix(3)) == [.begDown, .standUp, .spin], "\(moves)")
            #expect(!moves.contains(.begUp), "it was stroked and has had enough of that for the time being: \(moves)")
        }
        #expect(checked > 6, "\(checked)")
    }

    @Test func withTheBallLyingAStrokeMakesItSpinAndThenTheBallIsTakenAndTheFetchIsOver() {
        var checked = 0
        for seed in 1...12 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.move == .run && $0.pose.prop != nil })
            guard drive.move == .run, drive.brain.pose.prop != nil else { continue }
            let (mark, scene) = (drive.history.count, drive.brain.sceneSerial)
            drive.pet()
            checked += 1
            #expect(drive.move == .spin && drive.brain.pose.prop.map { CorgiProp($0.look) } == .ballRest, "the ball lies while it spins: \(drive.move)")
            drive.run(CorgiBrain.spinDuration + 0.3)
            let moves = drive.history[mark...].map { CorgiMove($0.pose.motion) }
            #expect(Array(moves.prefix(2)) == [.spin, .watch] && !moves.contains(.grab), "the ball is taken: \(moves)")
            // (The next scene is not the fetch: it is never the same one twice.)
            drive.run(1.5)
            #expect(!drive.brain.hasProps && drive.brain.sceneSerial > scene)
            drive.run(30)
            #expect(corgiPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0, "\(corgiPropProblems(drive.trail).prefix(3))")
        }
        #expect(checked > 8)
    }

    @Test func aStrokeWhileItSitsDownGetsUpLiesDownSpinsWatchesTheBallCarriesItOrSetsItDownIsNotTaken() {
        var drive = CorDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 14))
        var skipped: Set<CorgiMove> = []
        for _ in 0..<(4 * 60 * 120) {
            drive.run(0.25)
            if CorgiBrain.unbroken.contains(drive.move), drive.now < drive.brain.pose.end {
                let before = drive.brain.pose
                let outcome = drive.brain.pet(now: drive.now)
                #expect(outcome == .unchanged && drive.brain.pose == before, "a stroke during \(drive.move)")
                skipped.insert(drive.move)
            }
        }
        #expect(skipped.isSuperset(of: [.sitDown, .standUp, .lieDown, .getUp, .settle, .watch, .grab, .carry, .lower]), "\(skipped)")
        #expect(drive.brain.strayProps == 0)
    }

    @Test func aStrokeWakesASleeperWhichGetsUpAndSpins() {
        var drive = CorDrive(seed: 2, senses: CatSenses(idleSeconds: 1000, hour: 23))
        drive.run(200)
        #expect(drive.move == .sleep)
        drive.senses.idleSeconds = 0
        let mark = drive.history.count
        drive.pet()
        drive.run(4)
        let moves = drive.history[mark...].map { CorgiMove($0.pose.motion) }
        #expect(Array(moves.prefix(3)) == [.wake, .getUp, .spin], "\(moves)")
    }

    // MARK: Sleep

    @Test func awayForTheSleepTimeItLetsTheBallBeTakenLiesDownGoesToSleepOnItsSideAndGetsUpWhenTheUserIsBack() {
        for seed in 1...10 as ClosedRange<UInt64> {
            for state in 0..<3 {
                var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
                // The hardest times to go to sleep: with the ball lying, in its mouth, and on its feet at a run.
                switch state {
                case 0: run(&drive, until: { $0.move == .run && $0.pose.prop != nil })
                case 1: run(&drive, until: { $0.move == .carry })
                default: run(&drive, until: { $0.move == .trot })
                }
                guard drive.move == [.run, .carry, .trot][state] else { continue }
                drive.senses.idleSeconds = 1000
                let from = drive.history.count
                drive.run(200)
                let moves = drive.history[from...].map { CorgiMove($0.pose.motion) }
                #expect(moves.contains(.lieDown) && moves.contains(.settle) && drive.move == .sleep, "seed \(seed), \(state): \(moves)")
                #expect(moves.firstIndex(of: .lieDown)! < moves.firstIndex(of: .settle)! && moves.firstIndex(of: .settle)! < moves.firstIndex(of: .sleep)!)
                if state < 2 {
                    let taken = drive.history[from...].firstIndex { $0.pose.prop.map { CorgiProp($0.look) == .ballUp } ?? false }
                    #expect(taken != nil && taken! < from + moves.firstIndex(of: .lieDown)!, "the ball was taken up before it lay down")
                }
                #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil, "the ball went with it")
                #expect(corgiPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0, "\(corgiPropProblems(drive.trail).prefix(3))")
                // The user is back: it wakes and gets up.
                drive.senses.idleSeconds = 0
                drive.run(0.25)
                #expect(drive.move == .wake, "\(drive.move)")
                drive.run(5)
                #expect(drive.move != .sleep && drive.move != .wake && drive.brain.stance != .asleep)
            }
        }
    }

    // MARK: Coming back and the lane

    @Test func backOnTheNotchItStandsWhereItWasWithNothingOutAndTheBallDoesNotComeBack() {
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.hasProps })
            guard drive.brain.hasProps else { continue }
            drive.resume()
            let mark = drive.history.count - 1
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil && drive.move == .stand && drive.brain.stance == .standing)
            drive.run(3 * 3600)
            #expect(corgiPropProblems(Array(drive.trail[mark...])).isEmpty && drive.brain.strayProps == 0)
        }
    }

    @Test func aLaneThatChangesUnderACorgiWithTheBallOutTakesTheBallAndMovesItOutOfTheWay() {
        var moved = 0
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.hasProps && $0.pose.from == $0.pose.to && $0.pose.prop != nil })
            guard drive.brain.hasProps, drive.brain.pose.from == drive.brain.pose.to else { continue }
            let place = drive.brain.pose.from
            drive.lane = LaneContext(crossing: [(place - 0.05)...(place + 0.05)])
            drive.brain.settle(lane: drive.lane)
            moved += 1
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil, "no ball left in the crossing")
            #expect(!(place - 0.05 + 1e-9...place + 0.05 - 1e-9).contains(drive.brain.pose.to))
            #expect(drive.brain.stance == .standing)
            let mark = drive.history.count
            drive.run(2 * 3600)
            #expect(corgiPropProblems(Array(drive.trail[mark...])).isEmpty && drive.brain.strayProps == 0, "seed \(seed): \(corgiPropProblems(Array(drive.trail[mark...])).prefix(3))")
        }
        #expect(moved >= 8)
    }

    // MARK: Whatever interrupts

    @Test func throughAStormOfStrokesPointersSleepWakingLoadAndBurstsNothingIsLeftBehindAndItEndsWithNothingOut() {
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = CorDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.2, hour: 14))
            var generator = SplitMix64(seed: seed &* 7919)
            for second in 0..<(3 * 3600) {
                let roll = Double.random(in: 0..<1, using: &generator)
                if roll < 0.02 { drive.pet() }
                if roll > 0.98 { drive.senses.pointer = CorDrive.pointer(Double.random(in: 0...1, using: &generator), near: roll > 0.985) }
                if roll > 0.5, roll < 0.52 { drive.senses.pointer = nil }
                if second % 700 == 0 { drive.senses.idleSeconds = second % 1400 == 0 ? 5 : 400 }
                if second % 3600 == 1800 { drive.senses.hour = (drive.senses.hour + 9) % 24 }
                if second % 30 == 0 { drive.senses.cpuLoad = Double.random(in: 0...1, using: &generator) }
                drive.senses.busyBurst = (second / 50) % 9 == 0 && drive.senses.cpuLoad > 0.5
                drive.run(1)
            }
            #expect(corgiPropProblems(drive.trail).isEmpty, "seed \(seed): \(corgiPropProblems(drive.trail).prefix(3))")
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
