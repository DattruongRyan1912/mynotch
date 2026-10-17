import AppKit
import MyNotchCore
import NotchUI
import QuartzCore
import Testing
@testable import PetModule

/// The capybara on a stage and in a view: what is drawn, where it goes, what is left on the layers, and the settings that choose it.
@Suite(.serialized) @MainActor struct CapybaraStageTests {
    func capybaras(_ geometry: NotchGeometry, seed: UInt64 = 5, kinds: [CharacterKind] = [.capybara], reducesMotion: Bool = false) -> BodyRig {
        let rig = BodyRig(geometry: geometry, seed: seed, reducesMotion: reducesMotion)
        rig.show()
        rig.stage.characters = kinds
        return rig
    }

    func image(of layer: CALayer) -> AnyObject? { layer.contents as AnyObject? }

    // MARK: Registered, and in the menu

    @Test func theCapybaraIsAKindWithItsOwnSpeciesAndBrainAndIsNamedInTheMenuAfterTheCat() {
        #expect(CharacterKind.allCases == [.cat, .capybara, .hamster, .penguin], "declared after the cat: the draw order and the order in the menu")
        #expect(CharacterKind.capybara.displayName == "Capybara" && CharacterKind(rawValue: "capybara") == .capybara)
        #expect(CharacterKind.capybara.species is CapybaraSpecies && CharacterKind.cat.species is CatSpecies)
        #expect(CharacterKind.capybara.species !== CharacterKind.cat.species)
        #expect(CharacterKind.capybara.species.makeBrain(seed: 1, now: 0, position: 0.5) is CapybaraBrain)
        #expect(PetScreenRow.summary(of: [.cat, .capybara]) == "Mèo, Capybara" && PetScreenRow.summary(of: [.capybara]) == "Capybara")
    }

    @Test func aScreenCanChooseTheCapybaraAloneOrWithTheCatAndTheChoiceIsKeptByTheNameOfTheKind() throws {
        let screens = PetScreens().setting([.capybara], for: "A").setting([.capybara, .cat], for: "B").toggling(.capybara, on: "C")
        #expect(screens.kinds(for: "A") == [.capybara])
        #expect(screens.kinds(for: "B") == [.cat, .capybara], "in the order the kinds are declared, not as they were picked")
        #expect(screens.kinds(for: "C") == [.cat, .capybara], "the cat was the default, and the capybara is added to it")
        let text = String(decoding: try JSONEncoder().encode(PetScreens().setting([.cat, .capybara], for: "A")), as: UTF8.self)
        #expect(text.contains("[\"cat\",\"capybara\"]"), "\(text)")
        #expect(try JSONDecoder().decode(PetScreens.self, from: Data(text.utf8)).kinds(for: "A") == [.cat, .capybara])
        #expect(screens.canAdd(to: "A") && screens.setting([.cat, .capybara], for: "A").canAdd(to: "A"))
    }

    // MARK: Drawn

    @Test func aCapybaraAloneIsDrawnWithItsOwnStripsOnEveryKindOfNotch() throws {
        for geometry in [Screens.pill, Screens.tallPill, Screens.hardware] {
            let rig = capybaras(geometry)
            for _ in 0..<(4 * 60 * 5) {
                rig.advance(0.25)
                let pose = try #require(rig.stage.poses.first)
                for host in rig.hosts {
                    let strip = CapybaraSheets.shared.strip(for: CapybaraMove(pose.motion), facing: pose.facing)
                    #expect(!host.characters[0].sprite.isHidden)
                    #expect(image(of: host.characters[0].sprite) === strip.image as AnyObject, "\(geometry.kind): \(CapybaraMove(pose.motion))")
                }
            }
            #expect(rig.stage.poses.count == 1 && rig.stage.plan == nil, "the cat's plan is not a capybara's")
            rig.hide()
        }
    }

