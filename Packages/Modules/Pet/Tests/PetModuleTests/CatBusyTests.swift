import AppKit
import Foundation
import Testing
@testable import PetModule

/// What a cat was seen to do through a run of the stage at some load, a quarter of a second at a time.
@MainActor final class Seen {
    /// The seconds on the stage's clock at which the cat was running for its life.
    var running: [TimeInterval] = []
    var scenes = Set<CatScene>()
    var moves = Set<CatMove>()
    /// How much faster than its own pace each walk and trot was played.
    var walkScales: [Double] = []
    private var lastWalk: TimeInterval?

    /// The bursts as (start, end): the runs of ticks at which it was running.
    var bursts: [(start: TimeInterval, end: TimeInterval)] {
        var result: [(TimeInterval, TimeInterval)] = []
        for second in running {
            if let last = result.last, second - last.1 <= 0.5 { result[result.count - 1].1 = second } else { result.append((second, second)) }
        }
        return result
    }

    func note(_ plan: CatPlan?, scene: CatScene?, at now: TimeInterval) {
        guard let plan else { return }
        moves.insert(plan.move)
        if plan.move == .frantic { running.append(now) }
        if let scene { scenes.insert(scene) }
        if [CatMove.walk, .trot].contains(plan.move), lastWalk != plan.began {
            lastWalk = plan.began
            walkScales.append(plan.fpsScale)
        }
    }
}

extension StageRig {
    /// Lives `seconds` at `load`, and writes down what the cat did.
    func live(_ seconds: Double, load: Double, seen: Seen) {
        cpu.value = load
        for _ in 0..<Int((seconds * 4).rounded()) {
            advance(0.25)
            seen.note(stage.plan, scene: stage.scene, at: scheduler.seconds)
        }
    }
}

/// How the cat takes the Mac being busy, through the whole stage: the samples a second, the usual load, the bursts and the rest of its day.
@Suite(.serialized) @MainActor struct CatBusyTests {
    static let tick = 0.25

    @Test func aMacThatIsBusyAllTheTimeNeverMakesItRunAndEverySceneStillPlaysThroughHalfAnHour() {
        let rig = StageRig()
        rig.show()
        let seen = Seen()
        rig.live(30 * 60, load: 0.9, seen: seen)
        #expect(seen.running.isEmpty, "busy is what this Mac is: \(seen.bursts)")
        #expect(seen.scenes.count >= 8, "\(seen.scenes.count) scenes: \(seen.scenes)")
        #expect(seen.scenes.contains(.fret), "it sweats now and then")
        #expect(seen.moves.contains(.sweat))
        let normal = seen.walkScales.filter { $0 == 1 }
        #expect(!seen.walkScales.isEmpty && normal.isEmpty, "every walk is a little quicker than at rest")
        #expect(seen.walkScales.allSatisfy { $0 > 1 && $0 <= 1 + CatBrain.busyBoost })
    }

    @Test func aMacThatIsAsBusyAsEverButQuietAtFirstGetsBurstsNoMoreThanOneInFiveMinutesAndEachIsCapped() throws {
        let rig = StageRig()
        rig.show()
        let seen = Seen()
        rig.live(13 * 60, load: 0.05, seen: seen)
        #expect(seen.running.isEmpty)
        let stepAt = rig.scheduler.seconds
        rig.live(30 * 60, load: 0.9, seen: seen)
        let bursts = seen.bursts
        let first = try #require(bursts.first, "a spike over the usual is a burst")
        #expect(first.start - stepAt >= BusyWatch.hold && first.start - stepAt <= BusyWatch.hold + 6, "after the hold, and the lag of the smoothing: \(first.start - stepAt)")
        for burst in bursts {
            #expect(burst.end - burst.start <= BusyWatch.longestBurst + 2 * Self.tick, "\(burst) is longer than its cap")
        }
        for (before, after) in zip(bursts, bursts.dropFirst()) {
            #expect(after.start - before.start >= BusyWatch.cooldown - Self.tick, "a burst at \(after.start) after one at \(before.start)")
        }
        #expect(bursts.count <= 3, "\(bursts)")
        #expect(seen.scenes.count >= 8, "and the rest of the time it plays what it plays: \(seen.scenes.count) scenes")
    }

