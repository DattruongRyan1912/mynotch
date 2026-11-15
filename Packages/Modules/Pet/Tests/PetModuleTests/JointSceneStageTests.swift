import AppKit
import MyNotchCore
import NotchUI
import QuartzCore
import Testing
@testable import PetModule

/// Watches the capybara for `seconds` after a scene was ended early: it stays where it was, with its tub, for as long as it does what it was doing
/// (a walk, or a hop into or out of the tub, are its own day, and the place changes with them). To the last of a pixel: a character that is sent
/// to the very edge of another's room moves it by the rounding of a number.
@MainActor func expectHostStaysPut(_ rig: BodyRig, at index: Int = 1, was before: Pose, seconds: Double, _ label: String) {
    var moves: [CapybaraMove] = []
    for _ in 0..<Int(seconds * 4) {
        rig.advance(0.25)
        let now = rig.stage.poses[index]
        if moves.last != CapybaraMove(now.motion) { moves.append(CapybaraMove(now.motion)) }
        if now.from == now.to, abs(now.from - before.to) > 1e-6, !moves.contains(where: { [.walk, .climbOut, .climbIn].contains($0) }) {
            #expect(Bool(false), "\(label): the capybara jumped from \(before.to) to \(now.to) as \(moves)")
        }
    }
}

/// Everyone plays with the capybara, on a stage: when it happens, what each does while it does, how it ends, and what the views show. One
/// suite for the four guests (the cat's is `CatJointStageTests`), whose scenes are all the same in what they owe each other: only when both
/// share a screen, occasionally, one at a time, neither walks off, and a clean end whatever ends it. Everything runs on the scheduler the
/// test advances.
@Suite(.serialized) @MainActor struct JointSceneStageTests {
    /// The scenes of each guest, which one it plays being a matter of what fits.
    static let scenes: [(kind: CharacterKind, ids: Set<JointScene.ID>)] = [
        (.frog, [.frogOnHead]), (.hamster, [.hamsterBehind, .hamsterNap]), (.penguin, [.penguinBeside]), (.corgi, [.corgiBeside]),
    ]

    func pair(_ geometry: NotchGeometry = Screens.pill, seed: UInt64, kinds: [CharacterKind]) -> BodyRig {
        let rig = BodyRig(geometry: geometry, seed: seed)
        rig.show()
        rig.stage.characters = kinds
        return rig
    }

    func guest(_ rig: BodyRig, _ index: Int = 0) -> String { moveName(rig.stage.characters[index], rig.stage.poses[index]) }

    func capybara(_ rig: BodyRig, _ index: Int = 1) -> CapybaraMove { CapybaraMove(rig.stage.poses[index].motion) }

    /// Ticks until a scene is in progress and `ready` says so, for at most `minutes`.
    func untilScene(_ rig: BodyRig, minutes: Int = 90, ready: (BodyRig) -> Bool = { _ in true }) -> Bool {
        for _ in 0..<(4 * 60 * minutes) {
            rig.advance(0.25)
            if rig.stage.jointPlay != nil, ready(rig) { return true }
        }
        return false
    }

    func click(_ host: CatSpriteView, at point: CGPoint) throws {
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: host.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: host.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        host.mouseDown(with: event)
    }

    /// Whether the guest is in what the scene is made of now: not on its own day.
    func inScene(_ rig: BodyRig, _ pairing: Pairing) -> Bool { pairing.moves.contains(guest(rig)) }

    // MARK: Only when both share a screen

    @Test func itNeverHappensWithOneKindOnAScreenOrWithTheGuestAndTheCapybaraOnTwoScreens() {
        for (kind, _) in Self.scenes {
            for kinds in [[kind], [.capybara], [kind, kind], [.capybara, .capybara]] {
                let rig = pair(seed: 5, kinds: kinds)
                for _ in 0..<(4 * 3600 * 2) { rig.advance(0.25) }
                #expect(rig.stage.jointScenesBegun == 0 && rig.stage.jointPlay == nil, "\(kinds)")
                rig.hide()
            }
            let mac = BodyRig(geometry: Screens.hardware, seed: 3)
            mac.show()
            mac.stage.characters = [kind]
            let pill = BodyRig(geometry: Screens.pill, seed: 3, sharing: mac)
            pill.show()
            pill.stage.characters = [.capybara]
            for _ in 0..<(4 * 3600 * 3) { mac.advance(0.25) }
            #expect(mac.stage.jointScenesBegun == 0 && pill.stage.jointScenesBegun == 0, "\(kind) and the capybara, each on a screen of its own")
            #expect(mac.stage.poses.allSatisfy { !$0.behind && !$0.raised })
        }
    }

