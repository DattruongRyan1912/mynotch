import Foundation

/// How a brain keeps to the lane it shares with others, which is the same for every species: where it may not stop, where it may not go,
/// and the nearest place it may be sent to when it is asked for one it cannot have. Built from the `LaneContext` the stage gives at every
/// update, all of it shares of the lane, 0 to 1.
///
/// With nothing in the context (a character alone, on a lane with no camera) every answer is the one it was asked for.
nonisolated struct LaneKeeper: Sendable {
    let lane: LaneContext

    init(_ lane: LaneContext = LaneContext()) {
        self.lane = lane
    }

    /// Whether `place` is inside the crossing: a character that is walking through it is not stopped or startled there.
    func isInCrossing(_ place: Double) -> Bool {
        lane.crossing.contains { place > $0.lowerBound && place < $0.upperBound }
    }

    /// `share` if the character may stop there, else the end of the stretch it must not stop in that is nearer, among those it can reach.
    /// A stretch is the crossing or a place another character stands, joined with the ones it overlaps; if it leaves nowhere to stand
    /// within `reach`, the character stays where it is.
    func settled(_ share: Double, within reach: ClosedRange<Double> = 0...1) -> Double {
        guard let stretch = noStopping.first(where: { share > $0.lowerBound && share < $0.upperBound }) else { return share }
        let ends = [stretch.lowerBound, stretch.upperBound].filter(reach.contains)
        // The nearer end, and the upper when they are as near as each other.
        return ends.min { abs($0 - share) < abs($1 - share) || (abs($0 - share) == abs($1 - share) && $0 > $1) } ?? share
    }

    /// Whether a character may stop at `place`, which is to say that it is in neither the crossing nor a place another stands. A lane so
    /// crowded that nothing is left to stand in gives `settled` back the place it was asked for, which is no place for a prop: a tub, a
    /// wheel or a ball that is to take up room asks for a place that is really free and not whether `settled` returned it.
    func isFree(_ place: Double) -> Bool {
        !(lane.crossing + lane.zones).contains { place > $0.lowerBound && place < $0.upperBound }
    }

    /// The crossing and the places others stand, with the ones that overlap made one, from the lowest.
    private var noStopping: [ClosedRange<Double>] {
        guard !lane.zones.isEmpty else { return lane.crossing }
        var joined: [ClosedRange<Double>] = []
        for stretch in (lane.crossing + lane.zones).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = joined.last, stretch.lowerBound < last.upperBound {
                joined[joined.count - 1] = last.lowerBound...max(last.upperBound, stretch.upperBound)
            } else {
                joined.append(stretch)
            }
        }
        return joined
    }

    /// The part of the lane the character can walk in from `here`: a closed stretch is not entered, from whichever side it is on. One that
    /// finds itself in one (a lane with no room to stand outside it) may only walk out, to the nearer side.
    func reach(from here: Double) -> ClosedRange<Double> {
        var (low, high) = (0.0, 1.0)
        for stretch in lane.closed {
            if here <= stretch.lowerBound {
                high = min(high, stretch.lowerBound)
            } else if here >= stretch.upperBound {
                low = max(low, stretch.upperBound)
            } else if here - stretch.lowerBound < stretch.upperBound - here {
                high = min(high, stretch.lowerBound)
            } else {
                low = max(low, stretch.upperBound)
            }
        }
        return low...max(high, low)
    }

    /// Where a walk sent to `target` from `here` ends: held to what the character can reach, and out of the places it must not stop in.
    func destination(_ target: Double, from here: Double) -> Double {
        let reach = reach(from: here)
        return settled(min(max(target, reach.lowerBound), reach.upperBound), within: reach)
    }

    /// The same for a walk to an end of the lane, which a character alone is not kept out of the crossing for (it never was asked to be):
    /// with nobody else in the lane and nothing closed, the end is the end.
    func endOfLane(_ target: Double, from here: Double) -> Double {
        lane.closed.isEmpty && lane.zones.isEmpty ? target : destination(target, from: here)
    }
}
