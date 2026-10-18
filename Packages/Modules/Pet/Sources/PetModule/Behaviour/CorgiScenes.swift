import Foundation

/// A little thing the corgi does with its time, from start to finish: strung together out of steps by the brain, one at a time, each at the
/// moment it begins. It is a corgi, and what it likes is a ball and running about for the joy of it.
nonisolated enum CorgiScene: CaseIterable, Equatable, Sendable {
    case restStand
    /// A few trotting steps and a stop, twice.
    case trot
    /// Stands and wiggles its rear.
    case wiggle
    /// Sits for a while.
    case sit
    /// Lies down with its chin on its paws.
    case lieDown
    /// Lies down and goes to sleep on its side for a while.
    case nap
    /// A ball falls in from above and rolls away; it watches it, runs after it, takes it up, trots back with it, sets it down, and the ball
    /// is taken up again (and now and then thrown a second time).
    case fetch
    /// Runs back and forth as fast as it can, its ears flapping, and wiggles when it has run itself out.
    case zoomies
    /// A trot to the other end of the lane: the way through the portal, on a notch with a camera.
    case crossOver

    /// How much it likes to, by day and at night, and with the Mac as busy as `busyness` says (0 to 1): the busier the Mac, the more it
    /// runs about, for joy.
    func weight(night: Bool, busyness: Double) -> Double {
        switch self {
        case .restStand: 5
        case .trot: night ? 10 : 14
        case .wiggle: night ? 5 : 8
        case .sit: 7
        case .lieDown: night ? 9 : 6
        case .nap: night ? 12 : 5
        case .fetch: night ? 8 : 14
        case .zoomies: (night ? 6 : 9) + Self.busyZoomies * busyness
        case .crossOver: 3
        }
    }

    /// What a Mac at full tilt adds to how much it likes the zoomies.
    static let busyZoomies = 40.0
}

/// Somewhere on the lane, worked out when the step begins.
nonisolated enum CorgiPlace: Equatable, Sendable {
    /// So many pixels from where it is, either way, turning round at the ends.
    case away(ClosedRange<Double>)
    /// The end of the lane that it is farther from.
    case farEdge
    /// Most of the way to the end of the lane that it is farther from: one leg of the zoomies.
    case zoom
    /// Where there is room for the ball to fall and roll and be fetched, nearest to where it is.
    case fetchSpot
}

nonisolated enum CorgiStep: Equatable, Sendable {
    /// Stays where it is with this move, for this many seconds.
    case stay(CorgiMove, ClosedRange<Double>)
    /// Trots, or runs, to a place; `walkTo` and `runTo` are the same when the place has been worked out.
    case walk(CorgiPlace)
    case run(CorgiPlace)
    case walkTo(Double)
    case runTo(Double)
    /// The ball falls in from above in front of it and bounces and rolls away, and it watches.
    case toss
    /// Runs to the ball.
    case chase
    /// Takes the ball up in its mouth.
    case grab
    /// Trots back to where it was with the ball.
    case carryBack
    /// Puts its head down to set the ball on the floor.
    case lower
    /// The ball is set down, and bounces a little.
    case drop
    /// The ball is taken up out of sight.
    case takeBall
    /// Sits up and begs, which goes on until the pointer is gone (see `CorgiBrain`).
    case beg

    /// The way the corgi has to be to do it, which may mean getting up, sitting or lying down first.
    var stance: CorgiMove.Stance {
        switch self {
        case .stay(let move, _): move.stance
        case .beg: .begging
        default: .standing
        }
    }

    /// Whether it is a step of the scene with the ball.
    var isFetching: Bool {
        switch self {
        case .toss, .chase, .grab, .carryBack, .lower, .drop, .takeBall: true
        default: false
        }
    }
}

nonisolated extension CorgiScene {
    /// The steps of the scene, with the random lengths chosen. `busyness` is how busy the Mac is: the zoomies are longer when it is.
    func steps(using generator: inout SplitMix64, busyness: Double) -> [CorgiStep] {
        func seconds(_ low: Double, _ high: Double) -> ClosedRange<Double> {
            let start = Double.random(in: low...high, using: &generator)
            return start...start
        }
        func chance(_ probability: Double) -> Bool { Double.random(in: 0..<1, using: &generator) < probability }
        switch self {
        case .restStand:
            return [.stay(.stand, seconds(3, 6)), .stay(.blink, 0.4...0.4), .stay(.stand, seconds(2, 4))]
        case .trot:
            return [.walk(.away(24...80)), .stay(.stand, seconds(0.8, 2)), .walk(.away(16...56)), .stay(.stand, seconds(1.5, 3))]
        case .wiggle:
            return [.stay(.stand, seconds(1, 2)), .stay(.wiggle, seconds(2.5, 4.5)), .stay(.stand, seconds(1, 2))]
        case .sit:
            return [.stay(.sit, seconds(5, 10)), .stay(.stand, seconds(1, 2))]
        case .lieDown:
            return [.stay(.lie, seconds(6, 14)), .stay(.stand, seconds(1, 2))]
        case .nap:
            return [.stay(.lie, seconds(1.5, 3)), .stay(.sleep, seconds(10, 22)), .stay(.stand, seconds(1, 2))]
        case .crossOver:
            return [.walk(.farEdge), .stay(.stand, seconds(2, 4))]
        case .zoomies:
            let legs = Int((Double(Int.random(in: 3...5, using: &generator)) * (1 + 0.8 * busyness)).rounded())
            return Array(repeating: CorgiStep.run(.zoom), count: legs) + [.stay(.wiggle, seconds(1.2, 2.5)), .stay(.stand, seconds(1.5, 3))]
        case .fetch:
            let round: [CorgiStep] = [.toss, .chase, .grab, .carryBack, .lower, .drop, .stay(.wiggle, seconds(1, 1.8)), .takeBall]
            var steps: [CorgiStep] = [.walk(.fetchSpot)] + round
            // Now and then it is thrown a second time.
            if chance(0.4) { steps += [.stay(.stand, seconds(0.4, 0.9))] + round }
            return steps + [.stay(.stand, seconds(1, 2))]
        }
    }
}

nonisolated extension CorgiScene {
    /// What it does while it is by the capybara, from the moment it is there to the moment it goes: now and then a little wiggle of its rear,
    /// and then it lies down with its chin on its paws for a good while (getting down and up are the brain's). (Getting there and going are
    /// the brain's too.)
    static func together(using generator: inout SplitMix64) -> [CorgiStep] {
        func seconds(_ low: Double, _ high: Double) -> ClosedRange<Double> {
            let start = Double.random(in: low...high, using: &generator)
            return start...start
        }
        var steps: [CorgiStep] = []
        if Double.random(in: 0..<1, using: &generator) < 0.6 { steps += [.stay(.wiggle, seconds(1.5, 2.5))] }
        return steps + [.stay(.lie, seconds(10, 20)), .stay(.stand, seconds(0.5, 1))]
    }
}
