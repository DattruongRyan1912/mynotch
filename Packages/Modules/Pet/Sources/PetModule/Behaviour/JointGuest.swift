import Foundation

/// Where a guest is, and where it goes, for a scene played by the capybara: found once, when it is asked to take part, from where the
/// capybara stands, and kept while the scene lasts (the capybara holds still).
nonisolated struct JointPlace: Equatable, Sendable {
    /// Where the guest is while it plays, as a share of the lane: where its picture is, left edge to left edge.
    var target: Double
    /// Where it goes when it is done, out of the capybara's room and out of the room of what the capybara has out.
    var exit: Double
    /// Which side of the capybara it is on: 1 to its right, -1 to its left.
    var side: Double
    /// Whether that is the side the capybara faces (its snout), and not the side it turns its back to.
    var inFront: Bool
}

/// A guest's part in a scene, as the brain keeps it: which, how far it has come, and where.
nonisolated struct JointRun: Equatable, Sendable {
    nonisolated enum Phase: Equatable, Sendable {
        /// On its way to where it plays.
        case approach
        /// There, and playing.
        case together
        /// Done, or told to be: on its way out of the capybara's room, which is all it needs the capybara for no more.
        case exit
    }

    var scene: JointScene.ID
    var phase = Phase.approach
    /// Where the capybara was when the scene began: it holds still, so a capybara that is not there is a reason to go.
    var host: Double
    /// Everywhere the capybara takes room, which is where it is and, with its tub out, where the tub is and where it hopped into it from.
    var rooms: [Double]
    var place: JointPlace

    init(scene: JointScene.ID, host pose: Pose, now: TimeInterval, place: JointPlace) {
        self.scene = scene
        host = pose.position(at: now)
        rooms = pose.roomPlaces(at: now)
        self.place = place
    }

    /// Whether `place` (a share of the lane) is within the room of the capybara, given how far a share of the lane is in pixels.
    func isNear(_ place: Double, travel: Double) -> Bool {
        rooms.contains { abs(place - $0) * travel < JointRoom.clearance }
    }
}

nonisolated extension Pose {
    /// Where it takes room, as shares of the lane: where it is, and where what it has out takes up room too (a tub, and the place it hops into
    /// it from).
    func roomPlaces(at now: TimeInterval) -> [Double] {
        var places = [position(at: now)]
        if let prop, prop.look.occupies { places += [prop.to] + prop.alsoAt }
        return places
    }
}

/// How a guest finds its place by the capybara: out of the others' way, out of the camera's, and with a way to go when it is over that is
/// out of the capybara's room (which the scene did not ask of it) and out of the room of what the capybara has out (a tub, and the place the
/// capybara hops into it from).
nonisolated struct JointRoom {
    /// How far from the capybara, in pixels, a guest is out of its way: a picture and a little air, which is the room that two characters
    /// that are not playing together leave each other.
    static let clearance = CatMove.clearance

    let host: Pose
    let now: TimeInterval
    /// How far the guest can walk along the lane, in pixels of its picture.
    let travel: Double
    /// What the guest keeps to in the scene: the others' rooms and the camera's, but not the capybara's.
    let keeper: LaneKeeper

    /// Where the capybara stands, and where what it has out takes room.
    var places: [Double] { host.roomPlaces(at: now) }

    /// The ways a guest standing at `here` can be by the capybara, nearest first. `offsets` are how far from the capybara's picture the
    /// guest's is for it to be at the capybara's back (`rump`, below zero) and at its snout (`front`), in pixels, for a capybara that
    /// faces right; a capybara that faces left is the same the other way round. It goes out on the side it is on.
    func placings(offsets: (rump: Double, front: Double), from here: Double) -> [JointPlace] {
        guard travel >= 1 else { return [] }
        let way = host.facing == .right ? 1.0 : -1.0
        let there = host.position(at: now)
        let found = [false, true].compactMap { inFront -> JointPlace? in
            let target = there + way * (inFront ? offsets.front : offsets.rump) / travel
            return fit(target: target, side: target >= there ? 1 : -1, inFront: inFront, from: here)
        }
        return found.sorted { abs($0.target - here) < abs($1.target - here) }
    }

    /// The ways a guest can be at the capybara itself, `offset` pixels from its picture (for a capybara that faces right), as one that hides
    /// behind it is, nearest first. It may go out on either side.
    func hidings(offset: Double, from here: Double) -> [JointPlace] {
        guard travel >= 1 else { return [] }
        let way = host.facing == .right ? 1.0 : -1.0
        let target = host.position(at: now) + way * offset / travel
        return [-1.0, 1.0].compactMap { fit(target: target, side: $0, inFront: false, from: here) }
            .sorted { abs($0.exit - here) < abs($1.exit - here) }
    }

    /// The place at `target` with its way out on `side`, if the guest can be there and get out: nobody else's room, nothing of the camera's,
    /// and a way there from `here` and from there to the way out.
    private func fit(target: Double, side: Double, inFront: Bool, from here: Double) -> JointPlace? {
        let room = places
        let there = host.position(at: now)
        let clear = Self.clearance / travel
        // Out of the room of everything the capybara has, on that side.
        let exit = side > 0 ? (room.max() ?? there) + clear : (room.min() ?? there) - clear
        guard (0.0...1.0).contains(target), (0.0...1.0).contains(exit), keeper.isFree(target), keeper.isFree(exit),
              keeper.destination(target, from: here) == target, keeper.reach(from: target).contains(exit) else { return nil }
        let (low, high) = (min(target, exit), max(target, exit))
        if keeper.lane.crossing.contains(where: { high > $0.lowerBound && low < $0.upperBound }) { return nil }
        return JointPlace(target: target, exit: exit, side: side, inFront: inFront)
    }
}
