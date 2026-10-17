import Foundation

/// A little thing the penguin does with its time, from start to finish: strung together out of steps by the brain, one at a time, each at
/// the moment it begins. It is a clumsy bird, and what it is good at is lying down on its belly and going.
nonisolated enum PenguinScene: CaseIterable, Equatable, Sendable {
    case restStand
    /// A few waddling steps and a stop, twice.
    case waddle
    /// Lies down on its belly and glides, and gets up.
    case slideAbout
    /// A long glide to the other end of the lane: the way through the portal, on a notch with a camera.
    case crossOver
    /// The ice cracks open in front of it, it puts its line in and waits, now and then pulls a fish out and swallows it, takes the line in,
    /// and the hole closes.
    case fish
    /// Waddles, slips, falls flat, sits up dazed, gets up and brushes itself off.
    case slip
    /// Flaps its flippers.
    case flap
    /// Stands with its head tucked in for a while.
    case nap

    /// How much it likes to, by day and at night.
    func weight(night: Bool) -> Double {
        switch self {
        case .restStand: 6
        case .waddle: night ? 10 : 12
        case .slideAbout: 10
        case .crossOver: 3
        case .fish: night ? 10 : 12
        case .slip: 4
        case .flap: night ? 6 : 7
        case .nap: night ? 9 : 6
        }
    }
}

/// Somewhere on the lane, worked out when the step begins.
nonisolated enum PenguinPlace: Equatable, Sendable {
    /// So many pixels from where it is, either way, turning round at the ends.
    case away(ClosedRange<Double>)
    /// The end of the lane that it is farther from.
    case farEdge
    /// Where there is room for a hole in the ice in front of it (`PenguinMove.holeReach`) that is nearest to where it is.
    case fishSpot
}

nonisolated enum PenguinStep: Equatable, Sendable {
    /// Stays where it is with this move, for this many seconds.
    case stay(PenguinMove, ClosedRange<Double>)
    /// Waddles, or glides on its belly, to a place; `walkTo` and `slideTo` are the same when the place has been worked out (the penguin
    /// has to lie down before it glides, and turns to face the way it is going as it does).
    case walk(PenguinPlace)
    case slide(PenguinPlace)
    case walkTo(Double)
    case slideTo(Double)
    /// Slips on the ice, in one place, and ends flat on its belly.
    case slip
    /// Stands while the hole opens in front of it.
    case placeHole
    /// Puts its line in the hole.
    case cast
    /// Takes the line in.
    case reel
    /// Stands while the hole closes.
    case holeGoes
    /// Turns to look at the pointer, which goes on until it is gone (see `PenguinBrain`).
    case stare

    /// The way the penguin has to be to do it, which may mean getting up, lying down or untucking first.
    var stance: PenguinMove.Stance {
        switch self {
        case .stay(let move, _): move.stance
        case .walk, .walkTo, .slip, .placeHole, .cast, .holeGoes, .stare: .standing
        case .slide, .slideTo: .lying
        case .reel: .fishing
        }
    }

    /// The stance it leaves the penguin in.
    var endStance: PenguinMove.Stance {
        switch self {
        case .slip: .lying
        case .cast: .fishing
        case .reel: .standing
        default: stance
        }
    }
}

nonisolated extension PenguinScene {
    /// The steps of the scene, with the random lengths chosen.
    func steps(using generator: inout SplitMix64) -> [PenguinStep] {
        func seconds(_ low: Double, _ high: Double) -> ClosedRange<Double> {
            let start = Double.random(in: low...high, using: &generator)
            return start...start
        }
        func chance(_ probability: Double) -> Bool { Double.random(in: 0..<1, using: &generator) < probability }
        switch self {
        case .restStand:
            return [.stay(.stand, seconds(3, 6)), .stay(.blink, 0.4...0.4), .stay(.stand, seconds(2, 4))]
        case .waddle:
            return [.walk(.away(18...64)), .stay(.stand, seconds(0.8, 2)), .walk(.away(12...44)), .stay(.stand, seconds(1.5, 3))]
        case .slideAbout:
            var steps: [PenguinStep] = [.slide(.away(50...140)), .stay(.lie, seconds(0.5, 1.2))]
            if chance(0.4) { steps += [.slide(.away(40...110)), .stay(.lie, seconds(0.5, 1.2))] }
            return steps + [.stay(.stand, seconds(1, 2.5))]
        case .crossOver:
            return [.slide(.farEdge), .stay(.lie, seconds(0.6, 1.2)), .stay(.stand, seconds(2, 4))]
        case .fish:
            let bites: [PenguinStep] = [
                .stay(.bite, seconds(0.9, 1.4)), .stay(.pull, PenguinMove.pull.passDuration...PenguinMove.pull.passDuration),
                .stay(.gulp, (PenguinMove.gulp.passDuration + 0.4)...(PenguinMove.gulp.passDuration + 0.4)),
            ]
            // Two rounds of waiting: a fish in the first now and then, and a better chance in the second when there was none.
            let first = chance(0.4)
            let second = chance(first ? 0.2 : 0.65)
            var steps: [PenguinStep] = [.walk(.fishSpot), .placeHole, .stay(.stand, seconds(0.3, 0.7)), .cast, .stay(.fish, seconds(3, 7))]
            if first { steps += bites }
            steps.append(.stay(.fish, seconds(2.5, 6)))
            if second { steps += bites }
            return steps + [.stay(.fish, seconds(1, 2)), .reel, .holeGoes, .stay(.stand, seconds(1, 2))]
        case .slip:
            return [
                .walk(.away(20...56)), .stay(.stand, seconds(0.4, 0.8)), .slip, .stay(.dazed, seconds(1.2, 2.4)), .stay(.stand, seconds(0.8, 1.5)),
                .stay(.flap, seconds(1.2, 2.2)), .stay(.stand, seconds(1, 2)),
            ]
        case .flap:
            return [.stay(.stand, seconds(1, 2)), .stay(.flap, seconds(2.5, 5)), .stay(.stand, seconds(1, 2.5))]
        case .nap:
            return [.stay(.tucked, seconds(8, 16)), .stay(.stand, seconds(1, 2))]
        }
    }
}
