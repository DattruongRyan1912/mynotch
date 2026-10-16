import Foundation

/// What the cat is doing, which is which of its animations is playing.
nonisolated enum CatMove: CaseIterable, Equatable, Sendable {
    // Facing the viewer, in one place.
    case sit, blink, tailSwish, groom, scratch, lookLeft, lookRight, lookUp, yawn, purr, dance, sleep, loaf
    // Changing between the ways of being in one place, once through.
    case lieDown, sitDown, standUp
    // Side on, on its feet, going somewhere or about to.
    case walk, trot, frantic, chase, pounce, stretch, yarn, startled
    // Only its head, from below the edge of the strip.
    case peek

    /// How the cat is when it is doing this, and so what it has to do to get from one move to another: a cat does not walk from a nap.
    enum Stance: Equatable, Sendable {
        case seated, lying, standing
    }

    /// The stance the move is made in and, once through, ends in; nil for a move that is made from any.
    var stance: Stance? {
        switch self {
        case .sit, .blink, .tailSwish, .groom, .scratch, .lookLeft, .lookRight, .lookUp, .yawn, .purr, .dance, .sitDown: .seated
        case .sleep, .loaf, .lieDown: .lying
        case .walk, .trot, .frantic, .chase, .pounce, .stretch, .yarn, .startled, .standUp: .standing
        case .peek: nil
        }
    }

    /// The frames of the move: the art makes exactly this many (tested), and the brain, which must not build the art to plan, counts on them.
    var frameCount: Int {
        switch self {
        case .sit: 4
        case .blink, .lookLeft, .lookRight, .lookUp: 1
        case .tailSwish, .groom, .scratch, .dance, .trot, .frantic, .chase, .stretch, .yarn: 6
        case .yawn, .purr, .sleep, .lieDown, .sitDown, .standUp, .peek, .startled: 4
        case .loaf: 2
        case .walk, .pounce: 8
        }
    }

    /// Frames a second at the move's own pace.
    var fps: Double {
        switch self {
        case .sit, .sleep, .loaf, .lookLeft, .lookRight, .lookUp: 2
        case .blink: 4
        case .yawn, .peek: 5
        case .groom, .purr, .lieDown, .sitDown, .standUp, .stretch: 6
        case .tailSwish, .scratch, .dance, .startled: 8
        case .pounce, .yarn: 10
        case .walk, .trot, .chase, .frantic: 12
        }
    }

    /// Whether it goes round and round, or is played once and held on its last frame.
    var loops: Bool {
        switch self {
        case .yawn, .lieDown, .sitDown, .standUp, .pounce, .stretch, .peek, .startled: false
        default: true
        }
    }

    /// How far it goes in a frame, in points, when it goes somewhere.
    var advance: Double {
        switch self {
        case .walk: 2
        case .trot: 4
        case .chase: 5
        case .frantic: 6
        default: 0
        }
    }

    /// Time one pass through its frames takes.
    var passDuration: TimeInterval { Double(frameCount) / fps }

    /// How fast it goes, in points a second.
    var speed: Double { advance * fps }
}
