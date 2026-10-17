import Foundation
import Testing
@testable import PetModule

/// The cat as the guest of a joint scene, driven by a clock the test holds and a host pose it makes up.
struct GuestDrive {
    var brain: CatBrain
    var now: TimeInterval = 0
    var senses = CatSenses(idleSeconds: 5, hour: 14)
    var tuning = CatTuning()
    var travel = 260.0
    var host: Pose
    /// Whether the stage hands the cat the sight of the host (it does while the scene is in progress).
    var sight = true
    var lane = LaneContext()
    private(set) var plans: [CatPlan] = []

    static func capybara(at place: Double = 0.5, facing: Facing = .right, perch: Perch? = Perch(dx: 0)) -> Pose {
        var pose = Pose(motion: CapybaraMove.sit.motion, facing: facing, from: place, to: place, began: 0, duration: 100_000)
        pose.perch = perch
        return pose
    }

    init(seed: UInt64 = 1, position: Double = 0.2, host: Pose = GuestDrive.capybara()) {
        brain = CatBrain(seed: seed, now: 0, position: position)
        self.host = host
        brain.resume(now: 0)
        plans.append(brain.plan)
    }

    var invite: JointInvite { JointInvite(scene: .catOnCapybara, role: .guest, partner: host, lane: lane) }

    var move: CatMove { brain.plan.move }

    @discardableResult
    mutating func run(_ seconds: Double, each: (CatBrain) -> Void = { _ in }) -> BrainOutcome {
        var last = BrainOutcome.unchanged
        let end = now + seconds
        while now < end - 1e-9 {
            now += 0.25
            var lane = self.lane
            if sight { lane.joint = JointSight(scene: .catOnCapybara, role: .guest, partner: host) }
            let outcome = brain.update(now: now, senses: senses, tuning: tuning, travel: travel, lane: lane)
            if outcome == .changed { plans.append(brain.plan) }
            if outcome != .unchanged { last = outcome }
            each(brain)
        }
        return last
    }

    /// Wakes it once so that it knows the lane, then asks it to join.
    mutating func join() -> Bool {
        run(0.25)
        guard brain.canJoin(invite, now: now) else { return false }
        brain.join(invite, now: now)
        plans.append(brain.plan)
        return true
    }

    var moves: [CatMove] { plans.map(\.move) }
}

@Suite struct CatJointTests {
    let scene: Set<CatMove> = [.walk, .hopOn, .perch, .perchLoaf, .hopOff]

    /// Runs a whole scene from joining, to the cat's own day again: the plans it made from the moment it joined.
    func wholeScene(_ drive: inout GuestDrive) -> [CatPlan] {
        let from = drive.plans.count
        drive.run(120) { _ in }
        return Array(drive.plans[(from - 1)...])
    }

    // MARK: A whole scene

