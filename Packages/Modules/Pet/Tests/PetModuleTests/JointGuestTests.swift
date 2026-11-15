import Foundation
import Testing
@testable import PetModule

/// What a character is doing, by the name of its move, whichever species it is.
func moveName(_ kind: CharacterKind, _ pose: Pose) -> String {
    switch kind {
    case .cat: "\(CatMove(pose.motion))"
    case .capybara: "\(CapybaraMove(pose.motion))"
    case .hamster: "\(HamsterMove(pose.motion))"
    case .penguin: "\(PenguinMove(pose.motion))"
    case .corgi: "\(CorgiMove(pose.motion))"
    case .frog: "\(FrogMove(pose.motion))"
    }
}

/// One of the scenes the capybara plays with the others, and what its guest does in it.
struct Pairing {
    let scene: JointScene.ID
    let kind: CharacterKind
    /// Every move the guest may be in from the moment it is asked to the moment it is done, and the ones it must be in at some time.
    let moves: Set<String>
    let sees: Set<String>

    static let all: [Pairing] = [
        Pairing(
            scene: .hamsterBehind, kind: .hamster, moves: ["scurry", "sitDown", "standUp", "sit", "freeze", "blink"], sees: ["scurry", "freeze", "sit"]
        ),
        Pairing(
            scene: .hamsterNap, kind: .hamster, moves: ["scurry", "sitDown", "standUp", "sit", "curl", "ball", "sleep", "uncurl"],
            sees: ["scurry", "curl", "sleep", "uncurl"]
        ),
        Pairing(
            scene: .penguinBeside, kind: .penguin,
            moves: ["waddle", "stand", "blink", "flap", "bellyDown", "slide", "lie", "getUp", "lookTurn", "lookBack"], sees: ["slide", "getUp", "stand"]
        ),
        Pairing(
            scene: .corgiBeside, kind: .corgi, moves: ["trot", "stand", "blink", "wiggle", "lieDown", "lie", "getUp", "sit", "sitDown", "standUp"],
            sees: ["trot", "lieDown", "lie", "getUp"]
        ),
        Pairing(
            scene: .frogOnHead, kind: .frog, moves: ["hop", "sit", "blink", "puff", "headHopOn", "headSit", "headBlink", "headHopOff"],
            sees: ["hop", "headHopOn", "headSit", "headHopOff"]
        ),
    ]
}

/// A guest of any of the species in a scene with the capybara, driven by a clock the test holds and a capybara that holds still where it
/// is (and, for the frog, that sinks into the water when it is time).
struct PairDrive {
    var brain: any CharacterBrain
    let pairing: Pairing
    var now: TimeInterval = 0
    var senses = CatSenses(idleSeconds: 5, hour: 14)
    var tuning = CatTuning()
    var travel = 260.0
    var lane = LaneContext()
    var host: Pose
    /// Whether the capybara has a tub, and the time after which it has sunk in it to its eyes (nil: never).
    var tub = false
    var deepAt: TimeInterval?
    /// Whether the stage hands the guest the sight of the capybara (it does while the scene is in progress).
    var sight = true
    /// Every picture the guest had, one for each time it changed or was extended, with when.
    private(set) var every: [(at: TimeInterval, pose: Pose)] = []
    /// Where it was after every waking, in pixels of its picture.
    private(set) var places: [Double] = []

    var kind: CharacterKind { pairing.kind }

    static func capybara(
        at place: Double = 0.5, facing: Facing = .right, tub: Bool = false, deep: Bool = false, travel: Double = 260
    ) -> Pose {
        let way = facing == .right ? 1.0 : -1.0
        var pose = Pose(
            motion: (deep ? CapybaraMove.soakDeep : (tub ? .soak : .sit)).motion, facing: facing, from: place, to: place, began: 0, duration: 100_000
        )
        pose.perch = Perch(dx: 0, spot: deep ? .head : .back)
        if tub { pose.prop = PoseProp(look: CapybaraProp.tubRippling.look, from: place, to: place, alsoAt: [place - way * 24 / travel]) }
        return pose
    }

