import Foundation

/// What the frog is doing, which is which of its animations is playing.
nonisolated enum FrogMove: CaseIterable, Equatable, Sendable {
    // On the ground, side on, in one place or going somewhere. `hop` is how it gets about (one leg of it is a run of hops, a single looping
    // move so that the camera's portal sees one walk); `blink` is a slow one; `puff` blows its throat out and lets it go; `watch` is sitting
    // up with its eyes on something (the pointer, a moth), and `flick` is its tongue going out towards the pointer and back; `jump` is the
    // happy hop in place of a stroke.
    case sit, blink, puff, hop, watch, flick, jump
    // Catching a moth: the tongue shoots out to it, comes back with it, and the frog gulps.
    case snapOut, snapIn, gulp
    // Asleep on the ground, which is where it sleeps only when there is no room for a lily pad.
    case sleep
    // `hopOn` is the hop from the bank onto the lily pad and `hopOff` the hop back; on the pad it does what it does on the ground (the same
    // pictures, a few rows higher), and sleeps there.
    case hopOn, hopOff, padSit, padBlink, padPuff, padWatch, padFlick, padJump, padSleep

    /// Where the frog is when it is doing this, and so what it has to do to get from one move to another.
    enum Stance: Equatable, Sendable {
        case ground, pad
    }

    /// The stance the move is made in and, once through, ends in (a move that changes it ends in this).
    var stance: Stance {
        switch self {
        case .sit, .blink, .puff, .hop, .watch, .flick, .jump, .snapOut, .snapIn, .gulp, .sleep, .hopOff: .ground
        case .hopOn, .padSit, .padBlink, .padPuff, .padWatch, .padFlick, .padJump, .padSleep: .pad
        }
    }

    /// The same move on the other footing, where there is one: the move the art draws a few rows higher for the pad.
    var onTheGround: FrogMove {
        switch self {
        case .padSit: .sit
        case .padBlink: .blink
        case .padPuff: .puff
        case .padWatch: .watch
        case .padFlick: .flick
        case .padJump: .jump
        case .padSleep: .sleep
        default: self
        }
    }

    /// The frames of the move: the art makes exactly this many (tested), and the brain, which must not build the art to plan, counts on them.
    var frameCount: Int {
        switch self.onTheGround {
        case .watch: 2
        case .snapIn: 3
        case .sit, .blink, .snapOut, .sleep: 4
        case .flick: 5
        case .puff, .hop, .gulp, .hopOn, .hopOff: 6
        case .jump: 8
        default: 4
        }
    }

    /// Frames a second at the move's own pace.
    var fps: Double {
        switch self.onTheGround {
        case .sit, .sleep: 2
        case .watch: 2.5
        case .blink: 4
        case .puff, .gulp: 6
        case .hop, .jump, .hopOn, .hopOff: 8
        case .snapIn: 12
        case .flick: 14
        case .snapOut: 16
        default: 4
        }
    }

    /// Whether it goes round and round, or is played once and held on its last frame.
    var loops: Bool {
        switch self.onTheGround {
        case .sit, .hop, .watch, .sleep: true
        default: false
        }
    }

    /// How far it goes in a frame, in points, when it goes somewhere: a hop is three a frame, which is a leg of eighteen to a hop of six
    /// frames. Half a step has to be less than `CatField.leastEndError`. The hop on to the pad and off it is `hopSpan` in one pass of its
    /// frames, and is not this.
    var advance: Double { self == .hop ? 3 : 0 }

    /// Time one pass through its frames takes.
    var passDuration: TimeInterval { Double(frameCount) / fps }

    /// How fast it goes, in points a second.
    var speed: Double { advance * fps }

    /// How far a hop goes, in points: the cycle of its frames, which a leg is a whole number of, so that it ends on a landing.
    static let hopLength = FrogMove.hop.advance * Double(FrogMove.hop.frameCount)

    /// How far the lily pad is from where the frog hops from, in the picture's pixels: the hop on to it and the hop off it. Whole steps of the
    /// hop's frames (six in three quarters of a second, four pixels each).
    static let hopSpan = 24.0

    /// Where the moth hovers, from the left of the frog's picture, in pixels: at the tip of its tongue, which is the right of the picture
    /// when it faces right and the left when it faces left (the moth's picture is 11 across).
    static let mothReach = (right: 25.0, left: -4.0)
}

/// What the frog plays with, as a view knows it: a lily pad on a line of water, a whole picture of 32 by 24 like the frog's (it is drawn
/// over the frog, so the frog on it is drawn a few rows higher and nothing of the pad lands on it); and the moth, which is the cat's.
/// The pad rises out of the water, stands and ripples, takes the frog's weight and gives it back, and sinks again, and then there is nothing.
nonisolated enum FrogProp: CaseIterable, Equatable, Sendable {
    case padAppearing, padStill, padRippling, padLanding, padLeaping, padSinking
    /// The cat's moth, as it flies in and hovers, and held still for the tongue (a moth that bobs would not be where the tongue tip lands).
    case moth, mothHeld

    /// The pictures of it: the art makes exactly this many (tested), and the brain, which must not build the art to plan, counts on them.
    /// (The moth's are the cat's two.)
    var frameCount: Int {
        switch self {
        case .padStill: 1
        case .padRippling: 3
        case .padAppearing: 4
        case .padSinking: 5
        case .padLanding, .padLeaping: 6
        case .moth, .mothHeld: 2
        }
    }

    var fps: Double {
        switch self {
        case .padStill: 1
        case .padRippling: 2.5
        case .padAppearing, .padSinking: 6
        case .padLanding, .padLeaping: 8
        case .moth, .mothHeld: PropArt.moth.fps
        }
    }

    /// Time one pass takes: what the pose that shows it lasts.
    var passDuration: TimeInterval { Double(frameCount) / fps }

    var isMoth: Bool { self == .moth || self == .mothHeld }

    var isPad: Bool { !isMoth }

    /// Whether its pictures go round and round, or are played once and held on the last.
    var loops: Bool {
        switch self {
        case .padStill, .padRippling, .moth, .mothHeld: true
        default: false
        }
    }

    /// How high above the frog's feet the moth hovers, in points of the picture: the middle of it is at the tongue's tip. A moth that is
    /// held is where the middle of its bobbing is.
    static let mothRise = 5.0

    var look: PropLook {
        let key = Self.allCases.firstIndex(of: self) ?? 0
        switch self {
        case .moth: return PropLook(key: key, fps: fps, flutters: true, rise: Self.mothRise, animatesInPlace: true)
        case .mothHeld: return PropLook(key: key, fps: fps, rise: Self.mothRise + 2, animatesInPlace: true)
        default: return PropLook(key: key, fps: fps, animatesInPlace: self != .padStill, loops: loops, occupies: true)
        }
    }

    init(_ look: PropLook) {
        self = Self.allCases.indices.contains(look.key) ? Self.allCases[look.key] : .padStill
    }
}
