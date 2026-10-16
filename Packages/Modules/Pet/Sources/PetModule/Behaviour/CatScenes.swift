import Foundation

/// A little thing the cat does with its time, from start to finish: strung together out of steps by the brain, one at a time, each at the
/// moment it begins (so that a step knows where the cat is by then).
nonisolated enum CatScene: CaseIterable, Equatable, Sendable {
    /// Gets up, goes for a walk, sits down.
    case wander
    case restSit
    case groom
    case scratch
    case tailWatch
    case lookAround
    case stretch
    case yawnSit
    /// Lies down, loafs for a while, gets up and stretches.
    case nap
    /// A moth comes in at one end and the cat runs after it to the other.
    case mothChase
    /// A ball of yarn: a walk up to it, a bat, a roll, a walk, a bat, and sitting proudly beside it.
    case yarnPlay
    /// Trots to the middle of the strip, under the notch's middle, ducks out of sight below its edge and peeks back up.
    case peekaboo
    case dash
    /// Not one it picks: the pointer came close.
    case pounceAtPointer

    /// How much it likes to, by day and at night. A cat does not nap at its desk by day.
    func weight(night: Bool) -> Double {
        switch self {
        case .wander: night ? 8 : 22
        case .restSit: night ? 16 : 10
        case .groom: night ? 10 : 12
        case .scratch: night ? 4 : 8
        case .tailWatch: night ? 8 : 8
        case .lookAround: night ? 4 : 8
        case .stretch: night ? 8 : 6
        case .yawnSit: night ? 10 : 4
        case .nap: night ? 22 : 0
        case .mothChase: night ? 3 : 8
        case .yarnPlay: night ? 3 : 8
        case .peekaboo: night ? 2 : 6
        case .dash: night ? 2 : 5
        case .pounceAtPointer: 0
        }
    }
}

/// Somewhere on the lane, worked out when the step begins.
nonisolated enum Place: Equatable, Sendable {
    /// So many points from where it is, either way, turning round at the ends.
    case away(ClosedRange<Double>)
    /// The end of the lane that it is nearer, a little in from it.
    case nearEdge
    /// The end it is farther from.
    case farEdge
    /// The middle of the strip, which is under the middle of the notch.
    case centre
    /// A short way from the ball of yarn, on the side the cat is on.
    case besideBall
}

nonisolated enum Step: Equatable, Sendable {
    /// Stays where it is with this move, for this many seconds.
    case stay(CatMove, ClosedRange<Double>)
    /// A move that is played once, for as long as it takes.
    case once(CatMove)
    case go(CatMove, Place)
    case chaseMoth
    /// Puts the ball down a little way off, in the direction there is room in.
    case placeBall
    /// Bats the ball, which rolls.
    case batBall
    /// Pounces towards the pointer.
    case pounce
    case startle

    /// The way the cat has to be to do it, which may mean getting up or sitting down first; nil when it does not matter.
    var stance: CatMove.Stance? {
        switch self {
        case .stay(let move, _), .once(let move), .go(let move, _): move.stance
        case .chaseMoth, .batBall, .pounce, .startle: .standing
        case .placeBall: nil
        }
    }
}

nonisolated extension CatScene {
    /// The steps of the scene, with the random lengths chosen.
    func steps(using generator: inout SplitMix64) -> [Step] {
        func seconds(_ low: Double, _ high: Double) -> ClosedRange<Double> {
            let start = Double.random(in: low...high, using: &generator)
            return start...start
        }
        switch self {
        case .wander:
            return [.go(.walk, .away(40...140)), .stay(.sit, seconds(2, 5))]
        case .restSit:
            return [.stay(.sit, seconds(2.5, 5)), .stay(.blink, 0.3...0.3), .stay(.sit, seconds(2, 4))]
        case .groom:
            return [.stay(.sit, seconds(0.8, 1.5)), .stay(.groom, seconds(3.5, 5.5)), .stay(.sit, seconds(1, 2))]
        case .scratch:
            return [.stay(.sit, seconds(0.8, 1.2)), .stay(.scratch, seconds(2.5, 4)), .stay(.sit, seconds(1, 2))]
        case .tailWatch:
            return [.stay(.tailSwish, seconds(3, 5)), .stay(.sit, seconds(1, 2))]
        case .lookAround:
            return [
                .stay(.lookLeft, seconds(1.2, 2)), .stay(.lookRight, seconds(1.2, 2)), .stay(.lookUp, seconds(1.2, 1.8)),
                .stay(.sit, seconds(1, 2)),
            ]
        case .stretch:
            return [.once(.stretch), .stay(.sit, seconds(1, 2))]
        case .yawnSit:
            return [.once(.yawn), .stay(.sit, seconds(1.5, 3))]
        case .nap:
            return [.once(.lieDown), .stay(.loaf, seconds(8, 16)), .once(.stretch), .stay(.sit, seconds(1, 2))]
        case .mothChase:
            return [.go(.trot, .nearEdge), .chaseMoth, .stay(.tailSwish, seconds(2, 3))]
        case .yarnPlay:
            return [
                .placeBall, .go(.walk, .besideBall), .batBall, .go(.trot, .besideBall), .batBall, .go(.trot, .besideBall), .batBall,
                .stay(.tailSwish, seconds(2, 3)),
            ]
        case .peekaboo:
            return [.go(.trot, .centre), .once(.peek), .once(.peek), .go(.walk, .away(30...90)), .stay(.sit, seconds(1.5, 3))]
        case .dash:
            return [.go(.trot, .farEdge), .stay(.sit, seconds(2, 4))]
        case .pounceAtPointer:
            return [.pounce, .stay(.sit, seconds(1.5, 3))]
        }
    }
}
