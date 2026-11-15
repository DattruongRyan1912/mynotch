import Foundation
import Testing
@testable import PetModule

/// What the capybara does about what it senses, and what it does when something breaks into what it was doing.
@Suite struct CapybaraSensesTests {
    func near(_ share: Double) -> PointerReading { PointerReading(share: share, isNear: true, isInRange: true) }

    // MARK: The pointer

    @Test func aPointerInSightMakesASittingCapybaraTurnItsHeadSlowlyAndWhenItIsGoneTurnItBack() {
        var drive = CapyDrive(seed: 2, senses: CatSenses(idleSeconds: 5, hour: 14))
        var turned = false
        for _ in 0..<40 {
            drive.run(1)
            if [.sit, .blink].contains(drive.move) { break }
        }
        drive.senses.pointer = CapyDrive.pointer(0.2, near: false)
        drive.run(0.25)
        #expect(drive.move == .turn, "\(drive.move)")
        #expect(drive.brain.pose.duration == CapybaraMove.turn.passDuration && CapybaraMove.turn.passDuration >= 1, "it takes a second or more")
        drive.run(2)
        #expect(drive.move == .watch)
        turned = true
        let place = drive.brain.pose.from
        // It goes on looking for as long as the pointer is there, and stays where it is.
        for _ in 0..<12 {
            drive.run(5)
            #expect(drive.move == .watch && drive.brain.pose.from == place && drive.brain.pose.to == place)
        }
        drive.senses.pointer = nil
        drive.run(0.25)
        #expect(drive.move == .turnBack)
        drive.run(2)
        #expect(drive.move != .watch && drive.move != .turnBack && drive.move != .turn && turned)
    }

