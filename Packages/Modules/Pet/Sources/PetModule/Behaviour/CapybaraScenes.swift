import Foundation

/// A little thing the capybara does with its time, from start to finish: strung together out of steps by the brain, one at a time, each at
/// the moment it begins. They are long, and there are few of them: a capybara is not in a hurry and has no use for a change of scene.
nonisolated enum CapybaraScene: CaseIterable, Equatable, Sendable {
    case restSit
    /// Sits and nods off, with a bubble at its nose that grows and bursts.
    case doze
    /// A tub of water comes up out of the floor, it hops in and soaks for a good while, and hops out, and the tub goes.
    case soak
    /// The same with an orange on its head.
    case soakOrange
    /// An orange is put down in front of it: it picks it up, peels it, chews it, and the peel goes.
    case eatOrange
    /// A short walk, slowly.
    case stroll
    /// A long one, to the other end of the lane (through the portal, on a notch with a camera).
    case crossOver
    /// Lies down for a while.
    case nap
    /// Sits and sweats a little, with the Mac as busy as it is: the only scene a quiet Mac does not bring on.
    case fret

    /// How much it likes to, by day and at night, and with the Mac busy or not: soaking and dozing most, eating now and then, walking
    /// least and short, and at night more of lying about. A busy Mac does not hurry it; it only soaks for longer (`steps`) and sweats.
    func weight(night: Bool, busy: Bool = false) -> Double {
        switch self {
        case .restSit: night ? 8 : 8
        case .doze: night ? 26 : 18
        case .soak: night ? 20 : 18
        case .soakOrange: night ? 6 : 10
        case .eatOrange: night ? 3 : 12
        case .stroll: night ? 2 : 6
        case .crossOver: night ? 1 : 2.5
        case .nap: night ? 14 : 5
        case .fret: busy ? 9 : 0
        }
    }
}

/// Somewhere on the lane, worked out when the step begins.
nonisolated enum CapybaraPlace: Equatable, Sendable {
    /// So many pixels from where it is, either way, turning round at the ends.
    case away(ClosedRange<Double>)
    /// The end of the lane that it is farther from.
    case farEdge
    /// Where it has room to hop into a tub and out again (`CapybaraMove.hopSpan` each way) that is nearest to where it is.
    case soakStart
}

nonisolated enum CapybaraStep: Equatable, Sendable {
    /// Stays where it is with this move, for this many seconds.
    case stay(CapybaraMove, ClosedRange<Double>)
    case go(CapybaraPlace)
    /// Sits while a tub comes up out of the floor in front of it, a hop away.
    case placeTub
    /// Hops into the tub.
    case hopIn
    /// Hops out of it, the way it came.
    case hopOut
    /// Sits while the tub goes back into the floor.
    case tubGoes
    /// Sits while an orange is put down in front of it.
    case placeOrange
    /// Sits while the peel goes.
    case peelGoes

    /// The way the capybara has to be to do it, which may mean getting up or sitting down first.
    var stance: CapybaraMove.Stance {
        switch self {
        case .stay(let move, _): move.stance
        case .go, .hopIn: .standing
        case .hopOut: .soaking
        case .placeTub, .tubGoes, .placeOrange, .peelGoes: .seated
        }
    }
}

nonisolated extension CapybaraScene {
    /// The steps of the scene, with the random lengths chosen. `longer` is how much longer than usual it soaks: a busy Mac makes it stay
    /// in the water.
    func steps(using generator: inout SplitMix64, longer: Double = 1) -> [CapybaraStep] {
        func seconds(_ low: Double, _ high: Double, scaled: Bool = false) -> ClosedRange<Double> {
            let start = Double.random(in: low...high, using: &generator) * (scaled ? longer : 1)
            return start...start
        }
        switch self {
        case .restSit:
            return [.stay(.sit, seconds(4, 8)), .stay(.blink, 0.4...0.4), .stay(.sit, seconds(3, 6))]
        case .doze:
            return [.stay(.sit, seconds(1.5, 3)), .stay(.doze, seconds(10, 18)), .stay(.sit, seconds(1, 2))]
        case .soak:
            return [
                .go(.soakStart), .placeTub, .hopIn, .stay(.soak, seconds(14, 26, scaled: true)), .hopOut, .tubGoes, .stay(.sit, seconds(1, 2)),
            ]
        case .soakOrange:
            return [
                .go(.soakStart), .placeTub, .hopIn, .stay(.soak, seconds(4, 7)), .stay(.soakOrange, seconds(14, 24, scaled: true)),
                .stay(.soak, seconds(2, 4)), .hopOut, .tubGoes, .stay(.sit, seconds(1, 2)),
            ]
        case .eatOrange:
            return [
                .stay(.sit, seconds(1, 2)), .placeOrange, .stay(.hold, seconds(2, 3.5)), .stay(.peel, seconds(4, 6)),
                .stay(.chew, seconds(6, 9)), .peelGoes, .stay(.sit, seconds(1.5, 3)),
            ]
        case .stroll:
            return [.go(.away(20...60)), .stay(.sit, seconds(3, 6))]
        case .crossOver:
            return [.go(.farEdge), .stay(.sit, seconds(3, 6))]
        case .nap:
            return [.stay(.lie, seconds(8, 16)), .stay(.sit, seconds(1, 2))]
        case .fret:
            return [.stay(.sit, seconds(0.8, 1.5)), .stay(.sweat, seconds(3, 5)), .stay(.sit, seconds(1, 2))]
        }
    }
}