    init(
        _ pairing: Pairing, seed: UInt64 = 1, position: Double = 0.2, host: Pose? = nil, tub: Bool? = nil, travel: Double = 260
    ) {
        self.pairing = pairing
        self.travel = travel
        let soaking = tub ?? (pairing.scene == .frogOnHead)
        self.tub = soaking
        self.host = host ?? Self.capybara(tub: soaking, travel: travel)
        brain = pairing.kind.species.makeBrain(seed: seed, now: 0, position: position)
        brain.resume(now: 0)
        // The frog is let to hop on a moment after the capybara has begun to sink.
        deepAt = pairing.scene == .frogOnHead ? 1.5 : nil
    }

    var invite: JointInvite { JointInvite(scene: pairing.scene, role: .guest, partner: host, lane: lane) }

    var pose: Pose { brain.pose }

    var name: String { moveName(kind, brain.pose) }

    /// Where the capybara and what it has out take room, in pixels.
    var hostPlaces: [Double] {
        [host.to * travel] + (host.prop.map { [$0.to * travel] + $0.alsoAt.map { $0 * travel } } ?? [])
    }

    /// How far the guest is, at rest in `pose`, from the nearest place of the capybara's.
    func clearance(of pose: Pose) -> Double {
        hostPlaces.map { abs(pose.to * travel - $0) }.min() ?? .infinity
    }

    @discardableResult
    mutating func run(_ seconds: Double, each: (inout PairDrive) -> Void = { _ in }) -> BrainOutcome {
        var last = BrainOutcome.unchanged
        let end = now + seconds
        while now < end - 1e-9 {
            now += 0.25
            if let deepAt, now >= deepAt, !(host.perch?.spot == .head) { host = Self.capybara(at: host.to, facing: host.facing, tub: true, deep: true, travel: travel) }
            var lane = self.lane
            if sight { lane.joint = JointSight(scene: pairing.scene, role: .guest, partner: host) }
            let outcome = brain.update(now: now, senses: senses, tuning: tuning, travel: travel, lane: lane)
            if outcome != .unchanged { every.append((now, brain.pose)) }
            if outcome != .unchanged { last = outcome }
            places.append(brain.pose.position(at: now) * travel)
            each(&self)
        }
        return last
    }

    /// Wakes it once so that it knows the lane, then asks it to join.
    mutating func join() -> Bool {
        run(0.25)
        guard brain.canJoin(invite, now: now) else { return false }
        brain.join(invite, now: now)
        every.append((now, brain.pose))
        return true
    }

    /// Runs until it is done with the scene, or `seconds` have gone by. True if it is done.
    @discardableResult
    mutating func runScene(_ seconds: Double = 120) -> Bool {
        let end = now + seconds
        while brain.jointScene != nil, now < end { run(0.25) }
        return brain.jointScene == nil
    }

    /// Joins, and says so if it would not.
    mutating func mustJoin(_ label: String = "") {
        let joined = join()
        #expect(joined, "\(pairing.scene) \(label): it did not join")
    }

    /// Runs until the scene is over, and says so if it was not within `seconds`.
    mutating func mustFinish(_ seconds: Double = 120, _ label: String = "") {
        let over = runScene(seconds)
        #expect(over, "\(pairing.scene) \(label): not over after \(seconds) seconds")
    }

    /// The names of the moves it went through, one for each change of picture.
    var moves: [String] { every.map { moveName(kind, $0.pose) } }
}

@Suite struct JointGuestTests {
    static let clearance = JointRoom.clearance

    // MARK: A whole scene

