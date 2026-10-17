import Foundation

/// What several characters in one lane owe each other. They may walk past one another, so a place another stands in is only a place not to
/// stop in; and the camera's crossing, which one at a time goes through, is closed to a character while another is in it.
nonisolated enum LaneRules {
    /// What character `index` has to keep to, given the poses of all of them (nil for one that has none yet) as they stand at `now`.
    ///
    /// - `crossing`: where the lane is part in one view and part in the other, as shares of it.
    /// - `separation`: how far, as a share of the lane, another's stop must be from this one's.
    /// - `exempt`: the characters that are playing a joint scene together: each stands where it does because the other is there, so what
    ///   they owe each other is not asked of them (they still owe the others, and the crossing, what everyone does).
    static func context(
        for index: Int, poses: [Pose?], crossing: [ClosedRange<Double>], separation: Double, now: TimeInterval, exempt: Set<Int> = []
    ) -> LaneContext {
        var lane = LaneContext(crossing: crossing)
        let playing = exempt.contains(index)
        for (other, pose) in poses.enumerated() where other != index {
            guard let pose else { continue }
            // Another stops at the end of its walk, or where it is: nobody else stops within a picture of that.
            if separation > 0, !(playing && exempt.contains(other)) {
                lane.zones.append((pose.to - separation)...(pose.to + separation))
                // What it has out that takes up room (a tub) is a place not to stop in too, from the moment it is there.
                if let prop = pose.prop, prop.look.occupies {
                    for place in [prop.to] + prop.alsoAt { lane.zones.append((place - separation)...(place + separation)) }
                }
            }
            if isCrossing(pose, through: crossing, at: now) { lane.closed = crossing }
        }
        return lane
    }

    /// Whether the pose is a walk, not yet over, that goes into the crossing. The crossing is the walk's from the moment it begins to the
    /// moment it is over, which is more than the time the character is in it and means one walk at a time goes through, whatever the speeds.
    static func isCrossing(_ pose: Pose, through crossing: [ClosedRange<Double>], at now: TimeInterval) -> Bool {
        guard pose.from != pose.to, now < pose.end else { return false }
        let (low, high) = (min(pose.from, pose.to), max(pose.from, pose.to))
        return crossing.contains { high > $0.lowerBound && low < $0.upperBound }
    }

    /// Where a character stands, as a share of the lane, when there are `count` of them and this is number `index`: evenly, the first
    /// where a character alone stands (the middle).
    static func startingPlace(_ index: Int, of count: Int) -> Double {
        count > 1 ? Double(index + 1) / Double(count + 1) : 0.5
    }
}
