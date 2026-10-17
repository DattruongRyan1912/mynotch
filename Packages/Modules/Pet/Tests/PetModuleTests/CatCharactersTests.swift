import AppKit
import NotchUI
import QuartzCore
import Testing
@testable import PetModule

/// A species that is not the cat, to see that the stage and the views know a species only by what it hands them: a brain that goes up and
/// down the lane at its own pace, one picture, and no mew.
final class WalkerSpecies: Species {
    var meowsWhenPetted: Bool { false }

    static let strip: PixelStrip = {
        let palette = PixelPalette(colors: ["A": 0x336699, "B": 0xCC9933])
        let size = (Int(CatField.pictureSize.width), Int(CatField.pictureSize.height))
        let frames = ["A", "B"].map { PixelFrame(width: size.0, height: size.1, cells: Array(repeating: Character($0), count: size.0 * size.1)) }
        guard let strip = PixelStrip(frames: frames, palette: palette) else { fatalError("no strip") }
        return strip
    }()

    func makeBrain(seed: UInt64, now: TimeInterval, position: Double) -> any CharacterBrain {
        WalkerBrain(pose: Pose(motion: Walker.motion, facing: .right, from: position, to: position, began: now, duration: 1))
    }

    func strip(for motion: Motion, facing: Facing, appearance: Appearance) -> PixelStrip { Self.strip }
    func restingStrip(appearance: Appearance) -> PixelStrip { Self.strip }
    func propStrip(_ look: PropLook) -> PixelStrip { Self.strip }
}

/// The cat, that remembers the seeds it was asked to make brains with.
final class SeedSpy: Species {
    private(set) var seeds: [UInt64] = []
    private(set) var positions: [Double] = []

    func makeBrain(seed: UInt64, now: TimeInterval, position: Double) -> any CharacterBrain {
        seeds.append(seed)
        positions.append(position)
        return CatSpecies.shared.makeBrain(seed: seed, now: now, position: position)
    }

    func strip(for motion: Motion, facing: Facing, appearance: Appearance) -> PixelStrip {
        CatSpecies.shared.strip(for: motion, facing: facing, appearance: appearance)
    }

    func restingStrip(appearance: Appearance) -> PixelStrip { CatSpecies.shared.restingStrip(appearance: appearance) }
    func propStrip(_ look: PropLook) -> PixelStrip { CatSpecies.shared.propStrip(look) }
}

nonisolated enum Walker {
    static let motion = Motion(key: 77, fps: 4, loops: true)
}

/// Goes from where it is to the other end of the lane and back, three seconds each way, and takes a stroke with no change.
nonisolated struct WalkerBrain: CharacterBrain {
    var pose: Pose
    var pets = 0

    mutating func update(now: TimeInterval, senses: CatSenses, tuning: CatTuning, travel: Double, lane: LaneContext) -> BrainOutcome {
        guard now >= pose.end else { return .unchanged }
        let target = pose.to < 0.5 ? 0.9 : 0.1
        pose = Pose(
            motion: Walker.motion, facing: target > pose.to ? .right : .left, from: pose.to, to: target, began: now, duration: 3
        )
        return .changed
    }

    mutating func settle(lane: LaneContext) {}
    mutating func resume(now: TimeInterval) {}

    mutating func pet(now: TimeInterval) -> BrainOutcome {
        pets += 1
        return .unchanged
    }
}

/// Several characters, as the views draw them and the stage looks after them.
@Suite(.serialized) @MainActor struct CatCharactersTests {
    func threeIn(_ geometry: NotchGeometry, seed: UInt64 = 5, reducesMotion: Bool = false) -> BodyRig {
        let rig = BodyRig(geometry: geometry, seed: seed, reducesMotion: reducesMotion)
        rig.show()
        rig.stage.characters = [.cat, .cat, .cat]
        return rig
    }

    func click(_ host: CatSpriteView, at point: CGPoint) throws {
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: host.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: host.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        host.mouseDown(with: event)
    }

