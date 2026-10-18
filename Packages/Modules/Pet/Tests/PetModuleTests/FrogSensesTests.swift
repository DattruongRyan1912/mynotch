import Foundation
import Testing
@testable import PetModule

/// What the frog does about what it senses, and what it does when something breaks into what it was doing.
@Suite struct FrogSensesTests {
    func near(_ share: Double = 0.9) -> PointerReading { PointerReading(share: share, isNear: true, isInRange: true) }

    /// Runs until `condition` holds of the brain, for at most `limit` seconds.
    func run(_ drive: inout FrDrive, until condition: (FrogBrain) -> Bool, limit: Double = 7200) {
        var spent = 0.0
        while spent < limit, !condition(drive.brain) {
            drive.run(0.25)
            spent += 0.25
        }
    }

    static let watching: Set<FrogMove> = [.watch, .padWatch, .flick, .padFlick]

    /// Sitting about with nothing out and nothing under way: where a pointer finds it most of the time.
    static func sittingAbout(_ brain: FrogBrain) -> Bool {
        brain.move == .sit && brain.stance == .ground && !brain.hasProps && !brain.isWatching
    }

    static func free(_ brain: FrogBrain) -> Bool {
        brain.stance == .ground && !brain.hasProps && !brain.isAsleep && !FrogBrain.unbroken.contains(brain.move) && !FrogBrain.holds.contains(brain.move)
            && !(brain.move == .hop && brain.pose.from != brain.pose.to)
    }

    /// Whether it is on the pad, with nothing under way: sitting on it.
    static func onThePad(_ brain: FrogBrain) -> Bool {
        brain.move == .padSit && brain.stance == .pad && !brain.isWatching
    }

    // MARK: The pointer

    @Test func aPointerNearMakesItTurnToItAndWatchItWhereItSitsAndFlickItsTongueTowardsItAndWhenItIsGoneItGoesOn() {
        var checked = 0
        for seed in 1...12 as ClosedRange<UInt64> {
            for share in [0.95, 0.02] {
                var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
                run(&drive, until: Self.sittingAbout)
                guard Self.sittingAbout(drive.brain) else { continue }
                let place = drive.brain.pose.position(at: drive.now)
                drive.senses.pointer = near(share)
                drive.run(0.25)
                #expect(drive.move == .watch, "seed \(seed): \(drive.move)")
                let pose = drive.brain.pose
                #expect(abs(pose.to - place) < 0.03 && pose.from == pose.to, "it watches where it is")
                #expect(pose.facing == (share > 0.5 ? .right : .left), "it turns to the pointer")
                #expect(pose.fpsScale == 1 && pose.motion.loops && pose.prop == nil)
                // It watches for as long as the pointer is there (within the limit), and flicks its tongue at it now and then, towards it.
                let mark = drive.history.count
                drive.run(12)
                let moves = drive.history[mark...].map { FrogMove($0.pose.motion) }
                #expect(Set(moves).isSubset(of: [.watch, .flick]) && moves.contains(.flick), "seed \(seed): \(moves)")
                for entry in drive.history[mark...] {
                    #expect(entry.pose.from == pose.from && entry.pose.to == pose.to && entry.pose.facing == pose.facing, "it stays where it is and turned to it")
                }
                drive.senses.pointer = nil
                drive.run(0.5)
                #expect(drive.brain.isWatching, "a moment's grace: it does not stop at the first look: \(drive.move)")
                drive.run(0.9 + 2.5)
                #expect(!drive.brain.isWatching, "and then it goes on: \(drive.move)")
                #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
                checked += 1
            }
        }
        #expect(checked >= 12, "\(checked)")
    }

