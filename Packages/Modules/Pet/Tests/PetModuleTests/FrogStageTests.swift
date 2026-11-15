import AppKit
import MyNotchCore
import NotchUI
import QuartzCore
import Testing
@testable import PetModule

/// The frog on a stage and in a view: what is drawn, where it goes, what is left on the layers, how the Mac being busy has it hop about more,
/// the camera, and the settings that choose it. Everything on the stage's clock and the test's own Mac.
@Suite(.serialized) @MainActor struct FrogStageTests {
    func frogs(_ geometry: NotchGeometry, seed: UInt64 = 5, kinds: [CharacterKind] = [.frog], reducesMotion: Bool = false, hour: Int = 12) -> BodyRig {
        let rig = BodyRig(geometry: geometry, seed: seed, hour: hour, reducesMotion: reducesMotion)
        rig.show()
        rig.stage.characters = kinds
        return rig
    }

    func image(of layer: CALayer) -> AnyObject? { layer.contents as AnyObject? }

    // MARK: Registered, and in the menu

    @Test func theFrogIsAKindWithItsOwnSpeciesAndBrainAndIsNamedInTheMenuInVietnameseAfterTheOthers() {
        #expect(CharacterKind.allCases == [.cat, .capybara, .hamster, .penguin, .corgi, .frog], "declared after them: the draw order and the order in the menu")
        #expect(CharacterKind.frog.displayName == "Ếch" && CharacterKind(rawValue: "frog") == .frog)
        #expect(CharacterKind.frog.species is FrogSpecies && CharacterKind.cat.species is CatSpecies)
        for other in [CharacterKind.cat, .capybara, .hamster, .penguin, .corgi] { #expect(CharacterKind.frog.species !== other.species) }
        #expect(CharacterKind.frog.species.makeBrain(seed: 1, now: 0, position: 0.5) is FrogBrain)
        #expect(PetScreenRow.summary(of: [.cat, .frog]) == "Mèo, Ếch" && PetScreenRow.summary(of: [.frog]) == "Ếch")
        #expect(CharacterKind.frog.species.meowsWhenPetted == false)
    }

    @Test func aScreenCanChooseTheFrogAloneOrWithOthersAndTheOneThatIsTickedLastIsTheOneThatDoesNotFitWhenThreeAreChosen() throws {
        let screens = PetScreens().setting([.frog], for: "A").setting([.frog, .cat, .hamster], for: "B").toggling(.frog, on: "C")
        #expect(screens.kinds(for: "A") == [.frog])
        #expect(screens.kinds(for: "B") == [.cat, .hamster, .frog], "in the order the kinds are declared, not as they were picked")
        #expect(screens.kinds(for: "C") == [.cat, .frog], "the cat was the default, and the frog is added to it")
        let text = String(decoding: try JSONEncoder().encode(PetScreens().setting([.cat, .frog], for: "A")), as: UTF8.self)
        #expect(text.contains("[\"cat\",\"frog\"]"), "\(text)")
        #expect(try JSONDecoder().decode(PetScreens.self, from: Data(text.utf8)).kinds(for: "A") == [.cat, .frog])
        // Three is the most a screen has, and there are six kinds to choose from: the frog, the last, does not fit on a full screen.
        let full = PetScreens().setting([.cat, .capybara, .hamster], for: "A")
        #expect(full.kinds(for: "A").count == CharacterKind.maxPerScreen && !full.canAdd(to: "A"))
        #expect(full.toggling(.frog, on: "A") == full, "the frog cannot be added to a full screen, which is what the menu greys it for")
        #expect(PetScreens().setting(CharacterKind.allCases, for: "A").kinds(for: "A") == [.cat, .capybara, .hamster])
        #expect(full.toggling(.hamster, on: "A").toggling(.frog, on: "A").kinds(for: "A") == [.cat, .capybara, .frog])
    }

    // MARK: Drawn

    @Test func aFrogAloneIsDrawnWithItsOwnStripsItsPadWithItsOwnAndItsMothWithTheCatsOnEveryKindOfNotch() throws {
        for geometry in [Screens.pill, Screens.tallPill, Screens.hardware] {
            let rig = frogs(geometry, hour: 23)
            var (pads, moths) = (0, 0)
            var seen: Set<FrogMove> = []
            for _ in 0..<(4 * 60 * 20) {
                rig.advance(0.25)
                let pose = try #require(rig.stage.poses.first)
                seen.insert(FrogMove(pose.motion))
                for host in rig.hosts {
                    let strip = FrogSheets.shared.strip(for: FrogMove(pose.motion), facing: pose.facing)
                    #expect(!host.characters[0].sprite.isHidden)
                    #expect(image(of: host.characters[0].sprite) === strip.image as AnyObject, "\(geometry.kind): \(FrogMove(pose.motion))")
                    if let prop = pose.prop, !host.characters[0].prop.isHidden {
                        let look = FrogProp(prop.look)
                        #expect(image(of: host.characters[0].prop) === FrogSheets.shared.propStrip(look).image as AnyObject)
                        if look.isMoth {
                            #expect(image(of: host.characters[0].prop) === CatSheets.shared.propStrip(.moth).image as AnyObject, "the cat's moth, in the cat's colours")
                            moths += 1
                        } else {
                            pads += 1
                        }
                    }
                }
            }
            #expect(rig.stage.poses.count == 1 && rig.stage.plan == nil, "the cat's plan is not a frog's")
            #expect(pads > 30 && moths > 30, "\(geometry.kind): the pad was drawn \(pads) times and the moth \(moths)")
            #expect(seen.count >= 12, "\(seen)")
            rig.hide()
        }
    }

    @Test func inThePillItIsDrawnAtTheScaleOfTheLaneAndTheMothAndPadAtTheSameScaleAndTheHopsInWholeSteps() throws {
        for (geometry, scale) in [(Screens.pill, 1), (Screens.tallPill, 2)] {
            var (sawPad, sawMoth) = (false, false)
            var kinds: Set<FrogMove> = []
            for seed: UInt64 in 1...6 {
                let rig = frogs(geometry, seed: seed, hour: seed % 2 == 0 ? 23 : 12)
                let lane = try #require(rig.container.lane)
                #expect(lane.field.scale == scale)
                for _ in 0..<(4 * 60 * 40) {
                    rig.advance(0.25)
                    let layers = lane.characters[0]
                    #expect(layers.sprite.bounds.size == CGSize(width: 32 * scale, height: 24 * scale))
                    guard let pose = rig.stage.poses.first else { continue }
                    if let prop = pose.prop, !layers.prop.isHidden {
                        switch FrogProp(prop.look) {
                        case .padRippling:
                            sawPad = true
                            #expect(layers.prop.bounds.size == CGSize(width: 32 * scale, height: 24 * scale))
                            // The pad is under the frog: the same left edge.
                            #expect(abs(layers.prop.position.x - layers.sprite.position.x) <= CGFloat(scale), "\(layers.prop.position.x) under \(layers.sprite.position.x)")
                        case .moth, .mothHeld:
                            sawMoth = true
                            #expect(layers.prop.bounds.size == CGSize(width: 11 * scale, height: 7 * scale))
                            // It hovers as high above the frog's feet as the art says.
                            #expect(abs(layers.prop.position.y - layers.sprite.position.y - CGFloat(FrogProp(prop.look).look.rise) * CGFloat(scale)) < 0.5)
                        default: break
                        }
                    }
                    let move = FrogMove(pose.motion)
                    guard [.hop, .hopOn, .hopOff].contains(move), let walk = layers.sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation else { continue }
                    let stops = (walk.values as? [NSNumber] ?? []).map { CGFloat($0.doubleValue) }
                    guard stops.count > 4 else { continue }
                    kinds.insert(move)
                    // Whole steps, all of a size, and the size is the move's step at the scale of the lane (a leg that begins where the last one
                    // ended, a few points from where its plan says, is a step off at most).
                    let steps = Set(zip(stops, stops.dropFirst()).map { abs($1 - $0) })
                    let advance = move == .hop ? CGFloat(FrogMove.hop.advance) : CGFloat(FrogMove.hopSpan) / CGFloat(move.frameCount)
                    #expect(steps.count == 1, "\(move): steps of \(steps)")
                    #expect(abs((steps.first ?? 0) - advance * CGFloat(scale)) <= CGFloat(scale), "\(move): steps of \(steps) at scale \(scale)")
                }
                rig.hide()
                if sawPad && sawMoth && kinds.count == 3 { break }
            }
            #expect(sawPad && sawMoth && kinds == [.hop, .hopOn, .hopOff], "scale \(scale): a pad \(sawPad), a moth \(sawMoth), \(kinds)")
        }
    }

    @Test func throughHoursNoViewIsEverLeftShowingAPadOrAMothThatThePoseDoesNotHaveWhateverTheMacIsDoing() throws {
        for geometry in [Screens.pill, Screens.hardware] {
            for (seed, load) in [(UInt64(2), 0.05), (9, 0.6)] {
                let rig = frogs(geometry, seed: seed)
                rig.cpu.value = load
                var props = 0
                for tick in 0..<(4 * 60 * 90) {
                    if tick % 4000 == 1500 { rig.idle.seconds = 900 } else if tick % 4000 == 2500 { rig.idle.seconds = 0 }
                    if tick % 5000 == 3000 { rig.cpu.value = 0.97 } else if tick % 5000 == 4000 { rig.cpu.value = load }
                    rig.advance(0.25)
                    let pose = try #require(rig.stage.poses.first)
                    if pose.prop != nil { props += 1 }
                    for host in rig.hosts {
                        #expect(host.characters[0].prop.isHidden == (pose.prop == nil), "\(geometry.kind), seed \(seed): \(FrogMove(pose.motion)) with \(String(describing: pose.prop?.look))")
                    }
                }
                #expect(props > 200, "it has a pad or a moth out for a good part of its time: \(props)")
                rig.hide()
            }
        }
    }

    // MARK: A busy Mac

    @Test func aBusyMacHasItHopAboutMoreOnTheViewAndNeverQuickerAndWithTheReactionOffItDoesNotHopAboutMore() throws {
        func trial(seed: UInt64, load: Double, reacts: Bool) throws -> (hops: Double, fastest: Double, poses: [Pose]) {
            let rig = frogs(Screens.pill, seed: seed)
            defer { rig.hide() }
            let layers = try #require(rig.container.lane?.characters[0])
            rig.stage.tuning.reactsToBusyMachine = reacts
            // Quiet for long enough to know what is usual, and then the load.
            rig.cpu.value = 0.05
            for _ in 0..<(4 * 60 * 3) { rig.advance(0.25) }
            rig.cpu.value = load
            var (hops, ticks, fastest) = (0.0, 0.0, 0.0)
            var poses: [Pose] = []
            for _ in 0..<(4 * 60 * 12) {
                rig.advance(0.25)
                guard let pose = rig.stage.poses.first else { continue }
                poses.append(pose)
                ticks += 1
                if FrogMove(pose.motion) == .hop { hops += 1 }
                if let frames = layers.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation, FrogMove(pose.motion) == .hop {
                    // The frames on the view go as fast as the move's own pace, and no faster: it is no more frantic busy than quiet.
                    #expect(abs(frames.duration - 6 / FrogMove.hop.fps) < 1e-9 && pose.fpsScale == 1, "\(frames.duration)")
                    fastest = max(fastest, 6 / frames.duration)
                }
            }
            return (hops / ticks, fastest, poses)
        }
        var (busy, quiet, off, tested) = (0.0, 0.0, 0.0, 0.0)
        for seed: UInt64 in [3, 8, 12, 21, 34] {
            let (hot, calm, ignoring) = (try trial(seed: seed, load: 0.97, reacts: true), try trial(seed: seed, load: 0.05, reacts: true), try trial(seed: seed, load: 0.97, reacts: false))
            #expect(hot.fastest <= FrogMove.hop.fps + 1e-9 && ignoring.fastest <= FrogMove.hop.fps + 1e-9, "never in more of a hurry than a hop: \(hot.fastest) frames a second")
            #expect(calm.poses == ignoring.poses, "seed \(seed): with the reaction off a busy Mac is a quiet one")
            busy += hot.hops
            quiet += calm.hops
            off += ignoring.hops
            tested += 1
        }
        #expect(busy > quiet * 1.4, "a busy Mac had it hopping about: \(busy / tested) of its time against \(quiet / tested)")
        #expect(abs(off - quiet) < 1e-12)
    }

    // MARK: The pointer

    @Test func aPointerNearTheStripMakesItTurnAndWatchAndFlickItsTongueAndWhenItIsGoneItGoesOn() throws {
        let rig = frogs(Screens.pill, seed: 4)
        let host = try #require(rig.hosts.first)
        for _ in 0..<(4 * 20) { rig.advance(0.25) }
        let frame = try #require(host.screenFrame)
        rig.pointer.point = CGPoint(x: frame.midX, y: frame.midY)
        var moves: Set<FrogMove> = []
        for _ in 0..<(4 * 14) {
            rig.advance(0.25)
            let pose = try #require(rig.stage.poses.first)
            moves.insert(FrogMove(pose.motion))
            #expect(image(of: host.characters[0].sprite) === FrogSheets.shared.strip(for: FrogMove(pose.motion), facing: pose.facing).image as AnyObject)
        }
        #expect(moves.contains(.flick) || moves.contains(.padFlick), "\(moves)")
        rig.pointer.point = CGPoint(x: 9000, y: 9000)
        rig.advance(5)
        let pose = try #require(rig.stage.poses.first)
        #expect(![FrogMove.flick, .padFlick].contains(FrogMove(pose.motion)))
        rig.hide()
    }

    // MARK: The portal

    @Test func onAHardwareNotchItCrossesTheCameraThroughThePortalWithALegOfHopsAndNeverStopsInIt() throws {
        var through = 0
        for seed: UInt64 in [3, 8, 12] {
            let rig = frogs(Screens.hardware, seed: seed)
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
                #expect(!crossing.contains(to) || to == crossing.lowerBound || to == crossing.upperBound, "seed \(seed): a \(FrogMove(pose.motion)) ends at \(to)")
                let goesThrough = from <= crossing.lowerBound && to >= crossing.upperBound || from >= crossing.upperBound && to <= crossing.lowerBound
                for host in [left, right] {
                    let animation = host.characters[0].portal.animation(forKey: CatSpriteView.portalKey) as? CAKeyframeAnimation
                    #expect((animation != nil) == goesThrough, "\(FrogMove(pose.motion)) from \(from) to \(to): a portal \(animation != nil)")
                }
                if goesThrough {
                    through += 1
                    #expect(FrogMove(pose.motion) == .hop, "only a leg of hops goes through")
                    let walk = try #require(left.characters[0].sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation)
                    #expect(walk.duration >= abs(to - from) / CGFloat(FrogMove.hop.speed) - 0.5)
                }
                if [.hopOn, .hopOff].contains(FrogMove(pose.motion)) {
                    #expect(max(from, to) <= crossing.lowerBound || min(from, to) >= crossing.upperBound, "the hop on to the pad stays on its side of the camera")
                }
                if pose.from == pose.to {
                    stationary += 1
                    let visible = [left, right].filter { CGRect(origin: $0.characters[0].sprite.position, size: $0.characters[0].sprite.bounds.size).intersects($0.bounds) }
                    #expect(visible.count == 1, "seed \(seed): a \(FrogMove(pose.motion)) with the frog in \(visible.count) of the views")
                }
            }
            #expect(stationary > 100)
            rig.hide()
        }
        #expect(through >= 4, "it crosses the camera now and then: \(through) times")
    }