    // MARK: One cat is the cat it always was

    @Test func oneCatOnAStageIsTheBareBrainItAlwaysWasThroughTwoHoursOfMadeUpTime() throws {
        for (geometry, seed) in [(Screens.pill, UInt64(11)), (Screens.hardware, 5), (Screens.tallPill, 2)] {
            let rig = BodyRig(geometry: geometry, seed: seed)
            rig.show()
            let stageSeed = geometry.kind == .hardware ? seed : seed &+ 1
            var brain = CatBrain(seed: stageSeed, now: 0)
            let gaps = rig.stage.crossingShares()
            let field = try #require(rig.hosts.first?.field)
            let travel = Double(field.lane.travel) / Double(field.scale)
            brain.settle(gaps: gaps)
            brain.resume(now: 0)
            #expect(rig.stage.plan == brain.plan)
            var (idle, audio, hour) = (0.0, false, 14)
            var now = 0.0
            for tick in 0..<(4 * 60 * 60 * 2) {
                // What the Mac does, held by the test; the stage reads the idle time and the sound at every fourth waking, the hour at all.
                rig.idle.seconds = [0, 30, 400, 3][(tick / 4000) % 4]
                rig.audio.playing = (tick / 700) % 9 == 8
                rig.knobs.hour = (tick / 14400) % 2 == 0 ? 14 : 23
                if tick % 4 == 0 { (idle, audio) = (rig.idle.seconds, rig.audio.playing) }
                hour = rig.knobs.hour
                rig.advance(0.25)
                now += 0.25
                let senses = CatSenses(idleSeconds: idle, cpuLoad: 0.05, busyBurst: false, pointer: nil, audioPlaying: audio, hour: hour)
                _ = brain.update(now: now, senses: senses, tuning: CatTuning(), travel: travel, gaps: gaps)
                #expect(rig.stage.plan == brain.plan, "\(geometry.kind), seed \(seed), at \(now)")
                if tick % 3777 == 1000 {
                    rig.stage.catWasClicked()
                    _ = brain.pet(now: now)
                    #expect(rig.stage.plan == brain.plan)
                }
            }
            #expect(rig.stage.ticks == 4 * 60 * 60 * 2)
            rig.hide()
        }
    }

    @Test func theFirstCharacterHasTheStagesOwnSeedAndStartsInTheMiddleAndEachOtherHasAStreamOfItsOwn() {
        let spy = SeedSpy()
        let rig = BodyRig(geometry: Screens.pill, seed: 7, species: { _ in spy })
        rig.show()
        #expect(spy.seeds == [8] && spy.positions == [0.5], "the pill's stage is given the seed 8: a cat alone is as it was")
        rig.stage.characters = [.cat, .cat, .cat]
        #expect(spy.seeds.count == 3 && spy.seeds[0] == 8 && Set(spy.seeds).count == 3, "\(spy.seeds)")
        #expect(spy.positions[0] == 0.5 && spy.positions[1] == 2.0 / 4 && spy.positions[2] == 3.0 / 4, "spread where they come: \(spy.positions)")
    }

    // MARK: Drawing them

    @Test func eachCharacterIsDrawnOnLayersOfItsOwnInTheSameViewInAStableOrderAndNeverHidden() throws {
        for geometry in [Screens.pill, Screens.hardware] {
            let rig = threeIn(geometry)
            let stage = rig.stage
            for host in rig.hosts {
                #expect(host.characters.count == 3)
                let order = host.characters.flatMap { [$0.sprite, $0.prop, $0.portal] }.map(ObjectIdentifier.init)
                #expect((host.layer?.sublayers ?? []).map(ObjectIdentifier.init) == order, "the order the characters are in")
                #expect(Set(host.characters.map { ObjectIdentifier($0.sprite) }).count == 3)
            }
            let before = rig.hosts.map { ($0.layer?.sublayers ?? []).map(ObjectIdentifier.init) }
            for _ in 0..<(4 * 60 * 10) {
                rig.advance(0.25)
                for host in rig.hosts {
                    #expect(host.characters.allSatisfy { !$0.sprite.isHidden }, "no flicker: each is on all the time")
                }
            }
            #expect(rig.hosts.map { ($0.layer?.sublayers ?? []).map(ObjectIdentifier.init) } == before, "and the order is the same ten minutes on")
            #expect(stage.poses.count == 3)
        }
    }

