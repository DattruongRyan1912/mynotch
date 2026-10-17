import Foundation

/// Begins joint scenes between the characters of one stage, now and then, and ends them: when either of the two is done, or gone, or has
/// been touched, or when they have gone on too long. At most one at a time, never sooner than a few minutes after the last, and only
/// between two characters that share the stage and that both say they are ready for it.
///
/// It draws from a stream of its own, and only while there are two characters that make a pair on the stage, so a stage that has none
/// plays no differently for it. What each does in a scene is its brain's own business (`CharacterBrain.join`); the director only asks,
/// and tells them when it is over.
nonisolated struct JointDirector: Sendable {
    /// A scene in progress: who plays which part (their numbers on the stage) and when it began.
    struct Play: Equatable, Sendable {
        var scene: JointScene
        var host: Int
        var guest: Int
        var began: TimeInterval
    }

    /// How long after one scene ends (or after the characters come on) the next may begin: a few minutes, and by how much more or less it
    /// is a chance.
    static let spacing: ClosedRange<TimeInterval> = 180...300
    /// The longest a scene is let go on, whatever the characters are up to.
    static let longest: TimeInterval = 120

    private(set) var play: Play?
    private var nextAt: TimeInterval?
    private var generator: SplitMix64
    /// How many scenes were begun, for tests.
    private(set) var begun = 0

    init(seed: UInt64) {
        generator = SplitMix64(seed: seed)
    }

    /// The numbers of the two characters that are in a scene, which are not in each other's way.
    var exempt: Set<Int> { play.map { [$0.host, $0.guest] } ?? [] }

    /// Whether the characters of these kinds could play a scene at all, or are in one.
    func isPossible(among kinds: [CharacterKind]) -> Bool {
        play != nil || JointScene.all.contains { kinds.contains($0.host) && kinds.contains($0.guest) }
    }

    /// The characters are on a notch again, or none are: nothing was going on, and the next scene is a few minutes away.
    mutating func reset() {
        play = nil
        nextAt = nil
    }

    /// Looks at the characters before they are told what is around them: ends the scene they are in if it has to end, and begins one if
    /// it is time and two are ready. True if that changed what any of them is doing.
    ///
    /// `lanes` is what the stage tells a character of the lane it is in, for a character (its number) with these two (their numbers) in a
    /// scene: what the brains need to know whether there is room.
    mutating func direct(
        now: TimeInterval, kinds: [CharacterKind], brains: inout [(any CharacterBrain)?],
        lanes: (_ index: Int, _ playing: Set<Int>) -> LaneContext = { _, _ in LaneContext() }
    ) -> Bool {
        if let current = play {
            guard holds(current, now: now, kinds: kinds, brains: brains) else { return end(now: now, brains: &brains) }
            return false
        }
        let scenes = JointScene.all.filter { kinds.contains($0.host) && kinds.contains($0.guest) }
        guard !scenes.isEmpty else {
            nextAt = nil
            return false
        }
        guard let due = nextAt else {
            nextAt = now + Double.random(in: Self.spacing, using: &generator)
            return false
        }
        guard now >= due else { return false }
        for scene in scenes {
            for host in kinds.indices where kinds[host] == scene.host {
                for guest in kinds.indices where guest != host && kinds[guest] == scene.guest {
                    if begin(scene, host: host, guest: guest, now: now, brains: &brains, lanes: lanes) { return true }
                }
            }
        }
        return false
    }

    /// The scene is over, whatever it was up to: both are told, the one that is still on its back comes down and the one that was sat on
    /// goes on with its day. True if that changed what either is doing.
    mutating func end(now: TimeInterval, brains: inout [(any CharacterBrain)?]) -> Bool {
        guard let current = play else { return false }
        play = nil
        nextAt = now + Double.random(in: Self.spacing, using: &generator)
        var changed = false
        for index in [current.guest, current.host] where brains.indices.contains(index) {
            if let outcome = brains[index]?.leaveJoint(now: now), outcome != .unchanged { changed = true }
        }
        return changed
    }

    private func holds(_ current: Play, now: TimeInterval, kinds: [CharacterKind], brains: [(any CharacterBrain)?]) -> Bool {
        guard now - current.began < Self.longest, kinds.indices.contains(current.host), kinds.indices.contains(current.guest),
              kinds[current.host] == current.scene.host, kinds[current.guest] == current.scene.guest,
              let host = brains[current.host], let guest = brains[current.guest] else { return false }
        return host.jointScene == current.scene.id && guest.jointScene == current.scene.id
    }

    private mutating func begin(
        _ scene: JointScene, host: Int, guest: Int, now: TimeInterval, brains: inout [(any CharacterBrain)?],
        lanes: (Int, Set<Int>) -> LaneContext
    ) -> Bool {
        guard let hostBrain = brains[host], let guestBrain = brains[guest] else { return false }
        let playing: Set<Int> = [host, guest]
        let hostInvite = JointInvite(scene: scene.id, role: .host, partner: guestBrain.pose, lane: lanes(host, playing))
        let guestInvite = JointInvite(scene: scene.id, role: .guest, partner: hostBrain.pose, lane: lanes(guest, playing))
        guard hostBrain.canJoin(hostInvite, now: now), guestBrain.canJoin(guestInvite, now: now) else { return false }
        brains[host]?.join(hostInvite, now: now)
        brains[guest]?.join(guestInvite, now: now)
        guard brains[host]?.jointScene == scene.id, brains[guest]?.jointScene == scene.id else {
            // One said yes and then did not take the part: neither is in it.
            _ = brains[host]?.leaveJoint(now: now)
            _ = brains[guest]?.leaveJoint(now: now)
            return false
        }
        play = Play(scene: scene, host: host, guest: guest, began: now)
        begun += 1
        return true
    }
}