    @Test func inThePillItIsDrawnAtTheScaleOfTheLaneAndTheTubAtTheSameScaleAndTheHopInWholeSteps() throws {
        for (geometry, scale) in [(Screens.pill, 1), (Screens.tallPill, 2)] {
            var sawTub = false, sawHop = false
            for seed: UInt64 in 1...6 {
                let rig = capybaras(geometry, seed: seed)
                let lane = try #require(rig.container.lane)
                #expect(lane.field.scale == scale)
                for _ in 0..<(4 * 60 * 40) {
                    rig.advance(0.25)
                    let layers = lane.characters[0]
                    #expect(layers.sprite.bounds.size == CGSize(width: 32 * scale, height: 24 * scale))
                    guard let pose = rig.stage.poses.first else { continue }
                    if let prop = pose.prop, [.tubEmpty, .tubRippling].contains(CapybaraProp(prop.look)) {
                        sawTub = true
                        #expect(layers.prop.bounds.size == CGSize(width: 32 * scale, height: 24 * scale) && !layers.prop.isHidden)
                    }
                    if CapybaraMove(pose.motion) == .climbIn, let hop = layers.sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation {
                        let stops = (hop.values as? [NSNumber] ?? []).map { CGFloat($0.doubleValue) }
                        guard stops.count > 2 else { continue }
                        sawHop = true
                        for (a, b) in zip(stops, stops.dropFirst()) { #expect(abs(abs(b - a) - 4 * CGFloat(scale)) < 1.5, "steps of \(b - a) at scale \(scale)") }
                        #expect(abs(abs(stops.last! - stops[0]) - 24 * CGFloat(scale)) < 4 * CGFloat(scale), "the hop's span: \(stops)")
                    }
                }
                rig.hide()
                if sawTub && sawHop { break }
            }
            #expect(sawTub && sawHop, "scale \(scale): a tub \(sawTub) and a hop \(sawHop)")
        }
    }

    @Test func throughHoursNoViewIsEverLeftShowingATubOrAnOrangeThatThePoseDoesNotHave() throws {
        for geometry in [Screens.pill, Screens.hardware] {
            for seed: UInt64 in [2, 9] {
                let rig = capybaras(geometry, seed: seed)
                var props = 0
                for tick in 0..<(4 * 60 * 90) {
                    if tick % 4000 == 1500 { rig.idle.seconds = 900 } else if tick % 4000 == 2500 { rig.idle.seconds = 0 }
                    rig.advance(0.25)
                    let pose = try #require(rig.stage.poses.first)
                    if pose.prop != nil { props += 1 }
                    for host in rig.hosts {
                        #expect(host.characters[0].prop.isHidden == (pose.prop == nil), "\(geometry.kind), seed \(seed): \(CapybaraMove(pose.motion)) with \(String(describing: pose.prop?.look))")
                    }
                }
                #expect(props > 1000, "it has things out for a good part of its time: \(props)")
                rig.hide()
            }
        }
    }

    // MARK: The portal

    @Test func onAHardwareNotchItCrossesTheCameraSlowlyThroughThePortalAndNeverStopsInIt() throws {
        var through = 0
        for seed: UInt64 in [3, 8, 12] {
            let rig = capybaras(Screens.hardware, seed: seed)
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
                #expect(!crossing.contains(to) || to == crossing.lowerBound || to == crossing.upperBound, "seed \(seed): a \(CapybaraMove(pose.motion)) ends at \(to)")
                let goesThrough = from <= crossing.lowerBound && to >= crossing.upperBound || from >= crossing.upperBound && to <= crossing.lowerBound
                for host in [left, right] {
                    let animation = host.characters[0].portal.animation(forKey: CatSpriteView.portalKey) as? CAKeyframeAnimation
                    #expect((animation != nil) == goesThrough, "\(CapybaraMove(pose.motion)) from \(from) to \(to): a portal \(animation != nil)")
                }
                if goesThrough {
                    through += 1
                    let walk = try #require(left.characters[0].sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation)
                    #expect(CapybaraMove(pose.motion) == .walk, "only a walk goes through")
                    // Slowly: at a pace of 8 points a second or less (steps of a point at 8 frames a second), the whole of its width in
                    // the camera for as long as that takes.
                    #expect(walk.duration >= abs(to - from) / CGFloat(CapybaraMove.walk.speed) - 0.5, "it is not hurried through")
                }
                if pose.from == pose.to {
                    stationary += 1
                    let visible = [left, right].filter { CGRect(origin: $0.characters[0].sprite.position, size: $0.characters[0].sprite.bounds.size).intersects($0.bounds) }
                    #expect(visible.count == 1, "seed \(seed): a \(CapybaraMove(pose.motion)) with the capybara in \(visible.count) of the views")
                }
            }
            #expect(stationary > 100)
            rig.hide()
        }
        #expect(through >= 4, "it crosses the camera now and then: \(through) times")
    }

    @Test func aTubIsNeverSetDownInTheCameraOrAcrossIt() throws {
        for seed: UInt64 in [1, 4, 7, 11] {
            let rig = capybaras(Screens.hardware, seed: seed)
            let left = try #require(rig.container.leftWing)
            let field = left.field
            let crossing = try #require(field.crossing)
            var tubs = 0
            var last: Pose?
            for _ in 0..<(4 * 60 * 90) {
                rig.advance(0.25)
                guard let pose = rig.stage.poses.first, pose != last else { continue }
                last = pose
                guard let prop = pose.prop, [.tubEmpty, .tubRippling, .tubAppearing, .tubGoing].contains(CapybaraProp(prop.look)) else { continue }
                tubs += 1
                let x = field.lane.x(at: prop.from)
                #expect(x < crossing.lowerBound || x > crossing.upperBound, "seed \(seed): a tub at \(x), the camera is \(crossing)")
            }
            #expect(tubs > 10, "seed \(seed): \(tubs)")
            rig.hide()
        }
    }

