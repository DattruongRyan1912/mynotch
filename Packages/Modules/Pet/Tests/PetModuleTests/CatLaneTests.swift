import AppKit
import Testing
@testable import PetModule

/// Several characters in one lane: what they owe each other (`LaneRules`), what a brain does with it, and what a stage of three does through
/// hours of made-up time. Nothing here waits for a real clock: the stage is woken by a scheduler the test advances.
@Suite struct LaneRulesTests {
    func pose(from: Double, to: Double, began: TimeInterval = 0, duration: TimeInterval = 4) -> Pose {
        Pose(motion: CatMove.walk.motion, facing: .right, from: from, to: to, began: began, duration: duration)
    }

    let crossing: [ClosedRange<Double>] = [0.4...0.6]

    @Test func eachOtherCharactersStopIsAZoneToTheOneAskingAndItsOwnIsNot() {
        let poses: [Pose?] = [pose(from: 0.1, to: 0.1), pose(from: 0.2, to: 0.3), nil, pose(from: 0.9, to: 0.8)]
        let lane = LaneRules.context(for: 1, poses: poses, crossing: [], separation: 0.1, now: 1)
        #expect(lane.zones.count == 2, "where the others will be: the ones with a pose, and not the one asking")
        guard lane.zones.count == 2 else { return }
        #expect(abs(lane.zones[0].lowerBound - 0.0) < 1e-9 && abs(lane.zones[0].upperBound - 0.2) < 1e-9)
        #expect(abs(lane.zones[1].lowerBound - 0.7) < 1e-9 && abs(lane.zones[1].upperBound - 0.9) < 1e-9)
        #expect(lane.crossing.isEmpty && lane.closed.isEmpty)
        let alone = LaneRules.context(for: 0, poses: [pose(from: 0.1, to: 0.1)], crossing: crossing, separation: 0.1, now: 1)
        #expect(alone == LaneContext(crossing: crossing), "a character alone has the crossing and nothing else")
        #expect(LaneRules.context(for: 0, poses: poses, crossing: [], separation: 0, now: 1).zones.isEmpty, "no lane to speak of, no zones")
    }

    @Test func theCrossingIsClosedToAllButTheOneInItFromTheMomentItsWalkBeginsToTheMomentItIsOver() {
        let walker = pose(from: 0.1, to: 0.9, began: 10, duration: 6)
        let still = pose(from: 0.2, to: 0.2)
        let poses: [Pose?] = [walker, still]
        for now in [10.0, 12.0, 15.9] {
            #expect(LaneRules.context(for: 1, poses: poses, crossing: crossing, separation: 0.1, now: now).closed == crossing, "at \(now)")
            #expect(LaneRules.context(for: 0, poses: poses, crossing: crossing, separation: 0.1, now: now).closed.isEmpty, "not for the one in it")
        }
        #expect(LaneRules.context(for: 1, poses: poses, crossing: crossing, separation: 0.1, now: 16).closed.isEmpty, "over")
    }

    @Test func aWalkThatDoesNotGoIntoTheCrossingDoesNotCloseIt() {
        let before = pose(from: 0.05, to: 0.4, began: 0, duration: 6)
        let after = pose(from: 0.95, to: 0.6, began: 0, duration: 6)
        let inside = pose(from: 0.5, to: 0.5)
        for other in [before, after, inside] {
            let lane = LaneRules.context(for: 1, poses: [other, nil], crossing: crossing, separation: 0.1, now: 1)
            #expect(lane.closed.isEmpty, "\(other.from) to \(other.to)")
        }
        #expect(LaneRules.isCrossing(pose(from: 0.3, to: 0.41), through: crossing, at: 0), "it takes only a little of it")
        #expect(!LaneRules.isCrossing(pose(from: 0.3, to: 0.7), through: [], at: 0), "no camera, no crossing")
    }