    @Test func eachGuestComesPlaysAndGoesAndIsOutOfTheCapybarasWayWhenItIsDoneAndThenItsDayGoesOn() {
        for pairing in Pairing.all {
            var seen: Set<String> = []
            for seed in 1...14 as ClosedRange<UInt64> {
                for (position, facing) in [(0.1, Facing.right), (0.85, .left), (0.9, .right), (0.15, .left)] {
                    let host = PairDrive.capybara(at: 0.5, facing: facing, tub: pairing.scene == .frogOnHead || seed % 3 == 0)
                    var drive = PairDrive(pairing, seed: seed, position: position, host: host, tub: host.prop != nil)
                    let label = "\(pairing.scene), seed \(seed), from \(position), host facing \(facing)"
                    let joined = drive.join()
                    #expect(joined, "\(label): it did not join")
                    guard joined else { continue }
                    #expect(drive.brain.jointScene == pairing.scene)
                    drive.mustFinish(120, label)
                    // Only the moves the scene is made of, and none of them with a prop out.
                    for entry in drive.every {
                        #expect(pairing.moves.contains(moveName(pairing.kind, entry.pose)), "\(label): \(moveName(pairing.kind, entry.pose))")
                        #expect(entry.pose.prop == nil, "\(label): nothing out in a scene")
                    }
                    seen.formUnion(drive.moves)
                    // Out of the capybara's way, and of what it has out, when it is done: nobody is moved with a jump when the scene is over.
                    let clear = drive.clearance(of: drive.pose)
                    #expect(clear >= Self.clearance - 1e-6, "\(label): \(clear) points from the capybara's room when it was done")
                    // Whole, not a jump anywhere: the most a picture moves in a quarter of a second is a slide's, and the hop on to a head.
                    for (before, after) in zip(drive.places, drive.places.dropFirst()) {
                        #expect(abs(after - before) <= 14, "\(label): jumped from \(before) to \(after)")
                    }
                    // Its day goes on, and the scene's moves are not played again by themselves.
                    let from = drive.every.count
                    drive.run(600)
                    #expect(drive.brain.jointScene == nil)
                    for entry in drive.every[from...] {
                        #expect(!(entry.pose.behind), "\(label): behind nobody after the scene")
                        #expect(!(entry.pose.raised), "\(label): over nobody after the scene")
                    }
                }
            }
            #expect(pairing.sees.isSubset(of: seen), "\(pairing.scene): \(pairing.sees.subtracting(seen)) never seen, only \(seen.sorted())")
        }
    }

    @Test func itIsByTheCapybaraWhereItIsToBeAndNotAnywhereElseWhileItPlays() {
        let host = 0.5
        for pairing in Pairing.all where pairing.scene != .frogOnHead {
            for facing in [Facing.right, .left] {
                var drive = PairDrive(pairing, seed: 3, position: 0.1, host: PairDrive.capybara(at: host, facing: facing, tub: false))
                drive.mustJoin()
                var together: [Double] = []
                while drive.brain.jointScene != nil, drive.now < 120 {
                    drive.run(0.25)
                    let pose = drive.pose
                    // At rest, in the middle of the scene, which is not the going or the coming.
                    if pose.from == pose.to, drive.brain.jointScene != nil, drive.clearance(of: pose) < Self.clearance - 1e-6 { together.append(abs(pose.to - host) * 260) }
                }
                #expect(together.count > 20, "\(pairing.scene): it is by the capybara for a while")
                let near = together.sorted()[together.count / 2]
                switch pairing.scene {
                case .hamsterBehind: #expect(abs(near - 5) < 1e-6, "over its rump: \(near)")
                case .hamsterNap: #expect([24.0, 22.0].contains { abs(near - $0) < 1e-6 }, "touching it: \(near)")
                case .penguinBeside: #expect([25.0, 26.0].contains { abs(near - $0) < 1e-6 }, "beside it: \(near)")
                case .corgiBeside: #expect(abs(near - 30) < 1e-6, "lying beside it: \(near)")
                default: break
                }
            }
        }
    }

    @Test func theHamsterHidesBehindItAndIsDrawnUnderItAndOnlyThen() {
        let pairing = Pairing.all[0]
        var drive = PairDrive(pairing, seed: 5, position: 0.15)
        drive.mustJoin()
        var inScene = 0
        while drive.brain.jointScene != nil, drive.now < 120 {
            drive.run(0.25)
            if drive.brain.jointScene != nil {
                inScene += 1
                #expect(drive.pose.behind && !drive.pose.raised, "\(drive.name)")
            }
        }
        #expect(inScene > 40)
        drive.run(30)
        #expect(drive.every.last.map { !$0.pose.behind } ?? false)
        // The other hamster scene, and every other guest, is not drawn under anybody.
        for other in Pairing.all where other.scene != .hamsterBehind {
            var one = PairDrive(other, seed: 5, position: 0.15)
            one.mustJoin()
            one.runScene()
            #expect(one.every.allSatisfy { !$0.pose.behind }, "\(other.scene)")
        }
    }

