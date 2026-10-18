import Foundation

/// The characters the user can put on a screen. A new one is a new case here, a `Species` (see `Species.swift`) and one line in
/// `species`: nothing in the stage, the views or the settings is about one kind or another.
nonisolated enum CharacterKind: String, CaseIterable, Codable, Sendable {
    case cat
    case capybara
    case hamster
    case penguin
    case corgi
    case frog

    /// The most characters one screen has: the room to play in is two wings of 100 points, or a pill of 280.
    static let maxPerScreen = 3

    /// What the settings call it.
    var displayName: String {
        switch self {
        case .cat: "Mèo"
        case .capybara: "Capybara"
        case .hamster: "Hamster"
        case .penguin: "Chim cánh cụt"
        case .corgi: "Corgi"
        case .frog: "Ếch"
        }
    }
}

// MARK: What a brain tells a view

/// One of a species' animations, as a view needs to know it: which strip to play (`key` is the species' own number for it), how fast, and
/// whether it goes round or is played once and held.
nonisolated struct Motion: Hashable, Sendable {
    var key: Int
    var fps: Double
    var loops: Bool
    /// A head that peeks from below the edge of the lane: the bottom of its picture is cut off by the lane's floor.
    var sinks = false
}

/// What a character plays with, as a view needs to know it.
nonisolated struct PropLook: Hashable, Sendable {
    var key: Int
    var fps: Double
    /// It bobs up and down as it goes (a moth).
    var flutters = false
    /// How far above the character's feet it is, in points of the picture (a moth flutters above the lane's floor).
    var rise = 0.0
    /// Its pictures play while it stays where it is (a moth), and not only while it moves (a ball of yarn).
    var animatesInPlace = false
    /// Its pictures go round and round while it plays (a moth), or are played once and held on the last (a tub that comes up out of the
    /// floor).
    var loops = true
    /// It takes up room that another character does not stop in (a tub the capybara sits in), as a character that stands there would.
    var occupies = false
}

/// A place on a character where another can sit: how far, in pixels of the picture, the rider's picture is from this one's, left edge to
/// left edge, for the way this one faces now.
nonisolated struct Perch: Equatable, Sendable {
    /// Where on it the rider sits.
    nonisolated enum Spot: Equatable, Sendable {
        case back
        /// The top of the head, which a capybara has to be low in the water to give: there is no room above it in the picture otherwise.
        case head
    }

    var dx: Double
    var spot = Spot.back
}

/// Something with the character on the lane. Where it is, as a share of the lane like the character's own places (one that leaves goes
/// past 0 or 1), at the start and at the end of the pose; it moves when those differ.
nonisolated struct PoseProp: Equatable, Sendable {
    var look: PropLook
    var from: Double
    var to: Double
    /// Other places, shares of the lane, that go with it and take up room that others do not stop in, if it does (the place the capybara
    /// hops into its tub from, which it hops back to).
    var alsoAt: [Double] = []
}

/// How a character moves about its lane, as a view and the stage see it, whatever its species: where it is in the lane, as a share of the
/// way from one end to the other (0 left, 1 right), so that a character on two displays whose lanes are not the same length is at the
/// same place in both.
nonisolated struct Pose: Equatable, Sendable {
    var motion: Motion
    var facing: Facing
    var from: Double
    var to: Double
    /// When it began, on the brain's clock, in seconds.
    var began: TimeInterval
    var duration: TimeInterval
    /// How much faster than its animation's own pace the frames play.
    var fpsScale = 1.0
    /// The share of the pose that goes by before the character starts to go anywhere (the crouch before a pounce).
    var delay = 0.0
    var prop: PoseProp?
    /// Where another character can sit on it, while it is in a pose that holds still for that (a capybara sitting or in its tub).
    var perch: Perch?
    /// Drawn over the characters that are not: one that sits on another is not behind it.
    var raised = false
    /// Drawn under the characters that are not: one that hides behind another (the hamster behind the capybara) is hidden by it.
    var behind = false
    /// Places, as shares of the lane, that nobody else stops in or sets up a prop in while it is in this pose, for where it is going to be
    /// next (a guest in a scene with the capybara: the place it goes to when it is done, which has to be free when it gets there).
    var reserves: [Double] = []

    var end: TimeInterval { began + duration }

    /// Whether a view that shows `other` has to change anything to show this, which is what a brain tells with `.extended`: the time it
    /// began does not show, and how long a pose lasts shows only in how fast things go across the lane, so a character that sits for a
    /// second longer is still the same picture. A move that is played once is played again, so one that follows itself is a picture to
    /// start over.
    func looksLike(_ other: Pose) -> Bool {
        guard motion.loops, motion == other.motion, facing == other.facing, from == other.from, to == other.to, fpsScale == other.fpsScale,
              delay == other.delay, prop == other.prop, perch == other.perch, raised == other.raised, behind == other.behind else { return false }
        return (from == to && prop?.from == prop?.to) || duration == other.duration
    }

    /// Where the character is at `now`: it stays where it began for the pose's delay, goes to where it is going at an even pace, and
    /// stays there.
    func position(at now: TimeInterval) -> Double {
        guard to != from, duration > 0 else { return to }
        let progress = min(max((now - began) / duration, 0), 1)
        let moving = (progress - delay) / max(1 - delay, 0.0001)
        return from + (to - from) * min(max(moving, 0), 1)
    }
}