    @Test func charactersStartSpreadAcrossTheLaneAndOneAloneStartsWhereItAlwaysDid() {
        #expect(LaneRules.startingPlace(0, of: 1) == 0.5)
        #expect([0, 1].map { LaneRules.startingPlace($0, of: 2) } == [1.0 / 3, 2.0 / 3])
        #expect([0, 1, 2].map { LaneRules.startingPlace($0, of: 3) } == [0.25, 0.5, 0.75])
    }
}

/// A cat's plan and the pose a view and the stage see of it are the same thing: what one says, the other says.
@Suite struct PoseTests {
    @Test func aPoseSaysWhereTheCatIsAndWhenItsPlanIsOverAndLooksLikeWhatItsPlanLooksLike() {
        let moves: [CatMove] = [.sit, .walk, .sleep, .peek, .pounce, .frantic, .purr]
        var checked = 0
        for move in moves {
            for (from, to) in [(0.2, 0.2), (0.2, 0.7)] {
                for delay in [0.0, 0.4] {
                    let plan = CatPlan(move: move, facing: .left, from: from, to: to, began: 3, duration: 4, fpsScale: 1.2, delay: delay)
                    let pose = plan.pose
                    #expect(pose.motion == move.motion && pose.end == plan.end && pose.facing == .left)
                    for time in [3.0, 4.0, 5.5, 7.0, 9.0] { #expect(pose.position(at: time) == plan.position(at: time), "\(move) at \(time)") }
                    var other = plan
                    other.duration = 6
                    var turned = plan
                    turned.facing = .right
                    var carrying = plan
                    carrying.prop = CatProp(kind: .yarn, from: 0.3, to: 0.5)
                    for variant in [plan, other, turned, carrying] {
                        #expect(plan.pose.looksLike(variant.pose) == plan.looksLike(variant), "\(move)")
                        checked += 1
                    }
                }
            }
        }
        #expect(checked == 7 * 2 * 2 * 4)
        #expect(CatMove(CatMove.purr.motion) == .purr && CatMove(Motion(key: 999, fps: 1, loops: true)) == .sit, "a number that is none of the cat's is a sit")
        #expect(CatMove.allCases.allSatisfy { CatMove($0.motion) == $0 }, "every move has a number of its own")
        #expect(Set(CatMove.allCases.map { $0.motion.key }).count == CatMove.allCases.count)
        #expect(PropKind(PropKind.moth.look) == .moth && PropKind(PropKind.yarn.look) == .yarn)
    }
}

/// What every brain does to keep to a lane it shares.
@Suite struct LaneKeeperTests {
    let crossing = 0.40...0.60

    @Test func withNothingInTheLaneEveryAnswerIsTheOneAskedFor() {
        let keeper = LaneKeeper()
        for share in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(keeper.settled(share) == share && keeper.destination(share, from: 0.5) == share && keeper.endOfLane(share, from: 0.5) == share)
        }
        #expect(keeper.reach(from: 0.5) == 0...1 && !keeper.isInCrossing(0.5))
    }

    @Test func aPlaceInTheCrossingIsMovedToTheNearerEndAndTheEndsAreStillPlacesToStand() {
        let keeper = LaneKeeper(LaneContext(crossing: [crossing]))
        #expect(keeper.settled(0.44) == 0.40 && keeper.settled(0.56) == 0.60 && keeper.settled(0.5) == 0.60, "the upper when they are as near as each other")
        #expect(keeper.settled(0.40) == 0.40 && keeper.settled(0.60) == 0.60 && keeper.settled(0.1) == 0.1)
        #expect(keeper.isInCrossing(0.5) && !keeper.isInCrossing(0.4) && !keeper.isInCrossing(0.7))
        #expect(keeper.endOfLane(1.0, from: 0.1) == 1.0, "a cat alone goes to the end of the lane, camera or none")
    }