    @Test func theFrogWaitsForTheCapybaraToHaveSunkHopsOnToItsHeadSitsOverItAndHopsOffTheOtherWay() throws {
        let pairing = Pairing.all[4]
        for seed in 1...10 as ClosedRange<UInt64> {
            var drive = PairDrive(pairing, seed: seed, position: 0.85)
            drive.deepAt = 6
            drive.mustJoin()
            var firstHop: TimeInterval?
            while drive.brain.jointScene != nil, drive.now < 120 {
                drive.run(0.25)
                if firstHop == nil, drive.name == "headHopOn" { firstHop = drive.now }
            }
            // Not before the capybara was deep, and promptly after.
            let hop = try #require(firstHop, "seed \(seed)")
            #expect(hop >= 6 && hop <= 8, "seed \(seed): it hopped on at \(hop), the capybara was deep at 6")
            let up = try #require(drive.every.first { moveName(.frog, $0.pose) == "headHopOn" }?.pose)
            let down = try #require(drive.every.first { moveName(.frog, $0.pose) == "headHopOff" }?.pose)
            // On to the head, from behind the capybara, facing the way it faces; off it the other way.
            #expect(up.facing == .right && up.to == 0.5 && up.from < up.to)
            #expect(abs((up.to - up.from) * 260 - 24) <= 9 + 1e-6, "a hop of about the length of one: \((up.to - up.from) * 260)")
            #expect(down.facing == .left && down.from == 0.5 && down.to == up.from)
            let sits = drive.every.filter { ["headSit", "headBlink"].contains(moveName(.frog, $0.pose)) }
            #expect(sits.count > 2)
            for entry in sits { #expect(entry.pose.from == 0.5 && entry.pose.to == 0.5 && entry.pose.facing == .right && entry.pose.raised) }
            #expect(drive.every.filter { moveName(.frog, $0.pose).hasPrefix("head") }.allSatisfy { $0.pose.raised })
            #expect(drive.every.filter { !moveName(.frog, $0.pose).hasPrefix("head") }.allSatisfy { !$0.pose.raised })
            // Whole hops from where it was, and out of the room of the tub too: the place it hops into it from is behind the capybara.
            #expect(drive.clearance(of: drive.pose) >= Self.clearance - 1e-6)
        }
    }

    @Test func theFrogOnTheHeadComesDownAtOnceIfTheCapybaraComesUpAndIsNeverOnItAtAnotherTime() {
        var drive = PairDrive(Pairing.all[4], seed: 4, position: 0.85)
        drive.mustJoin()
        while drive.name != "headSit", drive.now < 60 { drive.run(0.25) }
        #expect(drive.name == "headSit")
        // The capybara is not deep any more: it has risen.
        drive.deepAt = nil
        drive.host = PairDrive.capybara(at: 0.5, facing: .right, tub: true)
        drive.run(0.25)
        #expect(drive.name == "headHopOff", "it hops off at once, with the capybara coming up: \(drive.name)")
        drive.mustFinish(60)
        #expect(drive.moves.filter { $0 == "headHopOff" }.count == 1)
        #expect(drive.clearance(of: drive.pose) >= Self.clearance - 1e-6)
    }

    @Test func theFrogNeverHopsOnWhenTheCapybaraNeverSinksAndGivesUpWithTheDirectorsLimit() {
        var drive = PairDrive(Pairing.all[4], seed: 2, position: 0.85)
        drive.deepAt = nil
        drive.mustJoin()
        drive.run(100)
        #expect(!drive.moves.contains("headHopOn"), "it waits for a head to sit on")
        #expect(drive.brain.jointScene == .frogOnHead)
        _ = drive.brain.leaveJoint(now: drive.now)
        drive.mustFinish(60)
        #expect(!drive.moves.contains("headHopOn"))
    }

    @Test func thePenguinLooksTheWayTheCapybaraLooksAndTurnsRoundThroughFacingTheViewerIfItCameToItsSnoutFromTheFront() {
        let pairing = Pairing.all[2]
        var turned = 0, straight = 0
        for facing in [Facing.right, .left] {
            for position in [0.05, 0.3, 0.7, 0.95] {
                for seed in 1...6 as ClosedRange<UInt64> {
                    var drive = PairDrive(pairing, seed: seed, position: position, host: PairDrive.capybara(at: 0.5, facing: facing))
                    drive.mustJoin()
                    // How it stands by the capybara once it is there, and has turned round if it is to.
                    var holds: [(at: TimeInterval, facing: Facing)] = []
                    var turnedAt: TimeInterval?
                    while drive.brain.jointScene != nil, drive.now < 120 {
                        drive.run(0.25)
                        if drive.name == "lookBack" { turnedAt = drive.now + PenguinMove.lookBack.passDuration }
                        if ["stand", "blink", "flap"].contains(drive.name), drive.clearance(of: drive.pose) < Self.clearance - 1e-6 {
                            holds.append((drive.now, drive.pose.facing))
                        }
                    }
                    // (Before it has turned it faces the way it came; after, or if it need not, the way the capybara looks.)
                    let after = turnedAt.map { turned in holds.filter { $0.at >= turned } } ?? holds
                    #expect(after.count > 10)
                    #expect(after.allSatisfy { $0.facing == facing }, "position \(position), seed \(seed): \(Set(after.map { "\($0.facing)" })) while the capybara looks \(facing)")
                    if drive.moves.contains("lookTurn") {
                        turned += 1
                        #expect(drive.moves.contains("lookBack"))
                    } else {
                        straight += 1
                    }
                }
            }
        }
        #expect(turned > 0 && straight > 0, "both ways of coming: \(turned) turned, \(straight) straight on")
    }

    @Test func thePenguinSlidesToItAndGetsUpAndOnlyTheSlideIsOnItsBelly() {
        var drive = PairDrive(Pairing.all[2], seed: 3, position: 0.1)
        drive.mustJoin()
        drive.runScene()
        let names = drive.moves
        let slide = names.firstIndex(of: "slide")
        let up = names.firstIndex(of: "getUp")
        #expect(slide != nil && up != nil && slide! < up!, "\(names)")
        for entry in drive.every where moveName(.penguin, entry.pose) == "slide" { #expect(entry.pose.from != entry.pose.to) }
        // Waddling out is what it does when it goes.
        #expect(names.last == "waddle" || names.suffix(3).contains("waddle"))
    }

    @Test func theCorgiMayWiggleFirstAndLiesDownByItWithItsChinOnItsPawsAndGetsUpToGo() {
        var wiggles = 0, plain = 0
        for seed in 1...20 as ClosedRange<UInt64> {
            var drive = PairDrive(Pairing.all[3], seed: seed, position: 0.1)
            drive.mustJoin()
            drive.runScene()
            let names = drive.moves
            let lie = names.firstIndex(of: "lieDown")
            #expect(lie != nil && names.firstIndex(of: "getUp").map { $0 > lie! } == true, "\(names)")
            if let wiggle = names.firstIndex(of: "wiggle") {
                wiggles += 1
                #expect(wiggle < lie!, "a wiggle first, and then it lies down")
            } else {
                plain += 1
            }
            // For a good while: ten seconds or more.
            let lying = drive.every.filter { moveName(.corgi, $0.pose) == "lie" }.map(\.pose.duration)
            #expect((lying.first ?? 0) >= 10)
        }
        #expect(wiggles > 3 && plain > 3, "now and then, not always: \(wiggles) and \(plain)")
    }

    @Test func theHamsterCurlsUpAgainstItAndSleepsAndUncurlsToGo() {
        for seed in 1...8 as ClosedRange<UInt64> {
            var drive = PairDrive(Pairing.all[1], seed: seed, position: 0.1)
            drive.mustJoin()
            drive.runScene()
            let names = drive.moves
            let curl = names.firstIndex(of: "curl"), sleep = names.firstIndex(of: "sleep"), uncurl = names.lastIndex(of: "uncurl")
            #expect(curl != nil && sleep != nil && uncurl != nil && curl! < sleep! && sleep! < uncurl!, "\(names)")
            #expect((drive.every.first { moveName(.hamster, $0.pose) == "sleep" }?.pose.duration ?? 0) >= 8)
        }
    }

    // MARK: Nothing it senses matters

    @Test func whileItPlaysNothingItSensesChangesAnythingItDoesNeitherTheMacNorTheSoundNorTheUserBeingAwayNorThePointer() {
        for pairing in Pairing.all {
            for seed in 1...6 as ClosedRange<UInt64> {
                var calm = PairDrive(pairing, seed: seed, position: 0.15)
                calm.mustJoin()
                calm.runScene()
                var stormy = PairDrive(pairing, seed: seed, position: 0.15)
                stormy.mustJoin()
                var round = 0
                while stormy.brain.jointScene != nil, stormy.now < 120 {
                    round += 1
                    stormy.senses.cpuLoad = 1
                    stormy.senses.busyBurst = round % 7 < 4
                    stormy.senses.audioPlaying = round % 3 == 0
                    stormy.senses.idleSeconds = round % 300 < 150 ? 10_000 : 5
                    stormy.senses.hour = round % 80 < 40 ? 23 : 14
                    stormy.senses.pointer = PointerReading(share: stormy.pose.to, isNear: round % 2 == 0, isInRange: true)
                    stormy.run(0.25)
                }
                #expect(stormy.moves == calm.moves, "\(pairing.scene), seed \(seed)")
                #expect(stormy.every.map(\.pose) == calm.every.map(\.pose), "\(pairing.scene), seed \(seed)")
            }
        }
    }

    @Test func aStrokeIsNotTakenWhileItIsInTheSceneItIsTheDirectorsToEndFirst() {
        for pairing in Pairing.all {
            var drive = PairDrive(pairing, seed: 3, position: 0.15)
            drive.mustJoin()
            drive.run(10)
            let before = drive.pose
            let outcome = drive.brain.pet(now: drive.now)
            #expect(outcome == .unchanged && drive.pose == before, "\(pairing.scene)")
        }
    }

    // MARK: Going early

    @Test func toldToLeaveFromAnyMomentItGetsOutOfTheCapybarasWayAndIsDoneWithTheSceneSoonAfter() {
        for pairing in Pairing.all {
            var leaves = 0
            for seed in 1...4 as ClosedRange<UInt64> {
                for offset in stride(from: 0.0, through: 60, by: 0.75) {
                    var drive = PairDrive(pairing, seed: seed, position: seed % 2 == 0 ? 0.1 : 0.9)
                    drive.mustJoin()
                    drive.run(offset)
                    guard drive.brain.jointScene != nil else { continue }
                    leaves += 1
                    // (A slide is not broken off, and goes on to where it was going.)
                    let farAtLeave: Double? = moveName(pairing.kind, drive.pose) == "slide" ? nil : drive.places.last.map { place in (drive.hostPlaces.map { abs(place - $0) }.min() ?? 0) }
                    _ = drive.brain.leaveJoint(now: drive.now)
                    let label = "\(pairing.scene), seed \(seed), told at \(offset) s"
                    drive.mustFinish(40)
                    let clear = drive.clearance(of: drive.pose)
                    #expect(clear >= Self.clearance - 1e-6, "\(label): \(clear) points from the capybara's room")
                    #expect(drive.pose.prop == nil)
                    // One that was far from the capybara when it was told goes about its day from where it was, and does not come to the capybara to
                    // go out of its way.
                    if let far = farAtLeave, far > 90 { #expect(clear > 60, "\(label): \(far) points away when told, and \(clear) from the room after") }
                    for (before, after) in zip(drive.places, drive.places.dropFirst()) {
                        #expect(abs(after - before) <= 14, "\(label): jumped from \(before) to \(after)")
                    }
                    // And it is not in the scene once it is told: asking again changes nothing.
                    let pose = drive.pose
                    let again = drive.brain.leaveJoint(now: drive.now)
                    #expect(again == .unchanged && drive.pose == pose, "\(label)")
                }
            }
            #expect(leaves > 60, "\(pairing.scene): \(leaves)")
        }
    }

    @Test func aCapybaraThatIsNotWhereItWasOrIsGoneEndsItAndTheGuestGoesOutOfItsWay() {
        for pairing in Pairing.all {
            for (label, change) in [
                ("moved", { (drive: inout PairDrive) in drive.host = PairDrive.capybara(at: 0.62, facing: drive.host.facing, tub: drive.tub, deep: drive.host.perch?.spot == .head) }),
                ("gone", { (drive: inout PairDrive) in drive.sight = false }),
            ] as [(String, (inout PairDrive) -> Void)] {
                var drive = PairDrive(pairing, seed: 6, position: 0.15)
                drive.mustJoin()
                drive.run(14)
                guard drive.brain.jointScene != nil else { continue }
                change(&drive)
                drive.run(0.25)
                drive.mustFinish(60, "capybara \(label)")
                #expect(drive.pose.prop == nil)
            }
        }
    }

    @Test func aCapybaraThatMovesWhileTheGuestIsInALongHoldSendsItOutAtOnceAndNotAtTheEndOfTheHold() {
        // The hold, and the least a hold of it lasts.
        let holds: [(Pairing, String, Double)] = [
            (Pairing.all[0], "freeze", 1.4), (Pairing.all[1], "sleep", 8), (Pairing.all[2], "stand", 3), (Pairing.all[3], "lie", 10), (Pairing.all[4], "headSit", 2),
        ]
        for (pairing, hold, longest) in holds {
            var fired = 0
            for seed in 1...8 as ClosedRange<UInt64> {
                var drive = PairDrive(pairing, seed: seed, position: 0.15)
                drive.mustJoin()
                while drive.brain.jointScene != nil, drive.now < 120 {
                    drive.run(0.25)
                    guard drive.name == hold, drive.pose.duration >= longest, drive.now - drive.pose.began < 0.3 else { continue }
                    fired += 1
                    // The capybara is not where it was.
                    drive.host = PairDrive.capybara(at: 0.62, facing: drive.host.facing, tub: drive.tub, deep: drive.host.perch?.spot == .head)
                    let before = drive.every.count
                    drive.run(1)
                    let since = drive.every[before...].map { moveName(pairing.kind, $0.pose) }
                    #expect(since.contains { $0 != hold }, "\(pairing.scene), seed \(seed): still \(hold) a second after the capybara moved")
                    drive.mustFinish(60, "seed \(seed)")
                    break
                }
            }
            #expect(fired >= 3, "\(pairing.scene): \(fired) long holds were seen")
        }
    }

    // MARK: When it will

    @Test func itWillOnlyJoinTheSceneItPlaysAndOnlyAsTheGuestAndOnlyOneAtATime() {
        for pairing in Pairing.all {
            var drive = PairDrive(pairing, seed: 2, position: 0.15)
            drive.run(0.25)
            var host = drive.invite
            host.role = .host
            #expect(!drive.brain.canJoin(host, now: drive.now), "\(pairing.scene): it is not the one that is played on")
            for other in Pairing.all.map(\.scene) where other != pairing.scene && !Pairing.all.filter({ $0.kind == pairing.kind }).map(\.scene).contains(other) {
                var wrong = drive.invite
                wrong.scene = other
                #expect(!drive.brain.canJoin(wrong, now: drive.now), "\(pairing.scene): not \(other)")
            }
            var cat = drive.invite
            cat.scene = .catOnCapybara
            #expect(!drive.brain.canJoin(cat, now: drive.now), "\(pairing.scene): not the cat's scene")
            #expect(drive.brain.canJoin(drive.invite, now: drive.now) || pairing.scene == .frogOnHead)
            let joined = drive.join()
            guard joined else { continue }
            #expect(!drive.brain.canJoin(drive.invite, now: drive.now), "one scene at a time")
        }
    }

    @Test func itWillNotJoinWhenItIsBusyOrAsleepOrHasNowhereToGoOrNoLaneAtAll() {
        for pairing in Pairing.all {
            var busy = PairDrive(pairing, seed: 2, position: 0.15)
            busy.senses.cpuLoad = 1
            busy.senses.busyBurst = true
            busy.run(2)
            #expect(!busy.brain.canJoin(busy.invite, now: busy.now), "\(pairing.scene): the Mac is busy")
            var asleep = PairDrive(pairing, seed: 2, position: 0.15)
            asleep.senses.idleSeconds = 10_000
            asleep.run(120)
            #expect(!asleep.brain.canJoin(asleep.invite, now: asleep.now), "\(pairing.scene): asleep")
            var narrow = PairDrive(pairing, seed: 2, position: 0.15, travel: 8)
            narrow.run(2)
            #expect(!narrow.brain.canJoin(narrow.invite, now: narrow.now), "\(pairing.scene): a lane of eight points")
            var none = PairDrive(pairing, seed: 2, position: 0.15, travel: 0)
            none.run(2)
            #expect(!none.brain.canJoin(none.invite, now: none.now), "\(pairing.scene): no lane")
        }
    }

    @Test func itWillNotJoinWhereThereIsNoRoomBesideTheCapybaraOrOutOfItsWayAndTheCameraIsNotCrossedForIt() {
        for pairing in Pairing.all {
            // Others' rooms that leave nowhere free but the capybara's own.
            var crowded = PairDrive(pairing, seed: 2, position: 0.15)
            crowded.lane = LaneContext(zones: [-0.1...0.4, 0.6...1.1])
            crowded.run(1)
            #expect(!crowded.brain.canJoin(crowded.invite, now: crowded.now), "\(pairing.scene): crowded either side")
            // The camera right where it would be, on both sides.
            var camera = PairDrive(pairing, seed: 2, position: 0.15)
            camera.lane = LaneContext(crossing: [0.3...0.45, 0.55...0.7])
            camera.run(1)
            #expect(!camera.brain.canJoin(camera.invite, now: camera.now), "\(pairing.scene): in the camera")
        }
    }

    @Test func itKeepsTheRoomItGoesToFreeForItselfWhileItIsThereAndForTheWayOut() {
        for pairing in Pairing.all {
            var drive = PairDrive(pairing, seed: 4, position: 0.15)
            drive.mustJoin()
            var exits: Set<Double> = []
            while drive.brain.jointScene != nil, drive.now < 120 {
                drive.run(0.25)
                if drive.brain.jointScene != nil { #expect(!drive.pose.reserves.isEmpty, "\(pairing.scene): \(drive.name)") }
                exits.formUnion(drive.pose.reserves)
            }
            // The place it goes to when it is done is the one it reserved, whatever place it was in.
            let last = drive.every.last { $0.pose.reserves.isEmpty == false }?.pose
            #expect(last.map { $0.reserves.contains { abs($0 - drive.pose.to) < 1e-9 } } == true || pairing.scene == .frogOnHead, "\(pairing.scene)")
            #expect(!exits.isEmpty)
            drive.run(5)
            #expect(drive.pose.reserves.isEmpty, "nothing is reserved once it is done")
        }
    }

    @Test func aGuestThatIsNotInASceneDoesNothingOfItAndIsNeverBehindOrOver() {
        for pairing in Pairing.all {
            var drive = PairDrive(pairing, seed: 7, position: 0.4)
            drive.run(3 * 3600)
            #expect(drive.every.allSatisfy { !$0.pose.behind && !$0.pose.raised }, "\(pairing.scene)")
            #expect(drive.brain.jointScene == nil)
            for entry in drive.every { #expect(entry.pose.reserves.isEmpty) }
        }
    }
}
