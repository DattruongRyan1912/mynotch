import Foundation

/// What the penguin is doing, which is which of its animations is playing.
nonisolated enum PenguinMove: CaseIterable, Equatable, Sendable {
    // On its feet, side on, in one place or going somewhere. `lookTurn`, `lookFlap` and `lookBack` are the stare at the pointer: it turns to
    // face the viewer, flaps, and turns back. `happy` is the flap for joy of a stroke, facing the viewer. `getUp`, `untuck` and `reel` are how
    // it comes back to this from lying, from asleep and from fishing.
    case stand, blink, flap, waddle, lookTurn, lookFlap, lookBack, happy, getUp, untuck, reel
    // On its belly: `bellyDown` is lying down onto it, `slide` is gliding on it, `lie` is lying still, `slip` is a fall (from its feet, in
    // one place) that ends flat on it, and `dazed` is lying there seeing stars.
    case bellyDown, slide, lie, slip, dazed
    // Asleep on its feet with its head tucked in: `tuck` is getting there, `tucked` is resting so, `sleep` is asleep, with the z's.
    case tuck, tucked, sleep
    // Fishing, with a rod, over a hole in the ice in front of it: `cast` puts the line in; then it waits (`fish`), the line jerks (`bite`),
    // it pulls a fish out (`pull`), swallows it (`gulp`), and now and then jumps for joy with the rod in its flipper (`fishHappy`).
    case cast, fish, bite, pull, gulp, fishHappy

    /// How the penguin is when it is doing this, and so what it has to do to get from one move to another.
    enum Stance: Equatable, Sendable {
        case standing, lying, tucked, fishing
    }

    /// The stance the move is made in and, once through, ends in (a move that changes it ends in this).
    var stance: Stance {
        switch self {
        case .stand, .blink, .flap, .waddle, .lookTurn, .lookFlap, .lookBack, .happy, .getUp, .untuck, .reel: .standing
        case .bellyDown, .slide, .lie, .slip, .dazed: .lying
        case .tuck, .tucked, .sleep: .tucked
        case .cast, .fish, .bite, .pull, .gulp, .fishHappy: .fishing
        }
    }

    /// The frames of the move: the art makes exactly this many (tested), and the brain, which must not build the art to plan, counts on them.
    var frameCount: Int {
        switch self {
        case .blink: 1
        case .lie, .tucked, .bite: 2
        case .lookTurn, .lookBack, .bellyDown, .tuck, .untuck: 3
        case .stand, .getUp, .slide, .dazed, .reel, .cast, .fish, .sleep: 4
        case .slip, .pull, .gulp: 5
        case .flap, .waddle, .lookFlap, .happy, .fishHappy: 6
        }
    }

    /// Frames a second at the move's own pace. Nothing but the slide and the busiest waddle is in any hurry: it is a clumsy bird.
    var fps: Double {
        switch self {
        case .lie, .tucked, .sleep: 2
        case .stand, .fish: 3
        case .blink, .dazed: 4
        case .lookTurn, .lookBack, .gulp: 6
        case .tuck, .untuck: 5
        case .flap, .waddle, .lookFlap, .getUp, .slip, .reel, .cast, .bite, .pull: 8
        case .happy, .fishHappy, .bellyDown: 10
        case .slide: 16
        }
    }

    /// Whether it goes round and round, or is played once and held on its last frame.
    var loops: Bool {
        switch self {
        case .lookTurn, .lookBack, .happy, .getUp, .untuck, .reel, .bellyDown, .slip, .tuck, .cast, .pull, .gulp, .fishHappy: false
        default: true
        }
    }

    /// How far it goes in a frame, in points, when it goes somewhere: the waddle is small steps, and the slide is the quickest thing it does
    /// and, with the frames it is played at, about the cat's trot. Neither is more than a few points a frame, so a walk that is sent to the
    /// end of the lane ends on the step it was meant to (`CatField.leastEndError`).
    var advance: Double {
        switch self {
        case .waddle: 2
        case .slide: 3
        default: 0
        }
    }

    /// Time one pass through its frames takes.
    var passDuration: TimeInterval { Double(frameCount) / fps }

    /// How fast it goes, in points a second.
    var speed: Double { advance * fps }

    /// Where the hole in the ice is from where the penguin stands, in the picture's pixels: the line of its rod comes down into the middle of
    /// it. The hole is on the side the penguin faces, which is the right of the picture when it faces right and the left when it faces left.
    static let holeReach = 12.0
    /// The most a busy Mac quickens the waddle by: a clumsy bird in a bit of a hurry is still clumsy.
    static let busyBoost = 0.5
}

/// What the penguin has out, as a view knows it: the hole in the ice it fishes in. It is flat on the floor in front of it, drawn over the
/// penguin, so that its fishing line goes into it and not in front of it.
nonisolated enum PenguinProp: CaseIterable, Equatable, Sendable {
    /// The ice cracks open and the hole is there; it stands still; it ripples while the line is in it, is stirred up when a fish bites and
    /// splashes when it is pulled out; and it closes again, and then nothing.
    case holeOpening, holeStill, holeRippling, holeChurning, holeSplashing, holeClosing

    /// The pictures of it: the art makes exactly this many (tested), and the brain, which must not build the art to plan, counts on them.
    var frameCount: Int {
        switch self {
        case .holeStill: 1
        case .holeChurning: 2
        case .holeRippling: 3
        case .holeOpening, .holeSplashing: 4
        case .holeClosing: 5
        }
    }

    var fps: Double {
        switch self {
        case .holeStill: 1
        case .holeRippling: 2.5
        case .holeOpening, .holeClosing: 6
        case .holeChurning, .holeSplashing: 8
        }
    }

    /// Time one pass takes: what a hole that opens or closes takes, and the pose that shows it lasts.
    var passDuration: TimeInterval { Double(frameCount) / fps }

    /// Whether its pictures go round and round, or are played once and held on the last.
    var loops: Bool { self == .holeStill || self == .holeRippling || self == .holeChurning }

    var look: PropLook {
        PropLook(
            key: Self.allCases.firstIndex(of: self) ?? 0, fps: fps, rise: 0, animatesInPlace: self != .holeStill, loops: loops, occupies: true
        )
    }

    init(_ look: PropLook) {
        self = Self.allCases.indices.contains(look.key) ? Self.allCases[look.key] : .holeStill
    }
}
