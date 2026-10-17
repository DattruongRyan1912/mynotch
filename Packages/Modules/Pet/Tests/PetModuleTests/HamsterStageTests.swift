import AppKit
import MyNotchCore
import NotchUI
import QuartzCore
import Testing
@testable import PetModule

/// The hamster on a stage and in a view: what is drawn, where it goes, what is left on the layers, how the Mac's load turns the wheel, and the
/// settings that choose it. Everything on the stage's clock and the test's own Mac.
@Suite(.serialized) @MainActor struct HamsterStageTests {
    func hamsters(_ geometry: NotchGeometry, seed: UInt64 = 5, kinds: [CharacterKind] = [.hamster], reducesMotion: Bool = false) -> BodyRig {
        let rig = BodyRig(geometry: geometry, seed: seed, reducesMotion: reducesMotion)
        rig.show()
        rig.stage.characters = kinds
        return rig
    }

    func image(of layer: CALayer) -> AnyObject? { layer.contents as AnyObject? }

    // MARK: Registered, and in the menu

    @Test func theHamsterIsAKindWithItsOwnSpeciesAndBrainAndIsNamedInTheMenuAfterTheOthers() {
        #expect(CharacterKind.allCases == [.cat, .capybara, .hamster, .penguin], "declared after them: the draw order and the order in the menu")
        #expect(CharacterKind.hamster.displayName == "Hamster" && CharacterKind(rawValue: "hamster") == .hamster)
        #expect(CharacterKind.hamster.species is HamsterSpecies && CharacterKind.cat.species is CatSpecies)
        #expect(CharacterKind.hamster.species !== CharacterKind.capybara.species)
        #expect(CharacterKind.hamster.species.makeBrain(seed: 1, now: 0, position: 0.5) is HamsterBrain)
        #expect(PetScreenRow.summary(of: [.cat, .capybara, .hamster]) == "Mèo, Capybara, Hamster" && PetScreenRow.summary(of: [.hamster]) == "Hamster")
    }

    @Test func aScreenCanChooseTheHamsterAloneOrWithOthersAndTheChoiceIsKeptByTheNameOfTheKind() throws {
        let screens = PetScreens().setting([.hamster], for: "A").setting([.hamster, .cat, .capybara], for: "B").toggling(.hamster, on: "C")
        #expect(screens.kinds(for: "A") == [.hamster])
        #expect(screens.kinds(for: "B") == [.cat, .capybara, .hamster], "in the order the kinds are declared, not as they were picked")
        #expect(screens.kinds(for: "C") == [.cat, .hamster], "the cat was the default, and the hamster is added to it")
        let text = String(decoding: try JSONEncoder().encode(PetScreens().setting([.cat, .hamster], for: "A")), as: UTF8.self)
        #expect(text.contains("[\"cat\",\"hamster\"]"), "\(text)")
        #expect(try JSONDecoder().decode(PetScreens.self, from: Data(text.utf8)).kinds(for: "A") == [.cat, .hamster])
        // Three is the most a screen has, and with the hamster there are three kinds to choose from.
        let full = PetScreens().setting([.cat, .capybara, .hamster], for: "A")
        #expect(full.kinds(for: "A").count == CharacterKind.maxPerScreen && !full.canAdd(to: "A"))
    }

    // MARK: Drawn

    @Test func aHamsterAloneIsDrawnWithItsOwnStripsAndItsWheelWithItsOwnOnEveryKindOfNotch() throws {
        for geometry in [Screens.pill, Screens.tallPill, Screens.hardware] {
            let rig = hamsters(geometry)
            var wheels = 0
            for _ in 0..<(4 * 60 * 10) {
                rig.advance(0.25)
                let pose = try #require(rig.stage.poses.first)
                for host in rig.hosts {
                    let strip = HamsterSheets.shared.strip(for: HamsterMove(pose.motion), facing: pose.facing)
                    #expect(!host.characters[0].sprite.isHidden)
                    #expect(image(of: host.characters[0].sprite) === strip.image as AnyObject, "\(geometry.kind): \(HamsterMove(pose.motion))")
                    if let prop = pose.prop, !host.characters[0].prop.isHidden {
                        #expect(image(of: host.characters[0].prop) === HamsterSheets.shared.propStrip(HamsterProp(prop.look)).image as AnyObject)
                        if HamsterProp(prop.look).isWheel { wheels += 1 }
                    }
                }
            }
            #expect(rig.stage.poses.count == 1 && rig.stage.plan == nil, "the cat's plan is not a hamster's")
            #expect(wheels > 50, "\(geometry.kind): the wheel was drawn: \(wheels)")
            rig.hide()
        }
    }