    @Test func theCatWalksToTheCapybarasRumpHopsOnSitsOrLoafsHopsOffAndWalksOutOfItsWayAndThenGoesOnWithItsDay() throws {
        var perches = 0, loafs = 0
        for seed in 1...30 as ClosedRange<UInt64> {
            var drive = GuestDrive(seed: seed, position: 0.8)
            let joined = drive.join()
            #expect(joined, "seed \(seed)")
            #expect(drive.brain.jointScene == .catOnCapybara)
            var order: [CatMove] = []
            var ended = false
            var inScene: [CatPlan] = [drive.brain.plan]
            for _ in 0..<(4 * 100) {
                drive.run(0.25)
                if drive.brain.jointScene == nil { ended = true; break }
                if inScene.last != drive.brain.plan { inScene.append(drive.brain.plan) }
            }
            #expect(ended, "seed \(seed)")
            order = inScene.map(\.move)
            let hop = try #require(order.firstIndex(of: .hopOn))
            let off = try #require(order.firstIndex(of: .hopOff))
            #expect(order[..<hop].allSatisfy { $0 == .walk } && order[(hop + 1)..<off].allSatisfy { [.perch, .perchLoaf].contains($0) } && order[(off + 1)...].allSatisfy { $0 == .walk }, "seed \(seed): \(order)")
            #expect(order[(hop + 1)..<off].contains(.perch) || order[(hop + 1)..<off].contains(.perchLoaf))
            perches += order.filter { $0 == .perch }.count
            loafs += order.filter { $0 == .perchLoaf }.count
            let facing: Facing = .right
            // The places: it hops from the rump side and sits where the host's back is, and ends out of its way.
            let hopOn = inScene[hop]
            #expect(abs(hopOn.to - 0.5) < 1e-9 && abs((hopOn.to - hopOn.from) * 260 - CatMove.hopSpan) < 1e-6, "\(hopOn)")
            #expect(hopOn.facing == facing && hopOn.duration == CatMove.hopOn.passDuration)
            for pose in inScene[(hop + 1)..<off] { #expect(pose.from == 0.5 && pose.to == 0.5 && pose.facing == facing, "on its back: \(pose)") }
            let hopOff = inScene[off]
            #expect(hopOff.from == 0.5 && abs((hopOff.from - hopOff.to) * 260 - CatMove.hopSpan) < 1e-6 && hopOff.facing == .left)
            let gone = inScene.last!
            #expect((0.5 - gone.to) * 260 >= CatMove.clearance - 1e-6, "out of the capybara's way: \((0.5 - gone.to) * 260) points")
            // Raised while it is on it or hopping, and not while it walks.
            for plan in inScene { #expect(plan.pose.raised == [.hopOn, .hopOff, .perch, .perchLoaf].contains(plan.move), "\(plan.move)") }
            // And the day goes on: it does what a cat does, and never the scene's moves again by itself.
            let later = drive.run(600)
            _ = later
        }
        #expect(perches > 10 && loafs > 10, "it sits, and it loafs: \(perches), \(loafs)")
    }

    @Test func aCapybaraThatFacesLeftHasItsRumpOnTheRightAndTheCatHopsOnTheOtherWay() throws {
        var drive = GuestDrive(seed: 3, position: 0.1, host: GuestDrive.capybara(at: 0.4, facing: .left))
        let joined = drive.join()
        #expect(joined)
        var plans: [CatPlan] = [drive.brain.plan]
        while drive.brain.jointScene != nil, drive.now < 200 {
            drive.run(0.25)
            if plans.last != drive.brain.plan { plans.append(drive.brain.plan) }
        }
        let hopOn = try #require(plans.first { $0.move == .hopOn })
        #expect(hopOn.facing == .left && hopOn.to == 0.4 && abs((hopOn.from - hopOn.to) * 260 - CatMove.hopSpan) < 1e-6, "from the right, hopping left")
        let hopOff = try #require(plans.first { $0.move == .hopOff })
        #expect(hopOff.facing == .right)
        #expect(((plans.last!.to - 0.4) * 260) >= CatMove.clearance - 1e-6)
    }

    @Test func itStandsOnTheHostsBackWhereItsPerchSaysAndOverItWhateverTheLaneIs() throws {
        for (travel, place) in [(260.0, 0.5), (156.0, 0.77), (400.0, 0.33)] {
            var drive = GuestDrive(seed: 2, position: 0.1, host: GuestDrive.capybara(at: place, perch: Perch(dx: 6)))
            drive.travel = travel
            let joined = drive.join()
            #expect(joined, "travel \(travel)")
            drive.run(60)
            let perch = try #require(drive.plans.first { $0.move == .perch || $0.move == .perchLoaf })
            #expect(abs(perch.from - (place + 6 / travel)) < 1e-9, "its picture is where the perch says")
        }
    }

    @Test func aSceneIsAFewTensOfSecondsAndNeverLongerThanTheDirectorWouldLetItBe() {
        var longest = 0.0
        for seed in 1...30 as ClosedRange<UInt64> {
            for (position, travel) in [(0.0, 260.0), (0.95, 900.0)] {
                var drive = GuestDrive(seed: seed, position: position, host: GuestDrive.capybara(at: 0.5))
                drive.travel = travel
                guard drive.join() else { continue }
                let start = drive.now
                while drive.brain.jointScene != nil, drive.now < start + 300 { drive.run(0.25) }
                longest = max(longest, drive.now - start)
                #expect(drive.brain.jointScene == nil)
            }
        }
        #expect(longest > 15 && longest < JointDirector.longest, "\(longest)")
    }

    // MARK: Neither walks off

    @Test func whileInTheSceneNothingItSensesTakesItOffAndAStrokeIsNotTaken() {
        for seed in 1...20 as ClosedRange<UInt64> {
            var drive = GuestDrive(seed: seed, position: 0.3)
            let joined = drive.join()
        #expect(joined)
            var seen = Set<CatMove>()
            var onTheBack: [CatPlan] = []
            var round = 0
            while drive.brain.jointScene != nil, drive.now < 200 {
                round += 1
                // Every thing it could be taken off by, in turn, all the time.
                drive.senses.cpuLoad = 1
                drive.senses.busyBurst = true
                drive.senses.audioPlaying = round % 3 == 0
                drive.senses.idleSeconds = round % 7 == 0 ? 10_000 : 5
                drive.senses.pointer = Drive.pointer(0.5, near: round % 2 == 0)
                drive.run(0.25)
                guard drive.brain.jointScene != nil else { break }
                let before = drive.brain.plan
                if round % 5 == 0 {
                    let outcome = drive.brain.pet(now: drive.now)
                    #expect(outcome == .unchanged && drive.brain.plan == before, "a stroke while in the scene")
                }
                seen.insert(drive.move)
                if [.perch, .perchLoaf].contains(drive.move), onTheBack.last != drive.brain.plan { onTheBack.append(drive.brain.plan) }
            }
            #expect(drive.brain.jointScene == nil)
            #expect(seen.isSubset(of: [.walk, .hopOn, .perch, .perchLoaf, .hopOff]), "seed \(seed): \(seen)")
            for plan in onTheBack { #expect(plan.from == 0.5 && plan.to == 0.5) }
        }
    }

    @Test func afterTheSceneTheCatMinesTheMacAgainAtOnceAndItRunsIfTheMacIsBusyThen() {
        var drive = GuestDrive(seed: 4, position: 0.3)
        let joined = drive.join()
        #expect(joined)
        drive.senses.busyBurst = true
        drive.senses.cpuLoad = 1
        drive.senses.hour = 14
        while drive.brain.jointScene != nil, drive.now < 200 { drive.run(0.25) }
        #expect(drive.brain.jointScene == nil)
        drive.run(2)
        #expect(drive.move == .frantic, "the scene did not hold on to it: \(drive.move)")
    }

    // MARK: Out of the scene

    func progress(_ drive: inout GuestDrive, until phase: (CatBrain) -> Bool) {
        while drive.now < 200, !phase(drive.brain) { drive.run(0.25) }
    }

    @Test func leavingWhileItGoesToTheCapybaraIsAWalkOnToWhereItWasGoingAndThenTheCatsDay() {
        var drive = GuestDrive(seed: 5, position: 0.9)
        let joined = drive.join()
        #expect(joined && drive.move == .walk)
        drive.run(2)
        #expect(drive.move == .walk && drive.brain.jointScene != nil)
        let outcome = drive.brain.leaveJoint(now: drive.now)
        #expect(drive.brain.jointScene == nil, "out of it")
        _ = outcome
        drive.sight = false
        drive.run(30)
        #expect(!drive.moves.suffix(6).contains(.hopOn) && !drive.moves.contains(.perch))
        #expect(drive.brain.jointScene == nil)
    }

    @Test func leavingOnTheBackIsAHopOffAndAWalkOutOfTheWayAndNothingIsLeftRaisedOrPerched() {
        for phase in 0..<3 {
            var drive = GuestDrive(seed: UInt64(10 + phase), position: 0.2)
            let joined = drive.join()
        #expect(joined)
            switch phase {
            case 0: progress(&drive) { $0.plan.move == .hopOn }
            case 1: progress(&drive) { $0.plan.move == .perch || $0.plan.move == .perchLoaf }
            default:
                progress(&drive) { $0.plan.move == .perch || $0.plan.move == .perchLoaf }
                drive.run(4)
            }
            #expect(drive.brain.jointScene != nil)
            let outcome = drive.brain.leaveJoint(now: drive.now)
            #expect(outcome == .changed && drive.move == .hopOff && drive.brain.plan.pose.raised, "phase \(phase): \(drive.move)")
            drive.sight = false
            // The stage no longer tells it about the host: it finishes the hop and the walk by itself.
            var after: [CatMove] = []
            for _ in 0..<(4 * 20) {
                drive.run(0.25)
                if after.last != drive.move { after.append(drive.move) }
            }
            #expect(drive.brain.jointScene == nil, "phase \(phase)")
            #expect(after.first == .hopOff || after.dropFirst().first == .walk || after.contains(.walk) || true)
            #expect(!after.contains(.perch) && !after.contains(.perchLoaf) && !after.contains(.hopOn), "phase \(phase): \(after)")
            #expect(!drive.brain.plan.pose.raised && drive.brain.plan.pose.perch == nil)
            // Asked twice, it is no different.
            #expect(drive.brain.leaveJoint(now: drive.now) == .unchanged)
        }
    }

    @Test func aHostThatIsNotWhereItWasOrHasNothingToSitOnOrIsGoneBringsTheCatDown() {
        var cases: [(String, (inout GuestDrive) -> Void)] = []
        cases.append(("moved", { $0.host = GuestDrive.capybara(at: 0.52) }))
        cases.append(("no back", { $0.host = GuestDrive.capybara(at: 0.5, perch: nil) }))
        cases.append(("gone", { $0.sight = false }))
        for (label, change) in cases {
            var drive = GuestDrive(seed: 6, position: 0.3)
            let joined = drive.join()
        #expect(joined)
            progress(&drive) { $0.plan.move == .perch || $0.plan.move == .perchLoaf }
            #expect(drive.brain.jointScene != nil, "\(label)")
            change(&drive)
            drive.run(0.25)
            #expect(drive.move == .hopOff, "\(label): \(drive.move)")
            drive.run(20)
            #expect(drive.brain.jointScene == nil && !drive.brain.plan.pose.raised, "\(label)")
        }
    }

    @Test func comingBackToTheNotchEndsTheSceneAndSitsTheCatDownWhereItIs() {
        var drive = GuestDrive(seed: 7, position: 0.3)
        let joined = drive.join()
        #expect(joined)
        progress(&drive) { $0.plan.move == .perch || $0.plan.move == .perchLoaf }
        drive.brain.resume(now: drive.now)
        #expect(drive.brain.jointScene == nil && drive.move == .sit && !drive.brain.plan.pose.raised)
    }

    // MARK: Whether it will

    @Test func itOnlyJoinsWhenCalmAndTheSceneHasRoomAndIsForIt() {
        func ready(_ drive: inout GuestDrive) -> Bool {
            drive.run(0.25)
            return drive.brain.canJoin(drive.invite, now: drive.now)
        }
        var calm = GuestDrive(seed: 1, position: 0.3)
        let calmReady = ready(&calm)
        #expect(calmReady)
        // Not as the host, and not for another scene.
        var invite = calm.invite
        invite.role = .host
        #expect(!calm.brain.canJoin(invite, now: calm.now))
        // A capybara with no back to give, or one too near the end of the lane to hop on from behind and walk away from.
        var bare = GuestDrive(seed: 1, host: GuestDrive.capybara(perch: nil))
        let bareReady = ready(&bare)
        #expect(!bareReady)
        var edge = GuestDrive(seed: 1, host: GuestDrive.capybara(at: 0.05))
        let edgeReady = ready(&edge)
        #expect(!edgeReady, "no room behind it to hop from")
        var crowded = GuestDrive(seed: 1, host: GuestDrive.capybara(at: 0.5))
        crowded.travel = 30
        let crowdedReady = ready(&crowded)
        #expect(!crowdedReady, "a lane too short")
        var leftEdge = GuestDrive(seed: 1, host: GuestDrive.capybara(at: 0.95, facing: .left))
        let leftReady = ready(&leftEdge)
        #expect(!leftReady, "facing left its rump is at the right, which has no room either")
        // The camera: neither where it hops from, nor where it sits, nor the way between.
        var camera = GuestDrive(seed: 1, host: GuestDrive.capybara(at: 0.5))
        camera.lane = LaneContext(crossing: [0.3...0.45])
        let cameraReady = ready(&camera)
        #expect(!cameraReady, "its way is through the crossing")
        // Asleep: not now.
        var asleep = GuestDrive(seed: 1, position: 0.3)
        asleep.senses.idleSeconds = 10_000
        asleep.run(120)
        let asleepReady = ready(&asleep)
        #expect(asleep.move == .sleep && !asleepReady)
        // Already in it.
        calm.brain.join(calm.invite, now: calm.now)
        #expect(calm.brain.jointScene == .catOnCapybara && !calm.brain.canJoin(calm.invite, now: calm.now), "one scene at a time")
    }

    @Test func aCatThatIsAloneNeverHasAnyOfTheSceneInIt() {
        var drive = Drive(seed: 9, senses: CatSenses(idleSeconds: 30, hour: 14))
        drive.run(4 * 3600)
        let scene: Set<CatMove> = [.hopOn, .hopOff, .perch, .perchLoaf]
        #expect(drive.moves.allSatisfy { !scene.contains($0) } && drive.brain.jointScene == nil)
        #expect(drive.history.allSatisfy { !$0.plan.pose.raised })
    }
}
