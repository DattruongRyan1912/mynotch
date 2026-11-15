import AppKit
import MyNotchCore
import NotchUI
import QuartzCore
import Testing
@testable import PetModule

/// The cat that sits on the capybara, on a stage: when it happens, what each does while it does, how it ends, and what the views show.
/// Everything runs on the scheduler the test advances.
@Suite(.serialized) @MainActor struct CatJointStageTests {
    static let sceneMoves: Set<CatMove> = [.hopOn, .hopOff, .perch, .perchLoaf]

    func pair(_ geometry: NotchGeometry = Screens.pill, seed: UInt64, kinds: [CharacterKind] = [.cat, .capybara]) -> BodyRig {
        let rig = BodyRig(geometry: geometry, seed: seed)
        rig.show()
        rig.stage.characters = kinds
        return rig
    }

    func catMove(_ rig: BodyRig) -> CatMove { CatMove(rig.stage.poses[0].motion) }

    func capybaraMove(_ rig: BodyRig) -> CapybaraMove { CapybaraMove(rig.stage.poses[1].motion) }

    /// Ticks until a scene is in progress and `ready` says so, for at most `minutes`.
    func untilScene(_ rig: BodyRig, minutes: Int = 80, ready: (BodyRig) -> Bool = { _ in true }) -> Bool {
        for _ in 0..<(4 * 60 * minutes) {
            rig.advance(0.25)
            if rig.stage.jointPlay != nil, ready(rig) { return true }
        }
        return false
    }

    func perched(_ rig: BodyRig) -> Bool { [CatMove.perch, .perchLoaf].contains(catMove(rig)) }

    func click(_ host: CatSpriteView, at point: CGPoint) throws {
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: host.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: host.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        host.mouseDown(with: event)
    }

    // MARK: Only when both share a screen

    @Test func itNeverHappensWithOneKindOnAScreenOrWithTheCatAndTheCapybaraOnTwoScreens() {
        for kinds in [[CharacterKind.cat], [.capybara], [.cat, .cat], [.capybara, .capybara]] {
            let rig = pair(seed: 5, kinds: kinds)
            for _ in 0..<(4 * 3600 * 2) { rig.advance(0.25) }
            #expect(rig.stage.jointScenesBegun == 0 && rig.stage.jointPlay == nil, "\(kinds)")
            rig.hide()
        }
        let mac = BodyRig(geometry: Screens.hardware, seed: 3)
        mac.show()
        mac.stage.characters = [.cat]
        let pill = BodyRig(geometry: Screens.pill, seed: 3, sharing: mac)
        pill.show()
        pill.stage.characters = [.capybara]
        for _ in 0..<(4 * 3600 * 3) { mac.advance(0.25) }
        #expect(mac.stage.jointScenesBegun == 0 && pill.stage.jointScenesBegun == 0, "each on a screen of its own")
        #expect(mac.stage.poses.allSatisfy { !Self.sceneMoves.contains(CatMove($0.motion)) })
    }

    @Test func sharingAScreenTheyDoPlayTogetherNowAndThenOnAPillAndOnTheMacsWings() {
        for (geometry, seeds) in [(Screens.pill, [3, 8, 21]), (Screens.tallPill, [3, 5])] as [(NotchGeometry, [UInt64])] {
            for seed in seeds {
                let rig = pair(geometry, seed: seed)
                let began = untilScene(rig, minutes: 90)
                #expect(began, "\(geometry.kind), seed \(seed)")
                #expect(rig.stage.jointPlay?.scene == .catOnCapybara && rig.stage.jointPlay?.host == 1 && rig.stage.jointPlay?.guest == 0)
                rig.hide()
            }
        }
        var scenes = 0
        for seed: UInt64 in [3, 8, 21, 55] {
            let rig = pair(Screens.hardware, seed: seed)
            for _ in 0..<(4 * 3600 * 3) { rig.advance(0.25) }
            scenes += rig.stage.jointScenesBegun
            rig.hide()
        }
        #expect(scenes > 0, "on the Mac's wings, where there is less room, too: \(scenes)")
    }

    // MARK: Neither walks off