    @Test func inThePillItIsDrawnAtTheScaleOfTheLaneAndTheWheelAtTheSameScaleAndTheHopInWholeSteps() throws {
        for (geometry, scale) in [(Screens.pill, 1), (Screens.tallPill, 2)] {
            var sawWheel = false, sawHop = false
            for seed: UInt64 in 1...6 {
                let rig = hamsters(geometry, seed: seed)
                rig.cpu.value = 0.3
                let lane = try #require(rig.container.lane)
                #expect(lane.field.scale == scale)
                for _ in 0..<(4 * 60 * 40) {
                    rig.advance(0.25)
                    let layers = lane.characters[0]
                    #expect(layers.sprite.bounds.size == CGSize(width: 32 * scale, height: 24 * scale))
                    guard let pose = rig.stage.poses.first else { continue }
                    if let prop = pose.prop, HamsterProp(prop.look) == .wheelStill {
                        sawWheel = true
                        #expect(layers.prop.bounds.size == CGSize(width: 32 * scale, height: 24 * scale) && !layers.prop.isHidden)
                    }
                    if HamsterMove(pose.motion) == .hopIn, let hop = layers.sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation {
                        let stops = (hop.values as? [NSNumber] ?? []).map { CGFloat($0.doubleValue) }
                        guard stops.count > 2 else { continue }
                        sawHop = true
                        for (a, b) in zip(stops, stops.dropFirst()) { #expect(abs(abs(b - a) - 6 * CGFloat(scale)) < 1.5, "steps of \(b - a) at scale \(scale)") }
                        #expect(abs(abs(stops.last! - stops[0]) - 24 * CGFloat(scale)) < 6 * CGFloat(scale), "the hop's span: \(stops)")
                    }
                }
                rig.hide()
                if sawWheel && sawHop { break }
            }
            #expect(sawWheel && sawHop, "scale \(scale): a wheel \(sawWheel) and a hop \(sawHop)")
        }
    }

    @Test func throughHoursNoViewIsEverLeftShowingAWheelOrSeedsThatThePoseDoesNotHaveWhateverTheMacIsDoing() throws {
        for geometry in [Screens.pill, Screens.hardware] {
            for (seed, load) in [(UInt64(2), 0.05), (9, 0.6)] {
                let rig = hamsters(geometry, seed: seed)
                rig.cpu.value = load
                var props = 0
                for tick in 0..<(4 * 60 * 90) {
                    if tick % 4000 == 1500 { rig.idle.seconds = 900 } else if tick % 4000 == 2500 { rig.idle.seconds = 0 }
                    if tick % 5000 == 3000 { rig.cpu.value = 0.97 } else if tick % 5000 == 4000 { rig.cpu.value = load }
                    rig.advance(0.25)
                    let pose = try #require(rig.stage.poses.first)
                    if pose.prop != nil { props += 1 }
                    for host in rig.hosts {
                        #expect(host.characters[0].prop.isHidden == (pose.prop == nil), "\(geometry.kind), seed \(seed): \(HamsterMove(pose.motion)) with \(String(describing: pose.prop?.look))")
                    }
                }
                #expect(props > 1000, "it has things out for a good part of its time: \(props)")
                rig.hide()
            }
        }
    }

    // MARK: The wheel turns with the Mac's load

    /// How long one pass of the wheel's pictures takes on the view, which is how fast it turns.
    func turning(_ layers: CharacterLayers) -> Double? {
        (layers.prop.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation).map(\.duration)
    }

    @Test func theWheelOnTheViewTurnsFasterTheBusierTheMacIsAndTheHamsterRunsInStepWithIt() throws {
        var seen: [WheelPace: (wheel: Double, legs: Double)] = [:]
        let rig = hamsters(Screens.pill, seed: 6)
        let layers = try #require(rig.container.lane?.characters[0])
        // The load goes up in steps and down again: at each, a long while for it to be in the wheel and run at the pace.
        let loads: [Double] = [0.04, 0.3, 0.55, 0.9, 0.04]
        for load in loads {
            rig.cpu.value = load
            for _ in 0..<(4 * 60 * 12) {
                rig.advance(0.25)
                guard let pose = rig.stage.poses.first, let prop = pose.prop, let wheel = turning(layers),
                      let pace = WheelPace(HamsterMove(pose.motion)) else { continue }
                // The pace it runs at, after a few seconds of the load: what the stage has read of it.
                #expect(HamsterProp(prop.look) == pace.prop)
                let legs = (layers.sprite.animation(forKey: CatSpriteView.framesKey) as? CAKeyframeAnimation)?.duration ?? 0
                if load == loads[3] || load == loads[0] { seen[pace] = (wheel, legs) }
                #expect(abs(wheel - HamsterProp.animationDuration(of: pace)) < 1e-9, "\(pace): a pass of the wheel takes \(wheel)")
            }
        }
        #expect(seen[.sprint] != nil && seen[.lazy] != nil, "it ran at both ends: \(seen.keys)")
        if let sprint = seen[.sprint], let lazy = seen[.lazy] {
            #expect(sprint.wheel < lazy.wheel / 3, "the wheel turns much faster: a pass takes \(sprint.wheel) s against \(lazy.wheel)")
            #expect(sprint.legs < lazy.legs / 2, "and so do its legs: \(sprint.legs) against \(lazy.legs)")
        }
    }

    @Test func aBusyMacAfterAQuietSpellHasTheHamsterInTheWheelAtASprintAndWithTheReactionOffItNeverRunsFasterThanALazyJog() throws {
        // (That a burst sends it to the wheel at once, once, is the brain's, and tested with it: this is the whole of it through the stage,
        // the load the stage reads and smooths, and the burst the stage's BusyWatch finds in it.)
        func trial(seed: UInt64, reacts: Bool) -> (wheel: Bool, sprinted: Bool, faster: Bool) {
            let rig = hamsters(Screens.pill, seed: seed)
            defer { rig.hide() }
            rig.stage.tuning.reactsToBusyMachine = reacts
            // Quiet for long enough to know what is usual.
            rig.cpu.value = 0.05
            for _ in 0..<(4 * 60 * 3) { rig.advance(0.25) }
            rig.cpu.value = 0.97
            var result = (wheel: false, sprinted: false, faster: false)
            for _ in 0..<(4 * 60) {
                rig.advance(0.25)
                guard let pose = rig.stage.poses.first else { continue }
                if let prop = pose.prop, HamsterProp(prop.look).isWheel { result.wheel = true }
                let move = HamsterMove(pose.motion)
                if move == .wheelSprint { result.sprinted = true }
                if [.wheelJog, .wheelRun, .wheelSprint].contains(move) { result.faster = true }
            }
            return result
        }
        var sprinted = 0, wheels = 0
        for seed: UInt64 in [3, 8, 12, 21, 34, 55] {
            let on = trial(seed: seed, reacts: true), off = trial(seed: seed, reacts: false)
            if on.sprinted { sprinted += 1 }
            if on.wheel { wheels += 1 }
            #expect(!off.sprinted && !off.faster, "seed \(seed): with the reaction off it runs no faster than a lazy jog")
        }
        #expect(sprinted >= 5 && wheels >= 5, "after a minute of a busy Mac it was in the wheel and sprinting: \(wheels) and \(sprinted) of 6")
    }

    // MARK: The pointer

    @Test func aPointerNearTheStripMakesItFreezeAndLookAndWhenItIsGoneItGoesOn() throws {
        let rig = hamsters(Screens.pill, seed: 4)
        let host = try #require(rig.hosts.first)
        for _ in 0..<(4 * 20) { rig.advance(0.25) }
        let frame = try #require(host.screenFrame)
        rig.pointer.point = CGPoint(x: frame.midX, y: frame.midY)
        rig.advance(1)
        let stare = try #require(rig.stage.poses.first)
        #expect([HamsterMove.freeze, .wheelWatch].contains(HamsterMove(stare.motion)), "\(HamsterMove(stare.motion))")
        #expect(image(of: host.characters[0].sprite) === HamsterSheets.shared.strip(for: HamsterMove(stare.motion), facing: stare.facing).image as AnyObject)
        rig.advance(5)
        #expect([HamsterMove.freeze, .wheelWatch].contains(HamsterMove(try #require(rig.stage.poses.first).motion)))
        rig.pointer.point = CGPoint(x: 9000, y: 9000)
        rig.advance(3)
        #expect(![HamsterMove.freeze, .wheelWatch].contains(HamsterMove(try #require(rig.stage.poses.first).motion)))
        rig.hide()
    }

    // MARK: The portal

    @Test func onAHardwareNotchItCrossesTheCameraThroughThePortalOnlyByAScurryAndNeverStopsInIt() throws {
        var through = 0
        for seed: UInt64 in [3, 8, 12] {
            let rig = hamsters(Screens.hardware, seed: seed)
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
                #expect(!crossing.contains(to) || to == crossing.lowerBound || to == crossing.upperBound, "seed \(seed): a \(HamsterMove(pose.motion)) ends at \(to)")
                let goesThrough = from <= crossing.lowerBound && to >= crossing.upperBound || from >= crossing.upperBound && to <= crossing.lowerBound
                for host in [left, right] {
                    let animation = host.characters[0].portal.animation(forKey: CatSpriteView.portalKey) as? CAKeyframeAnimation
                    #expect((animation != nil) == goesThrough, "\(HamsterMove(pose.motion)) from \(from) to \(to): a portal \(animation != nil)")
                }
                if goesThrough {
                    through += 1
                    #expect(HamsterMove(pose.motion) == .scurry, "only a scurry goes through")
                    let walk = try #require(left.characters[0].sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation)
                    #expect(walk.duration >= abs(to - from) / CGFloat(HamsterMove.scurry.speed) - 0.5)
                }
                if pose.from == pose.to {
                    stationary += 1
                    let visible = [left, right].filter { CGRect(origin: $0.characters[0].sprite.position, size: $0.characters[0].sprite.bounds.size).intersects($0.bounds) }
                    #expect(visible.count == 1, "seed \(seed): a \(HamsterMove(pose.motion)) with the hamster in \(visible.count) of the views")
                }
            }
            #expect(stationary > 100)
            rig.hide()
        }
        #expect(through >= 4, "it crosses the camera now and then: \(through) times")
    }