    @Test func aClosedStretchHoldsAWalkAtItsNearEdgeFromEitherSideAndLetsOneThatIsInItOutTheShortWay() {
        let keeper = LaneKeeper(LaneContext(crossing: [crossing], closed: [crossing]))
        #expect(keeper.reach(from: 0.1) == 0...0.40 && keeper.reach(from: 0.9) == 0.60...1)
        #expect(keeper.destination(0.95, from: 0.1) == 0.40 && keeper.destination(0.02, from: 0.9) == 0.60)
        #expect(keeper.destination(0.2, from: 0.1) == 0.2)
        #expect(keeper.reach(from: 0.45) == 0...0.40 && keeper.reach(from: 0.55) == 0.60...1, "out, by the nearer side")
        #expect(keeper.endOfLane(1.0, from: 0.1) == 0.40, "even to the end, once something is closed")
    }

    @Test func aPlaceWhereAnotherStandsAndTheCrossingAreOneStretchWhenTheyOverlapAndTheNearestFreePlaceIsInTheLane() {
        let keeper = LaneKeeper(LaneContext(crossing: [crossing], zones: [0.55...0.75]))
        #expect(keeper.settled(0.58) == 0.75 && keeper.settled(0.45) == 0.40)
        // At the end of the lane there is nowhere below, so the one end there is.
        let edge = LaneKeeper(LaneContext(zones: [-0.2...0.2]))
        #expect(edge.settled(0.05) == 0.2)
        #expect(LaneKeeper(LaneContext(zones: [-0.2...1.2])).settled(0.5) == 0.5, "nowhere to go: it stays")
    }
}

/// What one brain does with stretches it may not stop in, and stretches it may not go into.
@Suite struct CatBrainSharedLaneTests {
    /// A brain driven for `minutes`, told the lane it plays in, checking every plan it makes: the stretch kept clear of stops, and the
    /// ones it is not let into.
    func run(
        seed: UInt64, minutes: Int, from start: Double = 0.5, lane: LaneContext, senses: CatSenses = CatSenses(idleSeconds: 60, hour: 14),
        tuning: CatTuning = CatTuning()
    ) -> [CatPlan] {
        var brain = CatBrain(seed: seed, now: 0, position: start)
        brain.settle(lane: lane)
        var plans: [CatPlan] = []
        var now = 0.0
        for _ in 0..<(minutes * 60 * 4) {
            now += 0.25
            if brain.update(now: now, senses: senses, tuning: tuning, travel: 260, lane: lane) == .changed { plans.append(brain.plan) }
        }
        return plans
    }

    @Test func aCatNeverStopsInAZoneAndStillWalksThroughIt() {
        let zone = 0.40...0.60
        var through = 0
        var stops = 0
        for seed in 1...12 as ClosedRange<UInt64> {
            for start in [0.1, 0.9] {
                let plans = run(seed: seed, minutes: 20, from: start, lane: LaneContext(zones: [zone]))
                for plan in plans {
                    let ends = plan.to
                    #expect(!(ends > zone.lowerBound && ends < zone.upperBound), "seed \(seed): a \(plan.move) ends at \(ends)")
                    if plan.from == plan.to { stops += 1 }
                    if (plan.from < zone.lowerBound && plan.to > zone.upperBound) || (plan.from > zone.upperBound && plan.to < zone.lowerBound) { through += 1 }
                }
            }
        }
        #expect(stops > 1000 && through > 20, "it did things, and went through the zone: \(stops) stops, \(through) walks through")
    }

