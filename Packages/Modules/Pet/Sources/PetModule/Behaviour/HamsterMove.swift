import Foundation

/// What the hamster is doing, which is which of its animations is playing.
nonisolated enum HamsterMove: CaseIterable, Equatable, Sendable {
    // Sitting up, in one place. `stuffA`, `stuffB` and `stuffC` take a seed from the pile and put it in a cheek, which is a little fuller
    // each time; `puffed` is sitting with them full, and `unstuff` is how they go down.
    case sit, blink, groom, freeze, happy, stuffA, stuffB, stuffC, puffed, unstuff
    // Curled in a ball, and getting there and back: `ball` is resting in one, `sleep` is asleep in one, with the z's.
    case curl, ball, sleep, uncurl
    // On its feet, going somewhere or about to.
    case scurry, sitDown, standUp
    // In and out of the wheel, and in it: `wheelLazy` to `wheelSprint` are the four paces of running (see `WheelPace`).
    case hopIn, hopOut, wheelSit, wheelLazy, wheelJog, wheelRun, wheelSprint, wheelWatch, wheelHappy

    /// How the hamster is when it is doing this, and so what it has to do to get from one move to another.
    enum Stance: Equatable, Sendable {
        case standing, seated, curled, wheel
    }

    /// The stance the move is made in and, once through, ends in.
    var stance: Stance {
        switch self {
        case .sit, .blink, .groom, .freeze, .happy, .stuffA, .stuffB, .stuffC, .puffed, .unstuff, .sitDown, .uncurl, .hopOut: .seated
        case .curl, .ball, .sleep: .curled
        case .scurry, .standUp: .standing
        case .hopIn, .wheelSit, .wheelLazy, .wheelJog, .wheelRun, .wheelSprint, .wheelWatch, .wheelHappy: .wheel
        }
    }

    /// The frames of the move: the art makes exactly this many (tested), and the brain, which must not build the art to plan, counts on them.
    var frameCount: Int {
        switch self {
        case .blink: 1
        case .freeze, .ball, .wheelSit, .wheelWatch: 2
        case .sitDown, .standUp: 3
        case .sit, .groom, .puffed, .curl, .uncurl, .sleep, .hopIn, .hopOut, .wheelLazy, .wheelJog, .wheelRun, .wheelSprint: 4
        case .unstuff: 5
        case .scurry, .happy, .stuffA, .stuffB, .stuffC, .wheelHappy: 6
        }
    }

    /// Frames a second at the move's own pace. The hamster's quickness is in the walk and the running, and nowhere else.
    var fps: Double {
        switch self {
        case .sleep, .ball, .wheelSit: 2
        case .sit, .freeze, .puffed, .wheelWatch: 3
        case .blink, .wheelLazy: 4
        case .groom, .stuffA, .stuffB, .stuffC, .unstuff, .curl, .uncurl: 6
        case .hopIn, .hopOut, .wheelJog: 8
        case .happy, .wheelHappy: 10
        case .sitDown, .standUp: 12
        case .scurry, .wheelRun: 14
        case .wheelSprint: 22
        }
    }

    /// Whether it goes round and round, or is played once and held on its last frame.
    var loops: Bool {
        switch self {
        case .happy, .wheelHappy, .stuffA, .stuffB, .stuffC, .unstuff, .curl, .uncurl, .sitDown, .standUp, .hopIn, .hopOut: false
        default: true
        }
    }

    /// How far it goes in a frame, in points, when it goes somewhere: small steps, quickly. Never more than a few points a frame, so a walk
    /// that is sent to the end of the lane ends on the step it was meant to.
    var advance: Double {
        switch self {
        case .scurry: 2
        default: 0
        }
    }

    /// Time one pass through its frames takes.
    var passDuration: TimeInterval { Double(frameCount) / fps }

    /// How fast it goes, in points a second.
    var speed: Double { advance * fps }

    /// Whether it runs in the wheel.
    var runs: Bool {
        switch self {
        case .wheelLazy, .wheelJog, .wheelRun, .wheelSprint: true
        default: false
        }
    }

    /// How far it goes in the hop into the wheel and out of it, in the picture's pixels: the wheel is this far from where it hops from.
    /// Whole steps of the hop's frames (four in half a second, six pixels each).
    static let hopSpan = 24.0
    /// Where a seed it is to eat is put down, from the left of its picture, in pixels: just in front of its snout, which is the right of
    /// the picture when it faces right and the left when it faces left.
    static let seedReach = (right: 25.0, left: -7.0)
}