    @Test func eachCharactersPictureIsTheOneItsPoseIsOfAndItIsWhereItsPoseSaysItIs() throws {
        let rig = threeIn(Screens.pill, seed: 9)
        let lane = try #require(rig.container.lane)
        var checked = 0
        for _ in 0..<(4 * 60 * 5) {
            rig.advance(0.25)
            for (index, pose) in rig.stage.poses.enumerated() {
                let layers = lane.characters[index]
                let strip = CatSheets.shared.strip(for: CatMove(pose.motion), facing: pose.facing, coat: .tabby)
                #expect(layers.sprite.contents as AnyObject === strip.image)
                #expect(layers.sprite.animation(forKey: CatSpriteView.framesKey) != nil)
                checked += 1
            }
        }
        // Where they stand are different places, so no picture is on another's.
        var stood: [CGFloat] = []
        for (index, pose) in rig.stage.poses.enumerated() where pose.from == pose.to { stood.append(lane.characters[index].sprite.position.x) }
        #expect(Set(stood).count == stood.count, "\(stood)")
        #expect(checked == 3 * 4 * 60 * 5)
    }

    @Test func everyCharactersAnimationsBeginTogetherInBothWingsOfTheNotchAndThePortalToo() throws {
        let rig = threeIn(Screens.hardware, seed: 3)
        let (left, right) = (try #require(rig.container.leftWing), try #require(rig.container.rightWing))
        var seen = 0
        for _ in 0..<(4 * 60 * 15) {
            rig.advance(0.25)
            for index in 0..<3 {
                guard let one = left.characters[index].sprite.animation(forKey: CatSpriteView.walkKey),
                      let two = right.characters[index].sprite.animation(forKey: CatSpriteView.walkKey) else { continue }
                seen += 1
                #expect(one.beginTime == two.beginTime, "character \(index): not close: equal")
                #expect(left.characters[index].sprite.animation(forKey: CatSpriteView.framesKey)?.beginTime
                    == right.characters[index].sprite.animation(forKey: CatSpriteView.framesKey)?.beginTime)
                if let first = left.characters[index].portal.animation(forKey: CatSpriteView.portalKey),
                   let second = right.characters[index].portal.animation(forKey: CatSpriteView.portalKey) {
                    #expect(first.beginTime == second.beginTime)
                }
            }
        }
        #expect(seen > 100, "\(seen)")
    }