    @Test func neitherWalksOffDuringItWhateverTheMacDoesAndTheCatIsOnTheCapybarasBackAndOverItInTheView() throws {
        var observed = 0
        for seed: UInt64 in [3, 8, 21] {
            let rig = pair(seed: seed)
            let host = try #require(rig.hosts.first)
            let frame = host.screenFrame ?? .zero
            var scenes = 0
            var tick = 0
            var capybaraPlace: Double?
            var wasPlaying = false
            for _ in 0..<(4 * 3600 * 2) {
                rig.advance(0.25)
                tick += 1
                guard let play = rig.stage.jointPlay else {
                    if wasPlaying { capybaraPlace = nil }
                    wasPlaying = false
                    rig.cpu.value = 0.05
                    rig.audio.playing = false
                    rig.idle.seconds = 4
                    rig.pointer.point = CGPoint(x: 9000, y: 9000)
                    continue
                }
                if !wasPlaying { scenes += 1 }
                wasPlaying = true
                // The Mac does everything it can to take them away.
                rig.cpu.value = 0.99
                rig.audio.playing = tick % 40 < 20
                rig.idle.seconds = 10_000
                rig.pointer.point = CGPoint(x: frame.midX, y: frame.midY)
                let (cat, capybara) = (rig.stage.poses[0], rig.stage.poses[1])
                #expect(play.host == 1 && play.guest == 0)
                #expect(capybara.from == capybara.to && capybara.perch != nil, "the capybara is held where it is, with a back to sit on")
                if let place = capybaraPlace { #expect(capybara.to == place, "it does not move: \(capybara.to) for \(place)") } else { capybaraPlace = capybara.to }
                let move = CatMove(cat.motion)
                #expect([CatMove.walk, .hopOn, .perch, .perchLoaf, .hopOff].contains(move), "seed \(seed): the cat \(move) in the scene")
                if [.perch, .perchLoaf].contains(move) {
                    observed += 1
                    #expect(cat.from == capybara.to && cat.to == capybara.to, "on its back: \(cat.from) and \(capybara.to)")
                    #expect(cat.raised)
                    let (catLayers, capybaraLayers) = (host.characters[0], host.characters[1])
                    #expect(catLayers.sprite.zPosition > capybaraLayers.sprite.zPosition, "over it, though it is drawn first")
                    #expect(abs(catLayers.sprite.position.x - capybaraLayers.sprite.position.x) <= 4, "over its rump: \(catLayers.sprite.position.x), \(capybaraLayers.sprite.position.x)")
                    #expect(catLayers.sprite.position.y == capybaraLayers.sprite.position.y, "the picture is drawn to stand on it: nothing is lifted")
                }
            }
            #expect(scenes >= 1, "seed \(seed): \(scenes)")
            rig.hide()
        }
        #expect(observed > 100, "\(observed)")
    }

    @Test func aClickOnTheCatOnTheBackIsTheCatsStrokeAndNotTheCapybarasAndEndsTheSceneWithTheCatComingDown() throws {
        for seed: UInt64 in [3, 8] {
            let rig = pair(seed: seed)
            rig.stage.playsMeow = true
            #expect(untilScene(rig, minutes: 90) { perched($0) })
            let host = try #require(rig.hosts.first)
            let cat = host.characters[0].sprite
            let spot = CGPoint(x: cat.frame.midX, y: cat.frame.midY + 3)
            let before = rig.stage.strokes
            try click(host, at: spot)
            #expect(rig.stage.strokes == before + 1 && rig.meow.plays == 1, "the cat's, which mews")
            #expect(rig.stage.jointPlay == nil)
            #expect(catMove(rig) == .hopOff, "it comes down: \(catMove(rig))")
            #expect(capybaraMove(rig) != .happy && capybaraMove(rig) != .soakHappy, "not the capybara that was stroked")
            for _ in 0..<(4 * 20) { rig.advance(0.25) }
            #expect(!rig.stage.poses[0].raised && host.characters[0].sprite.zPosition == 0)
            rig.hide()
        }
    }

    @Test func aClickOnTheCapybaraTheCatIsSittingOnSquintsItAndTheCatComesDown() throws {
        for seed: UInt64 in [3, 8] {
            let rig = pair(seed: seed)
            rig.stage.playsMeow = true
            #expect(untilScene(rig, minutes: 90) { perched($0) })
            let host = try #require(rig.hosts.first)
            let capybara = host.characters[1].sprite
            // On its body, below the cat on its back, whichever way it faces.
            let spot = CGPoint(x: capybara.frame.minX + 16, y: capybara.frame.minY + 6)
            try click(host, at: spot)
            #expect(rig.meow.plays == 0, "a capybara does not mew")
            #expect(rig.stage.jointPlay == nil)
            #expect(catMove(rig) == .hopOff)
            let move = capybaraMove(rig)
            #expect(move == .happy || move == .soakHappy, "\(move)")
            for _ in 0..<(4 * 30) { rig.advance(0.25) }
            #expect(!rig.stage.poses[0].raised && host.characters[0].sprite.zPosition == 0)
            rig.hide()
        }
    }

    // MARK: Ending cleanly

    @Test func ifTheCapybaraIsTakenOffTheScreenMidSceneTheCatComesDownAndIsNeverLeftOnNothing() throws {
        for seed: UInt64 in [3, 8, 21] {
            let rig = pair(seed: seed)
            #expect(untilScene(rig, minutes: 90) { perched($0) })
            let host = try #require(rig.hosts.first)
            rig.stage.characters = [.cat]
            #expect(rig.stage.jointPlay == nil)
            #expect(host.characters.count == 1)
            #expect(catMove(rig) == .hopOff, "it comes down at once: \(catMove(rig))")
            var moves: [CatMove] = []
            for _ in 0..<(4 * 600) {
                rig.advance(0.25)
                if moves.last != catMove(rig) { moves.append(catMove(rig)) }
            }
            #expect(!moves.contains(.perch) && !moves.contains(.perchLoaf) && !moves.contains(.hopOn), "seed \(seed): \(moves)")
            #expect(!rig.stage.poses[0].raised && host.characters[0].sprite.zPosition == 0)
            #expect(rig.stage.jointScenesBegun == 1, "and nothing begins on a stage with no pair")
            rig.hide()
        }
    }

    @Test func ifTheCatIsTakenOffTheScreenTheCapybaraIsLetGoAndGoesOnWithItsDayAndItsTubGoesAtTheEnd() throws {
        for seed: UInt64 in [3, 8, 21] {
            let rig = pair(seed: seed)
            #expect(untilScene(rig, minutes: 90) { perched($0) })
            let host = try #require(rig.hosts.first)
            let soaking = rig.stage.poses[1].prop != nil
            rig.stage.characters = [.capybara]
            #expect(rig.stage.jointPlay == nil && host.characters.count == 1)
            var props = 0
            for _ in 0..<(4 * 900) {
                rig.advance(0.25)
                let pose = rig.stage.poses[0]
                if pose.prop != nil { props += 1 }
                #expect(host.characters[0].prop.isHidden == (pose.prop == nil), "\(CapybaraMove(pose.motion)) with \(String(describing: pose.prop?.look))")
                #expect(pose.perch == nil || pose.from == pose.to)
            }
            #expect(!soaking || props > 0)
            // Away for good, it ends up with nothing out.
            rig.idle.seconds = 10_000
            for _ in 0..<(4 * 300) { rig.advance(0.25) }
            #expect(rig.stage.poses[0].prop == nil && host.characters[0].prop.isHidden, "seed \(seed)")
            rig.hide()
        }
    }

    @Test func anyChangeInWhoIsOnTheStageEndsTheSceneEvenOneOfTheOthersAndNobodyIsLeftInIt() throws {
        let rig = pair(seed: 3, kinds: [.cat, .capybara, .cat])
        #expect(untilScene(rig, minutes: 120) { _ in true })
        rig.stage.characters = [.cat, .capybara]
        #expect(rig.stage.jointPlay == nil, "their numbers may have changed")
        for _ in 0..<(4 * 60) { rig.advance(0.25) }
        #expect(rig.stage.poses.count == 2)
    }

    @Test func reduceMotionStillsEveryoneAndTheSceneIsOverForGood() throws {
        let rig = pair(seed: 8)
        #expect(untilScene(rig, minutes: 90) { perched($0) })
        let host = try #require(rig.hosts.first)
        rig.knobs.reducesMotion = true
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { !rig.stage.isTicking }, seconds: 5))
        #expect(rig.stage.jointPlay == nil)
        #expect(host.characters.allSatisfy { $0.sprite.zPosition == 0 && $0.prop.isHidden })
        rig.knobs.reducesMotion = false
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { rig.stage.isTicking }, seconds: 5))
        #expect(rig.stage.jointPlay == nil && !Self.sceneMoves.contains(catMove(rig)), "back on the floor: \(catMove(rig))")
        #expect(!rig.stage.poses[0].raised)
    }

    @Test func aNotchThatLeavesTheScreenMidSceneComesBackWithBothSittingOnTheFloorAndNoSceneAFewMinutesOff() throws {
        let rig = pair(seed: 3)
        #expect(untilScene(rig, minutes: 90) { perched($0) })
        rig.hide()
        rig.show()
        #expect(rig.stage.jointPlay == nil)
        let poses = rig.stage.poses
        #expect(poses.allSatisfy { !$0.raised } && !Self.sceneMoves.contains(catMove(rig)), "\(catMove(rig))")
        let begun = rig.stage.jointScenesBegun
        for _ in 0..<(4 * 120) { rig.advance(0.25) }
        #expect(rig.stage.jointScenesBegun == begun, "a few minutes from now, not at once")
    }

    @Test func aNotchThatChangesSizeMidSceneEndsItAndTheCatComesDownBecauseTheLaneIsNotWhatItWasMadeFor() throws {
        for seed: UInt64 in [3, 8] {
            let rig = pair(seed: seed)
            #expect(untilScene(rig, minutes: 90) { perched($0) })
            let host = try #require(rig.hosts.first)
            let size = rig.container.frame.size
            rig.container.setFrameSize(NSSize(width: size.width + 40, height: size.height))
            rig.container.layoutSubtreeIfNeeded()
            #expect(rig.stage.jointPlay == nil, "the lane changed under them")
            #expect(catMove(rig) == .hopOff, "\(catMove(rig))")
            for _ in 0..<(4 * 30) { rig.advance(0.25) }
            #expect(!rig.stage.poses[0].raised && host.characters[0].sprite.zPosition == 0 && !Self.sceneMoves.contains(catMove(rig)))
            rig.hide()
        }
    }

    @Test func aSceneNeverGoesOnForMoreThanTheDirectorsLongestWhateverHappens() {
        let rig = pair(seed: 21)
        var longest = 0.0
        var started: TimeInterval?
        for _ in 0..<(4 * 3600 * 3) {
            rig.advance(0.25)
            let now = rig.scheduler.seconds
            if rig.stage.jointPlay != nil, started == nil { started = now }
            if rig.stage.jointPlay == nil, let began = started {
                longest = max(longest, now - began)
                started = nil
            }
        }
        #expect(longest > 10 && longest <= JointDirector.longest + 1, "\(longest)")
    }

    @Test func whenTheSceneIsEndedEarlyByAClickOnTheCatOrTheLaneMovingTheCapybaraDoesNotJumpAndItsTubIsNotTakenFromIt() throws {
        var ended = 0, withATub = 0
        for seed: UInt64 in [3, 8, 21, 34, 55, 89] {
            for how in ["click", "lane"] {
                let rig = pair(seed: seed)
                #expect(untilScene(rig, minutes: 90) { perched($0) })
                let host = try #require(rig.hosts.first)
                let before = rig.stage.poses[1]
                if before.prop != nil { withATub += 1 }
                if how == "click" {
                    let cat = host.characters[0].sprite
                    try click(host, at: CGPoint(x: cat.frame.midX, y: cat.frame.midY + 3))
                } else {
                    let size = rig.container.frame.size
                    rig.container.setFrameSize(NSSize(width: size.width + 40, height: size.height))
                    rig.container.layoutSubtreeIfNeeded()
                }
                #expect(rig.stage.jointPlay == nil)
                ended += 1
                // The cat is hopping off and walking out of the way, and is excused of the capybara's room until it is: the capybara stays.
                expectHostStaysPut(rig, was: before, seconds: 8, "seed \(seed), \(how)")
                for _ in 0..<(4 * 60) { rig.advance(0.25) }
                #expect(rig.stage.jointExempt.isEmpty)
                rig.hide()
            }
        }
        #expect(ended == 12 && withATub >= 3, "\(ended) scenes ended early, \(withATub) of them with a tub")
    }

    // MARK: Occasionally, one at a time

    @Test func atMostOneAtATimeWithAnotherCatOnTheScreenAndNeverSoonerThanAFewMinutesAfterTheLast() {
        for seed: UInt64 in [3, 8] {
            let rig = pair(seed: seed, kinds: [.cat, .capybara, .cat])
            var begun = 0
            var starts: [TimeInterval] = []
            var ends: [TimeInterval] = []
            var wasPlaying = false
            for _ in 0..<(4 * 3600 * 4) {
                rig.advance(0.25)
                let now = rig.scheduler.seconds
                let onTheBack = rig.stage.poses.indices.filter { [CatMove.hopOn, .perch, .perchLoaf, .hopOff].contains(CatMove(rig.stage.poses[$0].motion)) && $0 != 1 }
                #expect(onTheBack.count <= 1, "seed \(seed): two cats in the scene at \(now): \(onTheBack)")
                #expect(rig.stage.jointScenesBegun - begun <= 1)
                if rig.stage.jointScenesBegun != begun { starts.append(now) }
                begun = rig.stage.jointScenesBegun
                let playing = rig.stage.jointPlay != nil
                if wasPlaying, !playing { ends.append(now) }
                wasPlaying = playing
            }
            #expect(starts.count >= 3, "seed \(seed): occasional, but it does happen: \(starts.count) in four hours")
            #expect(starts.count <= 4 * 3600 / 180, "seed \(seed): \(starts.count)")
            for (end, next) in zip(ends, starts.dropFirst()) { #expect(next - end >= JointDirector.spacing.lowerBound - 1, "seed \(seed): \(next - end) seconds after the last") }
        }
    }

    // MARK: Three on a lane

    /// The characters of one stage looked at after every waking: no two at rest closer than a picture but the two of a scene while they play,
    /// and nobody at rest by the capybara's tub.
    func lanes(_ geometry: NotchGeometry, seeds: [UInt64], minutes: Int) throws -> (overlaps: [String], crossingTogether: [String], scenes: Int) {
        var overlaps: [String] = []
        var together: [String] = []
        var scenes = 0
        for seed in seeds {
            let rig = BodyRig(geometry: geometry, seed: seed)
            rig.show()
            rig.stage.characters = [.cat, .capybara, .cat]
            let field = try #require(rig.hosts.first?.field)
            let crossing = rig.stage.crossingShares()
            let (travel, width) = (Double(field.lane.travel), Double(field.spriteWidth))
            var wasPlaying = false
            for _ in 0..<(4 * 60 * minutes) {
                rig.advance(0.25)
                let now = rig.scheduler.seconds
                let poses = rig.stage.poses
                let play = rig.stage.jointPlay
                let excused = rig.stage.jointExempt
                if play != nil, !wasPlaying { scenes += 1 }
                wasPlaying = play != nil
                var inCrossing = 0
                func rests(_ pose: Pose) -> Bool { pose.from == pose.to || now >= pose.end }
                for (index, pose) in poses.enumerated() {
                    if LaneRules.isCrossing(pose, through: crossing, at: now) { inCrossing += 1 }
                    for other in poses.indices where other > index {
                        if excused.contains(index), excused.contains(other) { continue }
                        guard rests(pose), rests(poses[other]) else { continue }
                        let apart = abs(pose.position(at: now) - poses[other].position(at: now)) * travel
                        if apart < width { overlaps.append("seed \(seed) at \(now): \(index) and \(other) \(apart) points apart") }
                    }
                    // Whoever has a tub out has the room round it too: nobody else is at rest in it.
                    for (owner, tub) in poses.enumerated() where owner != index {
                        guard let prop = tub.prop, prop.look.occupies, rests(pose) else { continue }
                        if excused.contains(index), excused.contains(owner) { continue }
                        for place in [prop.to] + prop.alsoAt {
                            let apart = abs(pose.position(at: now) - place) * travel
                            if apart < width { overlaps.append("seed \(seed) at \(now): \(index) is \(apart) points from \(owner)'s tub or where it hops from") }
                        }
                    }
                }
                if inCrossing > 1 { together.append("seed \(seed) at \(now): \(inCrossing) in the crossing") }
            }
            rig.hide()
        }
        return (overlaps, together, scenes)
    }

    @Test func aCatAndACapybaraAndAnotherCatInAPillAreNeverOnEachOtherExceptThePairWhilePlayingAndNobodyStopsInTheTub() throws {
        let report = try lanes(Screens.pill, seeds: [3, 8, 21, 34], minutes: 40)
        #expect(report.overlaps.isEmpty, "\(report.overlaps.prefix(5))")
        #expect(report.scenes >= 4, "scenes among them: \(report.scenes)")
        let tall = try lanes(Screens.tallPill, seeds: [3, 8], minutes: 30)
        #expect(tall.overlaps.isEmpty, "\(tall.overlaps.prefix(5))")
    }

    @Test func onTheMacsWingsToTheyNeverStopOnEachOtherNorAreTwoInThePortalAtOnce() throws {
        let report = try lanes(Screens.hardware, seeds: [3, 8, 21, 34, 55], minutes: 40)
        #expect(report.overlaps.isEmpty, "\(report.overlaps.prefix(5))")
        #expect(report.crossingTogether.isEmpty, "\(report.crossingTogether.prefix(5))")
    }
}
