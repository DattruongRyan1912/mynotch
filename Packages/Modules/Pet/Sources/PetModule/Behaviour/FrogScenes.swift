import Foundation

/// A little thing the frog does with its time, from start to finish: strung together out of steps by the brain, one at a time, each at the
/// moment it begins. It is a frog, and what it likes is to sit, to sit on a lily pad, and to wait for a moth.
nonisolated enum FrogScene: CaseIterable, Equatable, Sendable {
    case restSit
    /// Blows its throat out, once or twice.
    case puff
    /// A few hops about the bank, with a rest after each.
    case hopAbout
    /// A lily pad comes up out of the water beside it, it hops on and sits there, blinking and puffing, and hops off, and the pad goes down.
    case lilyPad
    /// The same, with a doze on the pad, eyes shut.
    case nap
    /// A moth flies in, it watches it, shoots out its tongue, and gulps (and now and then there is a second).
    case mothCatch
    /// A run of hops to the other end of the lane: the way through the portal, on a notch with a camera.
    case crossOver

    /// How much it likes to, by day and at night, and with the Mac as busy as `busyness` says (0 to 1): the busier the Mac, the more it hops
    /// about, which is as hurried as a frog gets.
    func weight(night: Bool, busyness: Double) -> Double {
        switch self {
        case .restSit: night ? 5 : 6
        case .puff: night ? 8 : 7
        case .hopAbout: (night ? 8 : 10) + Self.busyHops * busyness
        case .lilyPad: night ? 14 : 18
        case .nap: night ? 14 : 5
        case .mothCatch: night ? 22 : 12
        case .crossOver: 3
        }
    }

    /// What a Mac at full tilt adds to how much it likes to hop about.
    static let busyHops = 40.0
}

/// Somewhere on the lane, worked out when the step begins.
nonisolated enum FrogPlace: Equatable, Sendable {
    /// So many pixels from where it is, either way, turning round at the ends.
    case away(ClosedRange<Double>)
    /// The end of the lane that it is farther from.
    case farEdge
    /// Where there is room for a lily pad and the hop on to it and off it, nearest to where it is.
    case padSpot
    /// Where there is room for a moth to come in and hover at the tip of its tongue, nearest to where it is.
    case mothSpot
}

nonisolated enum FrogStep: Equatable, Sendable {
    /// Stays where it is with this move, for this many seconds.
    case stay(FrogMove, ClosedRange<Double>)
    /// Hops to a place; `walkTo` is the same when the place has been worked out.
    case walk(FrogPlace)
    case walkTo(Double)
    /// The lily pad comes up out of the water beside it, a hop in front of it.
    case placePad
    case hopOn
    case hopOff
    /// The pad goes down, and there is nothing.
    case padSinks
    /// A moth comes flying in from the end of the lane, hovers where the tongue will reach it, is caught, and is gone.
    case mothComes
    case mothHovers(ClosedRange<Double>)
    case snap
    case reel
    /// Sits up and watches the pointer, which goes on until the pointer is gone (see `FrogBrain`).
    case look

    /// The footing it has to be on to do it, which may mean hopping off the pad first; nil for what it does on either (looking).
    var stance: FrogMove.Stance? {
        switch self {
        case .stay(let move, _): move.stance
        case .hopOff: .pad
        case .look: nil
        default: .ground
        }
    }

    /// The footing it is on when it has done it.
    var endStance: FrogMove.Stance? {
        switch self {
        case .hopOn: .pad
        case .hopOff: .ground
        default: stance
        }
    }
}

nonisolated extension FrogScene {
    /// The steps of the scene, with the random lengths chosen. `busyness` is how busy the Mac is: the hops are more and the rests between
    /// them shorter when it is, and the hops are no quicker.
    func steps(using generator: inout SplitMix64, busyness: Double) -> [FrogStep] {
        func seconds(_ low: Double, _ high: Double) -> ClosedRange<Double> {
            let start = Double.random(in: low...high, using: &generator)
            return start...start
        }
        func chance(_ probability: Double) -> Bool { Double.random(in: 0..<1, using: &generator) < probability }
        switch self {
        case .restSit:
            return [.stay(.sit, seconds(3, 6)), .stay(.blink, 1...1), .stay(.sit, seconds(2, 4))]
        case .puff:
            var steps: [FrogStep] = [.stay(.sit, seconds(1, 2)), .stay(.puff, FrogMove.puff.passDuration...FrogMove.puff.passDuration)]
            if chance(0.6) { steps += [.stay(.sit, seconds(0.4, 0.8)), .stay(.puff, FrogMove.puff.passDuration...FrogMove.puff.passDuration)] }
            return steps + [.stay(.sit, seconds(1.5, 3))]
        case .hopAbout:
            let legs = Int((Double(Int.random(in: 2...4, using: &generator)) * (1 + 0.8 * busyness)).rounded())
            var steps: [FrogStep] = []
            for _ in 0..<legs {
                steps.append(.walk(.away(18...54)))
                steps.append(.stay(.sit, seconds(max(0.8 - 0.55 * busyness, 0.25), max(2.0 - 1.4 * busyness, 0.5))))
            }
            return steps + [.stay(.sit, seconds(1, 2))]
        case .lilyPad:
            var steps: [FrogStep] = [.walk(.padSpot), .placePad, .hopOn, .stay(.padSit, seconds(2, 4)), .stay(.padBlink, 1...1), .stay(.padSit, seconds(3, 6))]
            steps += [.stay(.padPuff, FrogMove.padPuff.passDuration...FrogMove.padPuff.passDuration)]
            if chance(0.5) { steps += [.stay(.padSit, seconds(2, 4)), .stay(.padPuff, FrogMove.padPuff.passDuration...FrogMove.padPuff.passDuration)] }
            steps += [.stay(.padSit, seconds(3, 8))]
            if chance(0.5) { steps += [.stay(.padBlink, 1...1), .stay(.padSit, seconds(2, 5))] }
            return steps + [.hopOff, .padSinks, .stay(.sit, seconds(1, 2))]
        case .nap:
            return [
                .walk(.padSpot), .placePad, .hopOn, .stay(.padSit, seconds(1.5, 3)), .stay(.padSleep, seconds(10, 22)), .stay(.padSit, seconds(1, 2)),
                .hopOff, .padSinks, .stay(.sit, seconds(1, 2)),
            ]
        case .mothCatch:
            let hunt: [FrogStep] = [.mothComes, .mothHovers(seconds(1.5, 3.5)), .snap, .reel, .stay(.gulp, FrogMove.gulp.passDuration...FrogMove.gulp.passDuration)]
            var steps: [FrogStep] = [.walk(.mothSpot)] + hunt + [.stay(.sit, seconds(1.5, 3))]
            // Now and then there is a second, from where it is.
            if chance(0.35) { steps += hunt + [.stay(.sit, seconds(1.5, 3))] }
            return steps
        case .crossOver:
            return [.walk(.farEdge), .stay(.sit, seconds(2, 4))]
        }
    }
}
