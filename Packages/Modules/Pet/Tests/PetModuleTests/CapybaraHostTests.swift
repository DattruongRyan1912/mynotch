import Foundation
import Testing
@testable import PetModule

/// The capybara as the host of a joint scene: it gives its back while it sits or soaks, holds still for as long as it is asked to, and goes on
/// with its day, tub and all, when it is over.
@Suite struct CapybaraHostTests {
    func invite(_ guest: Pose = GuestDrive.capybara()) -> JointInvite { JointInvite(scene: .catOnCapybara, role: .host, partner: guest) }

    // MARK: When it will

    @Test func itGivesItsBackOnlyWhileItSitsOrSoaksAndHoldsStillWithTheTubInOrNothingOutAtAll() {
        var sat = 0, soaked = 0
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            for _ in 0..<(4 * 60 * 60 * 2) {
                drive.run(0.25)
                let ready = drive.brain.canJoin(invite(), now: drive.now)
                let move = drive.move
                if ready {
                    #expect([.sit, .blink, .soak, .soakOrange].contains(move), "ready as a \(move)")
                    #expect(drive.brain.pose.from == drive.brain.pose.to && drive.brain.pose.perch != nil)
                    if drive.brain.stance == .soaking { soaked += 1; #expect(drive.brain.pose.prop.map { CapybaraProp($0.look) } == .tubRippling) } else {
                        sat += 1
                        #expect(drive.brain.pose.prop == nil, "no tub, no orange, no peel by a capybara that is sat on")
                    }
                } else if [.doze, .sleep, .walk, .climbIn, .climbOut, .hold, .peel, .chew, .happy, .turn, .watch].contains(move) {
                    #expect(!ready)
                }
            }
        }
        #expect(sat > 1000 && soaked > 1000, "it is ready a good part of the time, in the tub or not: \(sat), \(soaked)")
    }

    @Test func itIsNotAskedToPlayAnythingButTheSceneItKnowsAsTheHost() {
        var drive = CapyDrive(seed: 2, senses: CatSenses(idleSeconds: 5, hour: 14))
        for _ in 0..<(4 * 600) {
            drive.run(0.25)
            if drive.brain.canJoin(invite(), now: drive.now) { break }
        }
        #expect(drive.brain.canJoin(invite(), now: drive.now))
        var guest = invite()
        guest.role = .guest
        #expect(!drive.brain.canJoin(guest, now: drive.now), "it is the one that is sat on")
        drive.brain.join(invite(), now: drive.now)
        #expect(drive.brain.jointScene == .catOnCapybara && !drive.brain.canJoin(invite(), now: drive.now), "one scene at a time")
    }

    // MARK: While it is played on

    @Test func whileItIsSatOnItHoldsTheSamePictureWhereItIsWhateverItSensesAndForAsLongAsItTakes() {
        for seed in 1...16 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            for _ in 0..<(4 * 3000) {
                drive.run(0.25)
                if drive.brain.canJoin(invite(), now: drive.now) { break }
            }
            guard drive.brain.canJoin(invite(), now: drive.now) else { continue }
            drive.brain.join(invite(), now: drive.now)
            let held = drive.brain.pose
            var round = 0
            for _ in 0..<(4 * 400) {
                round += 1
                drive.senses.cpuLoad = 1
                drive.senses.busyBurst = true
                drive.senses.audioPlaying = round % 3 == 0
                drive.senses.idleSeconds = round % 300 < 150 ? 10_000 : 5
                drive.senses.hour = round % 800 < 400 ? 23 : 14
                drive.senses.pointer = CapyDrive.pointer(0.5, near: round % 2 == 0)
                let before = drive.brain.pose
                let outcome = drive.brain.update(now: drive.now + Double(round) * 0.25, senses: drive.senses, tuning: drive.tuning, travel: 260, lane: drive.lane)
                #expect(outcome != .changed, "seed \(seed): the picture changed while it was sat on: \(before.motion) to \(drive.brain.pose.motion)")
                let now = drive.brain.pose
                #expect(now.motion == held.motion && now.from == held.from && now.to == held.to && now.facing == held.facing && now.prop == held.prop && now.perch == held.perch)
            }
            #expect(drive.brain.jointScene == .catOnCapybara)
        }
    }

    @Test func letGoItGoesOnWithItsDayAndATubIsNeverLeftBehindHoweverOftenItWasSatOnInIt() {
        var releasedInTheTub = 0, releasedSitting = 0
        for seed in 1...12 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            var generator = SplitMix64(seed: seed &* 31)
            for _ in 0..<(4 * 3600 * 3) {
                drive.run(0.25)
                // Now and then, when it is ready, a scene of 20 to 60 seconds.
                if drive.brain.jointScene == nil, drive.brain.canJoin(invite(), now: drive.now), Double.random(in: 0..<1, using: &generator) < 0.002 {
                    drive.brain.join(invite(), now: drive.now)
                    let held = drive.brain.stance
                    let length = Double.random(in: 20...60, using: &generator)
                    drive.run(length)
                    _ = drive.brain.leaveJoint(now: drive.now)
                    if held == .soaking { releasedInTheTub += 1 } else { releasedSitting += 1 }
                }
            }
            #expect(propProblems(drive.trail).isEmpty, "seed \(seed): \(propProblems(drive.trail).prefix(3))")
            #expect(drive.brain.strayProps == 0)
            #expect(drive.brain.jointScene == nil)
        }
        #expect(releasedInTheTub > 10 && releasedSitting > 10, "\(releasedInTheTub) and \(releasedSitting)")
    }

    @Test func releasedItSoaksOnOnlyForWhatWasLeftOfTheSoakAndThenHopsOutAndTheTubGoes() {
        var checked = 0
        for seed in 1...20 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            for _ in 0..<(4 * 3000) {
                drive.run(0.25)
                if drive.move == .soak, drive.brain.canJoin(invite(), now: drive.now) { break }
            }
            guard drive.move == .soak, drive.brain.canJoin(invite(), now: drive.now) else { continue }
            drive.brain.join(invite(), now: drive.now)
            drive.run(300)
            #expect(drive.move == .soak, "five minutes on, in the tub")
            _ = drive.brain.leaveJoint(now: drive.now)
            let from = drive.history.count
            drive.run(120)
            let after = drive.history[from...].map { CapybaraMove($0.pose.motion) }
            #expect(after.contains(.climbOut), "seed \(seed): \(after)")
            let tub = drive.history[from...].map { $0.pose.prop.map { CapybaraProp($0.look) } }
            #expect(tub.contains(.tubGoing), "seed \(seed): the tub went: \(tub)")
            #expect(propProblems(drive.trail).isEmpty, "seed \(seed): \(propProblems(drive.trail).prefix(3))")
            checked += 1
        }
        #expect(checked > 8)
    }

    @Test func aStrokeOnTheHostEndsItsPartInTheSceneAndItSquints() {
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, senses: CatSenses(idleSeconds: 5, hour: 14))
            for _ in 0..<(4 * 3000) {
                drive.run(0.25)
                if drive.brain.canJoin(invite(), now: drive.now) { break }
            }
            guard drive.brain.canJoin(invite(), now: drive.now) else { continue }
            drive.brain.join(invite(), now: drive.now)
            let soaking = drive.brain.stance == .soaking
            drive.run(5)
            drive.pet()
            #expect(drive.brain.jointScene == nil, "it is played with no more")
            #expect(drive.move == (soaking ? .soakHappy : .happy))
            drive.run(60)
            #expect(propProblems(drive.trail).isEmpty && drive.brain.strayProps == 0)
        }
    }

    @Test func aHostThatIsToldToStayThroughItsSettleStaysWhereItIsAndANewLaneDoesNotMoveIt() {
        var drive = CapyDrive(seed: 4, senses: CatSenses(idleSeconds: 5, hour: 14))
        for _ in 0..<(4 * 3000) {
            drive.run(0.25)
            if drive.brain.canJoin(invite(), now: drive.now) { break }
        }
        #expect(drive.brain.canJoin(invite(), now: drive.now))
        drive.brain.join(invite(), now: drive.now)
        let place = drive.brain.pose.to
        drive.brain.settle(lane: LaneContext(crossing: [(place - 0.1)...(place + 0.1)], zones: [(place - 0.05)...(place + 0.05)]))
        #expect(drive.brain.pose.to == place && drive.brain.pose.from == place, "the other is where it is because it is there")
    }
}
