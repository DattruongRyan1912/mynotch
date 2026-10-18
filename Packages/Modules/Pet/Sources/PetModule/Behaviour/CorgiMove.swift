import Foundation

/// What the corgi is doing, which is which of its animations is playing.
nonisolated enum CorgiMove: CaseIterable, Equatable, Sendable {
    // On its feet, side on, in one place or going somewhere. `trot` is its walk, `run` the zoomies (and the chase after the ball); `wiggle`
    // shakes its rear; `watch` is looking up at the ball as it falls and at where it goes; `spin` is the happy spin of a stroke.
    case stand, blink, trot, run, wiggle, watch, spin
    // With the ball: `grab` dips its head and takes it up in its mouth, `carry` trots with it, `lower` puts its head down to set it on the
    // floor (the same pictures as `grab`, backwards).
    case grab, carry, lower
    // Sitting, and sitting up to beg (`begUp`, `beg` with its paws together, `begDown`); `sitDown` and `standUp` get it there and back.
    case sitDown, standUp, sit, begUp, beg, begDown
    // Lying with its chin on its paws (`lieDown`, `lie`, `getUp`) and asleep on its side (`settle` onto it, `sleep`, `wake` from it).
    case lieDown, getUp, lie, settle, wake, sleep

    /// How the corgi is when it is doing this, and so what it has to do to get from one move to another.
    enum Stance: Equatable, Sendable {
        case standing, sitting, begging, lying, asleep
    }

    /// The stance the move is made in and, once through, ends in (a move that changes it ends in this).
    var stance: Stance {
        switch self {
        case .stand, .blink, .trot, .run, .wiggle, .watch, .spin, .grab, .carry, .lower, .standUp, .getUp: .standing
        case .sitDown, .sit, .begDown: .sitting
        case .begUp, .beg: .begging
        case .lieDown, .lie, .wake: .lying
        case .settle, .sleep: .asleep
        }
    }

    /// The frames of the move: the art makes exactly this many (tested), and the brain, which must not build the art to plan, counts on them.
    var frameCount: Int {
        switch self {
        case .blink: 1
        case .lie: 2
        case .sitDown, .standUp, .begUp, .begDown, .settle, .wake: 3
        case .stand, .watch, .grab, .lower, .sit, .beg, .lieDown, .getUp, .sleep: 4
        case .trot, .run, .carry, .wiggle: 6
        case .spin: 9
        }
    }

    /// Frames a second at the move's own pace.
    var fps: Double {
        switch self {
        case .sit, .lie, .sleep: 2
        case .stand, .watch: 3
        case .blink, .beg, .settle, .wake: 4
        case .lieDown, .getUp: 6
        case .grab, .lower, .sitDown, .standUp, .begUp, .begDown: 8
        case .trot, .carry, .wiggle, .spin: 12
        case .run: 16
        }
    }

    /// Whether it goes round and round, or is played once and held on its last frame.
    var loops: Bool {
        switch self {
        case .spin, .grab, .lower, .sitDown, .standUp, .begUp, .begDown, .lieDown, .getUp, .settle, .wake: false
        default: true
        }
    }

    /// How far it goes in a frame, in points, when it goes somewhere. The run is the quickest thing it does and no more than the cat's
    /// frantic one: a walk that is sent to a place ends on a whole step, and half of one has to be less than `CatField.leastEndError`.
    var advance: Double {
        switch self {
        case .trot, .carry: 3
        case .run: 5
        default: 0
        }
    }

    /// Time one pass through its frames takes.
    var passDuration: TimeInterval { Double(frameCount) / fps }

    /// How fast it goes, in points a second.
    var speed: Double { advance * fps }

    /// How many pixels the ball is, on the picture of the corgi as it stands over it, from where the corgi's picture begins to where the
    /// ball's does, when the corgi stands at the ball with its nose over it (the other way round when it faces left): the ball's picture is a
    /// whole picture like its own, and the ball is in the middle of it.
    static let ballReach = 9.0
}

/// What the corgi plays with, as a view knows it: a ball, a whole picture of 32 by 24 like the corgi's with the ball in the middle of it, so
/// that it is the same size as everything else on the lane. It falls in from above the strip and bounces and rolls, lies, is set down and
/// bounces a little, and is taken up out of sight; the bounces are in its pictures, and the roll across the lane is the prop's path. While the
/// corgi has it in its mouth (which is in the corgi's own pictures) the ball is a picture with nothing in it, which is still a prop: it
/// holds the room the ball will be set down in, so that nobody sets up a wheel or a tub there while the corgi trots back.
nonisolated enum CorgiProp: CaseIterable, Equatable, Sendable {
    case ballToss, ballRest, ballDrop, ballUp, ballHeld

    /// The pictures of it: the art makes exactly this many (tested), and the brain, which must not build the art to plan, counts on them.
    var frameCount: Int {
        switch self {
        case .ballRest, .ballHeld: 1
        case .ballDrop: 5
        case .ballUp: 6
        case .ballToss: 14
        }
    }

    var fps: Double {
        switch self {
        case .ballRest, .ballHeld: 1
        case .ballDrop: 10
        case .ballUp, .ballToss: 12
        }
    }

    /// Time one pass takes: what the pose that shows it lasts.
    var passDuration: TimeInterval { Double(frameCount) / fps }

    /// Whether its pictures go round and round, or are played once and held on the last.
    var loops: Bool { self == .ballRest || self == .ballHeld }

    var look: PropLook {
        PropLook(key: Self.allCases.firstIndex(of: self) ?? 0, fps: fps, rise: 0, animatesInPlace: self != .ballRest && self != .ballHeld, loops: loops, occupies: true)
    }

    init(_ look: PropLook) {
        self = Self.allCases.indices.contains(look.key) ? Self.allCases[look.key] : .ballRest
    }
}