    @Test func aPadIsNeverInTheCameraOrAcrossItAndNeitherIsTheMothOrTheFrogThatSitsOnOrHuntsItEvenWithABusyMac() throws {
        for (seed, load, hour) in [(UInt64(1), 0.05, 14), (4, 0.9, 23), (7, 0.5, 23), (11, 0.9, 14)] {
            let rig = frogs(Screens.hardware, seed: seed, hour: hour)
            rig.cpu.value = load
            let left = try #require(rig.container.leftWing)
            let field = left.field
            let crossing = try #require(field.crossing)
            var (pads, moths) = (0, 0)
            var last: Pose?
            for _ in 0..<(4 * 60 * 90) {
                rig.advance(0.25)
                guard let pose = rig.stage.poses.first, pose != last else { continue }
                last = pose
                guard let prop = pose.prop else { continue }
                let look = FrogProp(prop.look)
                if look.isMoth {
                    moths += 1
                    // The moth is a small picture: its way, from outside the lane to the tip of the frog's tongue, is on one side of the camera.
                    let xs = [prop.from, prop.to].map { field.lane.unboundedX(at: $0) }
                    let (low, high) = (xs.min() ?? 0, xs.max() ?? 0)
                    #expect(high <= crossing.lowerBound || low >= crossing.upperBound, "seed \(seed): the moth's way is \(low) to \(high), the camera is \(crossing)")
                } else {
                    pads += 1
                }
                var places = [prop.from, prop.to, pose.from, pose.to].map { field.lane.x(at: $0) }
                places += prop.alsoAt.map { field.lane.x(at: $0) }
                let (low, high) = (places.min() ?? 0, places.max() ?? 0)
                if !look.isMoth { for x in places { #expect(x < crossing.lowerBound || x > crossing.upperBound, "seed \(seed): \(x), the camera is \(crossing)") } }
                #expect(high <= crossing.lowerBound || low >= crossing.upperBound || look.isMoth, "seed \(seed): the whole of it is on one side of the camera: \(low) to \(high)")
            }
            #expect(pads > 20 && moths > 20, "seed \(seed): \(pads) pads, \(moths) moths")
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

    @Test func aClickOnTheFrogMakesItHopInPlaceAndNeverMewsWhateverTheMewSettingIsAndAClickOnTheCatDoes() throws {
        let rig = frogs(Screens.pill, kinds: [.cat, .frog])
        rig.stage.playsMeow = true
        // Until the frog is sitting about, which is what a stroke finds it doing a good part of the time.
        for _ in 0..<(4 * 60 * 10) {
            rig.advance(0.25)
            if let move = rig.stage.poses.last.map({ FrogMove($0.motion) }), [.sit, .padSit].contains(move) { break }
        }
        let host = try #require(rig.hosts.first)
        let (cat, frog) = (host.characters[0].sprite, host.characters[1].sprite)
        let before = try #require(rig.stage.poses.last)
        try click(host, at: CGPoint(x: frog.frame.midX, y: frog.frame.midY))
        #expect(rig.stage.strokes == 1 && rig.meow.plays == 0, "no mew for a frog")
        let hop = try #require(rig.stage.poses.last)
        #expect([FrogMove.jump, .padJump].contains(FrogMove(hop.motion)) && hop.from == hop.to, "it hops in place: \(FrogMove(hop.motion))")
        #expect(abs(hop.to - before.to) < 1e-9 && (FrogMove(hop.motion) == .padJump) == (FrogMove(before.motion).stance == .pad), "where it was, on the pad if it was on it")
        if FrogMove(hop.motion) == .padJump { #expect(hop.prop.map { FrogProp($0.look) } == .padRippling, "and the pad stays") }
        let catCentre = CGPoint(x: cat.frame.midX, y: cat.frame.midY)
        if !frog.frame.insetBy(dx: -2, dy: -2).contains(catCentre) {
            try click(host, at: catCentre)
            #expect(rig.stage.strokes == 2 && rig.meow.plays == 1, "and the cat's is a mew")
        }
        rig.hide()
        let alone = frogs(Screens.pill, kinds: [.frog])
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

    @Test func aClickWhereTheFrogsEmptyPictureIsOverTheCatIsTheCatsAndWhereItIsDrawnTheFrogs() throws {
        let rig = frogs(Screens.pill, seed: 5, kinds: [.cat, .frog])
        rig.stage.playsMeow = true
        for _ in 0..<40 { rig.advance(0.25) }
        let host = try #require(rig.hosts.first)
        let (cat, frog) = (host.characters[0].sprite, host.characters[1].sprite)
        let catAt = cat.position
        /// The frog's picture is put over the cat's, as it is when they walk through each other, and the two are still: a click that changes
        /// what is shown puts them back where the stage says they are.
        func arrange(_ offset: CGFloat) {
            cat.removeAllAnimations()
            frog.removeAllAnimations()
            cat.position = catAt
            frog.position = CGPoint(x: catAt.x + offset, y: catAt.y)
        }
        var found: (offset: CGFloat, cat: CGPoint, frog: CGPoint)?
        for offset in [CGFloat(16), 12, 20, 8, 24, -12, -16] where found == nil {
            arrange(offset)
            var onlyTheCat: CGPoint?, onlyTheFrog: CGPoint?
            let overlap = cat.frame.intersection(frog.frame)
            for x in stride(from: overlap.minX, to: overlap.maxX, by: 1) {
                for y in stride(from: overlap.minY, to: overlap.maxY, by: 1) {
                    let point = CGPoint(x: x + 0.5, y: y + 0.5)
                    let (c, f) = (hasInk(cat, at: point), hasInk(frog, at: point))
                    if c && !f, onlyTheCat == nil { onlyTheCat = point }
                    if f && !c, onlyTheFrog == nil { onlyTheFrog = point }
                }
            }
            if let c = onlyTheCat, let f = onlyTheFrog { found = (offset, c, f) }
        }
        let spot = try #require(found, "somewhere the cat is drawn where the frog is clear, and the frog where the cat is clear")
        arrange(spot.offset)
        try click(host, at: spot.cat)
        #expect(rig.meow.plays == 1 && rig.stage.strokes == 1, "the click was the cat's: a mew")
        arrange(spot.offset)
        try click(host, at: spot.frog)
        #expect(rig.meow.plays == 1 && rig.stage.strokes == 2, "and the click on the frog was the frog's: no mew")
        rig.hide()
    }

    // MARK: Reduce Motion, and taken away

    @Test func withReduceMotionTheFrogSitsStillWithItsEyesShutNowAndThenAndNothingOfItsIsOut() throws {
        let rig = frogs(Screens.hardware, kinds: [.frog, .cat], reducesMotion: true)
        for host in rig.hosts {
            #expect(host.characters.count == 2)
            #expect(image(of: host.characters[0].sprite) === FrogSheets.shared.restingStrip().image as AnyObject)
            #expect(host.characters.allSatisfy { $0.prop.isHidden && $0.portal.isHidden })
        }
        #expect(!rig.stage.isTicking)
    }

    /// Runs the stage until the frog (the last of the characters) has a pad out, with it on the pad.
    func onThePad(_ rig: BodyRig, minutes: Int = 240) -> Bool {
        for _ in 0..<(4 * 60 * minutes) {
            rig.advance(0.25)
            if let pose = rig.stage.poses.last, let prop = pose.prop, FrogProp(prop.look) == .padRippling { return true }
        }
        return false
    }

    @Test func turningReduceMotionOnInTheMiddleOfASitOnThePadStillsItAndTakesThePadOffTheView() throws {
        let rig = frogs(Screens.pill, seed: 4)
        let host = try #require(rig.hosts.first)
        #expect(onThePad(rig) && !host.characters[0].prop.isHidden)
        rig.knobs.reducesMotion = true
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { !rig.stage.isTicking }, seconds: 5))
        #expect(host.characters[0].prop.isHidden, "no pad left on the view")
        #expect(image(of: host.characters[0].sprite) === FrogSheets.shared.restingStrip().image as AnyObject)
        rig.knobs.reducesMotion = false
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { rig.stage.isTicking }, seconds: 5))
        #expect(rig.stage.poses.first?.prop == nil, "and none that comes back")
    }

    @Test func takingTheFrogOffAScreenInTheMiddleOfASitOnThePadTakesItsLayersAndItsPadOffTheView() throws {
        let rig = frogs(Screens.pill, seed: 4, kinds: [.cat, .frog])
        let host = try #require(rig.hosts.first)
        #expect(onThePad(rig) && host.characters.count == 2 && !host.characters[1].prop.isHidden)
        let frog = host.characters[1]
        rig.stage.characters = [.cat]
        #expect(host.characters.count == 1 && frog.sprite.isHidden && frog.prop.isHidden && frog.sprite.superlayer == nil)
        rig.advance(30)
        #expect(host.characters.count == 1 && rig.stage.poses.count == 1)
    }

    // MARK: With the others

    struct Report {
        var overlaps: [String] = []
        var crossingTogether: [String] = []
        var inTheWay: [String] = []
        var crossings = 0
        var pads = 0
        var together = 0
    }

    /// What the characters owe each other, looked at after every waking, for `minutes` of made-up time: not on each other, one at a time in the
    /// portal, nobody at rest in the room a prop takes up (a tub, a wheel, a hole, a ball or a pad), and a pad never where another character's
    /// tub, wheel, hole or ball is (nor theirs where its pad is).
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
            let playing = stage.jointExempt
            #expect(poses.count == kinds.count)
            var (inCrossing, walking) = (0, 0)
            func rests(_ pose: Pose) -> Bool { pose.from == pose.to || now >= pose.end }
            for (index, pose) in poses.enumerated() {
                if LaneRules.isCrossing(pose, through: crossing, at: now) { inCrossing += 1 }
                if pose.from != pose.to, now < pose.end { walking += 1 }
                if let prop = pose.prop, prop.look.occupies {
                    if kinds[index] == .frog { report.pads += 1 }
                    // Nobody else is at rest where the prop is, or where its owner stands or hops from.
                    for (other, otherPose) in poses.enumerated() where other != index && rests(otherPose) {
                        // (The pair that are playing, or only just done and still getting out of each other's way, owe each other nothing.)
                        if playing.contains(index), playing.contains(other) { continue }
                        // (Every prop keeps the place its owner stands or hops from too, the capybara's tub as the rest.)
                        for place in [prop.to] + prop.alsoAt {
                            let apart = abs(otherPose.position(at: now) - place) * travel
                            if apart < width { report.inTheWay.append("\(label) at \(now): \(other) \(apart) points from the room \(index)'s prop takes") }
                        }
                    }
                    // A pad is clear of a tub, a wheel, a hole or a ball that is out, and a tub, a wheel, a hole or a ball is clear of a pad.
                    for (other, otherPose) in poses.enumerated() where other > index {
                        guard let otherProp = otherPose.prop, otherProp.look.occupies, kinds[index] == .frog || kinds[other] == .frog else { continue }
                        let apart = abs(otherProp.to - prop.to) * travel
                        if apart < 20 { report.inTheWay.append("\(label) at \(now): \(index)'s prop and \(other)'s are \(apart) points apart") }
                    }
                }
                for other in poses.indices where other > index {
                    if playing.contains(index), playing.contains(other) { continue }
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

    @Test func aFrogWithTwoOfTheOthersOnTheMacsWingsNeverStopsOnThemOrInTheirRoomAndTheirTubWheelHoleAndBallAreClearOfItsPadAndOneAtATimeGoesThroughThePortal() throws {
        var report = Report()
        for (kinds, seed): ([CharacterKind], UInt64) in [
            ([.cat, .capybara, .frog], 3), ([.capybara, .hamster, .frog], 8), ([.hamster, .penguin, .frog], 21), ([.cat, .penguin, .frog], 55),
            ([.capybara, .corgi, .frog], 5), ([.cat, .hamster, .frog], 13), ([.penguin, .corgi, .frog], 34), ([.hamster, .corgi, .frog], 89),
        ] {
            let rig = BodyRig(geometry: Screens.hardware, seed: seed)
            let one = try live(rig, kinds: kinds, minutes: 20, label: "\(kinds), seed \(seed)") { tick in rig.cpu.value = tick % 4000 < 2000 ? 0.05 : 0.8 }
            report.overlaps += one.overlaps
            report.crossingTogether += one.crossingTogether
            report.inTheWay += one.inTheWay
            report.crossings += one.crossings
            report.pads += one.pads
            report.together += one.together
            rig.hide()
        }
        #expect(report.overlaps.isEmpty, "\(report.overlaps.prefix(5))")
        #expect(report.crossingTogether.isEmpty, "\(report.crossingTogether.prefix(5))")
        #expect(report.inTheWay.isEmpty, "\(report.inTheWay.prefix(5))")
        #expect(report.crossings > 100 && report.together > 50 && report.pads > 40, "\(report.crossings) in the portal, \(report.together) walking together, \(report.pads) with a pad out")
    }

    @Test func theSameInThePillAndTheTallPillAndTwoOfThemInTheNarrowWings() throws {
        var report = Report()
        // (Two characters in the tall pill, which is as far as the lane rules go: a lane so crowded that nothing is free leaves a character
        // where it is, and three in the tall pill is one.)
        let rows: [(NotchGeometry, [CharacterKind], CGFloat?)] = [
            (Screens.pill, [.cat, .capybara, .frog], nil), (Screens.tallPill, [.frog, .hamster], nil), (Screens.tallPill, [.penguin, .frog], nil),
            (Screens.pill, [.hamster, .frog], nil), (Screens.tallPill, [.corgi, .frog], nil),
            (Screens.hardware, [.cat, .frog], 360), (Screens.pill, [.penguin, .hamster, .frog], nil), (Screens.pill, [.capybara, .corgi, .frog], nil),
        ]
        for (geometry, kinds, width) in rows {
            for seed: UInt64 in [3, 8, 21] {
                let rig = BodyRig(geometry: geometry, seed: seed, width: width)
                let one = try live(rig, kinds: kinds, minutes: 15, label: "\(kinds), seed \(seed)") { tick in rig.cpu.value = tick % 3000 < 1500 ? 0.05 : 0.9 }
                report.overlaps += one.overlaps
                report.crossingTogether += one.crossingTogether
                report.inTheWay += one.inTheWay
                report.pads += one.pads
                report.together += one.together
                rig.hide()
            }
        }
        #expect(report.overlaps.isEmpty, "\(report.overlaps.prefix(5))")
        #expect(report.crossingTogether.isEmpty, "\(report.crossingTogether.prefix(5))")
        #expect(report.inTheWay.isEmpty, "\(report.inTheWay.prefix(5))")
        #expect(report.together > 200 && report.pads > 100, "\(report.together) walking together, \(report.pads) with a pad out")
    }
}
