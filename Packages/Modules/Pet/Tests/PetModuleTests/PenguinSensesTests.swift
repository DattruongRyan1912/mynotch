import Foundation
import Testing
@testable import PetModule

/// What the penguin does about what it senses, and what it does when something breaks into what it was doing.
@Suite struct PenguinSensesTests {
    func near(_ share: Double = 0.5) -> PointerReading { PointerReading(share: share, isNear: true, isInRange: true) }

    /// Runs until `condition` holds of the brain, for at most `limit` seconds.
    func run(_ drive: inout PenDrive, until condition: (PenguinBrain) -> Bool, limit: Double = 7200) {
        var spent = 0.0
        while spent < limit, !condition(drive.brain) {
            drive.run(0.5)
            spent += 0.5
        }
    }

    static let staring: Set<PenguinMove> = [.lookTurn, .lookFlap]

    // MARK: The pointer

    @Test func aPointerNearMakesItTurnToFaceTheViewerWhereItStandsAndFlapAndWhenItIsGoneItTurnsBackAMomentLater() {
        var checked = 0
        for seed in 1...12 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(30 + Double(seed) * 3)
            guard drive.brain.stance == .standing, !PenguinBrain.unbroken.contains(drive.move), !drive.brain.hasProps else { continue }
            let place = drive.brain.pose.position(at: drive.now)
            drive.senses.pointer = near()
            drive.run(0.25)
            #expect(drive.move == .lookTurn, "seed \(seed): \(drive.move)")
            let pose = drive.brain.pose
            #expect(abs(pose.to - place) < 0.03 && pose.from == pose.to, "it turns where it is")
            #expect(pose.fpsScale == 1 && !pose.motion.loops)
            drive.run(PenguinMove.lookTurn.passDuration + 0.25)
            #expect(drive.move == .lookFlap, "and flaps, facing the viewer: \(drive.move)")
            // It flaps for as long as the pointer is there, and stays where it is.
            for _ in 0..<5 {
                drive.run(2)
                #expect(drive.move == .lookFlap && drive.brain.pose.from == pose.from && drive.brain.pose.to == pose.to, "seed \(seed): \(drive.move)")
            }
            drive.senses.pointer = nil
            drive.run(0.5)
            #expect(drive.move == .lookFlap, "a moment's grace: it does not turn back at the first look")
            drive.run(0.75)
            #expect(drive.move == .lookBack, "and then it turns back: \(drive.move)")
            drive.run(PenguinMove.lookBack.passDuration + 0.5)
            #expect(!Self.staring.contains(drive.move) && drive.move != .lookBack, "and goes on: \(drive.move)")
            checked += 1
        }
        #expect(checked >= 5, "\(checked)")
    }

    @Test func aPointerThatIsOnlyInSightDoesNothingToItAndOnlyNearMakesItLook() {
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.senses.pointer = PointerReading(share: 0.5, isNear: false, isInRange: true)
            drive.run(1200)
            #expect(!drive.moves.contains(.lookTurn) && !drive.moves.contains(.lookFlap), "seed \(seed)")
            drive.senses.pointer = near()
            drive.run(90)
            #expect(drive.moves.contains(.lookTurn) || drive.scenes.last == .nap, "seed \(seed): it turns to look")
        }
    }

    @Test func itTurnsInTheMiddleOfAWaddleWhereItIsAndGoesOnWithItsSceneAfterwards() {
        var turned = 0
        for seed in 1...20 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.move == .waddle && $0.pose.from != $0.pose.to })
            drive.run(0.75)
            guard drive.move == .waddle else { continue }
            let mid = drive.brain.pose.position(at: drive.now + PenDrive.step)
            drive.senses.pointer = near()
            drive.run(0.25)
            turned += 1
            #expect(drive.move == .lookTurn && abs(drive.brain.pose.to - mid) < 0.02, "seed \(seed): \(drive.move) at \(drive.brain.pose.to), it was at \(mid)")
            drive.senses.pointer = nil
            drive.run(60)
            #expect(penguinPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        #expect(turned > 10)
    }

    @Test func aFisherTakesItsLineInAndTheHoleClosesBeforeItTurnsToLookAndNothingIsLeftOut() {
        var checked = 0
        for seed in 1...16 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.move == .fish && $0.pose.end - $0.pose.began > 2 })
            guard drive.move == .fish else { continue }
            let mark = drive.history.count
            drive.senses.pointer = near()
            drive.run(0.25)
            let first = PenguinMove(drive.brain.pose.motion)
            drive.run(6)
            let moves = drive.history[mark...].map { PenguinMove($0.pose.motion) }
            checked += 1
            #expect(first == .reel || drive.move == .reel || moves.first == .reel, "the line comes in first: \(moves)")
            guard let turn = moves.firstIndex(of: .lookTurn), let reel = moves.firstIndex(of: .reel) else {
                #expect(Bool(false), "seed \(seed): it turned to look: \(moves)")
                continue
            }
            #expect(reel < turn)
            let between = drive.history[mark...].map(\.pose)[reel..<turn]
            #expect(between.contains { $0.prop.map { PenguinProp($0.look) == .holeClosing } ?? false }, "the hole closed: \(moves) \(drive.history[mark...].map { String(describing: $0.pose.prop.map { PenguinProp($0.look) }) })")
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil && drive.brain.stance == .standing, "nothing out while it looks: \(drive.move) \(drive.brain.stance) \(drive.brain.hasProps)")
            drive.senses.pointer = nil
            drive.run(60)
            #expect(penguinPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0, "\(penguinPropProblems(drive.trail).prefix(3))")
        }
        #expect(checked > 8, "\(checked)")
    }

    @Test func onItsBellyItGetsUpBeforeItTurnsToLook() {
        var checked = 0
        for seed in 1...16 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.move == .dazed })
            guard drive.move == .dazed else { continue }
            let mark = drive.history.count
            drive.senses.pointer = near()
            drive.run(3)
            let moves = drive.history[mark...].map { PenguinMove($0.pose.motion) }
            checked += 1
            #expect(Array(moves.prefix(2)) == [.getUp, .lookTurn], "\(moves)")
        }
        #expect(checked > 8)
    }

    @Test func itDoesNotLookForEverAndNotAgainUntilThePointerHasBeenAwayAndNotMoreOftenThanTheCooldown() {
        var drive = PenDrive(seed: 2, senses: CatSenses(idleSeconds: 5, hour: 14))
        // Standing, with nothing out and nothing under way.
        run(&drive, until: { $0.move == .stand && $0.stance == .standing && !$0.hasProps })
        drive.senses.pointer = near()
        drive.run(1)
        #expect(drive.move == .lookTurn || drive.move == .lookFlap, "\(drive.move)")
        drive.run(PenguinBrain.freezeLimit + 2)
        #expect(!Self.staring.contains(drive.move), "it has looked as long as it will")
        let looks = drive.moves.filter { $0 == .lookTurn }.count
        drive.run(300)
        #expect(drive.moves.filter { $0 == .lookTurn }.count == looks, "a pointer that stays does not make it look again")
        func staring(_ drive: PenDrive) -> Bool { Self.staring.contains(drive.move) }
        // The pointer goes away and comes back: it looks again, once the cooldown is over.
        drive.senses.pointer = nil
        drive.run(1)
        run(&drive, until: { $0.stance == .standing && !$0.hasProps && !PenguinBrain.unbroken.contains($0.move) })
        drive.senses.pointer = near()
        drive.run(0.25)
        #expect(staring(drive), "\(drive.move)")
        drive.senses.pointer = nil
        drive.run(PenguinBrain.releaseDelay + 1.5)
        run(&drive, until: { $0.stance == .standing && !$0.hasProps && !PenguinBrain.unbroken.contains($0.move) }, limit: 30)
        drive.senses.pointer = near()
        drive.run(0.25)
        #expect(!staring(drive), "not again within the cooldown, which is \(drive.tuning.reactionCooldown) s")
        drive.senses.pointer = nil
        drive.run(drive.tuning.reactionCooldown + 3)
        run(&drive, until: { $0.stance == .standing && !$0.hasProps && !PenguinBrain.unbroken.contains($0.move) }, limit: 60)
        drive.senses.pointer = near()
        drive.run(0.25)
        #expect(staring(drive) || drive.brain.stance != .standing, "\(drive.move)")
    }

    @Test func aPointerNeverBreaksIntoAGlideAFallGettingUpTuckingInOrTheLineGoingInOrComingOutAndASleeperOrANapperIsNotLookedUpFromIt() {
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            for _ in 0..<(4 * 60 * 90) {
                drive.senses.pointer = near()
                drive.run(0.25)
            }
            let poses = drive.history.map(\.pose)
            for (before, after) in zip(poses, poses.dropFirst()) where PenguinBrain.unbroken.contains(PenguinMove(before.motion)) {
                #expect(after.began >= before.end - 1e-9, "seed \(seed): \(PenguinMove(before.motion)) was cut short by \(PenguinMove(after.motion))")
            }
            for entry in poses where PenguinMove(entry.motion) == .lookTurn { #expect(entry.from == entry.to) }
            #expect(penguinPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        var asleep = PenDrive(seed: 2, senses: CatSenses(idleSeconds: 1000, hour: 23))
        asleep.run(200)
        #expect(asleep.move == .sleep)
        asleep.senses.pointer = near()
        for _ in 0..<(4 * 40) {
            asleep.run(0.25)
            #expect(asleep.move == .sleep, "it is asleep: the pointer is nothing to it, not even for a moment")
        }
        var napping = PenDrive(seed: 3, senses: CatSenses(idleSeconds: 5, hour: 23))
        run(&napping, until: { $0.move == .tucked && $0.pose.end - $0.pose.began > 6 })
        #expect(napping.move == .tucked)
        napping.senses.pointer = near()
        napping.run(4)
        #expect(napping.move == .tucked, "a penguin with its head tucked in does not look: \(napping.move)")
    }

    // MARK: A stroke

    @Test func aStrokeMakesAHappyFlapFacingTheViewerWithAHeartAndTheDayGoesOnFromWhereItWas() {
        var drive = PenDrive(seed: 3, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&drive, until: { $0.move == .flap && $0.pose.end - $0.pose.began > 2.5 })
        #expect(drive.move == .flap)
        drive.run(0.5)
        let place = drive.brain.pose.from
        drive.pet()
        #expect(drive.move == .happy && drive.brain.pose.from == place && drive.brain.pose.to == place)
        #expect(PenguinArt.animation(for: .happy).frames.contains { $0.cells.contains("H") })
        #expect(drive.brain.pose.duration == PenguinBrain.happyDuration)
        drive.run(PenguinBrain.happyDuration + 0.5)
        #expect(drive.move == .flap, "it goes back to flapping: \(drive.move)")
        #expect(PenguinSpecies.shared.meowsWhenPetted == false, "the mew is the cat's")
    }

    @Test func fromAWaddleAStrokeStopsItWhereItIsAndItJumpsForJoyAndFromItsBellyItGetsUpFirstAndDropsWhatWasLeftOfTheScene() {
        var drive = PenDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&drive, until: { $0.move == .waddle && $0.pose.from != $0.pose.to })
        drive.run(0.75)
        let mid = drive.brain.pose.position(at: drive.now)
        drive.pet()
        #expect(drive.move == .happy && abs(drive.brain.pose.to - mid) < 1e-9 && drive.brain.pose.from == drive.brain.pose.to, "\(drive.move)")

        var lying = PenDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&lying, until: { $0.move == .dazed })
        #expect(lying.move == .dazed)
        let place = lying.brain.pose.from
        lying.pet()
        #expect(lying.move == .getUp, "\(lying.move)")
        lying.run(PenguinMove.getUp.passDuration + 0.05)
        #expect(lying.move == .happy && lying.brain.pose.from == place)
        lying.run(PenguinBrain.happyDuration + 0.3)
        #expect(lying.move != .bellyDown && lying.move != .dazed && lying.move != .lie, "it does not lie down again: \(lying.move)")
    }

    @Test func aStrokeOnItsBellyBetweenTwoGlidesGetsItUpAndDoesNotPutItBackOnItsBellyForTheSecondOne() {
        var checked = 0
        for seed in 1...40 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.move == .lie && $0.pose.end - $0.pose.began > 0.4 })
            guard drive.move == .lie, drive.scenes.last == .slideAbout else { continue }
            let scene = drive.brain.sceneSerial
            drive.pet()
            checked += 1
            var moves: [PenguinMove] = []
            for _ in 0..<(4 * 20) {
                drive.run(0.25)
                if drive.brain.sceneSerial != scene { break }
                moves.append(drive.move)
            }
            #expect(moves.contains(.happy), "seed \(seed): \(moves)")
            #expect(!moves.contains(.bellyDown) && !moves.contains(.slide) && !moves.contains(.lie), "seed \(seed): the glide it had left is dropped: \(moves)")
        }
        #expect(checked > 12, "\(checked)")
    }

    @Test func whileFishingAStrokeMakesItJumpForJoyWithTheRodInItsFlipperAndTheHoleWhereItWasAndItGoesOnFishing() {
        var checked = 0
        for seed in 1...12 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.move == .fish && $0.pose.end - $0.pose.began > 3 })
            guard drive.move == .fish else { continue }
            drive.run(1)
            let (place, hole) = (drive.brain.pose.to, drive.brain.pose.prop)
            drive.pet()
            checked += 1
            #expect(drive.move == .fishHappy && drive.brain.stance == .fishing, "\(drive.move)")
            #expect(drive.brain.pose.to == place && drive.brain.pose.prop?.from == hole?.from && drive.brain.pose.prop.map { PenguinProp($0.look) } == .holeRippling)
            drive.run(PenguinBrain.happyDuration + 0.3)
            #expect(PenguinMove(drive.brain.pose.motion) == .fish || drive.move == .reel, "and on fishing: \(drive.move)")
            drive.run(120)
            #expect(penguinPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        #expect(checked > 8)
    }

    @Test func aStrokeWhileItGlidesFallsGetsUpTucksCastsOrPullsAFishInIsNotTakenAndAStrokeOnALookEndsTheLook() {
        var drive = PenDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 14))
        var skipped: Set<PenguinMove> = []
        for _ in 0..<(4 * 60 * 120) {
            drive.run(0.25)
            if PenguinBrain.unbroken.contains(drive.move), drive.now < drive.brain.pose.end {
                let before = drive.brain.pose
                let outcome = drive.brain.pet(now: drive.now)
                #expect(outcome == .unchanged && drive.brain.pose == before, "a stroke during \(drive.move)")
                skipped.insert(drive.move)
            }
        }
        #expect(skipped.isSuperset(of: [.slide, .bellyDown, .getUp, .slip, .cast, .reel, .pull]), "\(skipped)")
        #expect(drive.brain.strayProps == 0)
        var staring = PenDrive(seed: 5, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&staring, until: { $0.stance == .standing && !$0.hasProps && !PenguinBrain.unbroken.contains($0.move) })
        staring.senses.pointer = near()
        staring.run(2)
        #expect(staring.move == .lookFlap)
        staring.pet()
        #expect(staring.move == .happy)
        staring.run(PenguinBrain.happyDuration + 0.5)
        #expect(!Self.staring.contains(staring.move), "the look is over: it was stroked: \(staring.move)")
        staring.run(60)
        #expect(!staring.brain.hasProps || penguinPropProblems(staring.trail).isEmpty)
    }

    @Test func aStrokeWakesASleeperWhichUntucksAndJumpsForJoy() {
        var drive = PenDrive(seed: 2, senses: CatSenses(idleSeconds: 1000, hour: 23))
        drive.run(200)
        #expect(drive.move == .sleep)
        drive.senses.idleSeconds = 0
        drive.pet()
        #expect(drive.move == .untuck, "\(drive.move)")
        drive.run(PenguinMove.untuck.passDuration + 0.3)
        #expect(drive.move == .happy)
    }

    // MARK: Sleep

    @Test func awayForTheSleepTimeItTakesItsLineInLetsTheHoleCloseGetsUpIfItIsDownTucksItsHeadInAndSleepsAndUntucksWhenTheUserIsBack() {
        for seed in 1...10 as ClosedRange<UInt64> {
            var fishing = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            // Wait until it is fishing, which is the hardest time to go to sleep.
            run(&fishing, until: { $0.stance == .fishing && $0.move == .fish })
            guard fishing.brain.stance == .fishing else { continue }
            fishing.senses.idleSeconds = 1000
            let from = fishing.history.count
            fishing.run(200)
            let moves = fishing.history[from...].map { PenguinMove($0.pose.motion) }
            #expect(moves.contains(.reel) && moves.contains(.tuck) && fishing.move == .sleep, "seed \(seed): \(moves)")
            #expect(moves.firstIndex(of: .reel)! < moves.firstIndex(of: .tuck)! && moves.firstIndex(of: .tuck)! < moves.firstIndex(of: .sleep)!)
            let closing = fishing.history[from...].firstIndex { $0.pose.prop.map { PenguinProp($0.look) == .holeClosing } ?? false }
            #expect(closing != nil && closing! < from + moves.firstIndex(of: .tuck)!, "the hole closed before it tucked in")
            #expect(!fishing.brain.hasProps && fishing.brain.pose.prop == nil, "the hole went with it")
            #expect(penguinPropProblems(fishing.trail).isEmpty && fishing.brain.strayProps == 0)
            // The user is back: it untucks.
            fishing.senses.idleSeconds = 0
            fishing.run(0.25)
            #expect(fishing.move == .untuck, "\(fishing.move)")
            fishing.run(5)
            #expect(fishing.move != .sleep && fishing.move != .untuck)

            var lying = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&lying, until: { $0.stance == .lying && $0.move != .slide && $0.move != .bellyDown })
            guard lying.brain.stance == .lying else { continue }
            lying.senses.idleSeconds = 1000
            let begun = lying.history.count
            lying.run(200)
            let down = lying.history[begun...].map { PenguinMove($0.pose.motion) }
            #expect(down.contains(.getUp) && down.contains(.tuck) && lying.move == .sleep, "seed \(seed): \(down)")
            #expect(down.firstIndex(of: .getUp)! < down.firstIndex(of: .tuck)!)
        }
    }

    // MARK: Coming back and the lane

    @Test func backOnTheNotchItStandsWhereItWasWithNothingOutAndTheHoleDoesNotComeBack() {
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.stance == .fishing })
            guard drive.brain.stance == .fishing else { continue }
            drive.resume()
            let mark = drive.history.count - 1
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil && drive.move == .stand && drive.brain.stance == .standing)
            drive.run(3 * 3600)
            #expect(penguinPropProblems(Array(drive.trail[mark...])).isEmpty && drive.brain.strayProps == 0)
        }
    }

    @Test func aLaneThatChangesUnderAFishingPenguinTakesItsHoleAndMovesItOutOfTheWay() {
        var moved = 0
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.stance == .fishing })
            guard drive.brain.stance == .fishing else { continue }
            let place = drive.brain.pose.from
            drive.lane = LaneContext(crossing: [(place - 0.05)...(place + 0.05)])
            drive.brain.settle(lane: drive.lane)
            moved += 1
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil, "no hole left in the crossing")
            #expect(!(place - 0.05 + 1e-9...place + 0.05 - 1e-9).contains(drive.brain.pose.to))
            #expect(drive.brain.stance == .standing)
            let mark = drive.history.count
            drive.run(2 * 3600)
            #expect(penguinPropProblems(Array(drive.trail[mark...])).isEmpty && drive.brain.strayProps == 0, "seed \(seed): \(penguinPropProblems(Array(drive.trail[mark...])).prefix(3))")
        }
        #expect(moved >= 8)
    }

    // MARK: Whatever interrupts

    @Test func throughAStormOfStrokesPointersSleepWakingAndLoadNothingIsLeftBehindAndItEndsWithNothingOut() {
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.2, hour: 14))
            var generator = SplitMix64(seed: seed &* 7919)
            for second in 0..<(3 * 3600) {
                let roll = Double.random(in: 0..<1, using: &generator)
                if roll < 0.02 { drive.pet() }
                if roll > 0.98 { drive.senses.pointer = PenDrive.pointer(Double.random(in: 0...1, using: &generator), near: roll > 0.985) }
                if roll > 0.5, roll < 0.52 { drive.senses.pointer = nil }
                if second % 700 == 0 { drive.senses.idleSeconds = second % 1400 == 0 ? 5 : 400 }
                if second % 3600 == 1800 { drive.senses.hour = (drive.senses.hour + 9) % 24 }
                if second % 30 == 0 { drive.senses.cpuLoad = Double.random(in: 0...1, using: &generator) }
                drive.senses.busyBurst = (second / 50) % 9 == 0 && drive.senses.cpuLoad > 0.5
                drive.run(1)
            }
            #expect(penguinPropProblems(drive.trail).isEmpty, "seed \(seed): \(penguinPropProblems(drive.trail).prefix(3))")
            #expect(drive.brain.strayProps == 0)
            // The user goes away for good: it ends what it was doing and sleeps on its feet, and has nothing out.
            drive.senses.pointer = nil
            drive.senses.busyBurst = false
            drive.senses.idleSeconds = 10_000
            drive.run(300)
            #expect(drive.move == .sleep && !drive.brain.hasProps && drive.brain.pose.prop == nil, "seed \(seed): \(drive.move)")
        }
    }
}
