import Foundation
import Testing
@testable import PetModule

/// A brain that does nothing but say whether it is ready for a joint scene and remember what it was asked, so that what the director
/// decides is all there is to see.
nonisolated struct ScriptedBrain: CharacterBrain {
    var pose: Pose
    var ready = true
    var takesThePart = true
    var scene: JointScene.ID?
    private(set) var asked: [JointInvite] = []
    private(set) var joined: [JointInvite] = []
    private(set) var left = 0

    init(position: Double = 0.5, ready: Bool = true) {
        pose = Pose(motion: Walker.motion, facing: .right, from: position, to: position, began: 0, duration: 1)
        self.ready = ready
    }

    var jointScene: JointScene.ID? { scene }

    mutating func update(now: TimeInterval, senses: CatSenses, tuning: CatTuning, travel: Double, lane: LaneContext) -> BrainOutcome { .unchanged }
    mutating func settle(lane: LaneContext) {}
    mutating func resume(now: TimeInterval) {}
    mutating func pet(now: TimeInterval) -> BrainOutcome { .unchanged }

    func canJoin(_ invite: JointInvite, now: TimeInterval) -> Bool { ready && scene == nil }

    mutating func join(_ invite: JointInvite, now: TimeInterval) {
        joined.append(invite)
        if takesThePart { scene = invite.scene }
    }

    mutating func leaveJoint(now: TimeInterval) -> BrainOutcome {
        left += 1
        let was = scene != nil
        scene = nil
        return was ? .changed : .unchanged
    }

    /// The brain is done with its part, as a guest that has hopped off is.
    mutating func finish() { scene = nil }
}

@Suite struct JointDirectorTests {
    typealias Brains = [(any CharacterBrain)?]

    func scripted(_ brains: Brains, _ index: Int) -> ScriptedBrain { brains[index] as! ScriptedBrain }

    /// The director looked at once a second for `seconds`, with `each` called before every look.
    func run(
        _ director: inout JointDirector, brains: inout Brains, kinds: [CharacterKind], from start: TimeInterval = 0, seconds: Int,
        untilBegun: Bool = false, each: (TimeInterval, inout Brains) -> Void = { _, _ in }
    ) -> [TimeInterval] {
        var begins: [TimeInterval] = []
        for second in 1...seconds {
            let now = start + TimeInterval(second)
            each(now, &brains)
            let before = director.begun
            _ = director.direct(now: now, kinds: kinds, brains: &brains)
            if director.begun != before { begins.append(now) }
            if untilBegun, !begins.isEmpty { break }
        }
        return begins
    }

    // MARK: Only between two characters that make a pair