    // MARK: Clicks and Reduce Motion

    func click(_ host: CatSpriteView, at point: CGPoint) throws {
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: host.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: host.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        host.mouseDown(with: event)
    }

    @Test func aClickOnTheCapybaraSquintsAndNeverMewsWhateverTheMewSettingIsAndAClickOnTheCatDoes() throws {
        let rig = capybaras(Screens.pill, kinds: [.cat, .capybara])
        rig.stage.playsMeow = true
        // Until the capybara is sitting about, which is what a stroke finds it doing most of the time.
        for _ in 0..<(4 * 60 * 10) {
            rig.advance(0.25)
            if let move = rig.stage.poses.last.map({ CapybaraMove($0.motion) }), [.sit, .doze, .blink].contains(move) { break }
        }
        let host = try #require(rig.hosts.first)
        let (cat, capybara) = (host.characters[0].sprite, host.characters[1].sprite)
        // Each is hit where it is drawn; the capybara's picture is over the cat's where they overlap.
        let capyCentre = CGPoint(x: capybara.frame.midX, y: capybara.frame.midY)
        try click(host, at: capyCentre)
        #expect(rig.stage.strokes == 1 && rig.meow.plays == 0, "no mew for a capybara")
        let squint = CapybaraMove(try #require(rig.stage.poses.last).motion)
        #expect(squint == .happy, "it squints: \(squint)")
        let catCentre = CGPoint(x: cat.frame.midX, y: cat.frame.midY)
        if !capybara.frame.insetBy(dx: -2, dy: -2).contains(catCentre) {
            try click(host, at: catCentre)
            #expect(rig.stage.strokes == 2 && rig.meow.plays == 1, "and the cat's is a mew")
        } else {
            rig.stage.catWasClicked(character: 0)
            #expect(rig.meow.plays == 1)
        }
        rig.hide()
        let alone = capybaras(Screens.pill, kinds: [.capybara])
        alone.stage.playsMeow = true
        alone.stage.catWasClicked()
        #expect(alone.meow.plays == 0 && alone.stage.strokes == 1)
    }

    @Test func withReduceMotionTheCapybaraSitsStillWithItsEyesShutNowAndThenAndNothingOfItsIsOut() throws {
        let rig = capybaras(Screens.hardware, kinds: [.capybara, .cat], reducesMotion: true)
        for host in rig.hosts {
            #expect(host.characters.count == 2)
            #expect(image(of: host.characters[0].sprite) === CapybaraSheets.shared.restingStrip().image as AnyObject)
            #expect(host.characters.allSatisfy { $0.prop.isHidden && $0.portal.isHidden })
        }
        #expect(!rig.stage.isTicking)
    }

    @Test func turningReduceMotionOnInTheMiddleOfASoakStillsItAndTakesTheTubOffTheView() throws {
        let rig = capybaras(Screens.pill, seed: 4)
        let host = try #require(rig.hosts.first)
        var soaking = false
        for _ in 0..<(4 * 60 * 120) {
            rig.advance(0.25)
            if let pose = rig.stage.poses.first, CapybaraMove(pose.motion) == .soak {
                soaking = true
                break
            }
        }
        #expect(soaking && !host.characters[0].prop.isHidden)
        rig.knobs.reducesMotion = true
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { !rig.stage.isTicking }, seconds: 5))
        #expect(host.characters[0].prop.isHidden, "no tub left on the view")
        #expect(image(of: host.characters[0].sprite) === CapybaraSheets.shared.restingStrip().image as AnyObject)
        rig.knobs.reducesMotion = false
        rig.notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(runLoop(until: { rig.stage.isTicking }, seconds: 5))
        #expect(rig.stage.poses.first?.prop == nil, "and none that comes back")
    }

    @Test func takingTheCapybaraOffAScreenInTheMiddleOfASoakTakesItsLayersAndItsTubOffTheView() throws {
        let rig = capybaras(Screens.pill, seed: 4, kinds: [.cat, .capybara])
        let host = try #require(rig.hosts.first)
        var soaking = false
        for _ in 0..<(4 * 60 * 180) {
            rig.advance(0.25)
            if let pose = rig.stage.poses.last, CapybaraMove(pose.motion) == .soak {
                soaking = true
                break
            }
        }
        #expect(soaking && host.characters.count == 2 && !host.characters[1].prop.isHidden)
        let capybara = host.characters[1]
        rig.stage.characters = [.cat]
        #expect(host.characters.count == 1 && capybara.sprite.isHidden && capybara.prop.isHidden && capybara.sprite.superlayer == nil)
        rig.advance(30)
        #expect(host.characters.count == 1 && rig.stage.poses.count == 1)
    }
}