    @Test func sharingAScreenTheyDoPlayTogetherNowAndThenOnAPillAndATallPillAndTheMacsWingsAndNeverTooOften() {
        var wings = 0
        for (kind, ids) in Self.scenes {
            for (geometry, seeds) in [(Screens.pill, [3, 8]), (Screens.tallPill, [3, 5]), (Screens.hardware, [3, 8, 21, 55])] as [(NotchGeometry, [UInt64])] {
                var begun = 0
                for seed in seeds {
                    let rig = pair(geometry, seed: seed, kinds: [kind, .capybara])
                    var starts: [TimeInterval] = []
                    var ends: [TimeInterval] = []
                    var wasPlaying = false
                    for _ in 0..<(4 * 3600 * 3) {
                        rig.advance(0.25)
                        let now = rig.scheduler.seconds
                        if let play = rig.stage.jointPlay, !wasPlaying {
                            starts.append(now)
                            #expect(ids.contains(play.scene.id) && play.host == 1 && play.guest == 0, "\(kind) on \(geometry.kind): \(play.scene.id)")
                        }
                        if rig.stage.jointPlay == nil, wasPlaying { ends.append(now) }
                        wasPlaying = rig.stage.jointPlay != nil
                    }
                    begun += starts.count
                    #expect(starts.count <= 3 * 3600 / 180, "\(kind), seed \(seed): \(starts.count) in three hours")
                    for (end, next) in zip(ends, starts.dropFirst()) {
                        #expect(next - end >= JointDirector.spacing.lowerBound - 1, "\(kind), seed \(seed): \(next - end) seconds after the last")
                    }
                    rig.hide()
                }
                #expect(begun >= 3 * seeds.count, "\(kind) on \(geometry.kind): occasional, but it does happen: \(begun)")
                if geometry.kind == .hardware { wings += begun }
            }
        }
        #expect(wings > 100, "on the Mac's wings too: \(wings)")
    }

    @Test func theHamsterHasBothOfItsScenesAndTheOtherGuestsHaveOnlyOne() {
        var played: [CharacterKind: Set<JointScene.ID>] = [:]
        for (kind, _) in Self.scenes {
            for seed: UInt64 in [3, 8, 21, 55, 89] {
                let rig = pair(seed: seed, kinds: [kind, .capybara])
                var wasPlaying = false
                for _ in 0..<(4 * 3600 * 3) {
                    rig.advance(0.25)
                    if let play = rig.stage.jointPlay, !wasPlaying { played[kind, default: []].insert(play.scene.id) }
                    wasPlaying = rig.stage.jointPlay != nil
                }
                rig.hide()
            }
        }
        #expect(played[.hamster] == [.hamsterBehind, .hamsterNap], "\(String(describing: played[.hamster]))")
        #expect(played[.frog] == [.frogOnHead] && played[.penguin] == [.penguinBeside] && played[.corgi] == [.corgiBeside])
    }

    // MARK: Neither walks off

