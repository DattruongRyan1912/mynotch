import Foundation

/// Which part of a joint scene a character plays.
nonisolated enum JointRole: Equatable, Sendable {
    /// The one that is played with: it holds still, in a pose that gives something to play on, until the scene is over.
    case host
    /// The one that comes to it, does the scene and goes.
    case guest
}

/// A scene played by two characters of two kinds together, in one lane: the host holds still and the guest does the scene on it or by it.
/// The stage's `JointDirector` begins one now and then between characters that share a screen, and ends it when either is done or gone;
/// what each does in it is its brain's own business (`CharacterBrain.join`).
///
/// To add a pairing: a case in `ID`, a line in `all`, and in each of the two brains what it does for that scene (the host's pose has to
/// give what the guest needs, see `Pose.perch`). Nothing in the stage is about one scene or another. The capybara is the host of all of
/// them, and `JointRoom` is how a guest finds where to be by it and where to go when it is over.
nonisolated struct JointScene: Hashable, Sendable {
    nonisolated enum ID: Hashable, Sendable {
        /// The cat walks to the capybara while it sits or soaks, hops on, sits or loafs on its back for a while and hops off.
        case catOnCapybara
        /// The capybara sinks in its tub until only its eyes are above the water, the frog hops on to its head, sits there a while, and
        /// hops off, and the capybara comes up.
        case frogOnHead
        /// The hamster scurries behind the capybara, which hides it but for its head, peeks out, and scurries away.
        case hamsterBehind
        /// The hamster scurries up to the capybara, curls into a ball against its side and sleeps a while, and scurries away.
        case hamsterNap
        /// The penguin slides up to the capybara on its belly and stands by it a while, both looking the same way, and waddles off.
        case penguinBeside
        /// The corgi trots up to the capybara, with a wiggle perhaps, lies down by it with its chin on its paws a while, and trots off.
        case corgiBeside
    }

    let id: ID
    let host: CharacterKind
    let guest: CharacterKind

    static let catOnCapybara = JointScene(id: .catOnCapybara, host: .capybara, guest: .cat)
    static let frogOnHead = JointScene(id: .frogOnHead, host: .capybara, guest: .frog)
    static let hamsterBehind = JointScene(id: .hamsterBehind, host: .capybara, guest: .hamster)
    static let hamsterNap = JointScene(id: .hamsterNap, host: .capybara, guest: .hamster)
    static let penguinBeside = JointScene(id: .penguinBeside, host: .capybara, guest: .penguin)
    static let corgiBeside = JointScene(id: .corgiBeside, host: .capybara, guest: .corgi)

    /// Every scene there is, in the order they are looked for.
    static let all: [JointScene] = [.catOnCapybara, .frogOnHead, .hamsterBehind, .hamsterNap, .penguinBeside, .corgiBeside]
}

/// What a brain is asked to take part in.
nonisolated struct JointInvite: Equatable, Sendable {
    var scene: JointScene.ID
    /// The part it is asked to play.
    var role: JointRole
    /// The other character, as it stands.
    var partner: Pose
    /// The lane as it is for this one once the scene has begun, which is not what it is before: what the two owe each other is not asked
    /// of them in it (`LaneRules`), so a place beside the host that was in its way is not.
    var lane = LaneContext()
}

/// What a brain in a scene is told about the other at every update.
nonisolated struct JointSight: Equatable, Sendable {
    var scene: JointScene.ID
    /// The part this brain plays.
    var role: JointRole
    /// The other character's pose.
    var partner: Pose
}