    @Test func aWheelIsNeverSetUpInTheCameraOrAcrossItEvenInAHurry() throws {
        for (seed, load) in [(UInt64(1), 0.05), (4, 0.9), (7, 0.5), (11, 0.9)] {
            let rig = hamsters(Screens.hardware, seed: seed)
            rig.cpu.value = load
            let left = try #require(rig.container.leftWing)
            let field = left.field
            let crossing = try #require(field.crossing)
            var wheels = 0
            var last: Pose?
            for _ in 0..<(4 * 60 * 90) {
                rig.advance(0.25)
                guard let pose = rig.stage.poses.first, pose != last else { continue }
                last = pose
                guard let prop = pose.prop, HamsterProp(prop.look).isWheel else { continue }
                wheels += 1
                let x = field.lane.x(at: prop.from)
                #expect(x < crossing.lowerBound || x > crossing.upperBound, "seed \(seed): a wheel at \(x), the camera is \(crossing)")
            }
            #expect(wheels > 10, "seed \(seed): \(wheels)")
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

    @Test func aClickOnTheHamsterMakesItHopAndNeverMewsWhateverTheMewSettingIsAndAClickOnTheCatDoes() throws {
        let rig = hamsters(Screens.pill, kinds: [.cat, .hamster])
        rig.stage.playsMeow = true
        // Until the hamster is sitting about, which is what a stroke finds it doing a good part of the time.
        for _ in 0..<(4 * 60 * 10) {
            rig.advance(0.25)
            if let move = rig.stage.poses.last.map({ HamsterMove($0.motion) }), [.sit, .groom, .blink].contains(move) { break }
        }
        let host = try #require(rig.hosts.first)
        let (cat, hamster) = (host.characters[0].sprite, host.characters[1].sprite)
        try click(host, at: CGPoint(x: hamster.frame.midX, y: hamster.frame.midY))
        #expect(rig.stage.strokes == 1 && rig.meow.plays == 0, "no mew for a hamster")
        let hop = HamsterMove(try #require(rig.stage.poses.last).motion)
        #expect(hop == .happy, "it hops: \(hop)")
        let catCentre = CGPoint(x: cat.frame.midX, y: cat.frame.midY)
        if !hamster.frame.insetBy(dx: -2, dy: -2).contains(catCentre) {
            try click(host, at: catCentre)
            #expect(rig.stage.strokes == 2 && rig.meow.plays == 1, "and the cat's is a mew")
        }
        rig.hide()
        let alone = hamsters(Screens.pill, kinds: [.hamster])
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

    @Test func aClickWhereTheHamstersEmptyPictureIsOverTheCatIsTheCatsAndWhereItIsDrawnTheHamsters() throws {
        let rig = hamsters(Screens.pill, seed: 5, kinds: [.cat, .hamster])
        rig.stage.playsMeow = true
        for _ in 0..<40 { rig.advance(0.25) }
        let host = try #require(rig.hosts.first)
        let (cat, hamster) = (host.characters[0].sprite, host.characters[1].sprite)
        let catAt = cat.position
        /// The hamster's picture is put over the cat's, as it is when they walk through each other, and the two are still: a click that
        /// changes what is shown puts them back where the stage says they are.
        func arrange() {
            cat.removeAllAnimations()
            hamster.removeAllAnimations()
            cat.position = catAt
            hamster.position = CGPoint(x: catAt.x + 16, y: catAt.y)
        }
        arrange()
        var onlyTheCat: CGPoint?, onlyTheHamster: CGPoint?
        let overlap = cat.frame.intersection(hamster.frame)
        for x in stride(from: overlap.minX, to: overlap.maxX, by: 1) {
            for y in stride(from: overlap.minY, to: overlap.maxY, by: 1) {
                let point = CGPoint(x: x + 0.5, y: y + 0.5)
                let (c, h) = (hasInk(cat, at: point), hasInk(hamster, at: point))
                if c && !h, onlyTheCat == nil { onlyTheCat = point }
                if h && !c, onlyTheHamster == nil { onlyTheHamster = point }
            }
        }
        let catPoint = try #require(onlyTheCat, "the cat is drawn where the hamster is clear")
        let hamsterPoint = try #require(onlyTheHamster, "and the hamster where the cat is clear")
        try click(host, at: catPoint)
        #expect(rig.meow.plays == 1 && rig.stage.strokes == 1, "the click was the cat's: a mew")
        arrange()
        try click(host, at: hamsterPoint)
        #expect(rig.meow.plays == 1 && rig.stage.strokes == 2, "and the click on the hamster was the hamster's: no mew")
        rig.hide()
    }

    // MARK: Reduce Motion, and taken away

    @Test func withReduceMotionTheHamsterSitsStillWithItsEyesShutNowAndThenAndNothingOfItsIsOut() throws {
        let rig = hamsters(Screens.hardware, kinds: [.hamster, .cat], reducesMotion: true)
        for host in rig.hosts {
            #expect(host.characters.count == 2)
            #expect(image(of: host.characters[0].sprite) === HamsterSheets.shared.restingStrip().image as AnyObject)
            #expect(host.characters.allSatisfy { $0.prop.isHidden && $0.portal.isHidden })
        }
        #expect(!rig.stage.isTicking)
    }

    @Test func turningReduceMotionOnInTheMiddleOfARunStillsItAndTakesTheWheelOffTheView() throws {
        let rig = hamsters(Screens.pill, seed: 4)
        rig.cpu.value = 0.3
        let host = try #require(rig.hosts.first)
        var running = false
        for _ in 0..<(4 * 60 * 180) {
            rig.advance(0.25)
            if let pose = rig.stage.poses.first, HamsterMove(pose.motion).runs {
                running = true
                break
            }
        }
        #expect(running && !host.characters[0].prop.isHidden)
        rig.knobs.reducesMotion = true
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { !rig.stage.isTicking }, seconds: 5))
        #expect(host.characters[0].prop.isHidden, "no wheel left on the view")
        #expect(image(of: host.characters[0].sprite) === HamsterSheets.shared.restingStrip().image as AnyObject)
        rig.knobs.reducesMotion = false
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { rig.stage.isTicking }, seconds: 5))
        #expect(rig.stage.poses.first?.prop == nil, "and none that comes back")
    }