    @Test func neitherWalksOffDuringItWhateverTheMacDoesTheGuestIsInTheScenesPicturesAndTheViewDrawsThemAsTheyAre() throws {
        for pairing in Pairing.all {
            var observed = 0
            for seed: UInt64 in [3, 8, 21] {
                let rig = pair(seed: seed, kinds: [pairing.kind, .capybara])
                let host = try #require(rig.hosts.first)
                let frame = host.screenFrame ?? .zero
                var scenes = 0, tick = 0
                var capybaraPlace: Double?
                var wasPlaying = false
                for _ in 0..<(4 * 3600 * 2) {
                    rig.advance(0.25)
                    tick += 1
                    guard let play = rig.stage.jointPlay, play.scene.id == pairing.scene else {
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
                    let (one, capybara) = (rig.stage.poses[0], rig.stage.poses[1])
                    #expect(play.host == 1 && play.guest == 0)
                    // The capybara is where it is, held (but for the frog's, which sinks and holds).
                    #expect(capybara.from == capybara.to, "the capybara is held where it is")
                    if let place = capybaraPlace { #expect(capybara.to == place, "it does not move: \(capybara.to) for \(place)") } else { capybaraPlace = capybara.to }
                    #expect(pairing.moves.contains(guest(rig)), "seed \(seed): the guest \(guest(rig)) in the scene")
                    if pairing.scene == .frogOnHead { #expect([CapybaraMove.soakSink, .soakDeep].contains(self.capybara(rig)), "\(self.capybara(rig))") }
                    observed += 1
                    // What the view draws.
                    let (guestLayers, capybaraLayers) = (host.characters[0], host.characters[1])
                    let raised = pairing.scene == .frogOnHead && moveName(.frog, one).hasPrefix("head")
                    #expect(one.raised == raised && one.behind == (pairing.scene == .hamsterBehind), "\(guest(rig))")
                    if raised { #expect(guestLayers.sprite.zPosition > capybaraLayers.sprite.zPosition) }
                    if pairing.scene == .hamsterBehind { #expect(guestLayers.sprite.zPosition < capybaraLayers.sprite.zPosition, "the hamster is drawn under the capybara") }
                    #expect(guestLayers.prop.isHidden && one.prop == nil, "nothing out for a scene")
                    #expect(capybaraLayers.prop.isHidden == (capybara.prop == nil))
                }
                #expect(scenes >= 1, "\(pairing.scene), seed \(seed): \(scenes)")
                rig.hide()
            }
            #expect(observed > 100, "\(pairing.scene): \(observed)")
        }
    }

    // MARK: Clicks

    @Test func aClickOnTheGuestIsNotItsStrokeWhileItPlaysItEndsTheSceneAndTheGuestGetsOutOfTheWayAndTheCapybaraStaysPut() throws {
        for pairing in Pairing.all {
            for seed: UInt64 in [3, 8] {
                let rig = pair(seed: seed, kinds: [pairing.kind, .capybara])
                rig.stage.playsMeow = true
                #expect(untilScene(rig, minutes: 120) { $0.stage.jointPlay?.scene.id == pairing.scene && $0.stage.poses[0].from == $0.stage.poses[0].to && pairing.sees.contains(self.guest($0)) && self.guest($0) != "sit" })
                let host = try #require(rig.hosts.first)
                let layers = host.characters[0].sprite
                let before = rig.stage.strokes
                let spot = CGPoint(x: layers.frame.midX, y: layers.frame.midY)
                try click(host, at: spot)
                #expect(rig.stage.strokes == before + 1)
                #expect(rig.meow.plays == 0, "none of them mews")
                #expect(rig.stage.jointPlay == nil, "\(pairing.scene), seed \(seed): over")
                // The capybara does not move, and its tub does not go, because of it.
                expectHostStaysPut(rig, was: rig.stage.poses[1], seconds: 3, "\(pairing.scene), seed \(seed)")
                // The guest is out of the way within a minute, and not behind or over anyone.
                for _ in 0..<(4 * 60) { rig.advance(0.25) }
                #expect(!rig.stage.poses[0].raised && !rig.stage.poses[0].behind)
                #expect(host.characters[0].sprite.zPosition == 0)
                #expect(rig.stage.jointExempt.isEmpty, "\(pairing.scene), seed \(seed): clear of the capybara a minute on")
                rig.hide()
            }
        }
    }

    @Test func aClickOnTheCapybaraSquintsItEndsTheSceneAndTheGuestLeavesAndTheFrogComesDownAndTheCapybaraComesUp() throws {
        for pairing in Pairing.all {
            for seed: UInt64 in [3, 8] {
                let rig = pair(seed: seed, kinds: [pairing.kind, .capybara])
                #expect(untilScene(rig, minutes: 120) { $0.stage.jointPlay?.scene.id == pairing.scene && $0.stage.poses[0].from == $0.stage.poses[0].to && pairing.sees.contains(self.guest($0)) && self.guest($0) != "sit" })
                let host = try #require(rig.hosts.first)
                let capy = host.characters[1].sprite
                // On its body, below whatever is on its head, whichever way it faces.
                try click(host, at: CGPoint(x: capy.frame.minX + 16, y: capy.frame.minY + 5))
                #expect(rig.stage.jointPlay == nil)
                if pairing.scene == .frogOnHead {
                    let move = capybara(rig)
                    #expect([CapybaraMove.soakRise, .soakSink].contains(move), "it comes up and does not jump for joy over a frog: \(move)")
                    #expect(guest(rig) == "headHopOff" || guest(rig) == "headHopOn" || guest(rig) == "headSit", "the frog comes down: \(guest(rig))")
                } else {
                    let move = capybara(rig)
                    #expect([CapybaraMove.happy, .soakHappy].contains(move), "\(move)")
                }
                for _ in 0..<(4 * 60) { rig.advance(0.25) }
                #expect(!rig.stage.poses[0].raised && !rig.stage.poses[0].behind && rig.stage.jointExempt.isEmpty)
                #expect(capybara(rig) != .soakDeep && capybara(rig) != .soakSink, "up")
                rig.hide()
            }
        }
    }

    @Test func aClickWhereOnlyTheHamsterPeeksOverTheCapybarasBackIsTheHamstersAndOnItsBodyTheCapybaras() throws {
        var heads = 0, bodies = 0
        for seed: UInt64 in [3, 8, 21, 34] {
            for onTheHead in [true, false] {
                let rig = pair(seed: seed, kinds: [.hamster, .capybara])
                rig.stage.playsMeow = true
                #expect(untilScene(rig, minutes: 120) { $0.stage.jointPlay?.scene.id == .hamsterBehind && self.guest($0) == "freeze" })
                let host = try #require(rig.hosts.first)
                #expect(rig.stage.poses[0].behind)
                let (hamster, capybara) = (host.characters[0].sprite, host.characters[1].sprite)
                #expect(hamster.zPosition < capybara.zPosition)
                let facing = rig.stage.poses[1].facing
                // A point of the picture, as a column and a row from the top of its frame, for a capybara that faces right (and the mirror image
                // of it for one that faces left), in the view's own coordinates, which go up from the bottom.
                func point(of layer: CALayer, column: CGFloat, row: CGFloat) -> CGPoint {
                    let across = facing == .right ? column : 32 - column
                    let unit = layer.frame.width / 32
                    return CGPoint(x: layer.frame.minX + across * unit, y: layer.frame.maxY - row * unit)
                }
                let strokes = rig.stage.strokes
                if onTheHead {
                    // The top of the hamster's head, over the capybara's back (which is row 13) and short of the capybara's head, which begins at
                    // column 16: nothing but the hamster is drawn there.
                    try click(host, at: point(of: hamster, column: 11.5, row: 8.5))
                    #expect(rig.stage.strokes == strokes + 1)
                    let move = capybaraMove(rig)
                    #expect(move != .happy && move != .soakHappy, "the hamster's stroke and not the capybara's: \(move)")
                    heads += 1
                } else {
                    // The capybara's rump, which is drawn over the hamster's body.
                    try click(host, at: point(of: capybara, column: 9.5, row: 17.5))
                    #expect(rig.stage.strokes == strokes + 1)
                    let move = capybaraMove(rig)
                    #expect(move == .happy || move == .soakHappy, "the capybara's stroke: \(move)")
                    bodies += 1
                }
                #expect(rig.meow.plays == 0, "neither of them mews")
                #expect(rig.stage.jointPlay == nil, "and the scene is over for a stroke on either")
                rig.hide()
            }
        }
        #expect(heads == 4 && bodies == 4)
    }

    func capybaraMove(_ rig: BodyRig) -> CapybaraMove { capybara(rig) }

    // MARK: Ending cleanly

    @Test func ifTheCapybaraIsTakenOffTheScreenMidSceneTheGuestGetsOutOfTheWayAndIsNeverLeftBehindOrOverNothing() throws {
        for pairing in Pairing.all {
            for seed: UInt64 in [3, 8, 21] {
                let rig = pair(seed: seed, kinds: [pairing.kind, .capybara])
                #expect(untilScene(rig, minutes: 120) { $0.stage.jointPlay?.scene.id == pairing.scene && pairing.sees.contains(self.guest($0)) && self.guest($0) != "sit" })
                let host = try #require(rig.hosts.first)
                let begun = rig.stage.jointScenesBegun
                rig.stage.characters = [pairing.kind]
                #expect(rig.stage.jointPlay == nil && host.characters.count == 1)
                for _ in 0..<(4 * 90) { rig.advance(0.25) }
                let pose = rig.stage.poses[0]
                #expect(!pose.raised && !pose.behind && host.characters[0].sprite.zPosition == 0, "\(pairing.scene), seed \(seed)")
                #expect(rig.stage.jointScenesBegun == begun, "and nothing begins on a stage with no pair")
                rig.hide()
            }
        }
    }

    @Test func ifTheGuestIsTakenOffTheScreenTheCapybaraIsLetGoRisesIfItHadSunkAndGoesOnWithItsDayAndItsTubGoesAtTheEnd() throws {
        for pairing in Pairing.all {
            for seed: UInt64 in [3, 8, 21] {
                let rig = pair(seed: seed, kinds: [pairing.kind, .capybara])
                #expect(untilScene(rig, minutes: 120) { $0.stage.jointPlay?.scene.id == pairing.scene && pairing.sees.contains(self.guest($0)) && self.guest($0) != "sit" })
                let host = try #require(rig.hosts.first)
                rig.stage.characters = [.capybara]
                #expect(rig.stage.jointPlay == nil && host.characters.count == 1)
                if pairing.scene == .frogOnHead {
                    let move = CapybaraMove(rig.stage.poses[0].motion)
                    #expect([CapybaraMove.soakRise, .soakSink, .soak].contains(move), "up it comes: \(move)")
                }
                var seenDeep = 0
                for _ in 0..<(4 * 900) {
                    rig.advance(0.25)
                    let pose = rig.stage.poses[0]
                    if CapybaraMove(pose.motion) == .soakDeep { seenDeep += 1 }
                    #expect(host.characters[0].prop.isHidden == (pose.prop == nil), "\(CapybaraMove(pose.motion)) with \(String(describing: pose.prop?.look))")
                }
                #expect(seenDeep == 0, "it never stays sunk with nobody on its head: \(seenDeep)")
                rig.idle.seconds = 10_000
                for _ in 0..<(4 * 300) { rig.advance(0.25) }
                #expect(rig.stage.poses[0].prop == nil && host.characters[0].prop.isHidden, "\(pairing.scene), seed \(seed)")
                rig.hide()
            }
        }
    }

    @Test func anyChangeInWhoIsOnTheStageEndsTheSceneAndAGuestOnItsWayOutIsStillExcusedFromTheCapybarasRoomUnderItsNewNumber() throws {
        for pairing in Pairing.all {
            let rig = pair(seed: 3, kinds: [pairing.kind, .capybara, .cat])
            #expect(untilScene(rig, minutes: 120) { $0.stage.jointPlay?.scene.id == pairing.scene })
            rig.stage.characters = [pairing.kind, .capybara]
            #expect(rig.stage.jointPlay == nil, "their numbers may have changed")
            #expect(rig.stage.jointExempt.isEmpty || rig.stage.jointExempt == [0, 1], "\(rig.stage.jointExempt)")
            for _ in 0..<(4 * 90) { rig.advance(0.25) }
            #expect(rig.stage.poses.count == 2 && rig.stage.jointExempt.isEmpty)
            rig.hide()
        }
    }

    @Test func aCharacterTakenOffBeforeThePairRenumbersThemAndTheGuestOnItsWayOutIsStillExcusedFromTheCapybarasRoomAndItStaysPut() throws {
        var checked = 0
        for pairing in Pairing.all {
            for seed: UInt64 in [3, 8, 21] {
                // The cat is first, the guest second and the capybara last: when the cat goes they are 0 and 1.
                let rig = pair(seed: seed, kinds: [.cat, pairing.kind, .capybara])
                var found = false
                for _ in 0..<(4 * 60 * 120) {
                    rig.advance(0.25)
                    if let play = rig.stage.jointPlay, play.scene.id == pairing.scene, rig.stage.poses[1].from == rig.stage.poses[1].to,
                       pairing.sees.contains(moveName(pairing.kind, rig.stage.poses[1])), moveName(pairing.kind, rig.stage.poses[1]) != "sit" {
                        found = true
                        break
                    }
                }
                guard found else { rig.hide(); continue }
                #expect(rig.stage.jointPlay?.guest == 1 && rig.stage.jointPlay?.host == 2)
                let before = rig.stage.poses[2]
                rig.stage.characters = [pairing.kind, .capybara]
                #expect(rig.stage.jointPlay == nil)
                // Still on its way out, the guest owes the capybara nothing under its new number, and the capybara is where it was.
                #expect(rig.stage.jointExempt == [0, 1], "\(pairing.scene), seed \(seed): \(rig.stage.jointExempt)")
                expectHostStaysPut(rig, at: 1, was: before, seconds: 8, "\(pairing.scene), seed \(seed)")
                for _ in 0..<(4 * 60) { rig.advance(0.25) }
                #expect(rig.stage.jointExempt.isEmpty, "clear of the capybara a minute on")
                checked += 1
                rig.hide()
            }
        }
        #expect(checked >= 8, "\(checked)")
    }

    @Test func reduceMotionStillsEveryoneAndTheSceneIsOverForGoodWithNobodyBehindOrOverOrSunk() throws {
        for pairing in Pairing.all {
            let rig = pair(seed: 8, kinds: [pairing.kind, .capybara])
            #expect(untilScene(rig, minutes: 120) { $0.stage.jointPlay?.scene.id == pairing.scene && pairing.sees.contains(self.guest($0)) })
            let host = try #require(rig.hosts.first)
            rig.knobs.reducesMotion = true
            rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
            #expect(runLoop(until: { !rig.stage.isTicking }, seconds: 5))
            #expect(rig.stage.jointPlay == nil)
            #expect(host.characters.allSatisfy { $0.sprite.zPosition == 0 && $0.prop.isHidden })
            rig.knobs.reducesMotion = false
            rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
            #expect(runLoop(until: { rig.stage.isTicking }, seconds: 5))
            #expect(rig.stage.jointPlay == nil && rig.stage.jointExempt.isEmpty)
            #expect(rig.stage.poses.allSatisfy { !$0.raised && !$0.behind }, "\(pairing.scene)")
            #expect(capybara(rig) != .soakDeep && capybara(rig) != .soakSink)
            rig.hide()
        }
    }

    @Test func aNotchThatLeavesTheScreenMidSceneComesBackWithBothOnTheFloorAndNoSceneAFewMinutesOff() throws {
        for pairing in Pairing.all {
            let rig = pair(seed: 3, kinds: [pairing.kind, .capybara])
            #expect(untilScene(rig, minutes: 120) { $0.stage.jointPlay?.scene.id == pairing.scene && pairing.sees.contains(self.guest($0)) })
            rig.hide()
            rig.show()
            #expect(rig.stage.jointPlay == nil && rig.stage.jointExempt.isEmpty)
            #expect(rig.stage.poses.allSatisfy { !$0.raised && !$0.behind }, "\(pairing.scene)")
            #expect(capybara(rig) != .soakDeep && capybara(rig) != .soakSink)
            let begun = rig.stage.jointScenesBegun
            for _ in 0..<(4 * 120) { rig.advance(0.25) }
            #expect(rig.stage.jointScenesBegun == begun, "a few minutes from now, not at once")
            rig.hide()
        }
    }

    @Test func aNotchThatChangesSizeMidSceneEndsItBecauseTheLaneIsNotWhatItWasMadeFor() throws {
        for pairing in Pairing.all {
            let rig = pair(seed: 3, kinds: [pairing.kind, .capybara])
            #expect(untilScene(rig, minutes: 120) { $0.stage.jointPlay?.scene.id == pairing.scene && pairing.sees.contains(self.guest($0)) })
            let size = rig.container.frame.size
            rig.container.setFrameSize(NSSize(width: size.width + 40, height: size.height))
            rig.container.layoutSubtreeIfNeeded()
            #expect(rig.stage.jointPlay == nil, "\(pairing.scene): the lane changed under them")
            for _ in 0..<(4 * 90) { rig.advance(0.25) }
            #expect(rig.stage.poses.allSatisfy { !$0.raised && !$0.behind }, "\(pairing.scene)")
            rig.hide()
        }
    }

    @Test func aSceneNeverGoesOnForMoreThanTheDirectorsLongestAndItsGuestIsOutOfTheCapybarasWayWhenItEnds() {
        for pairing in Pairing.all {
            let rig = pair(seed: 21, kinds: [pairing.kind, .capybara])
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
            #expect(longest > 10 && longest <= JointDirector.longest + 1, "\(pairing.scene): \(longest)")
        }
    }

    // MARK: Nothing jumps when it is over

    /// How the capybara looks after a scene is ended early, by each of the ways it can be: it stays where it is for as long as it stays, and its tub is
    /// not taken from it, because of anything that is done to it.
    @Test func whenASceneIsEndedEarlyTheCapybaraDoesNotJumpAndItsTubIsNotTakenFromIt() throws {
        var ended = 0, withATub = 0
        for pairing in Pairing.all {
            for seed: UInt64 in [3, 8, 21, 34] {
                let rig = pair(seed: seed, kinds: [pairing.kind, .capybara])
                #expect(untilScene(rig, minutes: 120) { $0.stage.jointPlay?.scene.id == pairing.scene && $0.stage.poses[0].from == $0.stage.poses[0].to && pairing.sees.contains(self.guest($0)) && self.guest($0) != "sit" })
                let host = try #require(rig.hosts.first)
                let before = rig.stage.poses[1]
                let size = rig.container.frame.size
                // The lane moves: the way a scene most easily ends early.
                rig.container.setFrameSize(NSSize(width: size.width + 40, height: size.height))
                rig.container.layoutSubtreeIfNeeded()
                #expect(rig.stage.jointPlay == nil)
                ended += 1
                if before.prop != nil { withATub += 1 }
                _ = host
                expectHostStaysPut(rig, was: before, seconds: 8, "\(pairing.scene), seed \(seed)")
                rig.hide()
            }
        }
        #expect(ended >= 15 && withATub >= 4, "\(ended) scenes ended early, \(withATub) of them with a tub")
    }

    // MARK: Occasionally, one at a time

    @Test func atMostOneAtATimeWithTwoOfTheGuestsAndTheCapybaraAndNeverSoonerThanAFewMinutesAfterTheLast() {
        for (kinds, seed) in [([CharacterKind.hamster, .capybara, .penguin], UInt64(3)), ([.corgi, .capybara, .frog], 8), ([.cat, .capybara, .corgi], 21)] {
            let rig = pair(seed: seed, kinds: kinds)
            var begun = 0
            var starts: [TimeInterval] = []
            var ends: [TimeInterval] = []
            var wasPlaying = false
            for _ in 0..<(4 * 3600 * 4) {
                rig.advance(0.25)
                let now = rig.scheduler.seconds
                #expect(rig.stage.jointScenesBegun - begun <= 1)
                if rig.stage.jointScenesBegun != begun { starts.append(now) }
                begun = rig.stage.jointScenesBegun
                // Only two are in a scene, and they are the capybara and one of the others.
                let exempt = rig.stage.jointExempt
                #expect(exempt.count <= 2, "\(kinds): \(exempt)")
                if let play = rig.stage.jointPlay { #expect(play.host == 1 && Set([play.guest]).isSubset(of: [0, 2])) }
                let playing = rig.stage.jointPlay != nil
                if wasPlaying, !playing { ends.append(now) }
                wasPlaying = playing
            }
            #expect(starts.count >= 3, "\(kinds): occasional, but it does happen: \(starts.count) in four hours")
            #expect(starts.count <= 4 * 3600 / 180, "\(kinds): \(starts.count)")
            for (end, next) in zip(ends, starts.dropFirst()) { #expect(next - end >= JointDirector.spacing.lowerBound - 1, "\(kinds): \(next - end) seconds after the last") }
            rig.hide()
        }
    }

    // MARK: Three on a lane

    /// The characters of one stage looked at after every waking: no two at rest closer than a picture but the two of a scene while they play or
    /// are only just out of it, and nobody at rest by the capybara's tub and the places that go with it, and one at a time in the portal.
    func lanes(_ geometry: NotchGeometry, kinds: [CharacterKind], seeds: [UInt64], minutes: Int) throws -> (overlaps: [String], inTheWay: [String], scenes: Int) {
        var overlaps: [String] = []
        var inTheWay: [String] = []
        var scenes = 0
        for seed in seeds {
            let rig = BodyRig(geometry: geometry, seed: seed)
            rig.show()
            rig.stage.characters = kinds
            let field = try #require(rig.hosts.first?.field)
            let (travel, width) = (Double(field.lane.travel), Double(field.spriteWidth))
            var wasPlaying = false
            for tick in 0..<(4 * 60 * minutes) {
                rig.cpu.value = tick % 3000 < 1500 ? 0.05 : 0.8
                rig.advance(0.25)
                let now = rig.scheduler.seconds
                let poses = rig.stage.poses
                let excused = rig.stage.jointExempt
                if rig.stage.jointPlay != nil, !wasPlaying { scenes += 1 }
                wasPlaying = rig.stage.jointPlay != nil
                func rests(_ pose: Pose) -> Bool { pose.from == pose.to || now >= pose.end }
                for (index, pose) in poses.enumerated() {
                    for other in poses.indices where other > index {
                        if excused.contains(index), excused.contains(other) { continue }
                        guard rests(pose), rests(poses[other]) else { continue }
                        let apart = abs(pose.position(at: now) - poses[other].position(at: now)) * travel
                        if apart < width { overlaps.append("seed \(seed) at \(now): \(kinds[index].rawValue) and \(kinds[other].rawValue) \(Int(apart)) points apart") }
                    }
                    for (owner, other) in poses.enumerated() where owner != index {
                        guard let prop = other.prop, prop.look.occupies, rests(pose) else { continue }
                        if excused.contains(index), excused.contains(owner) { continue }
                        for place in [prop.to] + prop.alsoAt where abs(pose.position(at: now) - place) * travel < width {
                            inTheWay.append("seed \(seed) at \(now): \(kinds[index].rawValue) is \(Int(abs(pose.position(at: now) - place) * travel)) points from \(kinds[owner].rawValue)'s prop")
                        }
                    }
                }
            }
            rig.hide()
        }
        return (overlaps, inTheWay, scenes)
    }

    @Test func threeOnAPillAreNeverOnEachOtherOrInTheRoomOfWhatIsOutExceptThePairThatPlaysAndIsGettingOutOfTheWay() throws {
        for kinds in [[CharacterKind.hamster, .capybara, .penguin], [.corgi, .capybara, .frog], [.frog, .capybara, .hamster], [.penguin, .capybara, .corgi]] {
            let report = try lanes(Screens.pill, kinds: kinds, seeds: [3, 8, 21, 34], minutes: 40)
            #expect(report.overlaps.isEmpty, "\(kinds): \(report.overlaps.prefix(3))")
            #expect(report.inTheWay.isEmpty, "\(kinds): \(report.inTheWay.prefix(3))")
            #expect(report.scenes >= 4, "\(kinds): scenes among them: \(report.scenes)")
        }
    }

    @Test func theSameInTheTallPillAndOnTheMacsWings() throws {
        for (geometry, rows) in [
            (Screens.tallPill, [[CharacterKind.hamster, .capybara, .penguin], [.corgi, .capybara, .frog]]),
            (Screens.hardware, [[CharacterKind.hamster, .capybara, .penguin], [.corgi, .capybara, .frog], [.cat, .capybara, .hamster]]),
        ] {
            for kinds in rows {
                let report = try lanes(geometry, kinds: kinds, seeds: [3, 8, 21], minutes: 40)
                #expect(report.overlaps.isEmpty, "\(kinds) on \(geometry.kind): \(report.overlaps.prefix(3))")
                #expect(report.inTheWay.isEmpty, "\(kinds) on \(geometry.kind): \(report.inTheWay.prefix(3))")
            }
        }
    }
}