    @Test func charactersThatDoNotMakeAPairNeverPlayTogetherHoweverLongAndNobodyIsAskedAnything() {
        let all: [[CharacterKind]] = [[.cat], [.cat, .cat], [.capybara, .capybara], [.capybara], [], [.cat, .cat, .cat]]
        for kinds in all {
            var director = JointDirector(seed: 5)
            var brains: Brains = kinds.map { _ in ScriptedBrain() }
            _ = run(&director, brains: &brains, kinds: kinds, seconds: 6 * 3600)
            #expect(director.begun == 0 && director.play == nil, "\(kinds)")
            for index in kinds.indices { #expect(scripted(brains, index).asked.isEmpty && scripted(brains, index).joined.isEmpty) }
            #expect(!director.isPossible(among: kinds))
        }
    }

    @Test func aCatAndACapybaraMakeAPairWhateverOrderTheyAreInAndAnyOtherOnesAreLeftOut() {
        for kinds in [[CharacterKind.cat, .capybara], [.capybara, .cat], [.cat, .cat, .capybara], [.capybara, .cat, .cat]] {
            var director = JointDirector(seed: 8)
            var brains: Brains = kinds.map { _ in ScriptedBrain() }
            #expect(director.isPossible(among: kinds))
            let begins = run(&director, brains: &brains, kinds: kinds, seconds: 400, untilBegun: true)
            #expect(begins.count == 1, "\(kinds)")
            let play = director.play
            let host = kinds.firstIndex(of: .capybara)!, guest = kinds.firstIndex(of: .cat)!
            #expect(play?.host == host && play?.guest == guest && play?.scene == .catOnCapybara, "\(kinds): \(String(describing: play))")
            #expect(director.exempt == [host, guest])
            for index in kinds.indices where index != host && index != guest { #expect(scripted(brains, index).joined.isEmpty && scripted(brains, index).asked.isEmpty) }
            #expect(scripted(brains, host).joined.map(\.role) == [.host] && scripted(brains, guest).joined.map(\.role) == [.guest])
            #expect(scripted(brains, host).joined[0].partner == scripted(brains, guest).pose, "each is told where the other is")
            #expect(scripted(brains, guest).joined[0].partner == scripted(brains, host).pose)
        }
    }

    // MARK: Occasionally

    @Test func theFirstSceneIsAFewMinutesAfterTheyComeOnAndTheNextIsAFewMinutesAfterTheLastEnded() {
        for seed in 1...20 as ClosedRange<UInt64> {
            var director = JointDirector(seed: seed)
            var brains: Brains = [ScriptedBrain(), ScriptedBrain()]
            var ends: [TimeInterval] = []
            var begins: [TimeInterval] = []
            for second in 1...(3 * 3600) {
                let now = TimeInterval(second)
                // A scene is 40 seconds of the guest's.
                if let start = begins.last, now == start + 40, var guest = brains[0] as? ScriptedBrain { guest.finish(); brains[0] = guest }
                let before = director.begun
                _ = director.direct(now: now, kinds: [.cat, .capybara], brains: &brains)
                if director.begun != before { begins.append(now) }
                if director.play == nil, let start = begins.last, ends.count < begins.count, now > start { ends.append(now) }
            }
            #expect(begins.count >= 20 && begins.count <= 60, "seed \(seed): \(begins.count) scenes in three hours")
            #expect(begins[0] >= 180 && begins[0] <= 301, "seed \(seed): the first at \(begins[0])")
            for (end, next) in zip(ends, begins.dropFirst()) { #expect(next - end >= 179 && next - end <= 301, "seed \(seed): \(next - end) seconds after the last") }
        }
    }

    @Test func notBeforeBothAreReadyAndThenAtOnce() {
        var director = JointDirector(seed: 3)
        var brains: Brains = [ScriptedBrain(ready: false), ScriptedBrain(ready: true)]
        var begins = run(&director, brains: &brains, kinds: [.capybara, .cat], seconds: 1000)
        #expect(begins.isEmpty, "the capybara is not ready")
        var host = brains[0] as! ScriptedBrain
        host.ready = true
        brains[0] = host
        var guest = brains[1] as! ScriptedBrain
        guest.ready = false
        brains[1] = guest
        begins = run(&director, brains: &brains, kinds: [.capybara, .cat], from: 1000, seconds: 500)
        #expect(begins.isEmpty, "and not the cat")
        guest.ready = true
        brains[1] = guest
        begins = run(&director, brains: &brains, kinds: [.capybara, .cat], from: 1500, seconds: 5)
        #expect(begins == [1501], "the moment both are: \(begins)")
    }

    // MARK: One at a time

    @Test func atMostOneAtATimeWhateverElseIsOnTheStage() {
        var director = JointDirector(seed: 11)
        var brains: Brains = [ScriptedBrain(), ScriptedBrain(), ScriptedBrain(), ScriptedBrain()]
        let kinds: [CharacterKind] = [.cat, .capybara, .cat, .cat]
        var sceneEnds = 0
        for second in 1...(5 * 3600) {
            let now = TimeInterval(second)
            let before = director.begun
            _ = director.direct(now: now, kinds: kinds, brains: &brains)
            let inScenes = brains.indices.filter { scripted(brains, $0).jointScene != nil }
            #expect(inScenes.count <= 2, "at \(now): \(inScenes)")
            if inScenes.count == 2 { #expect(inScenes.contains(1)) }
            if director.begun != before { #expect(director.play?.began == now) }
            // The guest of each scene hops off after 30 seconds.
            if let play = director.play, now - play.began >= 30 {
                var guest = scripted(brains, play.guest)
                guest.finish()
                brains[play.guest] = guest
                sceneEnds += 1
            }
        }
        #expect(sceneEnds > 30 && director.begun >= sceneEnds)
        let guests = [0, 2, 3].map { scripted(brains, $0).joined.count }
        #expect(guests.allSatisfy { $0 > 0 } || director.begun > 30, "any of the cats may be the guest: \(guests)")
    }

    // MARK: Over

    @Test func whenTheGuestIsDoneBothAreToldAndTheHostGoesOn() {
        var director = JointDirector(seed: 4)
        var brains: Brains = [ScriptedBrain(), ScriptedBrain()]
        _ = run(&director, brains: &brains, kinds: [.capybara, .cat], seconds: 400, untilBegun: true)
        #expect(director.play != nil)
        var guest = scripted(brains, 1)
        guest.finish()
        brains[1] = guest
        let changed = director.direct(now: 401, kinds: [.capybara, .cat], brains: &brains)
        #expect(director.play == nil && director.exempt.isEmpty)
        #expect(scripted(brains, 0).left == 1 && scripted(brains, 1).left == 1, "both are told it is over")
        #expect(changed, "the host's pose changed when it was released")
    }

    @Test func aSceneThatGoesOnForTwoMinutesIsEndedWhateverTheyAreUpTo() {
        var director = JointDirector(seed: 6)
        var brains: Brains = [ScriptedBrain(), ScriptedBrain()]
        let begins = run(&director, brains: &brains, kinds: [.capybara, .cat], seconds: 400, untilBegun: true)
        let start = begins[0]
        _ = run(&director, brains: &brains, kinds: [.capybara, .cat], from: start, seconds: Int(JointDirector.longest) - 2)
        #expect(director.play != nil, "not yet")
        _ = director.direct(now: start + JointDirector.longest, kinds: [.capybara, .cat], brains: &brains)
        #expect(director.play == nil && scripted(brains, 0).left == 1 && scripted(brains, 1).left == 1)
    }

    @Test func ifOneIsRemovedFromTheStageTheSceneIsOverAndTheOneThatIsLeftIsToldAndTheNextIsAFewMinutesOff() {
        for removed in [0, 1] {
            var director = JointDirector(seed: 9)
            var brains: Brains = [ScriptedBrain(), ScriptedBrain()]
            let begins = run(&director, brains: &brains, kinds: [.capybara, .cat], seconds: 400, untilBegun: true)
            #expect(director.play != nil)
            // What the stage does before it takes one away.
            _ = director.end(now: 410, brains: &brains)
            #expect(director.play == nil)
            #expect(scripted(brains, 0).left == 1 && scripted(brains, 1).left == 1)
            let survivor = scripted(brains, 1 - removed)
            #expect(survivor.jointScene == nil, "the one that stays is out of it")
            // The one that is left is alone, or in numbers that are not the same: nothing begins that is not a pair.
            var rest: Brains = [brains[1 - removed]]
            let later = run(&director, brains: &rest, kinds: [removed == 0 ? .cat : .capybara], from: 410, seconds: 4000)
            #expect(later.isEmpty && begins.count == 1)
            // And a pair again is a few minutes away, not at once.
            var again: Brains = [ScriptedBrain(), ScriptedBrain()]
            let afterwards = run(&director, brains: &again, kinds: [.capybara, .cat], from: 4410, seconds: 400)
            #expect(afterwards.count == 1 && afterwards[0] >= 4410 + 1, "\(afterwards)")
        }
    }

    @Test func aSceneWhoseCharactersAreNotWhoTheyWereIsOver() {
        var director = JointDirector(seed: 13)
        var brains: Brains = [ScriptedBrain(), ScriptedBrain()]
        _ = run(&director, brains: &brains, kinds: [.capybara, .cat], seconds: 400, untilBegun: true)
        #expect(director.play != nil)
        // The kinds on the stage changed under them without the stage saying so.
        _ = director.direct(now: 401, kinds: [.cat, .cat], brains: &brains)
        #expect(director.play == nil)
        var other = JointDirector(seed: 13)
        var more: Brains = [ScriptedBrain(), ScriptedBrain()]
        _ = run(&other, brains: &more, kinds: [.capybara, .cat], seconds: 400, untilBegun: true)
        more[0] = nil
        _ = other.direct(now: 401, kinds: [.capybara, .cat], brains: &more)
        #expect(other.play == nil, "a character with no brain is gone")
    }

    @Test func oneThatSaysYesAndThenDoesNotTakeThePartLeavesNeitherInTheSceneAndNothingBegins() {
        var director = JointDirector(seed: 2)
        var host = ScriptedBrain()
        host.takesThePart = false
        var brains: Brains = [host, ScriptedBrain()]
        let begins = run(&director, brains: &brains, kinds: [.capybara, .cat], seconds: 1500)
        #expect(begins.isEmpty && director.play == nil && director.begun == 0)
        #expect(scripted(brains, 1).jointScene == nil, "the guest is not left on its own in a scene")
        #expect(scripted(brains, 1).left > 0)
    }

    @Test func resettingForgetsTheSceneAndTheTimeAndTheNextOneIsAFewMinutesFromTheNextLook() {
        var director = JointDirector(seed: 7)
        var brains: Brains = [ScriptedBrain(), ScriptedBrain()]
        _ = run(&director, brains: &brains, kinds: [.capybara, .cat], seconds: 400, untilBegun: true)
        director.reset()
        #expect(director.play == nil)
        var fresh: Brains = [ScriptedBrain(), ScriptedBrain()]
        let begins = run(&director, brains: &fresh, kinds: [.capybara, .cat], from: 1000, seconds: 20)
        #expect(begins.isEmpty, "a few minutes: \(begins)")
    }

    @Test func theDirectorAndNothingElseDecidesWhenAndItIsTheSameForTheSameSeed() {
        func begins(seed: UInt64) -> [TimeInterval] {
            var director = JointDirector(seed: seed)
            var brains: Brains = [ScriptedBrain(), ScriptedBrain()]
            var starts: [TimeInterval] = []
            for second in 1...(2 * 3600) {
                let now = TimeInterval(second)
                if let start = starts.last, now == start + 30, var guest = brains[1] as? ScriptedBrain { guest.finish(); brains[1] = guest }
                let before = director.begun
                _ = director.direct(now: now, kinds: [.capybara, .cat], brains: &brains)
                if director.begun != before { starts.append(now) }
            }
            return starts
        }
        #expect(begins(seed: 3) == begins(seed: 3) && begins(seed: 3) != begins(seed: 4))
    }

    // MARK: The lane

    @Test func twoThatPlayTogetherOweEachOtherNoRoomAndTheOthersAndTheCrossingStillHaveWhatTheyAreOwed() {
        let still = { (place: Double) in Pose(motion: Walker.motion, facing: .right, from: place, to: place, began: 0, duration: 1) }
        var tub = still(0.5)
        tub.prop = PoseProp(look: PropLook(key: 0, fps: 1, occupies: true), from: 0.55, to: 0.55)
        let poses: [Pose?] = [still(0.3), tub, still(0.7)]
        let plain = LaneRules.context(for: 0, poses: poses, crossing: [0.4...0.6], separation: 0.1, now: 1)
        #expect(plain.zones.count == 3, "a character's place, a tub's, and the third one's: \(plain.zones)")
        let paired = LaneRules.context(for: 0, poses: poses, crossing: [0.4...0.6], separation: 0.1, now: 1, exempt: [0, 1])
        #expect(paired.zones.count == 1 && paired.zones[0].lowerBound == 0.7 - 0.1 && paired.crossing == [0.4...0.6], "only the third's: \(paired.zones)")
        let third = LaneRules.context(for: 2, poses: poses, crossing: [], separation: 0.1, now: 1, exempt: [0, 1])
        #expect(third.zones.count == 3, "the third is not in the scene, and owes both of them what it owes anyone")
        let none = LaneRules.context(for: 0, poses: poses, crossing: [], separation: 0.1, now: 1, exempt: [])
        #expect(none == plain || none.zones == plain.zones)
    }

    @Test func aPropThatDoesNotTakeUpRoomMakesNoZone() {
        var moth = Pose(motion: Walker.motion, facing: .right, from: 0.3, to: 0.3, began: 0, duration: 1)
        moth.prop = PoseProp(look: PropLook(key: 0, fps: 1), from: 0.9, to: 0.9)
        let lane = LaneRules.context(for: 1, poses: [moth, nil], crossing: [], separation: 0.1, now: 0)
        #expect(lane.zones.count == 1)
    }
}
