import Foundation

/// A little thing the hamster does with its time, from start to finish: strung together out of steps by the brain, one at a time, each at
/// the moment it begins. A hamster is busy all the time with something, and its signature is the wheel.
nonisolated enum HamsterScene: CaseIterable, Equatable, Sendable {
    case restSit
    /// Short runs about the floor, in quick small steps, and stops to look about.
    case scurry
    /// A long one, to the other end of the lane (through the portal, on a notch with a camera).
    case crossOver
    /// The wheel pops up, it hops in and runs: lazily on a quiet Mac, as fast as the Mac is busy; and hops out, and the wheel goes.
    case wheel
    /// Seeds are put down in front of it, and it stuffs them into its cheeks one at a time, until they are full, and then lets them out.
    case stuff
    /// Washes its face.
    case groom
    /// Curls into a ball for a while.
    case nap

    /// How much it likes to, by day and at night (it is a night animal: more about, less asleep), and with the Mac busy or not: the wheel
    /// is what it does most when the Mac is busy, six times as much as when it is not.
    func weight(night: Bool, busy: Bool = false) -> Double {
        switch self {
        case .restSit: 7
        case .scurry: night ? 16 : 14
        case .crossOver: night ? 4 : 3
        case .wheel: busy ? 40 : (night ? 9 : 6)
        case .stuff: 12
        case .groom: night ? 10 : 12
        case .nap: night ? 4 : 9
        }
    }
}

/// Somewhere on the lane, worked out when the step begins.
nonisolated enum HamsterPlace: Equatable, Sendable {
    /// So many pixels from where it is, either way, turning round at the ends.
    case away(ClosedRange<Double>)
    /// The end of the lane that it is farther from.
    case farEdge
    /// Where it has room to hop into a wheel and out again (`HamsterMove.hopSpan` each way) that is nearest to where it is.
    case wheelStart
}

nonisolated enum HamsterStep: Equatable, Sendable {
    /// Stays where it is with this move, for this many seconds.
    case stay(HamsterMove, ClosedRange<Double>)
    case go(HamsterPlace)
    /// Sits while a wheel pops up in front of it, a hop away.
    case placeWheel
    /// Hops into the wheel.
    case hopIn
    /// Hops out of it, the way it came.
    case hopOut
    /// Sits while the wheel goes.
    case wheelGoes
    /// Runs in the wheel, for this many seconds, at the pace the Mac's load gives (`WheelPace`).
    case run(ClosedRange<Double>)
    /// Sits while three seeds are put down in front of it.
    case placeSeeds
    /// Takes the first, second or third seed and stuffs it in a cheek.
    case stuff(Int)

    /// The way the hamster has to be to do it, which may mean getting up, sitting down or uncurling first.
    var stance: HamsterMove.Stance {
        switch self {
        case .stay(let move, _): move.stance
        case .go: .standing
        case .hopOut, .run: .wheel
        case .placeWheel, .hopIn, .wheelGoes, .placeSeeds, .stuff: .seated
        }
    }

    /// The stance it leaves the hamster in.
    var endStance: HamsterMove.Stance {
        switch self {
        case .hopIn: .wheel
        case .hopOut: .seated
        default: stance
        }
    }
}

nonisolated extension HamsterScene {
    /// The steps of the scene, with the random lengths chosen. `busy` is whether the Mac is busy, which makes it run without a rest, and
    /// `longer` how much longer than usual it runs for it.
    func steps(using generator: inout SplitMix64, busy: Bool = false, longer: Double = 1) -> [HamsterStep] {
        func seconds(_ low: Double, _ high: Double) -> ClosedRange<Double> {
            let start = Double.random(in: low...high, using: &generator)
            return start...start
        }
        switch self {
        case .restSit:
            return [.stay(.sit, seconds(3, 6)), .stay(.blink, 0.4...0.4), .stay(.sit, seconds(2, 4))]
        case .scurry:
            return [.go(.away(18...60)), .stay(.sit, seconds(0.8, 2)), .go(.away(12...40)), .stay(.sit, seconds(1.5, 3))]
        case .crossOver:
            return [.go(.farEdge), .stay(.sit, seconds(2, 4))]
        case .wheel:
            let (first, second) = (seconds(6, 12), seconds(5, 10))
            func scaled(_ range: ClosedRange<Double>) -> ClosedRange<Double> { (range.lowerBound * longer)...(range.upperBound * longer) }
            let setUp: [HamsterStep] = [.go(.wheelStart), .placeWheel, .hopIn]
            let packUp: [HamsterStep] = [.hopOut, .wheelGoes, .stay(.sit, seconds(1, 2))]
            if busy { return setUp + [.run(scaled(seconds(16, 30)))] + packUp }
            // A quiet Mac: it sits in the wheel now and then, between lazy jogs.
            return setUp + [.stay(.wheelSit, seconds(2, 4)), .run(first), .stay(.wheelSit, seconds(6, 12)), .run(second)] + packUp
        case .stuff:
            return [
                .stay(.sit, seconds(1, 2)), .placeSeeds, .stuff(1), .stuff(2), .stuff(3), .stay(.puffed, seconds(3, 6)), .stay(.unstuff, 1...1),
                .stay(.sit, seconds(1.5, 3)),
            ]
        case .groom:
            return [.stay(.sit, seconds(0.8, 1.6)), .stay(.groom, seconds(4, 8)), .stay(.sit, seconds(1, 2))]
        case .nap:
            return [.stay(.ball, seconds(8, 16)), .stay(.sit, seconds(1, 2))]
        }
    }
}