    @Test func takingTheHamsterOffAScreenInTheMiddleOfARunTakesItsLayersAndItsWheelOffTheView() throws {
        let rig = hamsters(Screens.pill, seed: 4, kinds: [.cat, .hamster])
        rig.cpu.value = 0.3
        let host = try #require(rig.hosts.first)
        var running = false
        for _ in 0..<(4 * 60 * 240) {
            rig.advance(0.25)
            if let pose = rig.stage.poses.last, HamsterMove(pose.motion).runs {
                running = true
                break
            }
        }
        #expect(running && host.characters.count == 2 && !host.characters[1].prop.isHidden)
        let hamster = host.characters[1]
        rig.stage.characters = [.cat]
        #expect(host.characters.count == 1 && hamster.sprite.isHidden && hamster.prop.isHidden && hamster.sprite.superlayer == nil)
        rig.advance(30)
        #expect(host.characters.count == 1 && rig.stage.poses.count == 1)
    }

    // MARK: With the others

    struct Report {
        var overlaps: [String] = []
        var crossingTogether: [String] = []
        var inTheWay: [String] = []
        var crossings = 0
        var wheels = 0
        var together = 0
    }

    /// What the characters owe each other, looked at after every waking, for `minutes` of made-up time: not on each other, one at a time in the
    /// portal, and nobody at rest in the room a wheel or a tub takes up.
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
                    report.wheels += 1
                    // Nobody else is at rest where the prop is, or where its owner hops from.
                    for (other, otherPose) in poses.enumerated() where other != index && rests(otherPose) {
                        // (The pair that are playing, one on the other's back, owe each other nothing.)
                        if let play, Set([index, other]) == [play.host, play.guest] { continue }
                        // (The hamster's wheel keeps the place it hops from too. The capybara's tub is held to its own place here, as PET6's test
                        // holds it: a cat has been found at rest 13 points from the place the capybara hops from, once or twice in fifteen minutes.)
                        for place in kinds[index] == .hamster ? [prop.from] + prop.alsoAt : [prop.from] {
                            let apart = abs(otherPose.position(at: now) - place) * travel
                            if apart < width { report.inTheWay.append("\(label) at \(now): \(other) \(apart) points from the room \(index)'s prop takes") }
                        }
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

    @Test func aCatACapybaraAndAHamsterOnTheMacsWingsNeverStopOnEachOtherOrInTheirRoomAndOneAtATimeGoesThroughThePortal() throws {
        var report = Report()
        for seed: UInt64 in [3, 8, 21, 55] {
            let rig = BodyRig(geometry: Screens.hardware, seed: seed)
            let one = try live(rig, kinds: [.cat, .capybara, .hamster], minutes: 20, label: "seed \(seed)") { tick in rig.cpu.value = tick % 4000 < 2000 ? 0.05 : 0.8 }
            report.overlaps += one.overlaps
            report.crossingTogether += one.crossingTogether
            report.inTheWay += one.inTheWay
            report.crossings += one.crossings
            report.wheels += one.wheels
            report.together += one.together
            rig.hide()
        }
        #expect(report.overlaps.isEmpty, "\(report.overlaps.prefix(5))")
        #expect(report.crossingTogether.isEmpty, "\(report.crossingTogether.prefix(5))")
        #expect(report.inTheWay.isEmpty, "\(report.inTheWay.prefix(5))")
        #expect(report.crossings > 100 && report.together > 50 && report.wheels > 100, "\(report.crossings) in the portal, \(report.together) walking together, \(report.wheels) with a prop out")
    }

    @Test func theSameInThePillAndTheTallPillAndTwoOfThemInTheNarrowWings() throws {
        var report = Report()
        let rows: [(NotchGeometry, [CharacterKind], CGFloat?)] = [
            (Screens.pill, [.cat, .capybara, .hamster], nil), (Screens.tallPill, [.hamster, .capybara, .cat], nil), (Screens.pill, [.capybara, .hamster], nil),
            (Screens.hardware, [.cat, .hamster], 360),
        ]
        for (geometry, kinds, width) in rows {
            for seed: UInt64 in [3, 8, 21] {
                let rig = BodyRig(geometry: geometry, seed: seed, width: width)
                let one = try live(rig, kinds: kinds, minutes: 15, label: "\(kinds), seed \(seed)") { tick in rig.cpu.value = tick % 3000 < 1500 ? 0.05 : 0.9 }
                report.overlaps += one.overlaps
                report.crossingTogether += one.crossingTogether
                report.inTheWay += one.inTheWay
                report.wheels += one.wheels
                report.together += one.together
                rig.hide()
            }
        }
        #expect(report.overlaps.isEmpty, "\(report.overlaps.prefix(5))")
        #expect(report.crossingTogether.isEmpty, "\(report.crossingTogether.prefix(5))")
        #expect(report.inTheWay.isEmpty, "\(report.inTheWay.prefix(5))")
        #expect(report.together > 200 && report.wheels > 100, "\(report.together) walking together, \(report.wheels) with a prop out")
    }
}

extension HamsterProp {
    /// How long one pass of a pace's wheel takes: six pictures at its speed.
    static func animationDuration(of pace: WheelPace) -> Double { Double(pace.prop.frameCount) / pace.prop.fps }
}