    @Test func aCatHeldOutOfAStretchIsNeverSeenInItOrBeyondItThroughHoursOfEveryKindOfDay() {
        let closed = 0.40...0.60
        let kinds: [(String, CatSenses)] = [
            ("a day at the desk", CatSenses(idleSeconds: 60, hour: 14)),
            ("a night", CatSenses(idleSeconds: 60, hour: 23)),
            ("music", CatSenses(idleSeconds: 5, audioPlaying: true, hour: 14)),
            ("a busy Mac", CatSenses(idleSeconds: 5, cpuLoad: 0.95, busyBurst: true, hour: 14)),
            ("a pointer about", CatSenses(idleSeconds: 5, pointer: PointerReading(share: 0.5, isNear: true, isInRange: true), hour: 14)),
        ]
        var walks = 0
        for (name, senses) in kinds {
            for seed in 1...8 as ClosedRange<UInt64> {
                for start in [0.1, 0.9] {
                    let side: (Double) -> Bool = start < 0.5 ? { $0 <= closed.lowerBound + 1e-9 } : { $0 >= closed.upperBound - 1e-9 }
                    let plans = run(seed: seed, minutes: 10, from: start, lane: LaneContext(crossing: [closed], closed: [closed]), senses: senses)
                    for plan in plans {
                        #expect(side(plan.from) && side(plan.to), "\(name), seed \(seed): a \(plan.move) from \(plan.from) to \(plan.to)")
                        if plan.from != plan.to { walks += 1 }
                    }
                }
            }
        }
        #expect(walks > 500, "and it walked about on its side: \(walks)")
    }

    @Test func aBurstSendsACatToTheEdgeOfTheClosedStretchAndNotThroughIt() {
        let closed = 0.40...0.60
        var brain = CatBrain(seed: 1, now: 0, position: 0.1)
        let lane = LaneContext(crossing: [closed], closed: [closed])
        brain.settle(lane: lane)
        var now = 0.0
        var farthest = 0.0
        for _ in 0..<(4 * 60) {
            now += 0.25
            _ = brain.update(now: now, senses: CatSenses(cpuLoad: 1, busyBurst: true), tuning: CatTuning(), travel: 260, lane: lane)
            farthest = max(farthest, brain.plan.to, brain.plan.position(at: now))
        }
        #expect(farthest <= closed.lowerBound + 1e-9 && farthest > 0.3, "it ran as far as it was let: \(farthest)")
    }

    @Test func aStretchThatIsClosedOnlyWhenOthersAreInItLetsTheCatThroughOnceItIsOpen() {
        var brain = CatBrain(seed: 4, now: 0, position: 0.1)
        let shut = LaneContext(crossing: [0.4...0.6], closed: [0.4...0.6])
        let open = LaneContext(crossing: [0.4...0.6])
        var now = 0.0
        var crossed = false
        for step in 0..<(4 * 60 * 20) {
            now += 0.25
            let lane = step < 4 * 60 * 5 ? shut : open
            _ = brain.update(now: now, senses: CatSenses(idleSeconds: 60, hour: 14), tuning: CatTuning(), travel: 260, lane: lane)
            if step < 4 * 60 * 5 { #expect(brain.plan.to <= 0.4 + 1e-9 && brain.plan.position(at: now) <= 0.4 + 1e-9, "shut at \(now)") }
            crossed = crossed || brain.plan.to > 0.6
        }
        #expect(crossed, "and once it is open the cat goes through")
    }

    @Test func aCatThatStandsInAZoneWhenItIsTakenIsPutAtTheNearerEndOfIt() {
        var brain = CatBrain(seed: 1, now: 0, position: 0.45)
        brain.settle(lane: LaneContext(zones: [0.40...0.60]))
        #expect(brain.plan.from == 0.40 && brain.plan.to == 0.40)
        var other = CatBrain(seed: 1, now: 0, position: 0.55)
        other.settle(lane: LaneContext(zones: [0.40...0.60]))
        #expect(other.plan.to == 0.60)
        var free = CatBrain(seed: 1, now: 0, position: 0.9)
        free.settle(lane: LaneContext(zones: [0.40...0.60]))
        #expect(free.plan.to == 0.9)
    }

    @Test func zonesThatOverlapAreOneAndTheCatIsPutOutsideAllOfThem() {
        var brain = CatBrain(seed: 1, now: 0, position: 0.5)
        brain.settle(lane: LaneContext(zones: [0.30...0.50, 0.45...0.65]))
        #expect(brain.plan.to == 0.30 || brain.plan.to == 0.65, "not at 0.50, which is the end of the first and the inside of the second: \(brain.plan.to)")
        // And one with nowhere to go (zones that cover the whole lane) stays where it is.
        var boxed = CatBrain(seed: 1, now: 0, position: 0.5)
        boxed.settle(lane: LaneContext(zones: [-0.1...1.1]))
        #expect(boxed.plan.to == 0.5)
    }

    @Test func aCatAloneWithNoZonesAndNothingClosedIsTheCatItWas() {
        // The same seed through the same day with the lane given as the crossing alone and as a full context: one and the same cat.
        for seed in 1...6 as ClosedRange<UInt64> {
            var old = CatBrain(seed: seed, now: 0)
            var new = CatBrain(seed: seed, now: 0)
            let gaps: [ClosedRange<Double>] = [0.35...0.55]
            old.settle(gaps: gaps)
            new.settle(lane: LaneContext(crossing: gaps))
            var now = 0.0
            for step in 0..<(4 * 60 * 30) {
                now += 0.25
                let senses = CatSenses(idleSeconds: step % 3000 < 1500 ? 60 : 5, audioPlaying: step % 4000 > 3800, hour: 14)
                let one = old.update(now: now, senses: senses, tuning: CatTuning(), travel: 260, gaps: gaps)
                let two = new.update(now: now, senses: senses, tuning: CatTuning(), travel: 260, lane: LaneContext(crossing: gaps))
                #expect(one == two && old.plan == new.plan, "seed \(seed) at \(now)")
            }
        }
    }
}

/// Three characters on a stage, woken by a scheduler that the test advances.
@Suite(.serialized) @MainActor struct CatLaneTests {
    struct Report {
        var overlaps: [String] = []
        var crossingTogether: [String] = []
        var crossings = 0
        var moving = 0
        var together = 0
        var ticks = 0
    }