    @Test func aSpikeThatDoesNotHoldMakesNoBurstAndOneThatDoesMakesOneThatEndsWhenTheLoadDoes() throws {
        let rig = StageRig()
        rig.show()
        let seen = Seen()
        rig.live(120, load: 0.05, seen: seen)
        rig.live(7, load: 0.95, seen: seen)
        rig.live(120, load: 0.05, seen: seen)
        #expect(seen.running.isEmpty, "a spike of seven seconds is not a burst")
        let stepAt = rig.scheduler.seconds
        rig.live(16, load: 0.95, seen: seen)
        let dropAt = rig.scheduler.seconds
        rig.live(30, load: 0.05, seen: seen)
        let burst = try #require(seen.bursts.first, "one of sixteen is")
        #expect(seen.bursts.count == 1)
        #expect(burst.start - stepAt >= BusyWatch.hold)
        #expect(burst.end - dropAt <= 4, "and it is over soon after the load is: \(burst.end - dropAt)")
        #expect(rig.stage.plan?.move != .frantic)
    }

    @Test func withTheReactionOffNothingIsDifferentWhateverTheMacDoes() throws {
        let rig = StageRig()
        rig.stage.tuning = CatTuning(reactsToBusyMachine: false)
        rig.show()
        let seen = Seen()
        rig.live(13 * 60, load: 0.05, seen: seen)
        rig.live(20 * 60, load: 0.95, seen: seen)
        #expect(seen.running.isEmpty, "no burst")
        #expect(!seen.scenes.contains(.fret) && !seen.moves.contains(.sweat), "no sweat")
        #expect(!seen.walkScales.isEmpty && seen.walkScales.allSatisfy { $0 == 1 }, "and no quicker walks")
        #expect(seen.scenes.count >= 8)
    }

    @Test func theReactionTurnedOffInTheMiddleOfABurstEndsItAtTheNextTick() {
        let rig = StageRig()
        rig.show()
        let seen = Seen()
        rig.live(13 * 60, load: 0.05, seen: seen)
        rig.live(15, load: 0.95, seen: seen)
        #expect(rig.stage.plan?.move == .frantic)
        rig.stage.tuning = CatTuning(reactsToBusyMachine: false)
        rig.live(1, load: 0.95, seen: seen)
        #expect(rig.stage.plan?.move != .frantic)
    }

    @Test func theCatLeavingTheNotchAndComingBackDoesNotGiveItAnotherBurstWithinTheCooldown() throws {
        let rig = StageRig()
        rig.show()
        let seen = Seen()
        rig.live(13 * 60, load: 0.05, seen: seen)
        rig.live(20, load: 0.95, seen: seen)
        #expect(seen.bursts.count == 1)
        // Another activity takes the notch, and gives it back, again and again, with the Mac as busy as ever.
        func cycle() {
            rig.hide()
            rig.advance(2)
            rig.show()
            rig.live(40, load: 0.05, seen: seen)
            rig.live(20, load: 0.95, seen: seen)
        }
        let firstStart = try #require(seen.bursts.first).start
        while rig.scheduler.seconds - firstStart < BusyWatch.cooldown - 70 { cycle() }
        #expect(seen.bursts.count == 1, "\(seen.bursts)")
        // And once the cooldown is over, a spike that holds is a burst again.
        while rig.scheduler.seconds - firstStart < BusyWatch.cooldown + 10 { cycle() }
        #expect(seen.bursts.count == 2, "\(seen.bursts)")
    }

    @Test func aBurstShowsAsAFranticRunAcrossTheLaneThatQuickensWithTheLoad() throws {
        let rig = StageRig()
        rig.show()
        let seen = Seen()
        rig.live(120, load: 0.05, seen: seen)
        rig.live(15, load: 1.0, seen: seen)
        let plan = try #require(rig.stage.plan)
        #expect(plan.move == .frantic)
        #expect(plan.fpsScale > 1)
        let frames = try #require(rig.host.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation)
        #expect(abs(frames.duration - CatMove.frantic.passDuration / plan.fpsScale) < 1e-9)
    }
}
