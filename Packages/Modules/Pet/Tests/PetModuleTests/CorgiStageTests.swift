import AppKit
import MyNotchCore
import NotchUI
import QuartzCore
import Testing
@testable import PetModule

/// The corgi on a stage and in a view: what is drawn, where it goes, what is left on the layers, how the Mac being busy sends it running
/// about, the camera, and the settings that choose it. Everything on the stage's clock and the test's own Mac.
@Suite(.serialized) @MainActor struct CorgiStageTests {
    func corgis(_ geometry: NotchGeometry, seed: UInt64 = 5, kinds: [CharacterKind] = [.corgi], reducesMotion: Bool = false) -> BodyRig {
        let rig = BodyRig(geometry: geometry, seed: seed, reducesMotion: reducesMotion)
        rig.show()
        rig.stage.characters = kinds
        return rig
    }

    func image(of layer: CALayer) -> AnyObject? { layer.contents as AnyObject? }

    // MARK: Registered, and in the menu

    @Test func theCorgiIsAKindWithItsOwnSpeciesAndBrainAndIsNamedInTheMenuAfterTheOthers() {
        #expect(CharacterKind.allCases == [.cat, .capybara, .hamster, .penguin, .corgi], "declared after them: the draw order and the order in the menu")
        #expect(CharacterKind.corgi.displayName == "Corgi" && CharacterKind(rawValue: "corgi") == .corgi)
        #expect(CharacterKind.corgi.species is CorgiSpecies && CharacterKind.cat.species is CatSpecies)
        for other in [CharacterKind.cat, .capybara, .hamster, .penguin] { #expect(CharacterKind.corgi.species !== other.species) }
        #expect(CharacterKind.corgi.species.makeBrain(seed: 1, now: 0, position: 0.5) is CorgiBrain)
        #expect(PetScreenRow.summary(of: [.cat, .corgi]) == "Mèo, Corgi" && PetScreenRow.summary(of: [.corgi]) == "Corgi")
        #expect(CharacterKind.corgi.species.meowsWhenPetted == false)
    }

    @Test func aScreenCanChooseTheCorgiAloneOrWithOthersAndTheOneThatIsTickedLastIsTheOneThatDoesNotFitWhenThreeAreChosen() throws {
        let screens = PetScreens().setting([.corgi], for: "A").setting([.corgi, .cat, .hamster], for: "B").toggling(.corgi, on: "C")
        #expect(screens.kinds(for: "A") == [.corgi])
        #expect(screens.kinds(for: "B") == [.cat, .hamster, .corgi], "in the order the kinds are declared, not as they were picked")
        #expect(screens.kinds(for: "C") == [.cat, .corgi], "the cat was the default, and the corgi is added to it")
        let text = String(decoding: try JSONEncoder().encode(PetScreens().setting([.cat, .corgi], for: "A")), as: UTF8.self)
        #expect(text.contains("[\"cat\",\"corgi\"]"), "\(text)")
        #expect(try JSONDecoder().decode(PetScreens.self, from: Data(text.utf8)).kinds(for: "A") == [.cat, .corgi])
        // Three is the most a screen has, and there are five kinds to choose from: the corgi, the last, does not fit on a full screen.
        let full = PetScreens().setting([.cat, .capybara, .hamster], for: "A")
        #expect(full.kinds(for: "A").count == CharacterKind.maxPerScreen && !full.canAdd(to: "A"))
        #expect(full.toggling(.corgi, on: "A") == full, "the corgi cannot be added to a full screen, which is what the menu greys it for")
        #expect(PetScreens().setting(CharacterKind.allCases, for: "A").kinds(for: "A") == [.cat, .capybara, .hamster])
        #expect(full.toggling(.hamster, on: "A").toggling(.corgi, on: "A").kinds(for: "A") == [.cat, .capybara, .corgi])
    }

    // MARK: Drawn

    @Test func aCorgiAloneIsDrawnWithItsOwnStripsAndItsBallWithItsOwnOnEveryKindOfNotch() throws {
        for geometry in [Screens.pill, Screens.tallPill, Screens.hardware] {
            let rig = corgis(geometry)
            var balls = 0
            var seen: Set<CorgiMove> = []
            for _ in 0..<(4 * 60 * 12) {
                rig.advance(0.25)
                let pose = try #require(rig.stage.poses.first)
                seen.insert(CorgiMove(pose.motion))
                for host in rig.hosts {
                    let strip = CorgiSheets.shared.strip(for: CorgiMove(pose.motion), facing: pose.facing)
                    #expect(!host.characters[0].sprite.isHidden)
                    #expect(image(of: host.characters[0].sprite) === strip.image as AnyObject, "\(geometry.kind): \(CorgiMove(pose.motion))")
                    if let prop = pose.prop, !host.characters[0].prop.isHidden {
                        #expect(image(of: host.characters[0].prop) === CorgiSheets.shared.propStrip(CorgiProp(prop.look)).image as AnyObject)
                        balls += 1
                    }
                }
            }
            #expect(rig.stage.poses.count == 1 && rig.stage.plan == nil, "the cat's plan is not a corgi's")
            #expect(balls > 30, "\(geometry.kind): the ball was drawn: \(balls)")
            #expect(seen.count >= 8, "\(seen)")
            rig.hide()
        }
    }

    @Test func inThePillItIsDrawnAtTheScaleOfTheLaneAndTheBallAtTheSameScaleAndTheTrotAndTheRunInWholeSteps() throws {
        for (geometry, scale) in [(Screens.pill, 1), (Screens.tallPill, 2)] {
            var sawBall = false
            var kinds: Set<CorgiMove> = []
            for seed: UInt64 in 1...6 {
                let rig = corgis(geometry, seed: seed)
                let lane = try #require(rig.container.lane)
                #expect(lane.field.scale == scale)
                for _ in 0..<(4 * 60 * 40) {
                    rig.advance(0.25)
                    let layers = lane.characters[0]
                    #expect(layers.sprite.bounds.size == CGSize(width: 32 * scale, height: 24 * scale))
                    guard let pose = rig.stage.poses.first else { continue }
                    if let prop = pose.prop, CorgiProp(prop.look) == .ballRest {
                        sawBall = true
                        #expect(layers.prop.bounds.size == CGSize(width: 32 * scale, height: 24 * scale) && !layers.prop.isHidden)
                    }
                    let move = CorgiMove(pose.motion)
                    guard [.trot, .run, .carry].contains(move), let walk = layers.sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation else { continue }
                    let stops = (walk.values as? [NSNumber] ?? []).map { CGFloat($0.doubleValue) }
                    guard stops.count > 4 else { continue }
                    kinds.insert(move)
                    // Whole steps, all of a size, and the size is the move's step at the scale of the lane (a leg that begins where the last one
                    // ended, a few points from where its plan says, is a step off at most).
                    let steps = Set(zip(stops, stops.dropFirst()).map { abs($1 - $0) })
                    #expect(steps.count == 1, "\(move): steps of \(steps)")
                    #expect(abs((steps.first ?? 0) - CGFloat(move.advance) * CGFloat(scale)) <= CGFloat(scale), "\(move): steps of \(steps) at scale \(scale)")
                }
                rig.hide()
                if sawBall && kinds.count == 3 { break }
            }
            #expect(sawBall && kinds == [.trot, .run, .carry], "scale \(scale): a ball \(sawBall), \(kinds)")
        }
    }

    @Test func throughHoursNoViewIsEverLeftShowingABallThatThePoseDoesNotHaveWhateverTheMacIsDoing() throws {
        for geometry in [Screens.pill, Screens.hardware] {
            for (seed, load) in [(UInt64(2), 0.05), (9, 0.6)] {
                let rig = corgis(geometry, seed: seed)
                rig.cpu.value = load
                var props = 0
                for tick in 0..<(4 * 60 * 90) {
                    if tick % 4000 == 1500 { rig.idle.seconds = 900 } else if tick % 4000 == 2500 { rig.idle.seconds = 0 }
                    if tick % 5000 == 3000 { rig.cpu.value = 0.97 } else if tick % 5000 == 4000 { rig.cpu.value = load }
                    rig.advance(0.25)
                    let pose = try #require(rig.stage.poses.first)
                    if pose.prop != nil { props += 1 }
                    for host in rig.hosts {
                        #expect(host.characters[0].prop.isHidden == (pose.prop == nil), "\(geometry.kind), seed \(seed): \(CorgiMove(pose.motion)) with \(String(describing: pose.prop?.look))")
                    }
                }
                #expect(props > 200, "it has a ball out for a good part of its time: \(props)")
                rig.hide()
            }
        }
    }

    // MARK: A busy Mac

    @Test func aBusyMacHasItRunAboutMoreOnTheViewAndNeverQuickerAndWithTheReactionOffItDoesNotRunAboutMore() throws {
        func trial(seed: UInt64, load: Double, reacts: Bool) throws -> (runs: Double, fastest: Double, poses: [Pose]) {
            let rig = corgis(Screens.pill, seed: seed)
            defer { rig.hide() }
            let layers = try #require(rig.container.lane?.characters[0])
            rig.stage.tuning.reactsToBusyMachine = reacts
            // Quiet for long enough to know what is usual, and then the load.
            rig.cpu.value = 0.05
            for _ in 0..<(4 * 60 * 3) { rig.advance(0.25) }
            rig.cpu.value = load
            var (runs, ticks, fastest) = (0.0, 0.0, 0.0)
            var poses: [Pose] = []
            for _ in 0..<(4 * 60 * 12) {
                rig.advance(0.25)
                guard let pose = rig.stage.poses.first else { continue }
                poses.append(pose)
                ticks += 1
                if CorgiMove(pose.motion) == .run, pose.prop == nil { runs += 1 }
                if let frames = layers.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation, CorgiMove(pose.motion) == .run {
                    // The frames on the view go as fast as the move's own pace, and no faster: it is no more frantic busy than quiet.
                    #expect(abs(frames.duration - 6 / CorgiMove.run.fps) < 1e-9 && pose.fpsScale == 1, "\(frames.duration)")
                    fastest = max(fastest, 6 / frames.duration)
                }
            }
            return (runs / ticks, fastest, poses)
        }
        var (busy, quiet, off, tested) = (0.0, 0.0, 0.0, 0.0)
        for seed: UInt64 in [3, 8, 12, 21, 34] {
            let (hot, calm, ignoring) = (try trial(seed: seed, load: 0.97, reacts: true), try trial(seed: seed, load: 0.05, reacts: true), try trial(seed: seed, load: 0.97, reacts: false))
            #expect(hot.fastest <= CorgiMove.run.fps + 1e-9 && ignoring.fastest <= CorgiMove.run.fps + 1e-9, "never in more of a hurry than the run: \(hot.fastest) frames a second")
            #expect(calm.poses == ignoring.poses, "seed \(seed): with the reaction off a busy Mac is a quiet one")
            busy += hot.runs
            quiet += calm.runs
            off += ignoring.runs
            tested += 1
        }
        #expect(busy > quiet * 1.4, "a busy Mac had it running about for joy: \(busy / tested) of its time against \(quiet / tested)")
        #expect(abs(off - quiet) < 1e-12)
    }

    // MARK: The pointer

    @Test func aPointerNearTheStripMakesItSitUpToBegAndWhenItIsGoneItSitsDownAndGoesOn() throws {
        let rig = corgis(Screens.pill, seed: 4)
        let host = try #require(rig.hosts.first)
        for _ in 0..<(4 * 20) { rig.advance(0.25) }
        let frame = try #require(host.screenFrame)
        rig.pointer.point = CGPoint(x: frame.midX, y: frame.midY)
        rig.advance(4)
        let begging = try #require(rig.stage.poses.first)
        #expect([CorgiMove.sitDown, .begUp, .beg].contains(CorgiMove(begging.motion)), "\(CorgiMove(begging.motion))")
        #expect(image(of: host.characters[0].sprite) === CorgiSheets.shared.strip(for: CorgiMove(begging.motion), facing: begging.facing).image as AnyObject)
        rig.advance(4)
        #expect(CorgiMove(try #require(rig.stage.poses.first).motion) == .beg)
        rig.pointer.point = CGPoint(x: 9000, y: 9000)
        rig.advance(4)
        #expect(![CorgiMove.begUp, .beg, .begDown].contains(CorgiMove(try #require(rig.stage.poses.first).motion)))
        rig.hide()
    }

    // MARK: The portal

    @Test func onAHardwareNotchItCrossesTheCameraThroughThePortalOnlyAtATrotAndNeverStopsInIt() throws {
        var through = 0
        for seed: UInt64 in [3, 8, 12] {
            let rig = corgis(Screens.hardware, seed: seed)
            let left = try #require(rig.container.leftWing)
            let right = try #require(rig.container.rightWing)
            let field = left.field
            let crossing = try #require(field.crossing)
            var last: Pose?
            var stationary = 0
            for _ in 0..<(4 * 60 * 120) {
                rig.advance(0.25)
                guard let pose = rig.stage.poses.first, pose != last else { continue }
                last = pose
                let (from, to) = (field.lane.x(at: pose.from), field.lane.x(at: pose.to))
                #expect(!crossing.contains(to) || to == crossing.lowerBound || to == crossing.upperBound, "seed \(seed): a \(CorgiMove(pose.motion)) ends at \(to)")
                let goesThrough = from <= crossing.lowerBound && to >= crossing.upperBound || from >= crossing.upperBound && to <= crossing.lowerBound
                for host in [left, right] {
                    let animation = host.characters[0].portal.animation(forKey: CatSpriteView.portalKey) as? CAKeyframeAnimation
                    #expect((animation != nil) == goesThrough, "\(CorgiMove(pose.motion)) from \(from) to \(to): a portal \(animation != nil)")
                }
                if goesThrough {
                    through += 1
                    #expect(CorgiMove(pose.motion) == .trot, "only a trot goes through")
                    let walk = try #require(left.characters[0].sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation)
                    #expect(walk.duration >= abs(to - from) / CGFloat(CorgiMove.trot.speed) - 0.5)
                }
                if [.run, .carry].contains(CorgiMove(pose.motion)) {
                    #expect(max(from, to) <= crossing.lowerBound || min(from, to) >= crossing.upperBound, "a run stays on its side of the camera")
                }
                if pose.from == pose.to {
                    stationary += 1
                    let visible = [left, right].filter { CGRect(origin: $0.characters[0].sprite.position, size: $0.characters[0].sprite.bounds.size).intersects($0.bounds) }
                    #expect(visible.count == 1, "seed \(seed): a \(CorgiMove(pose.motion)) with the corgi in \(visible.count) of the views")
                }
            }
            #expect(stationary > 100)
            rig.hide()
        }
        #expect(through >= 4, "it crosses the camera now and then: \(through) times")
    }

    @Test func aBallIsNeverInTheCameraOrAcrossItEvenWithABusyMacAndNeitherIsTheCorgiThatFetchesIt() throws {
        for (seed, load) in [(UInt64(1), 0.05), (4, 0.9), (7, 0.5), (11, 0.9)] {
            let rig = corgis(Screens.hardware, seed: seed)
            rig.cpu.value = load
            let left = try #require(rig.container.leftWing)
            let field = left.field
            let crossing = try #require(field.crossing)
            var balls = 0
            var last: Pose?
            for _ in 0..<(4 * 60 * 90) {
                rig.advance(0.25)
                guard let pose = rig.stage.poses.first, pose != last else { continue }
                last = pose
                guard let prop = pose.prop else { continue }
                balls += 1
                var places = [prop.from, prop.to, pose.from, pose.to].map { field.lane.x(at: $0) }
                places += prop.alsoAt.map { field.lane.x(at: $0) }
                let (low, high) = (places.min() ?? 0, places.max() ?? 0)
                for x in places { #expect(x < crossing.lowerBound || x > crossing.upperBound, "seed \(seed): \(x), the camera is \(crossing)") }
                #expect(high <= crossing.lowerBound || low >= crossing.upperBound, "seed \(seed): the whole fetch is on one side of the camera: \(low) to \(high)")
            }
            #expect(balls > 40, "seed \(seed): \(balls)")
            rig.hide()
        }
    }

    // MARK: Clicks, and who is clicked

    func click(_ host: CatSpriteView, at point: CGPoint) throws {
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: host.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: host.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        host.mouseDown(with: event)
    }

    @Test func aClickOnTheCorgiMakesItSpinForJoyAndNeverMewsWhateverTheMewSettingIsAndAClickOnTheCatDoes() throws {
        let rig = corgis(Screens.pill, kinds: [.cat, .corgi])
        rig.stage.playsMeow = true
        // Until the corgi is standing about, which is what a stroke finds it doing a good part of the time.
        for _ in 0..<(4 * 60 * 10) {
            rig.advance(0.25)
            if let move = rig.stage.poses.last.map({ CorgiMove($0.motion) }), [.stand, .blink, .wiggle].contains(move) { break }
        }
        let host = try #require(rig.hosts.first)
        let (cat, corgi) = (host.characters[0].sprite, host.characters[1].sprite)
        try click(host, at: CGPoint(x: corgi.frame.midX, y: corgi.frame.midY))
        #expect(rig.stage.strokes == 1 && rig.meow.plays == 0, "no mew for a corgi")
        #expect(CorgiMove(try #require(rig.stage.poses.last).motion) == .spin, "it spins for joy")
        let catCentre = CGPoint(x: cat.frame.midX, y: cat.frame.midY)
        if !corgi.frame.insetBy(dx: -2, dy: -2).contains(catCentre) {
            try click(host, at: catCentre)
            #expect(rig.stage.strokes == 2 && rig.meow.plays == 1, "and the cat's is a mew")
        }
        rig.hide()
        let alone = corgis(Screens.pill, kinds: [.corgi])
        alone.stage.playsMeow = true
        alone.stage.catWasClicked()
        #expect(alone.meow.plays == 0 && alone.stage.strokes == 1)
    }

    /// Whether the picture a layer shows has a pixel that is not clear at `point`, in its view's coordinates.
    func hasInk(_ layer: CALayer, at point: CGPoint) -> Bool {
        guard let contents = layer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { return false }
        let image = contents as! CGImage
        let (frame, rect) = (layer.frame, layer.contentsRect)
        guard frame.contains(point) else { return false }
        let across = rect.minX + (point.x - frame.minX) / frame.width * rect.width
        let up = rect.minY + (point.y - frame.minY) / frame.height * rect.height
        let (column, row) = (Int((across * CGFloat(image.width)).rounded(.down)), Int(((1 - up) * CGFloat(image.height)).rounded(.down)))
        guard let piece = image.cropping(to: CGRect(x: column, y: row, width: 1, height: 1)) else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(piece, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel[3] > 0
    }

    @Test func aClickWhereTheCorgisEmptyPictureIsOverTheCatIsTheCatsAndWhereItIsDrawnTheCorgis() throws {
        let rig = corgis(Screens.pill, seed: 5, kinds: [.cat, .corgi])
        rig.stage.playsMeow = true
        for _ in 0..<40 { rig.advance(0.25) }
        let host = try #require(rig.hosts.first)
        let (cat, corgi) = (host.characters[0].sprite, host.characters[1].sprite)
        let catAt = cat.position
        /// The corgi's picture is put over the cat's, as it is when they walk through each other, and the two are still: a click that
        /// changes what is shown puts them back where the stage says they are.
        func arrange(_ offset: CGFloat) {
            cat.removeAllAnimations()
            corgi.removeAllAnimations()
            cat.position = catAt
            corgi.position = CGPoint(x: catAt.x + offset, y: catAt.y)
        }
        var found: (offset: CGFloat, cat: CGPoint, corgi: CGPoint)?
        for offset in [CGFloat(16), 12, 20, 8, 24, -12, -16] where found == nil {
            arrange(offset)
            var onlyTheCat: CGPoint?, onlyTheCorgi: CGPoint?
            let overlap = cat.frame.intersection(corgi.frame)
            for x in stride(from: overlap.minX, to: overlap.maxX, by: 1) {
                for y in stride(from: overlap.minY, to: overlap.maxY, by: 1) {
                    let point = CGPoint(x: x + 0.5, y: y + 0.5)
                    let (c, p) = (hasInk(cat, at: point), hasInk(corgi, at: point))
                    if c && !p, onlyTheCat == nil { onlyTheCat = point }
                    if p && !c, onlyTheCorgi == nil { onlyTheCorgi = point }
                }
            }
            if let c = onlyTheCat, let p = onlyTheCorgi { found = (offset, c, p) }
        }
        let spot = try #require(found, "somewhere the cat is drawn where the corgi is clear, and the corgi where the cat is clear")
        arrange(spot.offset)
        try click(host, at: spot.cat)
        #expect(rig.meow.plays == 1 && rig.stage.strokes == 1, "the click was the cat's: a mew")
        arrange(spot.offset)
        try click(host, at: spot.corgi)
        #expect(rig.meow.plays == 1 && rig.stage.strokes == 2, "and the click on the corgi was the corgi's: no mew")
        rig.hide()
    }

    // MARK: Reduce Motion, and taken away

    @Test func withReduceMotionTheCorgiStandsStillWithItsEyesShutNowAndThenAndNothingOfItsIsOut() throws {
        let rig = corgis(Screens.hardware, kinds: [.corgi, .cat], reducesMotion: true)
        for host in rig.hosts {
            #expect(host.characters.count == 2)
            #expect(image(of: host.characters[0].sprite) === CorgiSheets.shared.restingStrip().image as AnyObject)
            #expect(host.characters.allSatisfy { $0.prop.isHidden && $0.portal.isHidden })
        }
        #expect(!rig.stage.isTicking)
    }

    /// Runs the stage until the corgi (the last of the characters) has the ball out.
    func fetching(_ rig: BodyRig, minutes: Int = 240) -> Bool {
        for _ in 0..<(4 * 60 * minutes) {
            rig.advance(0.25)
            if let pose = rig.stage.poses.last, pose.prop != nil { return true }
        }
        return false
    }

    @Test func turningReduceMotionOnInTheMiddleOfAFetchStillsItAndTakesTheBallOffTheView() throws {
        let rig = corgis(Screens.pill, seed: 4)
        let host = try #require(rig.hosts.first)
        #expect(fetching(rig) && !host.characters[0].prop.isHidden)
        rig.knobs.reducesMotion = true
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { !rig.stage.isTicking }, seconds: 5))
        #expect(host.characters[0].prop.isHidden, "no ball left on the view")
        #expect(image(of: host.characters[0].sprite) === CorgiSheets.shared.restingStrip().image as AnyObject)
        rig.knobs.reducesMotion = false
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { rig.stage.isTicking }, seconds: 5))
        #expect(rig.stage.poses.first?.prop == nil, "and none that comes back")
    }

    @Test func takingTheCorgiOffAScreenInTheMiddleOfAFetchTakesItsLayersAndItsBallOffTheView() throws {
        let rig = corgis(Screens.pill, seed: 4, kinds: [.cat, .corgi])
        let host = try #require(rig.hosts.first)
        #expect(fetching(rig) && host.characters.count == 2 && !host.characters[1].prop.isHidden)
        let corgi = host.characters[1]
        rig.stage.characters = [.cat]
        #expect(host.characters.count == 1 && corgi.sprite.isHidden && corgi.prop.isHidden && corgi.sprite.superlayer == nil)
        rig.advance(30)
        #expect(host.characters.count == 1 && rig.stage.poses.count == 1)
    }

    // MARK: With the others

    struct Report {
        var overlaps: [String] = []
        var crossingTogether: [String] = []
        var inTheWay: [String] = []
        var crossings = 0
        var balls = 0
        var together = 0
    }

    /// What the characters owe each other, looked at after every waking, for `minutes` of made-up time: not on each other, one at a time in the
    /// portal, nobody at rest in the room a prop takes up (a tub, a wheel, a hole or a ball), and a ball never where another character's tub,
    /// wheel or hole is (nor theirs where its ball is).
    func live(_ rig: BodyRig, kinds: [CharacterKind], minutes: Int, label: String, each: (Int) -> Void = { _ in }) throws -> Report {
        rig.show()
        let stage = rig.stage
        stage.characters = kinds
        let field = try #require(rig.hosts.first?.field)
        let crossing = stage.crossingShares()
        let (travel, width) = (Double(field.lane.travel), Double(field.spriteWidth))
        var report = Report()
        for tick in 0..<(4 * 60 * minutes) {
            each(tick)
            rig.advance(0.25)
            let now = rig.scheduler.seconds
            let poses = stage.poses
            let play = stage.jointPlay
            #expect(poses.count == kinds.count)
            var (inCrossing, walking) = (0, 0)
            func rests(_ pose: Pose) -> Bool { pose.from == pose.to || now >= pose.end }
            for (index, pose) in poses.enumerated() {
                if LaneRules.isCrossing(pose, through: crossing, at: now) { inCrossing += 1 }
                if pose.from != pose.to, now < pose.end { walking += 1 }
                if let prop = pose.prop, prop.look.occupies {
                    if kinds[index] == .corgi { report.balls += 1 }
                    // Nobody else is at rest where the prop is, or where its owner stands or hops from.
                    for (other, otherPose) in poses.enumerated() where other != index && rests(otherPose) {
                        // (The pair that are playing, one on the other's back, owe each other nothing.)
                        if let play, Set([index, other]) == [play.host, play.guest] { continue }
                        // (The capybara's tub is held to its own place here, as PET6's test holds it: a cat has been found at rest 13 points from
                        // the place the capybara hops from, once or twice in fifteen minutes.)
                        for place in kinds[index] == .capybara ? [prop.from] : [prop.to] + prop.alsoAt {
                            let apart = abs(otherPose.position(at: now) - place) * travel
                            if apart < width { report.inTheWay.append("\(label) at \(now): \(other) \(apart) points from the room \(index)'s prop takes") }
                        }
                    }
                    // A ball is clear of a tub, a wheel or a hole that is out, and a tub, a wheel or a hole is clear of a ball.
                    for (other, otherPose) in poses.enumerated() where other > index {
                        guard let otherProp = otherPose.prop, otherProp.look.occupies, kinds[index] == .corgi || kinds[other] == .corgi else { continue }
                        let apart = abs(otherProp.to - prop.to) * travel
                        if apart < 20 { report.inTheWay.append("\(label) at \(now): \(index)'s prop and \(other)'s are \(apart) points apart") }
                    }
                }
                for other in poses.indices where other > index {
                    if let play, Set([index, other]) == [play.host, play.guest] { continue }
                    guard rests(poses[index]), rests(poses[other]) else { continue }
                    let apart = abs(poses[index].position(at: now) - poses[other].position(at: now)) * travel
                    if apart < width { report.overlaps.append("\(label) at \(now): \(index) and \(other) \(apart) points apart (\(width) is a picture)") }
                }
            }
            if inCrossing > 1 { report.crossingTogether.append("\(label) at \(now): \(inCrossing) in the crossing") }
            if inCrossing == 1 { report.crossings += 1 }
            if walking > 1 { report.together += 1 }
        }
        return report
    }

    @Test func aCorgiWithTwoOfTheOthersOnTheMacsWingsNeverStopsOnThemOrInTheirRoomAndTheirTubWheelAndHoleAreClearOfItsBallAndOneAtATimeGoesThroughThePortal() throws {
        var report = Report()
        for (kinds, seed): ([CharacterKind], UInt64) in [
            ([.cat, .capybara, .corgi], 3), ([.capybara, .hamster, .corgi], 8), ([.hamster, .penguin, .corgi], 21), ([.cat, .penguin, .corgi], 55),
            ([.capybara, .penguin, .corgi], 5), ([.cat, .hamster, .corgi], 13),
        ] {
            let rig = BodyRig(geometry: Screens.hardware, seed: seed)
            let one = try live(rig, kinds: kinds, minutes: 20, label: "\(kinds), seed \(seed)") { tick in rig.cpu.value = tick % 4000 < 2000 ? 0.05 : 0.8 }
            report.overlaps += one.overlaps
            report.crossingTogether += one.crossingTogether
            report.inTheWay += one.inTheWay
            report.crossings += one.crossings
            report.balls += one.balls
            report.together += one.together
            rig.hide()
        }
        #expect(report.overlaps.isEmpty, "\(report.overlaps.prefix(5))")
        #expect(report.crossingTogether.isEmpty, "\(report.crossingTogether.prefix(5))")
        #expect(report.inTheWay.isEmpty, "\(report.inTheWay.prefix(5))")
        #expect(report.crossings > 100 && report.together > 50 && report.balls > 40, "\(report.crossings) in the portal, \(report.together) walking together, \(report.balls) with a ball out")
    }

    @Test func theSameInThePillAndTheTallPillAndTwoOfThemInTheNarrowWings() throws {
        var report = Report()
        let rows: [(NotchGeometry, [CharacterKind], CGFloat?)] = [
            (Screens.pill, [.cat, .capybara, .corgi], nil), (Screens.tallPill, [.corgi, .hamster], nil), (Screens.tallPill, [.penguin, .corgi], nil),
            (Screens.pill, [.hamster, .corgi], nil),
            (Screens.hardware, [.cat, .corgi], 360), (Screens.pill, [.penguin, .hamster, .corgi], nil), (Screens.pill, [.capybara, .penguin, .corgi], nil),
        ]
        for (geometry, kinds, width) in rows {
            for seed: UInt64 in [3, 8, 21] {
                let rig = BodyRig(geometry: geometry, seed: seed, width: width)
                let one = try live(rig, kinds: kinds, minutes: 15, label: "\(kinds), seed \(seed)") { tick in rig.cpu.value = tick % 3000 < 1500 ? 0.05 : 0.9 }
                report.overlaps += one.overlaps
                report.crossingTogether += one.crossingTogether
                report.inTheWay += one.inTheWay
                report.balls += one.balls
                report.together += one.together
                rig.hide()
            }
        }
        #expect(report.overlaps.isEmpty, "\(report.overlaps.prefix(5))")
        #expect(report.crossingTogether.isEmpty, "\(report.crossingTogether.prefix(5))")
        #expect(report.inTheWay.isEmpty, "\(report.inTheWay.prefix(5))")
        #expect(report.together > 200 && report.balls > 100, "\(report.together) walking together, \(report.balls) with a ball out")
    }
}