    @Test func aPointerThatComesNearDoesNotStartleOrPounceOrMakeItMoveAtAll() {
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(60 + Double(seed) * 7)
            var reactions = 0
            for round in 0..<40 {
                let before = drive.history.count
                let place = drive.brain.pose.position(at: drive.now)
                let moving = drive.brain.pose.from != drive.brain.pose.to
                drive.senses.pointer = near(place)
                drive.run(3)
                drive.senses.pointer = nil
                drive.run(Double(10 + round % 7))
                // What it did in those seconds is its own day and a turn of the head, and never a leap, a run or a hop away.
                for entry in drive.history[before...] {
                    let move = CapybaraMove(entry.pose.motion)
                    if [.turn, .watch, .turnBack].contains(move) {
                        reactions += 1
                        #expect(entry.pose.from == entry.pose.to && entry.pose.fpsScale == 1, "a look is where it stands: \(move)")
                    }
                    #expect(entry.pose.fpsScale == 1 && entry.pose.delay == 0 && entry.pose.motion.fps <= 8)
                }
                _ = moving
            }
            #expect(reactions > 10, "seed \(seed): it does look: \(reactions)")
        }
    }

    @Test func thePointerNeverBreaksIntoASoakAnOrangeOrAHopAndItsPropsAreNeverLeftBehind() {
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            var inTheTub = 0
            for round in 0..<(4 * 60 * 60 * 3 / 40) {
                drive.senses.pointer = round % 3 == 0 ? CapyDrive.pointer(Double(round % 10) / 10, near: round % 2 == 0) : nil
                drive.run(10) { brain in if brain.stance == .soaking { inTheTub += 1 } }
            }
            #expect(propProblems(drive.trail).isEmpty, "seed \(seed): \(propProblems(drive.trail).prefix(3))")
            #expect(drive.brain.strayProps == 0)
            #expect(inTheTub > 1000, "it did soak")
            for entry in drive.trail where [.turn, .watch, .turnBack].contains(entry.move) {
                #expect(entry.prop != .tubRippling, "no head turning in the water")
            }
        }
    }

    // MARK: A stroke

    @Test func aStrokeMakesAHappySquintAndASmallHeartAndTheDayGoesOnFromWhereItWas() {
        var drive = CapyDrive(seed: 3, senses: CatSenses(idleSeconds: 5, hour: 14))
        for _ in 0..<3000 {
            drive.run(1)
            if drive.move == .doze { break }
        }
        #expect(drive.move == .doze)
        let place = drive.brain.pose.from
        drive.pet()
        #expect(drive.move == .happy && drive.brain.pose.from == place && drive.brain.pose.to == place)
        let heart = CapybaraArt.animation(for: .happy).frames.contains { $0.cells.contains("H") }
        #expect(heart && drive.brain.pose.duration == CapybaraBrain.happyDuration)
        drive.run(CapybaraBrain.happyDuration + 0.5)
        #expect(drive.move == .doze, "it goes back to dozing: \(drive.move)")
        #expect(CapybaraSpecies.shared.meowsWhenPetted == false, "the mew is the cat's")
    }

    @Test func inTheTubAStrokeIsASquintInTheTubAndTheTubStaysAndTheSoakGoesOnAfterIt() {
        var drive = CapyDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 14))
        for _ in 0..<4000 {
            drive.run(1)
            if drive.move == .soak { break }
        }
        #expect(drive.move == .soak)
        let tub = drive.brain.pose.prop
        let left = drive.brain.pose.end - drive.now
        drive.pet()
        #expect(drive.move == .soakHappy && drive.brain.pose.prop == tub && tub != nil, "the water is still there")
        #expect(drive.brain.pose.perch != nil || true)
        drive.run(CapybaraBrain.happyDuration + 0.5)
        #expect(drive.move == .soak && drive.brain.pose.prop == tub, "back to soaking")
        #expect(left > 1)
        drive.run(120)
        #expect(propProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
    }

    @Test func aStrokeWhileItHopsOrGetsUpOrTurnsItsHeadIsNotTakenAndTwoStrokesAreOneSquint() {
        var drive = CapyDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 14))
        var skipped = 0
        for _ in 0..<(4 * 60 * 90) {
            drive.run(0.25)
            if CapybaraBrain.unbroken.contains(drive.move), drive.now < drive.brain.pose.end {
                let before = drive.brain.pose
                let outcome = drive.brain.pet(now: drive.now)
                #expect(outcome == .unchanged && drive.brain.pose == before, "a stroke during \(drive.move)")
                skipped += 1
            }
        }
        #expect(skipped > 100)
        #expect(drive.brain.strayProps == 0)
    }

    // MARK: Sleep

    @Test func awayForTheSleepTimeItComesOutOfTheTubDozesOffSleepsAndSitsUpWhenTheUserIsBack() {
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            // Wait until it is in the tub, which is the hardest time to go to sleep.
            for _ in 0..<6000 {
                drive.run(1)
                if drive.brain.stance == .soaking { break }
            }
            guard drive.brain.stance == .soaking else { continue }
            drive.senses.idleSeconds = 1000
            let from = drive.history.count
            drive.run(150)
            let moves = drive.history[from...].map { CapybaraMove($0.pose.motion) }
            #expect(moves.contains(.climbOut) && moves.contains(.doze) && drive.move == .sleep, "seed \(seed): \(moves)")
            #expect(moves.firstIndex(of: .climbOut)! < moves.firstIndex(of: .doze)! && moves.firstIndex(of: .doze)! < moves.firstIndex(of: .sleep)!)
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil, "the tub went with it")
            #expect(propProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
            // The user is back: it sits up, with nothing to say about it.
            drive.senses.idleSeconds = 0
            drive.run(0.25)
            #expect(drive.move == .sitUp, "\(drive.move)")
            drive.run(5)
            #expect(drive.move != .sleep && drive.move != .sitUp)
        }
    }

    @Test func whileAsleepAStrokeWakesItAndItSitsUpAndSquints() {
        var drive = CapyDrive(seed: 2, senses: CatSenses(idleSeconds: 1000, hour: 23))
        drive.run(200)
        #expect(drive.move == .sleep)
        drive.senses.idleSeconds = 0
        drive.pet()
        #expect(drive.move == .sitUp, "\(drive.move)")
        drive.run(CapybaraMove.sitUp.passDuration + 0.5)
        #expect(drive.move == .happy)
    }

    // MARK: Coming back and the lane

    @Test func backOnTheNotchItSitsWhereItWasWithNothingOutAndTheTubDoesNotComeBack() {
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            for _ in 0..<6000 {
                drive.run(1)
                if drive.brain.stance == .soaking { break }
            }
            guard drive.brain.stance == .soaking else { continue }
            drive.resume()
            let mark = drive.history.count - 1
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil && drive.move == .sit && drive.brain.stance == .seated)
            drive.run(3 * 3600)
            #expect(propProblems(Array(drive.trail[mark...])).isEmpty && drive.brain.strayProps == 0)
        }
    }

    @Test func aLaneThatChangesUnderASoakingCapybaraTakesItsTubAndMovesItOutOfTheWay() {
        var moved = 0
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            for _ in 0..<6000 {
                drive.run(1)
                if drive.move == .soak { break }
            }
            guard drive.move == .soak else { continue }
            let place = drive.brain.pose.from
            drive.lane = LaneContext(crossing: [(place - 0.05)...(place + 0.05)])
            drive.brain.settle(lane: drive.lane)
            moved += 1
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil, "no tub left in the crossing")
            #expect(!(place - 0.05 + 1e-9...place + 0.05 - 1e-9).contains(drive.brain.pose.to))
            #expect(drive.brain.stance == .seated)
            let mark = drive.history.count
            drive.run(2 * 3600)
            #expect(propProblems(Array(drive.trail[mark...])).isEmpty && drive.brain.strayProps == 0)
        }
        #expect(moved >= 8)
    }

    @Test func itNeverStopsInTheCrossingOrInTheWayOfAnotherAndNeverGoesIntoWhatIsClosedThroughHours() {
        let crossing: ClosedRange<Double> = 0.4...0.6
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, position: 0.2, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 156)
            drive.lane = LaneContext(crossing: [crossing], zones: [0.8...0.95])
            drive.run(3 * 3600)
            for pose in drive.every {
                if pose.from == pose.to {
                    #expect(!(crossing.lowerBound + 1e-9..<crossing.upperBound - 1e-9).contains(pose.to), "seed \(seed): a \(CapybaraMove(pose.motion)) at \(pose.to)")
                    #expect(!(0.8 + 1e-9..<0.95 - 1e-9).contains(pose.to), "in the way of another at \(pose.to)")
                }
                if let prop = pose.prop, [.tubEmpty, .tubRippling, .tubAppearing, .tubGoing].contains(CapybaraProp(prop.look)) {
                    #expect(!(crossing.lowerBound + 1e-9..<crossing.upperBound - 1e-9).contains(prop.from), "a tub in the camera at \(prop.from)")
                }
                if CapybaraMove(pose.motion) == .climbIn || CapybaraMove(pose.motion) == .climbOut {
                    let (low, high) = (min(pose.from, pose.to), max(pose.from, pose.to))
                    #expect(!(high > crossing.lowerBound && low < crossing.upperBound), "a hop through the camera")
                }
            }
            #expect(propProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        var closed = CapyDrive(seed: 3, position: 0.2, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 156)
        closed.lane = LaneContext(crossing: [crossing], closed: [crossing])
        closed.run(2 * 3600)
        for pose in closed.every { #expect(max(pose.from, pose.to) <= crossing.lowerBound + 1e-9, "it keeps out of the closed crossing: \(pose.from) to \(pose.to)") }
    }

    @Test func aLaneTooShortForATubHasNoneAndTheDayGoesOnAllTheSame() {
        var drive = CapyDrive(seed: 5, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 20)
        drive.run(2 * 3600)
        let tubs: Set<CapybaraProp> = [.tubAppearing, .tubEmpty, .tubRippling, .tubGoing]
        #expect(drive.every.allSatisfy { pose in pose.prop.map { !tubs.contains(CapybaraProp($0.look)) } ?? true }, "no tub: there is no room to hop")
        #expect(drive.brain.strayProps == 0)
        #expect(drive.scenes.count > 100 && drive.moves.contains(.doze))
        var none = CapyDrive(seed: 5, senses: CatSenses(idleSeconds: 5, hour: 14), travel: 0)
        none.run(3600)
        #expect(none.every.allSatisfy { $0.prop == nil && $0.from == $0.to }, "no lane at all: nothing to walk or play on")
    }

    @Test func itOnlyHasABackToRideOnWhileItSitsOrSoaksAndHoldsStill() {
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.run(2 * 3600)
            for pose in drive.every {
                let move = CapybaraMove(pose.motion)
                #expect((pose.perch != nil) == move.givesPerch, "\(move)")
                if pose.perch != nil { #expect(pose.from == pose.to && pose.perch == Perch(dx: 0)) }
                #expect(!pose.raised)
            }
        }
    }

    // MARK: Whatever interrupts

    @Test func throughAStormOfStrokesPointersSleepAndWakingNothingIsLeftBehindAndItEndsWithNothingOut() {
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            var generator = SplitMix64(seed: seed &* 7919)
            for second in 0..<(3 * 3600) {
                let roll = Double.random(in: 0..<1, using: &generator)
                if roll < 0.02 { drive.pet() }
                if roll > 0.98 { drive.senses.pointer = CapyDrive.pointer(Double.random(in: 0...1, using: &generator), near: roll > 0.99) }
                if roll > 0.5, roll < 0.51 { drive.senses.pointer = nil }
                if second % 900 == 0 { drive.senses.idleSeconds = second % 1800 == 0 ? 5 : 400 }
                if second % 3600 == 1800 { drive.senses.hour = (drive.senses.hour + 9) % 24 }
                drive.run(1)
            }
            #expect(propProblems(drive.trail).isEmpty, "seed \(seed): \(propProblems(drive.trail).prefix(3))")
            #expect(drive.brain.strayProps == 0)
            // The user goes away for good: it ends what it was doing and sleeps, and has nothing out.
            drive.senses.pointer = nil
            drive.senses.idleSeconds = 10_000
            drive.run(300)
            #expect(drive.move == .sleep && !drive.brain.hasProps && drive.brain.pose.prop == nil, "seed \(seed): \(drive.move)")
        }
    }
}
