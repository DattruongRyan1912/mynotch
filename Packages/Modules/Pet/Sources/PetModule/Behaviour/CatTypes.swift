import Foundation

/// What the cat is doing, which is which of its animations is playing.
nonisolated enum CatPose: CaseIterable, Equatable, Sendable {
    case sit, blink, walk, run, lick, yawn, sleep, startled, dance, purr
}

nonisolated enum Facing: Equatable, Sendable {
    case left, right
}

/// What the cat can tell about the world, read while it is on the notch and never otherwise.
nonisolated struct CatSenses: Equatable, Sendable {
    /// Seconds since the user last touched the keyboard or the pointer.
    var idleSeconds: TimeInterval = 0
    /// How busy the processors are, 0 to 1.
    var cpuLoad: Double = 0
    /// The pointer is close to the notch.
    var pointerNear = false
    /// The Mac is playing sound.
    var audioPlaying = false
    /// The hour of the day, 0 to 23.
    var hour = 12
}

/// What the user chose, and the rules of the cat's day.
nonisolated struct CatTuning: Equatable, Sendable {
    /// Idle time after which the cat falls asleep, in the daytime.
    var sleepAfter: TimeInterval = 300
    /// At night it nods off in this share of that time.
    static let nightSleepFactor = 0.3
    /// Never sooner than this, so a short setting at night is not a cat that sleeps through a pause for thought.
    static let shortestSleepAfter: TimeInterval = 30

    static func isNight(hour: Int) -> Bool { hour >= 22 || hour < 6 }

    func sleepThreshold(hour: Int) -> TimeInterval {
        Self.isNight(hour: hour) ? max(sleepAfter * Self.nightSleepFactor, Self.shortestSleepAfter) : sleepAfter
    }
}

/// How the cat moves about its lane: where it is in it, as a share of the way from one end to the other (0 left, 1 right), so that a
/// cat on two displays whose lanes are not the same length is at the same place in both.
nonisolated struct CatPlan: Equatable, Sendable {
    var pose: CatPose
    var facing: Facing
    var from: Double
    var to: Double
    /// When the plan began, on the brain's clock, in seconds.
    var began: TimeInterval
    var duration: TimeInterval
    /// How much faster than its animation's own pace the frames play (a cat that runs harder).
    var fpsScale: Double = 1

    var end: TimeInterval { began + duration }

    /// Where the cat is at `now`: it goes from `from` to `to` at an even pace over the plan, and stays where it got to after it.
    func position(at now: TimeInterval) -> Double {
        guard to != from, duration > 0 else { return to }
        let progress = min(max((now - began) / duration, 0), 1)
        return from + (to - from) * progress
    }

    /// Whether a host that shows `other` has to change anything to show this: the time it began does not show, and how long a plan lasts
    /// shows only in how fast the cat crosses its lane, so a cat that sits for a second longer is still the same picture.
    func looksLike(_ other: CatPlan) -> Bool {
        guard pose == other.pose, facing == other.facing, from == other.from, to == other.to, fpsScale == other.fpsScale else { return false }
        return from == to || duration == other.duration
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