    /// Everything the characters owe each other, looked at after every waking, for `minutes` of made-up time.
    func live(
        _ rig: BodyRig, count: Int = 3, minutes: Int, label: String, each: (Int) -> Void = { _ in }
    ) throws -> Report {
        rig.show()
        let stage = rig.stage
        stage.characters = Array(repeating: .cat, count: count)
        let field = try #require(rig.hosts.first?.field)
        let crossing = stage.crossingShares()
        let travel = Double(field.lane.travel)
        let width = Double(field.spriteWidth)
        var report = Report()
        for tick in 0..<(4 * 60 * minutes) {
            each(tick)
            rig.advance(0.25)
            let now = rig.scheduler.seconds
            let poses = stage.poses
            report.ticks += 1
            #expect(poses.count == count)
            var walking = 0
            var inCrossing = 0
            for (index, pose) in poses.enumerated() {
                if LaneRules.isCrossing(pose, through: crossing, at: now) { inCrossing += 1 }
                if pose.from != pose.to, now < pose.end { walking += 1 }
                for other in poses.indices where other > index {
                    let (one, two) = (poses[index], poses[other])
                    func rests(_ pose: Pose) -> Bool { pose.from == pose.to || now >= pose.end }
                    guard rests(one), rests(two) else { continue }
                    let apart = abs(one.position(at: now) - two.position(at: now)) * travel
                    if apart < width { report.overlaps.append("\(label) at \(now): \(index) and \(other) \(apart) points apart (\(width) is a picture)") }
                }
            }
            if inCrossing > 1 { report.crossingTogether.append("\(label) at \(now): \(inCrossing) in the crossing") }
            if inCrossing == 1 { report.crossings += 1 }
            if walking > 0 { report.moving += 1 }
            if walking > 1 { report.together += 1 }
        }
        return report
    }