    @Test func theTongueIsFlickedTowardsThePointerWhicheverSideItIsOnAndTurnsWithItAndItIsNeverOutOfThePicture() {
        var drive = FrDrive(seed: 3, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&drive, until: Self.sittingAbout)
        drive.senses.pointer = near(0.95)
        drive.run(0.25)
        let mark = drive.history.count
        drive.run(10)
        drive.senses.pointer = near(0.02)
        drive.run(10)
        let flicks = drive.history[mark...].filter { FrogMove($0.pose.motion) == .flick }
        #expect(flicks.count >= 4 && flicks.contains { $0.pose.facing == .right } && flicks.contains { $0.pose.facing == .left }, "\(flicks.count)")
        // The moment the pointer is on the other side the next picture of the watching has turned.
        let turned = drive.history[mark...].filter { $0.at > 10.5 + Double(mark) * 0 && FrogMove($0.pose.motion) == .watch }
        #expect(turned.contains { $0.pose.facing == .left })
        // (The tongue is in the picture: it is drawn on the board and never touches the edge of it.)
        for move in [FrogMove.flick, .padFlick, .snapOut, .snapIn] {
            for frame in FrogArt.animation(for: move).frames {
                for facing in [frame, frame.mirrored] {
                    for y in 0..<facing.height {
                        for x in 0..<facing.width where "Tt".contains(facing[x, y]) {
                            #expect((1...30).contains(x) && (1...22).contains(y), "\(move): tongue at \(x), \(y)")
                        }
                    }
                }
            }
        }
    }

