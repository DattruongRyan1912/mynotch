import Foundation

/// What the capybara is doing, which is which of its animations is playing.
nonisolated enum CapybaraMove: CaseIterable, Equatable, Sendable {
    // Side on, sitting, in one place.
    case sit, blink, doze, hold, peel, chew, happy, sweat, turn, watch, turnBack
    // Lying down, and getting there and back.
    case lie, sleep, lieDown, sitUp
    // On its feet, going somewhere or about to.
    case walk, sitDown, standUp
    // In and out of the tub, and in it.
    case climbIn, climbOut, soak, soakOrange, soakHappy
    // Sinking in the tub until only its eyes are above the water, so that there is room over its head for a frog to sit on it; there; and
    // coming up again. (Appended: the numbers the views know the moves by are their places in this list.)
    case soakSink, soakDeep, soakRise

    /// How the capybara is when it is doing this, and so what it has to do to get from one move to another.
    enum Stance: Equatable, Sendable {
        case standing, seated, lying, soaking
    }

    /// The stance the move is made in and, once through, ends in.
    var stance: Stance {
        switch self {
        case .sit, .blink, .doze, .hold, .peel, .chew, .happy, .sweat, .turn, .watch, .turnBack, .sitDown, .sitUp: .seated
        case .lie, .sleep, .lieDown: .lying
        case .walk, .standUp, .climbOut: .standing
        case .soak, .soakOrange, .soakHappy, .climbIn, .soakSink, .soakDeep, .soakRise: .soaking
        }
    }

    /// The frames of the move: the art makes exactly this many (tested), and the brain, which must not build the art to plan, counts on them.
    var frameCount: Int {
        switch self {
        case .sit: 4
        case .blink, .watch: 1
        case .doze: 8
        case .hold: 2
        case .peel, .chew, .happy, .sweat, .sleep, .lieDown, .sitUp, .sitDown, .standUp, .soak, .soakOrange, .soakHappy, .soakSink, .soakDeep,
             .soakRise: 4
        case .turn, .turnBack: 3
        case .lie: 2
        case .walk, .climbIn, .climbOut: 6
        }
    }

    /// Frames a second at the move's own pace: a capybara takes its time.
    var fps: Double {
        switch self {
        case .sit, .lie, .sleep, .soak, .soakOrange, .soakDeep, .hold, .watch: 2
        case .blink, .turn, .turnBack, .doze: 3
        case .peel, .chew, .happy, .sweat, .soakHappy: 4
        case .lieDown, .sitUp, .sitDown, .standUp: 5
        case .climbIn, .climbOut, .soakSink, .soakRise: 6
        case .walk: 8
        }
    }

    /// Whether it goes round and round, or is played once and held on its last frame.
    var loops: Bool {
        switch self {
        case .lieDown, .sitUp, .sitDown, .standUp, .turn, .turnBack, .climbIn, .climbOut, .soakSink, .soakRise: false
        default: true
        }
    }

    /// How far it goes in a frame, in points, when it goes somewhere: slowly.
    var advance: Double {
        switch self {
        case .walk: 1
        default: 0
        }
    }

    /// Time one pass through its frames takes.
    var passDuration: TimeInterval { Double(frameCount) / fps }

    /// How fast it goes, in points a second.
    var speed: Double { advance * fps }

    /// Where on its back something can sit: a capybara has a back to give only when it is sitting or in its tub, and holds still.
    var givesPerch: Bool {
        switch self {
        case .sit, .blink, .soak, .soakOrange: true
        default: false
        }
    }

    /// Where on it something can sit, if it can: on its back while it sits or soaks, and on its head when it has sunk down in the tub.
    var perchSpot: Perch.Spot? {
        if self == .soakDeep { return .head }
        return givesPerch ? .back : nil
    }

    /// How far it goes in the hop into the tub or out of it, in the picture's pixels: the tub is this far from where it hops from. It is
    /// what makes the hop's steps whole (six frames of a second, four pixels each).
    static let hopSpan = 24.0
    /// How far, in pixels, the picture of what sits on its back is from its own: not at all (see `CapybaraArt.perchShift`).
    static let perchShift = 0.0
    /// Where an orange it is to eat is put down, from the left of its picture, in pixels: just in front of its snout, which is the right
    /// of the picture when it faces right and the left when it faces left; and the peel it leaves, nearer.
    static let orangeReach = (right: 27.0, left: -6.0)
    static let peelReach = (right: 22.0, left: -2.0)
}