    @Test func threeCatsOnTheMacsWingsNeverStopOnEachOtherAndOneAtATimeGoesThroughThePortal() throws {
        var overlaps: [String] = []
        var together: [String] = []
        var crossings = 0
        var bothMoving = 0
        for seed: UInt64 in [3, 4, 8, 21, 55] {
            let rig = BodyRig(geometry: Screens.hardware, seed: seed)
            let report = try live(rig, minutes: 20, label: "seed \(seed)")
            overlaps += report.overlaps
            together += report.crossingTogether
            crossings += report.crossings
            bothMoving += report.together
            rig.hide()
        }
        #expect(overlaps.isEmpty, "\(overlaps.prefix(5))")
        #expect(together.isEmpty, "\(together.prefix(5))")
        #expect(crossings > 100, "they did go through the portal: \(crossings) wakings with one in it")
        #expect(bothMoving > 500, "they walked about together, past each other: \(bothMoving)")
    }

    @Test func threeCatsInThePillAreNeverOnEachOtherEitherAndTwoCatsAreNoDifferent() throws {
        var overlaps: [String] = []
        var walkingTogether = 0
        for (geometry, count) in [(Screens.pill, 3), (Screens.pill, 2), (Screens.tallPill, 3)] {
            for seed: UInt64 in [3, 8, 21] {
                let rig = BodyRig(geometry: geometry, seed: seed)
                let report = try live(rig, count: count, minutes: 20, label: "\(count) in a pill, seed \(seed)")
                overlaps += report.overlaps
                walkingTogether += report.together
                rig.hide()
            }
        }
        #expect(overlaps.isEmpty, "\(overlaps.prefix(5))")
        #expect(walkingTogether > 300, "\(walkingTogether)")
    }

    @Test func twoInTheNarrowWingsOfASmallRowToo() throws {
        // A row of 360 has a wing of 70: room to stand for one cat each side of the camera, and no more.
        var overlaps: [String] = []
        var together: [String] = []
        var moving = 0
        for seed: UInt64 in [3, 8, 21] {
            let rig = BodyRig(geometry: Screens.hardware, seed: seed, width: 360)
            let report = try live(rig, count: 2, minutes: 15, label: "seed \(seed), 360 wide")
            overlaps += report.overlaps
            together += report.crossingTogether
            moving += report.moving
            rig.hide()
        }
        #expect(overlaps.isEmpty, "\(overlaps.prefix(5))")
        #expect(together.isEmpty, "\(together.prefix(5))")
        #expect(moving > 500, "they walk about on their sides: \(moving)")
    }