    @Test func eachCharacterBeginsAtNowLessHowLongItsPoseHasLastedInAViewThatIsShownItLate() throws {
        // The Mac's notch has three characters for ten seconds; then the notch of the same display, a second one, is put on, and is
        // shown them: every picture begins at (now - elapsed), as it does in a view that was there from the start.
        let rig = BodyRig(geometry: Screens.pill, seed: 3)
        rig.show()
        rig.stage.characters = [.cat, .cat, .cat]
        rig.advance(10.1)
        let late = BodyRig(geometry: Screens.pill, sharing: rig)
        late.show()
        let (early, joined) = (try #require(rig.container.lane), try #require(late.container.lane))
        #expect(joined.stage === early.stage && joined.characters.count == 3)
        for index in 0..<3 {
            let one = early.characters[index].sprite.animation(forKey: CatSpriteView.framesKey)
            let other = joined.characters[index].sprite.animation(forKey: CatSpriteView.framesKey)
            #expect(one != nil && one?.beginTime == other?.beginTime, "character \(index): not close: equal")
        }
    }

    @Test func charactersThatLeaveTakeTheirLayersWithThemAndOnesThatComeGetTheirsAtTheEnd() throws {
        let rig = BodyRig(geometry: Screens.pill)
        rig.show()
        let lane = try #require(rig.container.lane)
        #expect(lane.characters.count == 1)
        let first = lane.characters[0]
        rig.stage.characters = [.cat, .cat]
        #expect(lane.characters.count == 2 && lane.characters[0] === first, "the first keeps its own")
        let second = lane.characters[1]
        rig.stage.characters = [.cat, .cat, .cat]
        #expect(lane.characters.count == 3 && lane.characters[1] === second)
        rig.stage.characters = [.cat]
        #expect(lane.characters.count == 1)
        #expect([second.sprite, second.prop, second.portal].allSatisfy { $0.superlayer == nil }, "no layer left on the view for one that went")
        #expect((lane.layer?.sublayers ?? []).count == 3)
        rig.advance(1)
        #expect(lane.isShowingCat)
    }

    @Test func aCharacterThatIsAnotherSpeciesThanTheLayersHadBeginsOnThemFromTheStartAndNotFromWhereTheLastOneStood() throws {
        let rig = BodyRig(geometry: Screens.pill)
        rig.show()
        let lane = try #require(rig.container.lane)
        let field = lane.field
        let walker = WalkerSpecies()
        let cat = CharacterDrawing(
            species: CatSpecies.shared,
            pose: Pose(motion: CatMove.walk.motion, facing: .right, from: 0.2, to: 0.21, began: 0, duration: 1), elapsed: 0, appearance: Appearance()
        )
        lane.show(characters: [cat])
        let stood = try #require(lane.characters[0].spriteStands)
        let other = CharacterDrawing(
            species: walker, pose: Pose(motion: Walker.motion, facing: .right, from: 0.2, to: 0.2, began: 0, duration: 9), elapsed: 0,
            appearance: Appearance()
        )
        #expect(abs(stood - field.local(share: 0.2)) > 0 && abs(stood - field.local(share: 0.2)) < CatSpriteView.continuityLimit)
        lane.show(characters: [other])
        #expect(lane.sprite.position.x == field.local(share: 0.2), "from its own place, not the cat's: \(lane.sprite.position.x) and \(stood)")
        #expect(lane.sprite.contents as AnyObject === WalkerSpecies.strip.image)
        // The same species again goes on from where it stands, which is what a leg of a walk after a leg does.
        lane.show(characters: [other])
        #expect(lane.sprite.position.x == field.local(share: 0.2))
    }

    // MARK: Clicks

    @Test func aClickIsAStrokeForTheCharacterItLandedOnAndForNoOtherAndATopOneWinsWhereTwoOverlap() throws {
        let rig = threeIn(Screens.pill, seed: 9)
        rig.advance(1)
        let lane = try #require(rig.container.lane)
        let poses = rig.stage.poses
        let frames = lane.characters.map { $0.sprite.frame }
        for target in 0..<3 {
            let rig = threeIn(Screens.pill, seed: 9)
            rig.advance(1)
            let lane = try #require(rig.container.lane)
            let frame = lane.characters[target].sprite.frame
            // Where only this one is: the middle of its picture, unless another's picture covers it, which a higher one does.
            let covered = (target + 1..<3).contains { lane.characters[$0].sprite.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
            guard !covered else { continue }
            let hit = lane.hitTest(lane.convert(CGPoint(x: frame.midX, y: frame.midY), to: lane.superview))
            #expect(hit === lane)
            try click(lane, at: CGPoint(x: frame.midX, y: frame.midY))
            #expect(rig.stage.strokes == 1)
            for (index, pose) in rig.stage.poses.enumerated() {
                #expect((pose.motion == CatMove.purr.motion) == (index == target), "clicked \(target): \(index) is \(pose.motion)")
            }
        }
        #expect(poses.count == 3 && Set(frames.map { $0.minX }).count == 3)
    }

    @Test func onlyACharacterThatMewsMewsWhenItIsClicked() throws {
        var made = 0
        let rig = BodyRig(geometry: Screens.pill, seed: 4, species: { _ in
            made += 1
            return made == 2 ? WalkerSpecies() : CatSpecies.shared
        })
        rig.show()
        rig.stage.playsMeow = true
        rig.stage.characters = [.cat, .cat]
        rig.advance(1)
        let lane = try #require(rig.container.lane)
        let frames = lane.characters.map { $0.sprite.frame }
        #expect(frames[0].intersects(frames[1]) == false, "two places: \(frames)")
        try click(lane, at: CGPoint(x: frames[1].midX, y: frames[1].midY))
        #expect(rig.stage.strokes == 1 && rig.meow.plays == 0, "the walker does not mew")
        try click(lane, at: CGPoint(x: frames[0].midX, y: frames[0].midY))
        #expect(rig.stage.strokes == 2 && rig.meow.plays == 1, "the cat does")
    }

    // MARK: Another species

    @Test func aSpeciesThatIsNotTheCatIsRunByTheStageAndDrawnByTheViewsWithNothingMadeForIt() throws {
        var made = 0
        let rig = BodyRig(geometry: Screens.hardware, seed: 4, species: { _ in
            made += 1
            // The first is the stage's own cat, the second a walker.
            return made == 2 ? WalkerSpecies() : CatSpecies.shared
        })
        rig.show()
        rig.stage.characters = [.cat, .cat]
        let (left, right) = (try #require(rig.container.leftWing), try #require(rig.container.rightWing))
        var legs = Set<TimeInterval>()
        for _ in 0..<(4 * 60) {
            rig.advance(0.25)
            let walker = try #require(rig.stage.poses.last)
            #expect(walker.motion == Walker.motion)
            legs.insert(walker.began)
            for host in [left, right] {
                #expect(host.characters[1].sprite.contents as AnyObject === WalkerSpecies.strip.image, "its own picture")
                #expect(host.characters[0].sprite.contents as AnyObject !== WalkerSpecies.strip.image, "and the cat its own")
            }
        }
        #expect(legs.count >= 20, "its brain was asked what to do, again and again, once a leg of three seconds: \(legs.count)")
    }

    // MARK: Sitting still

    @Test func oneCatSitsWhereItAlwaysDidAndSeveralSitApartWithReduceMotion() throws {
        for geometry in [Screens.pill, Screens.hardware] {
            let alone = BodyRig(geometry: geometry, reducesMotion: true)
            alone.show()
            let lane = try #require(alone.hosts.first)
            #expect(lane.sprite.position.x == lane.field.local(lane.field.lane.restingX.rounded()))

            for count in [2, 3] {
                let rig = BodyRig(geometry: geometry, reducesMotion: true)
                rig.show()
                rig.stage.characters = Array(repeating: .cat, count: count)
                let field = try #require(rig.hosts.first?.field)
                let places = field.restingPlaces(count: count)
                #expect(places.count == count)
                let sorted = places.sorted()
                for (one, other) in zip(sorted, sorted.dropFirst()) {
                    #expect(other - one >= field.spriteWidth, "\(geometry.kind), \(count): \(places)")
                }
                for place in places { #expect(place >= field.lane.minX && place <= field.lane.maxX) }
                if let crossing = field.stopFree { for place in places { #expect(!(place > crossing.lowerBound && place < crossing.upperBound), "not in the crossing") } }
                // Every picture is at its place, in the view it falls in, and in none of the others.
                for host in rig.hosts {
                    #expect(host.characters.count == count)
                    for (index, layers) in host.characters.enumerated() {
                        #expect(!layers.sprite.isHidden && layers.prop.isHidden && layers.portal.isHidden)
                        #expect(layers.sprite.position.x == host.field.local(places[index].rounded()))
                    }
                }
                #expect(!rig.stage.isTicking)
            }
        }
    }
}
