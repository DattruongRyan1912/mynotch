import Foundation
import Testing
@testable import PetModule

/// How a guest finds its place by the capybara and its way out, and what is kept free for it while it plays.
@Suite struct JointRoomTests {
    let travel = 260.0

    func host(at place: Double = 0.5, facing: Facing = .right, tub: Bool = false) -> Pose {
        GuestDrive.capybara(at: place, facing: facing).withTub(tub, travel: travel)
    }

    func room(_ host: Pose, lane: LaneContext = LaneContext()) -> JointRoom {
        JointRoom(host: host, now: 0, travel: travel, keeper: LaneKeeper(lane))
    }

    @Test func theRoomOfACapybaraIsWhereItIsAndWithItsTubOutWhereTheTubIsAndWhereItHoppedIntoItFrom() {
        #expect(room(host()).places == [0.5])
        let tub = room(host(tub: true)).places
        #expect(tub.count == 3 && tub[0] == 0.5 && tub[1] == 0.5 && abs(tub[2] - (0.5 - 24 / travel)) < 1e-9, "\(tub)")
        #expect(host(tub: true).roomPlaces(at: 0) == tub)
    }

    @Test func aGuestIsBesideItOnEitherSideTheNearerFirstAndItsWayOutIsAClearanceFromTheCapybaraOnTheSideItIsOn() throws {
        for facing in [Facing.right, .left] {
            let way = facing == .right ? 1.0 : -1.0
            let found = room(host(facing: facing)).placings(offsets: (rump: -25, front: 26), from: 0.1)
            #expect(found.count == 2)
            // From the left, the nearer side is the left one: the rump side for a capybara that faces right and the snout side for one that faces left.
            #expect(found[0].target < found[1].target)
            let rump = try #require(found.first { !$0.inFront }), front = try #require(found.first { $0.inFront })
            #expect(abs(rump.target - (0.5 - way * 25 / travel)) < 1e-9 && abs(front.target - (0.5 + way * 26 / travel)) < 1e-9, "\(facing)")
            #expect(rump.side == -way && front.side == way)
            for place in found {
                #expect(abs(abs(place.exit - 0.5) * travel - JointRoom.clearance) < 1e-9, "a clearance from it")
                #expect((place.exit > 0.5) == (place.side > 0), "on its own side")
            }
        }
    }

    @Test func withItsTubOutTheWayOutIsAClearanceFromTheTubAndFromWhereItHoppedFromToo() throws {
        let found = room(host(tub: true)).placings(offsets: (rump: -25, front: 26), from: 0.1)
        let rump = try #require(found.first { !$0.inFront })
        // The place it hopped from is 24 behind, so the way out on that side is that much farther.
        #expect(abs((0.5 - rump.exit) * travel - (24 + JointRoom.clearance)) < 1e-9, "\((0.5 - rump.exit) * travel)")
        let front = try #require(found.first { $0.inFront })
        #expect(abs((front.exit - 0.5) * travel - JointRoom.clearance) < 1e-9)
    }

    @Test func notWhereThereIsNoLaneTheCameraOrAnotherCharactersRoomIsInTheWayAndTheNearerSideIsTakenWhenTheOtherHasNoRoom() {
        // At the left end there is no room on the left.
        let atEnd = room(host(at: 0.05)).placings(offsets: (rump: -25, front: 26), from: 0.5)
        #expect(atEnd.count == 1 && atEnd[0].inFront, "only to the right: \(atEnd.map(\.target))")
        // The camera between where it would be and where it goes out to.
        #expect(room(host(), lane: LaneContext(crossing: [0.55...0.7])).placings(offsets: (rump: -25, front: 26), from: 0.1).count == 1)
        // Another's room over the place it would be.
        let crowded = room(host(), lane: LaneContext(zones: [0.3...0.45, 0.55...0.7]))
        #expect(crowded.placings(offsets: (rump: -25, front: 26), from: 0.1).isEmpty)
        // A way that is shut: another is in the camera, which is between a guest that is to its right and the capybara, and which the way out
        // on the capybara's right would end in.
        let shut = room(host(), lane: LaneContext(crossing: [0.6...0.7], closed: [0.6...0.7]))
        #expect(shut.placings(offsets: (rump: -25, front: 26), from: 0.9).isEmpty, "it cannot come from the right of the camera")
        #expect(shut.placings(offsets: (rump: -25, front: 26), from: 0.1).count == 1, "and from the left it has the one side the way out of is not in the camera")
        // A camera narrower than the way between where it would be and where it goes out to, with both ends of the way outside it: not walked
        // across for it (the rump side), and the snout side, where there is none, is.
        let narrow = room(host(), lane: LaneContext(crossing: [0.37...0.39])).placings(offsets: (rump: -25, front: 26), from: 0.1)
        #expect(narrow.count == 1 && narrow[0].inFront, "the camera between the place and the way out: \(narrow.map(\.inFront))")
        // No lane to speak of.
        #expect(JointRoom(host: host(), now: 0, travel: 0, keeper: LaneKeeper()).placings(offsets: (rump: -25, front: 26), from: 0.1).isEmpty)
    }