    @Test func threeInARowThatHasRoomForTwoStayWhereTheyAreWhenThereIsNoRoomAndNeverLoopOrLeaveTheLane() throws {
        for seed: UInt64 in [3, 8] {
            let rig = BodyRig(geometry: Screens.hardware, seed: seed, width: 360)
            rig.show()
            rig.stage.characters = [.cat, .cat, .cat]
            for _ in 0..<(4 * 60 * 10) {
                rig.advance(0.25)
                for pose in rig.stage.poses { #expect((0.0...1.0).contains(pose.from) && (0.0...1.0).contains(pose.to), "seed \(seed): \(pose)") }
            }
            #expect(rig.stage.poses.count == 3 && rig.stage.isTicking)
            rig.hide()
        }
    }

    @Test func throughABusyMinuteAndAPointerAndAPettingAfterQuietEnoughToKnowWhatIsUsual() throws {
        var overlaps: [String] = []
        var together: [String] = []
        for seed: UInt64 in [3, 8] {
            let rig = BodyRig(geometry: Screens.hardware, seed: seed)
            let frame = { rig.hosts.first?.screenFrame ?? .zero }
            // A quiet Mac for long enough to know what is usual, then a burst, then quiet, with the pointer by the wing for a while.
            let report = try live(rig, minutes: 12, label: "busy, seed \(seed)") { tick in
                rig.cpu.value = tick >= 4 * 60 * 3 && tick < 4 * 60 * 4 + 40 ? 0.97 : 0.05
                rig.idle.seconds = tick % 3000 < 1500 ? 30 : 4
                if tick == 4 * 60 * 8 { rig.pointer.point = CGPoint(x: frame().midX, y: frame().midY) }
                if tick == 4 * 60 * 8 + 80 { rig.pointer.point = CGPoint(x: 9000, y: 9000) }
                if tick == 4 * 60 * 9 { rig.stage.catWasClicked(character: 1) }
            }
            overlaps += report.overlaps
            together += report.crossingTogether
            rig.hide()
        }
        #expect(overlaps.isEmpty, "\(overlaps.prefix(5))")
        #expect(together.isEmpty, "\(together.prefix(5))")
    }

    @Test func aBurstOfTheMacBeingBusySendsEveryCharacterRunningAndTheyStillDoNotStopOnEachOther() throws {
        let rig = BodyRig(geometry: Screens.pill, seed: 5)
        var frantic = Set<Int>()
        let report = try live(rig, minutes: 8, label: "burst") { tick in
            rig.cpu.value = tick >= 4 * 60 * 3 && tick < 4 * 60 * 4 ? 0.98 : 0.05
            for (index, pose) in rig.stage.poses.enumerated() where pose.motion == CatMove.frantic.motion { frantic.insert(index) }
        }
        #expect(frantic == [0, 1, 2], "every one of them ran: \(frantic)")
        #expect(report.overlaps.isEmpty, "\(report.overlaps.prefix(5))")
    }

    @Test func eachCharacterHasABrainOfItsOwnAndTheFirstIsTheOneAStageAloneHas() throws {
        let rig = BodyRig(geometry: Screens.pill, seed: 9)
        rig.show()
        let stage = rig.stage
        stage.characters = [.cat, .cat, .cat]
        var days: [[Int]] = [[], [], []]
        for _ in 0..<(4 * 120) {
            rig.advance(0.25)
            for (index, pose) in stage.poses.enumerated() where days[index].last != pose.motion.key { days[index].append(pose.motion.key) }
        }
        let places = stage.poses.map(\.to)
        #expect(Set(places).count == 3, "three of them, in three places: \(places)")
        #expect(Set(days).count == 3, "each has a day of its own: a brain with a stream of its own")
        // Alone, the same stage has the cat it always had: the first of the three has the seed the stage was given.
        let alone = BodyRig(geometry: Screens.pill, seed: 9)
        alone.show()
        #expect(alone.stage.characters == [.cat] && alone.stage.plan?.from == 0.5)
    }

    @Test func aCharacterThatStaysKeepsWhatItWasDoingWhenAnotherComesOrGoes() throws {
        let rig = BodyRig(geometry: Screens.pill, seed: 9)
        rig.show()
        let stage = rig.stage
        rig.advance(37)
        let before = try #require(stage.plan)
        stage.characters = [.cat, .cat]
        #expect(stage.poses.count == 2 && stage.plan == before, "the first goes on as it was")
        rig.advance(0.25)
        stage.characters = [.cat]
        #expect(stage.poses.count == 1 && stage.plan?.began == stage.poses[0].began)
        #expect(rig.hosts.allSatisfy { $0.characters.count == 1 })
    }

    @Test func aStageIsNeverGivenMoreThanThreeCharacters() {
        let rig = BodyRig(geometry: Screens.pill)
        rig.show()
        rig.stage.characters = [.cat, .cat, .cat, .cat, .cat]
        #expect(rig.stage.characters.count == CharacterKind.maxPerScreen && rig.stage.poses.count == 3)
        #expect(rig.hosts.allSatisfy { $0.characters.count == 3 })
    }

    @Test func aStageWithNoCharactersAtAllStopsTickingAndShowsNothing() {
        let rig = BodyRig(geometry: Screens.pill)
        rig.show()
        rig.advance(2)
        #expect(rig.stage.isTicking)
        rig.stage.characters = []
        #expect(!rig.stage.isTicking && rig.scheduler.pendingCount == 0)
        #expect(rig.hosts.allSatisfy { !$0.isShowingCat && !$0.isAnimating })
        rig.stage.characters = [.cat]
        #expect(rig.stage.isTicking && rig.hosts.allSatisfy { $0.isShowingCat })
    }
}