/// How fast it runs in the wheel, which is how busy the Mac is: four paces, each its own animation of the hamster and of the wheel.
nonisolated enum WheelPace: Int, CaseIterable, Comparable, Equatable, Sendable {
    case lazy, jog, run, sprint

    static func < (lhs: WheelPace, rhs: WheelPace) -> Bool { lhs.rawValue < rhs.rawValue }

    var move: HamsterMove {
        switch self {
        case .lazy: .wheelLazy
        case .jog: .wheelJog
        case .run: .wheelRun
        case .sprint: .wheelSprint
        }
    }

    var prop: HamsterProp {
        switch self {
        case .lazy: .wheelLazy
        case .jog: .wheelJog
        case .run: .wheelRun
        case .sprint: .wheelSprint
        }
    }

    init?(_ move: HamsterMove) {
        guard let pace = Self.allCases.first(where: { $0.move == move }) else { return nil }
        self = pace
    }

    /// The load, 0 to 1, from which the pace is this one when the Mac is getting busier, and the lower one below which it is the one before
    /// when it is getting quieter: the pace does not flicker between two while the load sits on a line between them.
    var risesAt: Double {
        switch self {
        case .lazy: 0
        case .jog: 0.22
        case .run: 0.45
        case .sprint: 0.7
        }
    }

    var fallsAt: Double { self == .lazy ? 0 : risesAt - 0.07 }

    /// The pace for `load`, given the one it is at: stays where it is until the load is clearly past a line.
    static func pace(for load: Double, from current: WheelPace) -> WheelPace {
        var pace = current
        while let up = WheelPace(rawValue: pace.rawValue + 1), load >= up.risesAt { pace = up }
        while pace > .lazy, load < pace.fallsAt { pace = WheelPace(rawValue: pace.rawValue - 1) ?? .lazy }
        return pace
    }
}

/// What the hamster has out, as a view knows it. The wheel is drawn over the hamster, so what is inside it is seen through the ring.
nonisolated enum HamsterProp: CaseIterable, Equatable, Sendable {
    /// A pile of seeds in front of it: three, two, one.
    case seeds3, seeds2, seeds1
    /// The wheel popping up beside it, standing, turning at each of the paces, and going again.
    case wheelAppearing, wheelStill, wheelLazy, wheelJog, wheelRun, wheelSprint, wheelGoing

    /// The pictures of it: the art makes exactly this many (tested), and the brain, which must not build the art to plan, counts on them.
    var frameCount: Int {
        switch self {
        case .seeds3, .seeds2, .seeds1, .wheelStill: 1
        case .wheelAppearing: 4
        case .wheelLazy, .wheelJog, .wheelRun, .wheelSprint: 6
        case .wheelGoing: 5
        }
    }

    /// How fast the wheel turns: a picture is a tenth of the way round its rungs, and the paces are the Mac's load.
    var fps: Double {
        switch self {
        case .seeds3, .seeds2, .seeds1, .wheelStill: 1
        case .wheelLazy: 2.5
        case .wheelJog: 5
        case .wheelRun: 9
        case .wheelSprint: 16
        case .wheelAppearing, .wheelGoing: 6
        }
    }

    /// Time one pass takes: what a wheel that comes up or goes takes, and the pose that shows it lasts.
    var passDuration: TimeInterval { Double(frameCount) / fps }

    var turns: Bool { self == .wheelLazy || self == .wheelJog || self == .wheelRun || self == .wheelSprint }

    var isWheel: Bool { !(self == .seeds3 || self == .seeds2 || self == .seeds1) }

    var look: PropLook {
        PropLook(
            key: Self.allCases.firstIndex(of: self) ?? 0, fps: fps, rise: isWheel ? 0 : 1, animatesInPlace: turns || self == .wheelAppearing || self == .wheelGoing,
            loops: turns, occupies: isWheel
        )
    }

    init(_ look: PropLook) {
        self = Self.allCases.indices.contains(look.key) ? Self.allCases[look.key] : .seeds3
    }
}