/// What the user chose that changes how a character looks.
nonisolated struct Appearance: Equatable, Sendable {
    var coat = CatCoat.tabby
}

// MARK: What a stage tells a brain

/// What a character has to keep to in a lane it shares: the stretches of it, as shares of the lane, that its brain plans around.
nonisolated struct LaneContext: Equatable, Sendable {
    /// The camera's crossing, where it is part in one view and part in another: it goes through and never stops in it, and is not
    /// interrupted on the way.
    var crossing: [ClosedRange<Double>] = []
    /// Where another character stands: it may walk through, never stop in it.
    var zones: [ClosedRange<Double>] = []
    /// Where it may not go at all (the crossing, while another character is in it): a walk that would go through is held at the edge.
    var closed: [ClosedRange<Double>] = []

    /// The joint scene it is in with another character, and where the other is: nil for a character that is not in one.
    var joint: JointSight?

    var isEmpty: Bool { crossing.isEmpty && zones.isEmpty && closed.isEmpty && joint == nil }
}

/// What an update did to a character's pose.
nonisolated enum BrainOutcome: Equatable, Sendable {
    /// Nothing came due.
    case unchanged
    /// A new pose that looks like the one before it (a cat that goes on sleeping): a view has nothing to redraw.
    case extended
    /// A different picture: a view starts the new animation.
    case changed
}

/// What decides what one character does. A value that holds no timer and reads nothing: it is told the time and what the character senses,
/// and says whether the picture changed, so every rule of its day is a test with a made-up clock.
nonisolated protocol CharacterBrain: Sendable {
    /// What the character is doing now.
    var pose: Pose { get }

    /// Advances the character to `now`. `travel` is how far, in points of its picture's pixels, it can walk along the lane.
    mutating func update(now: TimeInterval, senses: CatSenses, tuning: CatTuning, travel: Double, lane: LaneContext) -> BrainOutcome

    /// The lane it plays in changed under it (views came or went, the notch moved): where it must not stop is not what it was.
    mutating func settle(lane: LaneContext)

    /// The character is back on a notch after being out of sight: where it was, at rest, and nothing it last saw is news.
    mutating func resume(now: TimeInterval)

    /// A stroke.
    mutating func pet(now: TimeInterval) -> BrainOutcome

    // MARK: Playing together (see `JointScene`)

    /// The scene it is in with another character, nil when it is in none. A brain that is frightened out of a scene, or has finished its
    /// part, says nil, and the stage then ends the other's.
    var jointScene: JointScene.ID? { get }

    /// Whether it would take this part now: calm, and in a state the scene can begin from.
    func canJoin(_ invite: JointInvite, now: TimeInterval) -> Bool

    /// Takes the part. Only called after `canJoin` said yes.
    mutating func join(_ invite: JointInvite, now: TimeInterval)

    /// Leaves the scene it is in, cleanly, wherever it stands: the other went, or the scene is over. A character that sits on another
    /// comes down, and one that is sat on goes on with its day.
    mutating func leaveJoint(now: TimeInterval) -> BrainOutcome
}

/// Most characters play no joint scene at all, and a character that does only takes its part in the ones it knows.
nonisolated extension CharacterBrain {
    var jointScene: JointScene.ID? { nil }
    func canJoin(_ invite: JointInvite, now: TimeInterval) -> Bool { false }
    mutating func join(_ invite: JointInvite, now: TimeInterval) {}
    mutating func leaveJoint(now: TimeInterval) -> BrainOutcome { .unchanged }
}