    @Test func aPointerThatIsOnlyInSightDoesNothingToItAndOnlyNearMakesItWatch() {
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            drive.senses.pointer = PointerReading(share: 0.5, isNear: false, isInRange: true)
            drive.run(1200)
            #expect(!drive.moves.contains(.flick) && !drive.moves.contains(.padFlick), "seed \(seed)")
            drive.senses.pointer = near()
            drive.run(120)
            #expect(drive.moves.contains(.flick) || drive.moves.contains(.padFlick) || drive.moves.contains(.watch), "seed \(seed): it watches")
        }
    }

    @Test func aLegOfHopsIsNotBrokenOffInTheAirAndItWatchesWhenItHasLanded() {
        var checked = 0
        for seed in 1...20 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.move == .hop && $0.pose.from != $0.pose.to && $0.pose.duration >= 2.25 })
            drive.run(0.5)
            guard drive.move == .hop else { continue }
            let leg = drive.brain.pose
            drive.senses.pointer = near()
            let mark = drive.history.count
            drive.run(0.25)
            #expect(drive.brain.pose == leg, "seed \(seed): the leg goes on")
            drive.run(leg.end - drive.now + 0.5)
            let next = drive.history[mark...].first
            checked += 1
            #expect(next.map { FrogMove($0.pose.motion) } == .watch && (next?.pose.began ?? 0) >= leg.end - 1e-9, "seed \(seed): \(String(describing: next.map { FrogMove($0.pose.motion) }))")
            #expect(abs((next?.pose.from ?? 0) - leg.to) < 1e-9, "it watches where it landed")
            drive.senses.pointer = nil
            drive.run(30)
            #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        #expect(checked > 10, "\(checked)")
    }

    @Test func aMothThatIsComingOrHoveringIsCaughtBeforeItTurnsToThePointerAndNothingIsLeftOut() {
        var checked = 0
        for seed in 1...16 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 23))
            run(&drive, until: { $0.pose.prop.map { FrogProp($0.look) == .moth } ?? false })
            guard drive.brain.pose.prop != nil else { continue }
            let mark = drive.history.count
            drive.senses.pointer = near()
            drive.run(10)
            let moves = drive.history[mark...].map { FrogMove($0.pose.motion) }
            checked += 1
            #expect(moves.contains(.snapOut) && moves.contains(.snapIn), "seed \(seed): \(moves)")
            if let flick = moves.firstIndex(where: { $0 == .flick || $0 == .padFlick }), let reel = moves.firstIndex(of: .snapIn) {
                #expect(flick > reel, "the moth first: \(moves)")
            }
            drive.senses.pointer = nil
            drive.run(60)
            #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0, "\(frogPropProblems(drive.trail).prefix(3))")
        }
        #expect(checked > 8, "\(checked)")
    }

    @Test func onThePadItWatchesFromThePadAndFlicksFromItAndOnLeavingGoesOnWithTheSceneAndAsleepItDoesNotWatchAtAll() {
        var checked = 0
        for seed in 1...16 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: Self.onThePad)
            guard Self.onThePad(drive.brain) else { continue }
            let (place, scene) = (drive.brain.pose.from, drive.brain.sceneSerial)
            drive.senses.pointer = near()
            drive.run(0.25)
            #expect(drive.move == .padWatch && drive.brain.stance == .pad && drive.brain.pose.from == place, "seed \(seed): \(drive.move)")
            #expect(drive.brain.pose.prop.map { FrogProp($0.look) } == .padRippling, "the pad is under it")
            let mark = drive.history.count
            drive.run(12)
            let moves = drive.history[mark...].map { FrogMove($0.pose.motion) }
            #expect(Set(moves).isSubset(of: [.padWatch, .padFlick]) && moves.contains(.padFlick), "\(moves)")
            drive.senses.pointer = nil
            drive.run(120)
            let after = drive.history[mark...].map { FrogMove($0.pose.motion) }
            #expect(after.contains(.hopOff) && drive.brain.sceneSerial >= scene, "the scene goes on: it hops off the pad and the pad goes down: \(after.prefix(12))")
            #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
            checked += 1
        }
        #expect(checked > 8, "\(checked)")
        var asleep = FrDrive(seed: 2, senses: CatSenses(idleSeconds: 1000, hour: 23))
        asleep.run(300)
        #expect(asleep.move == .padSleep)
        asleep.senses.pointer = near()
        for _ in 0..<(4 * 40) {
            asleep.run(0.25)
            #expect(asleep.move == .padSleep, "it is asleep: the pointer is nothing to it, not even for a moment")
        }
    }

    @Test func aPointerThatComesWhileThePadIsComingUpIsWatchedWithThePadLyingThereAndThenItHopsOn() {
        var checked = 0
        for seed in 1...16 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.pose.prop.map { FrogProp($0.look) == .padAppearing } ?? false })
            guard drive.brain.pose.prop != nil else { continue }
            let mark = drive.history.count
            drive.senses.pointer = near()
            drive.run(0.25)
            #expect(drive.move == .watch && drive.brain.pose.prop.map { FrogProp($0.look) } == .padStill, "seed \(seed): \(drive.move) with \(String(describing: drive.brain.pose.prop?.look))")
            drive.run(3)
            drive.senses.pointer = nil
            drive.run(30)
            let moves = drive.history[mark...].map { FrogMove($0.pose.motion) }
            #expect(moves.contains(.hopOn) && moves.contains(.hopOff), "it goes on to the pad: \(moves.prefix(10))")
            #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0, "\(frogPropProblems(drive.trail).prefix(3))")
            checked += 1
        }
        #expect(checked > 8, "\(checked)")
    }

    @Test func itDoesNotWatchForEverAndNotAgainUntilThePointerHasBeenAwayAndNotMoreOftenThanTheCooldown() {
        var drive = FrDrive(seed: 2, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&drive, until: Self.sittingAbout)
        drive.senses.pointer = near()
        drive.run(1)
        #expect(drive.brain.isWatching, "\(drive.move)")
        drive.run(FrogBrain.watchLimit + 3)
        #expect(!drive.brain.isWatching, "it has watched as long as it will: \(drive.move)")
        #expect(drive.watchings == 1)
        drive.run(300)
        #expect(drive.watchings == 1, "a pointer that stays does not make it watch again")
        // The pointer goes away and comes back: it watches again, once the cooldown is over.
        drive.senses.pointer = nil
        drive.run(1)
        run(&drive, until: Self.free)
        drive.senses.pointer = near()
        drive.run(1)
        #expect(drive.watchings == 2 && drive.brain.isWatching, "it watches again")
        drive.senses.pointer = nil
        drive.run(FrogBrain.releaseDelay + 3)
        #expect(!drive.brain.isWatching)
        drive.senses.pointer = near()
        drive.run(2)
        #expect(drive.watchings == 2, "not again within the cooldown, which is \(drive.tuning.reactionCooldown) s")
        drive.senses.pointer = nil
        drive.run(drive.tuning.reactionCooldown + 6)
        run(&drive, until: Self.free)
        drive.senses.pointer = near()
        drive.run(1)
        #expect(drive.watchings == 3, "and when it is over it watches")
    }

    @Test func aPointerNeverBreaksIntoAHopOnOrOffAJumpTheTongueAtAMothOrASwallowAndAnythingItWatchesFromIsGoneOnFrom() {
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            // The pointer comes and goes: near for two seconds in every fourteen, which is more than the cooldown apart, so that it is heard of
            // again and again, in whatever the frog is in the middle of.
            for tick in 0..<(4 * 60 * 90) {
                drive.senses.pointer = (tick + Int(seed) * 7) % (4 * 14) < 4 * 2 ? near(Double(tick % 7) / 6) : nil
                drive.run(0.25)
            }
            let poses = drive.history.map(\.pose)
            for (before, after) in zip(poses, poses.dropFirst()) where FrogBrain.unbroken.contains(FrogMove(before.motion)) || (FrogMove(before.motion) == .hop && before.from != before.to) {
                #expect(after.began >= before.end - 1e-9, "seed \(seed): \(FrogMove(before.motion)) was cut short by \(FrogMove(after.motion))")
            }
            for entry in poses where Self.watching.contains(FrogMove(entry.motion)) { #expect(entry.from == entry.to) }
            #expect(drive.watchings > 60, "it watched again and again: \(drive.watchings) times")
            #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
    }

    // MARK: A stroke

    @Test func aStrokeMakesItHopInPlaceWithAHeartAndTheDayGoesOnFromWhereItWas() {
        var drive = FrDrive(seed: 3, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&drive, until: { $0.move == .sit && $0.pose.end - $0.pose.began > 2.5 && Self.free($0) && !$0.isWatching })
        #expect(drive.move == .sit)
        drive.run(0.5)
        let (place, left) = (drive.brain.pose.from, drive.brain.pose.end - drive.now)
        drive.pet()
        #expect(drive.move == .jump && drive.brain.pose.from == place && drive.brain.pose.to == place, "in place: \(drive.move)")
        #expect(FrogArt.animation(for: .jump).frames.contains { $0.cells.contains("H") })
        #expect(drive.brain.pose.duration == FrogMove.jump.passDuration)
        drive.run(FrogMove.jump.passDuration + 0.25)
        #expect(drive.move == .sit && drive.brain.pose.end - drive.now <= left, "it goes back to sitting for what was left of it: \(drive.move)")
        #expect(FrogSpecies.shared.meowsWhenPetted == false, "the mew is the cat's")
    }

    @Test func inTheMiddleOfALegOfHopsAStrokeHopsInPlaceWhereItIsAndItGoesOnWithTheScene() {
        var drive = FrDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 14))
        run(&drive, until: { $0.move == .hop && $0.pose.from != $0.pose.to })
        drive.run(0.75)
        let mid = drive.brain.pose.position(at: drive.now)
        let scene = drive.brain.sceneSerial
        drive.pet()
        #expect(drive.move == .jump && abs(drive.brain.pose.to - mid) < 1e-9 && drive.brain.pose.from == drive.brain.pose.to, "\(drive.move)")
        drive.run(FrogMove.jump.passDuration + 0.5)
        #expect(drive.brain.sceneSerial - scene <= 1, "the scene goes on, or the next one begins")
        #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
    }

    @Test func onThePadAStrokeIsAHopInPlaceOnThePadAndThePadStaysAndTheSceneGoesOn() throws {
        var checked = 0
        for seed in 1...12 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { Self.onThePad($0) && $0.pose.end - $0.pose.began > 3 })
            guard Self.onThePad(drive.brain) else { continue }
            drive.run(0.5)
            let place = drive.brain.pose.from
            let mark = drive.history.count
            drive.pet()
            checked += 1
            let jump = drive.brain.pose
            #expect(FrogMove(jump.motion) == .padJump && jump.from == place && jump.to == place, "\(drive.move)")
            let pad = try #require(jump.prop)
            #expect(FrogProp(pad.look) == .padRippling && pad.to == place && drive.brain.hasProps, "the pad is where it was")
            drive.run(FrogMove.padJump.passDuration + 0.25)
            #expect(drive.move == .padSit && drive.brain.stance == .pad, "back to sitting on it: \(drive.move)")
            drive.run(120)
            let moves = drive.history[mark...].map { FrogMove($0.pose.motion) }
            #expect(moves.contains(.hopOff) && frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
        #expect(checked > 8, "\(checked)")
    }

    @Test func aStrokeOnAWatchingFrogEndsTheWatchingAndItHopsAndGoesOnAndDoesNotWatchAgainAtOnce() {
        var checked = 0
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: Self.sittingAbout)
            guard Self.sittingAbout(drive.brain) else { continue }
            drive.senses.pointer = near()
            run(&drive, until: { $0.move == .watch })
            guard drive.move == .watch else { continue }
            let mark = drive.history.count
            drive.pet()
            drive.run(5)
            let moves = drive.history[mark...].map { FrogMove($0.pose.motion) }
            checked += 1
            #expect(moves.first == .jump, "\(moves)")
            #expect(!moves.contains(.flick) && !drive.brain.isWatching, "it was stroked and has had enough of that for the time being: \(moves)")
        }
        #expect(checked > 6, "\(checked)")
    }

    @Test func aStrokeFrightensOffAMothWhichFliesAwayFromWhereItIsAndTheHuntIsOver() throws {
        var checked = 0
        for seed in 1...16 as ClosedRange<UInt64> {
            for state in 0..<2 {
                var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 23))
                run(&drive, until: { $0.pose.prop.map { FrogProp($0.look) == .moth } ?? false })
                guard drive.brain.pose.prop != nil else { continue }
                // Once while it comes in, and once while it hovers.
                if state == 1 {
                    run(&drive, until: { $0.pose.prop.map { $0.from == $0.to } ?? false }, limit: 60)
                } else {
                    drive.run(0.5)
                }
                guard let moth = drive.brain.pose.prop, FrogProp(moth.look) == .moth, drive.now < drive.brain.pose.end else { continue }
                let at = moth.from + (moth.to - moth.from) * min(max((drive.now - drive.brain.pose.began) / drive.brain.pose.duration, 0), 1)
                let (mark, scene) = (drive.history.count, drive.brain.sceneSerial)
                drive.pet()
                checked += 1
                let jump = drive.brain.pose
                #expect(FrogMove(jump.motion) == .jump && jump.from == jump.to, "\(drive.move)")
                let leaving = try #require(jump.prop)
                #expect(FrogProp(leaving.look) == .moth && abs(leaving.from - at) < 1e-9, "it flies away from where it was: \(leaving.from) and \(at)")
                #expect(leaving.to < 0 || leaving.to > 1, "off the end of the lane: \(leaving.to)")
                #expect(!drive.brain.hasProps, "the brain has let it go")
                drive.run(FrogMove.jump.passDuration + 0.5)
                let moves = drive.history[mark...].map { FrogMove($0.pose.motion) }
                #expect(!moves.contains(.snapOut) && !moves.contains(.gulp), "the hunt is over: \(moves)")
                #expect(drive.brain.sceneSerial > scene && drive.brain.pose.prop.map { FrogProp($0.look).isMoth } != true, "the moth is gone")
                drive.run(60)
                #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0, "\(frogPropProblems(drive.trail).prefix(3))")
            }
        }
        #expect(checked > 12, "\(checked)")
    }

    @Test func aStrokeWhileItHopsOnOrOffJumpsSnapsTheTongueSwallowsOrLandsIsNotTaken() {
        var drive = FrDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 23))
        var skipped: Set<FrogMove> = []
        for tick in 0..<(4 * 60 * 120) {
            drive.run(0.25)
            if FrogBrain.unbroken.contains(drive.move), drive.now < drive.brain.pose.end {
                let before = drive.brain.pose
                let outcome = drive.brain.pet(now: drive.now)
                #expect(outcome == .unchanged && drive.brain.pose == before, "a stroke during \(drive.move)")
                skipped.insert(drive.move)
            } else if tick % 200 == 100 {
                drive.pet()
                if drive.move == .jump || drive.move == .padJump { skipped.insert(drive.move) }
            }
        }
        #expect(skipped.isSuperset(of: [.hopOn, .hopOff, .snapOut, .snapIn, .gulp, .jump]), "\(skipped)")
        #expect(drive.brain.strayProps == 0)
    }

    // MARK: Sleep

    @Test func awayForTheSleepTimeItGoesToThePadWhichComesUpForItAndSleepsThereWithItsEyesShutAndWakesAndHopsOffWhenTheUserIsBack() {
        for seed in 1...10 as ClosedRange<UInt64> {
            for state in 0..<4 {
                var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
                // The hardest times to go to sleep: with a moth hovering, in the middle of a leg of hops, on the pad, and about to sit down.
                switch state {
                case 0: run(&drive, until: { $0.pose.prop.map { FrogProp($0.look) == .moth } ?? false })
                case 1: run(&drive, until: { $0.move == .hop && $0.pose.from != $0.pose.to })
                case 2: run(&drive, until: Self.onThePad)
                default: run(&drive, until: Self.sittingAbout)
                }
                guard drive.brain.pose.prop != nil || state == 1 || state == 3 else { continue }
                drive.senses.idleSeconds = 1000
                let from = drive.history.count
                drive.run(200)
                let moves = drive.history[from...].map { FrogMove($0.pose.motion) }
                #expect(drive.move == .padSleep && drive.brain.stance == .pad, "seed \(seed), \(state): \(moves)")
                #expect(moves.contains(.padSleep) && (state == 2 || moves.contains(.hopOn)), "seed \(seed), \(state): \(moves)")
                if state == 0 { #expect(moves.firstIndex(of: .snapIn).map { $0 < (moves.firstIndex(of: .hopOn) ?? Int.max) } ?? false, "the moth is caught first: \(moves)") }
                #expect(drive.brain.pose.prop.map { FrogProp($0.look) } == .padRippling, "asleep on the pad")
                #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0, "\(frogPropProblems(drive.trail).prefix(3))")
                // The user is back: it wakes with its eyes open, hops off, and the pad goes down.
                drive.senses.idleSeconds = 0
                drive.run(0.25)
                #expect(drive.move == .padSit, "\(drive.move)")
                let woke = drive.history.count
                run(&drive, until: { $0.stance == .ground && !$0.hasProps }, limit: 12)
                let after = drive.history[woke...].map { FrogMove($0.pose.motion) }
                #expect(after.starts(with: [.hopOff, .sit]) && !drive.brain.isAsleep && drive.brain.stance == .ground && !drive.brain.hasProps, "\(after)")
                #expect(frogPropProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
            }
        }
    }

    @Test func awayWithNoRoomForAPadItSleepsOnTheGroundWithItsEyesShutAndGetsUpWhenTheUserIsBack() {
        // (A lane of eight pixels has no room for a pad; two zones joined cover a whole lane.)
        for (lane, travel) in [(LaneContext(), 8.0), (LaneContext(zones: [-0.01...0.61, 0.6...1.2]), 237)] {
            var drive = FrDrive(seed: 2, position: 0.3, senses: CatSenses(idleSeconds: 1000, hour: 23), travel: travel)
            drive.lane = lane
            drive.run(300)
            #expect(drive.move == .sleep && drive.brain.stance == .ground && drive.brain.pose.prop == nil && !drive.brain.hasProps, "\(drive.move)")
            #expect(!drive.moves.contains(.hopOn) && !drive.moves.contains(.padSleep))
            #expect(FrogArt.animation(for: .sleep).frames.allSatisfy { $0.cells.contains("Z") && $0.cells.contains("K") })
            drive.senses.idleSeconds = 0
            drive.run(0.25)
            #expect(drive.move == .sit, "\(drive.move)")
            drive.run(60)
            #expect(drive.brain.strayProps == 0 && frogPropProblems(drive.trail).isEmpty)
        }
    }

    @Test func aStrokeWakesASleeperOnThePadWhichJumpsAndHopsOffAndTheUserComingBackBeforeItSleepsStopsItGoing() {
        var drive = FrDrive(seed: 2, senses: CatSenses(idleSeconds: 1000, hour: 23))
        drive.run(300)
        #expect(drive.move == .padSleep)
        drive.senses.idleSeconds = 0
        let mark = drive.history.count
        drive.pet()
        run(&drive, until: { $0.stance == .ground && !$0.hasProps }, limit: 12)
        let moves = drive.history[mark...].map { FrogMove($0.pose.motion) }
        // (The user being back wakes it on the same tick, so the stroke finds it awake on the pad.)
        #expect(moves.contains(.hopOff) && !drive.brain.hasProps && drive.brain.stance == .ground, "\(moves)")
        // The user is back while it is on its way to the pad: it does not go on to sleep there.
        var checked = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var walking = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&walking, until: Self.sittingAbout)
            walking.senses.idleSeconds = 1000
            run(&walking, until: { $0.pose.prop != nil })
            guard walking.brain.pose.prop != nil, !walking.brain.isAsleep else { continue }
            checked += 1
            let begun = walking.history.count
            walking.senses.idleSeconds = 0
            walking.run(30)
            // (A doze on the pad is a scene of the day, which is not as long as the sleep that goes on until the user is back.)
            let slept = walking.history[begun...].filter { [.padSleep, .sleep].contains(FrogMove($0.pose.motion)) && $0.pose.duration == FrogBrain.sleepChunk }
            #expect(slept.isEmpty, "seed \(seed)")
            #expect(frogPropProblems(walking.trail).isEmpty && walking.brain.strayProps == 0)
        }
        #expect(checked > 4, "\(checked)")
    }

    // MARK: Coming back and the lane

    @Test func backOnTheNotchItSitsWhereItWasWithNothingOutAndThePadAndTheMothDoNotComeBack() {
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.hasProps })
            guard drive.brain.hasProps else { continue }
            drive.resume()
            let mark = drive.history.count - 1
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil && drive.move == .sit && drive.brain.stance == .ground)
            drive.run(3 * 3600)
            #expect(frogPropProblems(Array(drive.trail[mark...])).isEmpty && drive.brain.strayProps == 0)
        }
    }

    @Test func aLaneThatChangesUnderAFrogOnThePadTakesThePadAndMovesItOutOfTheWay() {
        var moved = 0
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            run(&drive, until: { $0.hasProps && $0.pose.from == $0.pose.to && $0.pose.prop != nil })
            guard drive.brain.hasProps, drive.brain.pose.from == drive.brain.pose.to else { continue }
            let place = drive.brain.pose.from
            drive.lane = LaneContext(crossing: [(place - 0.05)...(place + 0.05)])
            drive.brain.settle(lane: drive.lane)
            moved += 1
            #expect(!drive.brain.hasProps && drive.brain.pose.prop == nil, "no pad left in the crossing")
            #expect(!(place - 0.05 + 1e-9...place + 0.05 - 1e-9).contains(drive.brain.pose.to))
            #expect(drive.brain.stance == .ground)
            let mark = drive.history.count
            drive.run(2 * 3600)
            #expect(frogPropProblems(Array(drive.trail[mark...])).isEmpty && drive.brain.strayProps == 0, "seed \(seed): \(frogPropProblems(Array(drive.trail[mark...])).prefix(3))")
        }
        #expect(moved >= 8)
    }

    // MARK: Whatever interrupts

    @Test func throughAStormOfStrokesPointersSleepWakingLoadAndBurstsNothingIsLeftBehindAndItEndsWithNothingOut() {
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = FrDrive(seed: seed, senses: CatSenses(idleSeconds: 5, cpuLoad: 0.2, hour: 14))
            var generator = SplitMix64(seed: seed &* 7919)
            for second in 0..<(3 * 3600) {
                let roll = Double.random(in: 0..<1, using: &generator)
                if roll < 0.02 { drive.pet() }
                if roll > 0.98 { drive.senses.pointer = FrDrive.pointer(Double.random(in: 0...1, using: &generator), near: roll > 0.985) }
                if roll > 0.5, roll < 0.52 { drive.senses.pointer = nil }
                if second % 700 == 0 { drive.senses.idleSeconds = second % 1400 == 0 ? 5 : 400 }
                if second % 3600 == 1800 { drive.senses.hour = (drive.senses.hour + 9) % 24 }
                if second % 30 == 0 { drive.senses.cpuLoad = Double.random(in: 0...1, using: &generator) }
                drive.senses.busyBurst = (second / 50) % 9 == 0 && drive.senses.cpuLoad > 0.5
                drive.run(1)
            }
            #expect(frogPropProblems(drive.trail).isEmpty, "seed \(seed): \(frogPropProblems(drive.trail).prefix(3))")
            #expect(drive.brain.strayProps == 0)
            // The user goes away for good: it ends what it was doing and sleeps on the pad, and has nothing out but the pad.
            drive.senses.pointer = nil
            drive.senses.busyBurst = false
            drive.senses.idleSeconds = 10_000
            drive.run(300)
            #expect(drive.brain.isAsleep && drive.brain.pose.prop.map { FrogProp($0.look).isPad } != false, "seed \(seed): \(drive.move)")
            // And back for good: the pad goes down and nothing is out.
            drive.senses.idleSeconds = 0
            run(&drive, until: { $0.stance == .ground && !$0.hasProps }, limit: 20)
            #expect(!drive.brain.hasProps && drive.brain.stance == .ground && !drive.brain.isAsleep, "seed \(seed): \(drive.move)")
        }
    }
}