    @Test func aGuestThatHidesBehindItMayGoOutOnEitherSideTheNearerToWhereItIsFirstAndOnlyOnesThatHaveRoom() {
        let both = room(host()).hidings(offset: -5, from: 0.1)
        #expect(both.count == 2 && both.allSatisfy { abs($0.target - (0.5 - 5 / travel)) < 1e-9 })
        #expect(both[0].exit < both[1].exit, "from the left, the left way is nearer")
        #expect(both.map(\.side) == [-1, 1])
        let right = room(host(), lane: LaneContext(zones: [0.0...0.4])).hidings(offset: -5, from: 0.9)
        #expect(right.count == 1 && right[0].side == 1)
        let mirrored = room(host(facing: .left)).hidings(offset: -5, from: 0.1)
        #expect(mirrored.allSatisfy { abs($0.target - (0.5 + 5 / travel)) < 1e-9 }, "behind it is the other way for one that faces the other way")
    }

    // MARK: What is kept free for it

    @Test func theRoomAGuestReservesIsKeptFreeFromEveryoneButTheCapybaraItIsWithAndTheTubsPlacesAreToo() {
        let still = { (place: Double) in Pose(motion: Walker.motion, facing: .right, from: place, to: place, began: 0, duration: 1) }
        var guest = still(0.3)
        guest.reserves = [0.8]
        let poses: [Pose?] = [still(0.1), guest, still(0.5)]
        // Another, not in the scene: owes its place and the one it reserved.
        let other = LaneRules.context(for: 0, poses: poses, crossing: [], separation: 0.1, now: 0)
        #expect(other.zones.contains { $0.lowerBound == 0.8 - 0.1 && $0.upperBound == 0.8 + 0.1 }, "\(other.zones)")
        // The capybara it plays with, which is excused of it, owes it nothing.
        let host = LaneRules.context(for: 2, poses: poses, crossing: [], separation: 0.1, now: 0, exempt: [1, 2])
        #expect(!host.zones.contains { $0.lowerBound == 0.8 - 0.1 } && !host.zones.contains { $0.lowerBound == 0.3 - 0.1 }, "\(host.zones)")
        #expect(host.zones.count == 1, "only the first character's: \(host.zones)")
        // And the one that reserved it owes the others what it does.
        let back = LaneRules.context(for: 1, poses: poses, crossing: [], separation: 0.1, now: 0, exempt: [1, 2])
        #expect(back.zones.count == 1 && back.zones[0].lowerBound == 0.1 - 0.1)
    }

    @Test func aPictureBehindOrOverIsAnotherPictureAndAPerchOnTheHeadIsAnotherPerch() {
        let base = Pose(motion: Motion(key: 1, fps: 2, loops: true), facing: .right, from: 0.5, to: 0.5, began: 0, duration: 2)
        var behind = base
        behind.behind = true
        var raised = base
        raised.raised = true
        #expect(!base.looksLike(behind) && !base.looksLike(raised) && !behind.looksLike(raised) && base.looksLike(base))
        // A reserved place is not a different picture.
        var reserved = base
        reserved.reserves = [0.9]
        #expect(base.looksLike(reserved))
        #expect(Perch(dx: 0) == Perch(dx: 0, spot: .back) && Perch(dx: 0) != Perch(dx: 0, spot: .head))
    }
}

extension Pose {
    /// The capybara pose with its tub out and the place it hopped into it from, as `GuestDrive.capybara` makes it for a lane of `travel`.
    func withTub(_ tub: Bool, travel: Double) -> Pose {
        guard tub else { return self }
        var pose = self
        let way = facing == .right ? 1.0 : -1.0
        pose.prop = PoseProp(look: CapybaraProp.tubRippling.look, from: to, to: to, alsoAt: [to - way * 24 / travel])
        return pose
    }
}
