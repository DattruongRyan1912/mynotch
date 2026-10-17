import Foundation

nonisolated enum Facing: Equatable, Sendable {
    case left, right
}

/// Where the pointer is, as the cat sees it. Nil in the senses when it is too far to matter.
nonisolated struct PointerReading: Equatable, Sendable {
    /// Where along the strip the pointer is, as a share of the cat's lane (0 left, 1 right), not held to the lane: a pointer past the end
    /// of it is below 0 or above 1.
    var share: Double
    /// Close to the strip: the cat pounces.
    var isNear: Bool
    /// Within sight of it: the cat looks.
    var isInRange: Bool
    /// Above the strip (in the menu bar), not below it.
    var isAbove: Bool

    init(share: Double, isNear: Bool, isInRange: Bool, isAbove: Bool = true) {
        self.share = share
        self.isNear = isNear
        self.isInRange = isInRange || isNear
        self.isAbove = isAbove
    }
}

/// What the cat can tell about the world, read while it is on the notch and never otherwise.
nonisolated struct CatSenses: Equatable, Sendable {
    /// Seconds since the user last touched the keyboard or the pointer.
    var idleSeconds: TimeInterval = 0
    /// How busy the processors are, 0 to 1, as of the last second: what a busy Mac does to the cat's mood and pace.
    var cpuLoad: Double = 0
    /// The Mac is busy by its own standards: a load clearly over what it usually is, held for some seconds, and not for long (`BusyWatch`).
    /// This, and not the load, is what makes the cat run.
    var busyBurst = false
    var pointer: PointerReading?
    /// The Mac is playing sound.
    var audioPlaying = false
    /// The hour of the day, 0 to 23.
    var hour = 12

    var pointerNear: Bool { pointer?.isNear ?? false }
}

/// What the user chose, and the rules of the cat's day.
nonisolated struct CatTuning: Equatable, Sendable {
    /// Idle time after which the cat falls asleep, in the daytime.
    var sleepAfter: TimeInterval = 300
    /// Whether a busy Mac has any effect on the cat: the burst of running, and the quicker walks and the sweat that go with a high load.
    var reactsToBusyMachine = true
    /// At night it nods off in this share of that time.
    static let nightSleepFactor = 0.3
    /// Never sooner than this, so a short setting at night is not a cat that sleeps through a pause for thought.
    static let shortestSleepAfter: TimeInterval = 30

    static func isNight(hour: Int) -> Bool { hour >= 22 || hour < 6 }

    func sleepThreshold(hour: Int) -> TimeInterval {
        Self.isNight(hour: hour) ? max(sleepAfter * Self.nightSleepFactor, Self.shortestSleepAfter) : sleepAfter
    }
}

nonisolated enum PropKind: Equatable, Sendable {
    /// A moth that flutters along the strip.
    case moth
    /// A ball of yarn that lies, or rolls.
    case yarn
}

/// Something on the strip with the cat. Where it is, as a share of the lane like the cat's own places (a moth that leaves goes past 0 or 1),
/// at the start and at the end of the plan; the yarn rolls when those differ and lies still when they do not.
nonisolated struct CatProp: Equatable, Sendable {
    var kind: PropKind
    var from: Double
    var to: Double
}

/// How the cat moves about its lane: where it is in it, as a share of the way from one end to the other (0 left, 1 right), so that a cat
/// on two displays whose lanes are not the same length is at the same place in both.
nonisolated struct CatPlan: Equatable, Sendable {
    var move: CatMove
    var facing: Facing
    var from: Double
    var to: Double
    /// When the plan began, on the brain's clock, in seconds.
    var began: TimeInterval
    var duration: TimeInterval
    /// How much faster than its animation's own pace the frames play (a cat that runs harder).
    var fpsScale: Double = 1
    /// The share of the plan that goes by before the cat starts to go anywhere: the crouch before a pounce.
    var delay: Double = 0
    var prop: CatProp?

    var end: TimeInterval { began + duration }

    /// How the plan is going at `now`, 0 to 1.
    func progress(at now: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(max((now - began) / duration, 0), 1)
    }

    /// Where the cat is at `now`: it stays where it began for the plan's delay, goes to where it is going at an even pace, and stays there.
    func position(at now: TimeInterval) -> Double {
        guard to != from else { return to }
        let moving = (progress(at: now) - delay) / max(1 - delay, 0.0001)
        return from + (to - from) * min(max(moving, 0), 1)
    }

    /// Where the prop is at `now`: it goes along its own path at an even pace over the plan.
    func propPosition(at now: TimeInterval) -> Double? {
        prop.map { $0.from + ($0.to - $0.from) * progress(at: now) }
    }

    /// Whether a host that shows `other` has to change anything to show this: the time it began does not show, and how long a plan lasts
    /// shows only in how fast things go across the lane, so a cat that sits for a second longer is still the same picture.
    func looksLike(_ other: CatPlan) -> Bool {
        // A move that is played once is played again, so one that follows itself is a picture to start over.
        guard move.loops, move == other.move, facing == other.facing, from == other.from, to == other.to, fpsScale == other.fpsScale,
              delay == other.delay, prop == other.prop else { return false }
        return (from == to && prop?.from == prop?.to) || duration == other.duration
    }
}

/// A small generator that gives the same numbers for the same seed, so the cat's whims can be tested.
nonisolated struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
