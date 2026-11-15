import AppKit
import Metal
import QuartzCore
import Testing
@testable import PetModule

/// The cat as the render server plays it, rendered offscreen by a `CARenderer` into a texture of its own (nothing on the screen, no
/// window): the real view's layers with their real animations, at moments through the loops, against a plain layer showing the one
/// picture that should be there, drawn the way any layer draws an image.
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil), .serialized) @MainActor struct CatRenderTests {
    static let ground = CGColor(gray: 0.1, alpha: 1)

    /// Renders `layer` at media times and hands back BGRA bytes, rows as the texture has them.
    final class Offscreen {
        let queue: MTLCommandQueue
        let texture: MTLTexture
        let renderer: CARenderer
        let width: Int
        let height: Int

        init?(layer: CALayer, width: Int, height: Int) {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            description.usage = [.renderTarget, .shaderRead]
            description.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: description) else { return nil }
            self.queue = queue
            self.texture = texture
            self.width = width
            self.height = height
            renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
            renderer.layer = layer
            renderer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        }

        func render(atTime time: CFTimeInterval) -> [UInt8] {
            renderer.beginFrame(atTime: time, timeStamp: nil)
            renderer.addUpdate(renderer.updateBounds())
            renderer.render()
            renderer.endFrame()
            let fence = queue.makeCommandBuffer()
            fence?.commit()
            fence?.waitUntilCompleted()
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            return bytes
        }
    }

    /// How many bytes differ: a failure says that, not the two textures.
    func difference(_ first: [UInt8], _ second: [UInt8]) -> Int {
        first.count != second.count ? Int.max : zip(first, second).filter { $0 != $1 }.count
    }

    /// The real view, 64 by 40 points, scaled up `scale` times by the layer above it as a Retina display scales, with the cat sitting at
    /// its lane's left end.
    func scene(
        move: CatMove, facing: Facing, coat: CatCoat = .tabby, scale: Int = 1, elapsed: TimeInterval = 0
    ) -> (CatSpriteView, Offscreen, CFTimeInterval)? {
        let stage = CatStage(scheduler: ManualSchedulerStub.make())
        let host = CatSpriteView(stage: stage)
        host.frame = CGRect(x: 0, y: 0, width: 64, height: 40)
        host.layer?.backgroundColor = Self.ground
        host.show(plan: CatPlan(move: move, facing: facing, from: 0, to: 0, began: 0, duration: 99), elapsed: elapsed, coat: coat)
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 64, height: 40)
        root.anchorPoint = .zero
        root.position = .zero
        root.setAffineTransform(CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        guard let layer = host.layer else { return nil }
        root.addSublayer(layer)
        guard let offscreen = Offscreen(layer: root, width: 64 * scale, height: 40 * scale) else { return nil }
        // Pin the loop to the layer's own time, so that a frame rendered `seconds` later is `seconds` into the animation (less the
        // `elapsed` it was shown at).
        let begin = host.sprite.convertTime(CACurrentMediaTime(), from: nil)
        guard let added = host.sprite.animation(forKey: CatSpriteView.framesKey)?.copy() as? CAKeyframeAnimation else { return nil }
        added.beginTime = begin - elapsed
        host.sprite.add(added, forKey: CatSpriteView.framesKey)
        CATransaction.flush()
        return (host, offscreen, begin)
    }

    /// A plain layer with `frame` of the move's strip as its contents: what showing the right picture looks like.
    func reference(move: CatMove, facing: Facing, coat: CatCoat = .tabby, frame: Int, scale: Int = 1) -> Offscreen? {
        let strip = CatSheets.shared.strip(for: move, facing: facing, coat: coat)
        let cell = strip.frameWidth + 2 * PixelStrip.margin
        let crop = CGRect(x: frame * cell + PixelStrip.margin, y: PixelStrip.margin, width: strip.frameWidth, height: strip.frameHeight)
        guard let picture = strip.image.cropping(to: crop) else { return nil }
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 64, height: 40)
        root.anchorPoint = .zero
        root.position = .zero
        root.backgroundColor = Self.ground
        root.setAffineTransform(CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        let sprite = CALayer()
        sprite.anchorPoint = .zero
        sprite.bounds = CGRect(x: 0, y: 0, width: 32, height: 24)
        sprite.position = CGPoint(x: WalkLane(width: 64, spriteWidth: 32).minX, y: CatSpriteView.floor)
        sprite.contents = picture
        sprite.contentsGravity = .resize
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        root.addSublayer(sprite)
        // Handed to a renderer first and committed after, as a layer is that the renderer is to draw.
        let offscreen = Offscreen(layer: root, width: 64 * scale, height: 40 * scale)
        CATransaction.flush()
        return offscreen
    }

    @Test func eachMomentOfEachAnimationShowsTheFrameThatShouldBeThereAndTheSameAsAPlainLayerShowingIt() throws {
        var compared = 0
        for (move, facing) in [
            (CatMove.walk, Facing.right), (.walk, .left), (.trot, .right), (.sit, .right), (.sleep, .right), (.purr, .left),
            (.groom, .right), (.stretch, .left), (.startled, .right), (.dance, .right),
        ] {
            // The host's lane puts the cat at 6 points from the left; the reference puts it there too.
            let (_, offscreen, begin) = try #require(scene(move: move, facing: facing))
            let slot = 1 / move.fps
            var previous: [UInt8] = []
            var distinct = 0
            // Two passes, in the middle of every frame's turn (a move played once is held on its last frame after the first).
            for index in 0..<(2 * move.frameCount) {
                let rendered = offscreen.render(atTime: begin + (Double(index) + 0.5) * slot)
                let shown = move.loops ? index % move.frameCount : min(index, move.frameCount - 1)
                let expected = try #require(reference(move: move, facing: facing, frame: shown)).render(atTime: CACurrentMediaTime())
                let differing = difference(rendered, expected)
                #expect(differing == 0, "\(move) \(facing) at frame \(shown) of turn \(index): \(differing) bytes differ")
                if rendered != previous { distinct += 1 }
                previous = rendered
                compared += 1
            }
            if move.frameCount > 1 { #expect(distinct > 1, "\(move) \(facing) moves") }
        }
        #expect(compared > 100)
    }

    @Test func theFramesAreHeldForTheirWholeSlotAndStepAtItsEdge() throws {
        let (_, offscreen, begin) = try #require(scene(move: .walk, facing: .right))
        let slot = 1 / CatMove.walk.fps
        let early = offscreen.render(atTime: begin + 0.1 * slot)
        let late = offscreen.render(atTime: begin + 0.9 * slot)
        let next = offscreen.render(atTime: begin + 1.1 * slot)
        #expect(difference(early, late) == 0, "held, not blended")
        #expect(difference(early, next) > 100, "and a new picture in the next slot")
    }

    @Test(arguments: [2, 3]) func everyPixelOfTheCatIsAWholeBlockOfDevicePixelsOfOneColourOnADisplayThatScalesBy(scale: Int) throws {
        let (_, offscreen, begin) = try #require(scene(move: .sit, facing: .right, scale: scale))
        let bytes = offscreen.render(atTime: begin + 0.01)
        let width = offscreen.width
        func colour(_ x: Int, _ y: Int) -> [UInt8] { Array(bytes[(y * width + x) * 4..<(y * width + x) * 4 + 4]) }
        let (left, floor) = (6 * scale, 1 * scale)
        let (rows, columns) = (24, 32)
        // Which rows the picture's rows are on depends on the way the renderer lays its texture out, so both are tried, and one of them
        // has to be crisp throughout.
        var crisp = [true, true]
        for (index, top) in [offscreen.height - floor - rows * scale, floor].enumerated() {
            for row in 0..<rows {
                for column in 0..<columns {
                    let block = (0..<scale).flatMap { dy in (0..<scale).map { dx in colour(left + column * scale + dx, top + row * scale + dy) } }
                    if Set(block).count != 1 { crisp[index] = false }
                }
            }
        }
        #expect(crisp.contains(true), "no pixel of the cat is smeared across its neighbours at \(scale)x")
    }

    @Test func thePixelsAreTheFramesPixelsInEveryCoatsColours() throws {
        for coat in CatCoat.allCases {
            let (_, offscreen, begin) = try #require(scene(move: .sit, facing: .right, coat: coat))
            let bytes = offscreen.render(atTime: begin + 0.01)
            let (width, height) = (offscreen.width, offscreen.height)
            let frame = CatArt.animation(for: .sit).frames[0]
            // The ground, as the texture has it: the corner is outside the cat.
            let ground = Array(bytes[0..<3])
            func matches(top: Int, flipped: Bool) -> Int {
                var count = 0
                for row in 0..<frame.height {
                    for column in 0..<frame.width {
                        let shown = flipped ? frame.height - 1 - row : row
                        let offset = ((top + shown) * width + 6 + column) * 4
                        let pixel = Array(bytes[offset..<offset + 4])
                        if let rgb = coat.palette.colors[frame[column, row]] {
                            let expected: [UInt8] = [UInt8(rgb & 0xFF), UInt8((rgb >> 8) & 0xFF), UInt8((rgb >> 16) & 0xFF)]
                            // Blue, green, red: within a few steps of the palette's own, since the layer may be colour-managed.
                            if zip(pixel.prefix(3), expected).allSatisfy({ abs(Int($0) - Int($1)) <= 6 }) { count += 1 }
                        } else if Array(pixel.prefix(3)) == ground {
                            count += 1
                        }
                    }
                }
                return count
            }
            // The renderer may lay its texture out with the layer's bottom at either end; the picture is the right way up in both.
            let best = max(matches(top: height - 1 - 24, flipped: false), matches(top: 1, flipped: true))
            #expect(best == CatArt.width * CatArt.height, "\(coat): \(best) of \(CatArt.width * CatArt.height) pixels are the sprite's")
        }
    }

    @Test func aMothThatFliesOutOfTheStripIsCutOffByItsEdge() throws {
        let stage = CatStage(scheduler: ManualSchedulerStub.make())
        let host = CatSpriteView(stage: stage)
        host.frame = CGRect(x: 0, y: 0, width: 64, height: 40)
        host.layer?.backgroundColor = Self.ground
        // A moth well past the strip's right end: it is on the strip's layer, and the rest of the texture is beyond it.
        host.show(plan: CatPlan(move: .sit, facing: .right, from: 0, to: 0, began: 0, duration: 9, prop: CatProp(kind: .moth, from: 2.6, to: 2.6)), elapsed: 0, coat: .tabby)
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 96, height: 40)
        root.anchorPoint = .zero
        root.position = .zero
        root.addSublayer(try #require(host.layer))
        let offscreen = try #require(Offscreen(layer: root, width: 96, height: 40))
        CATransaction.flush()
        let bytes = offscreen.render(atTime: CACurrentMediaTime())
        var outside = 0
        var inside = 0
        for y in 0..<40 {
            for x in 0..<96 where bytes[(y * 96 + x) * 4 + 3] != 0 { if x >= 64 { outside += 1 } else { inside += 1 } }
        }
        #expect(outside == 0, "nothing past the strip's edge")
        #expect(inside > 64 * 20, "the strip itself is drawn")
        // And the moth is partly in the strip: a pale pixel of a wing near its right edge.
        var wing = 0
        for y in 0..<40 { for x in 56..<64 where bytes[(y * 96 + x) * 4 + 2] > 200 && bytes[(y * 96 + x) * 4 + 1] > 190 { wing += 1 } }
        #expect(wing > 0, "the part of the moth that is still on the strip")
    }

    @Test func theYarnRollsThroughItsFramesAndTheMothFlutters() throws {
        for (kind, animation) in [(PropKind.yarn, PropArt.yarn), (.moth, PropArt.moth)] {
            let stage = CatStage(scheduler: ManualSchedulerStub.make())
            let host = CatSpriteView(stage: stage)
            host.frame = CGRect(x: 0, y: 0, width: 64, height: 40)
            host.layer?.backgroundColor = Self.ground
            host.show(plan: CatPlan(move: .sit, facing: .right, from: 0, to: 0, began: 0, duration: 99, prop: CatProp(kind: kind, from: 0.4, to: kind == .yarn ? 0.9 : 0.4)), elapsed: 0, coat: .tabby)
            let root = CALayer()
            root.bounds = CGRect(x: 0, y: 0, width: 64, height: 40)
            root.anchorPoint = .zero
            root.position = .zero
            root.addSublayer(try #require(host.layer))
            let offscreen = try #require(Offscreen(layer: root, width: 64, height: 40))
            let begin = host.prop.convertTime(CACurrentMediaTime(), from: nil)
            for key in [CatSpriteView.framesKey, CatSpriteView.walkKey, CatSpriteView.bobKey] {
                guard let added = host.prop.animation(forKey: key)?.copy() as? CAKeyframeAnimation else { continue }
                added.beginTime = begin
                host.prop.add(added, forKey: key)
            }
            _ = try #require(host.prop.animation(forKey: CatSpriteView.framesKey))
            CATransaction.flush()
            var seen = Set<[UInt8]>()
            for index in 0..<animation.frames.count {
                seen.insert(offscreen.render(atTime: begin + (Double(index) + 0.5) / animation.fps))
            }
            #expect(seen.count == animation.frames.count, "\(kind): a picture for each frame")
        }
    }

    // MARK: Turning round at the end of the lane

    /// Where the cat is in a rendered strip: the middle of the columns that are not the ground.
    func catCentre(_ bytes: [UInt8], width: Int, height: Int) -> Double? {
        let ground = Array(bytes[0..<3])
        var (low, high) = (width, -1)
        for x in 0..<width {
            for y in 0..<height where Array(bytes[(y * width + x) * 4..<(y * width + x) * 4 + 3]) != ground {
                low = min(low, x)
                high = max(high, x)
                break
            }
        }
        return high < 0 ? nil : Double(low + high) / 2
    }

    /// Pins every animation of `layer` to begin at `begin`, as the tests do to know what a moment shows.
    func pin(_ layer: CALayer, at begin: CFTimeInterval) {
        for key in layer.animationKeys() ?? [] {
            guard let added = layer.animation(forKey: key)?.copy() as? CAAnimation else { continue }
            added.beginTime = begin
            layer.add(added, forKey: key)
        }
    }

    /// How the render server may treat the animations of a leg that has just been added.
    enum Delay: CaseIterable {
        /// Begins at once, as it should.
        case none
        /// Begins a quarter of a second after it is added: a begin time that is yet to come.
        case late
        /// Is not on the layer at all for a quarter of a second, and then is: what a screen that draws a layer only now and then, and an
        /// animation that is only now taken up, make of it, as far as the layer can tell.
        case absent
    }

    /// The cat runs the length of the lane, and runs back: every moment from before the second leg begins to its end, as the render
    /// server may draw it. The first frames of a leg can be drawn before its animation is: then what is shown of the layer is its own value,
    /// which must be where the cat stands, and not where it is going, or the cat is seen at the other end of the strip until the animation
    /// takes over, which on a screen can be for a few frames (the cat was seen to flash at the opposite edge for 66 to 230 ms).
    @Test(arguments: [true, false], Delay.allCases) func aTurnAtTheEndOfTheLaneNeverShowsTheCatAtTheOtherEndFirst(atTheRightEnd: Bool, delay: Delay) throws {
        let stage = CatStage(scheduler: ManualSchedulerStub.make())
        let host = CatSpriteView(stage: stage)
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 26)
        host.layer?.backgroundColor = Self.ground
        let (start, end) = atTheRightEnd ? (0.1, 1.0) : (0.9, 0.0)
        let distance = abs(end - start) * Double(host.lane.travel)
        let outward = CatPlan(move: .frantic, facing: atTheRightEnd ? .right : .left, from: start, to: end, began: 0, duration: distance / CatMove.frantic.speed)
        // The first leg has been run: the cat is at the end of the lane and stays there.
        host.show(plan: outward, elapsed: outward.duration, coat: .tabby)
        try arrive(host.sprite)
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 300, height: 26)
        root.anchorPoint = .zero
        root.position = .zero
        root.addSublayer(try #require(host.layer))
        let offscreen = try #require(Offscreen(layer: root, width: 300, height: 26))
        CATransaction.flush()

        // And the second leg: back the way it came.
        let back = CatPlan(move: .frantic, facing: atTheRightEnd ? .left : .right, from: end, to: start, began: 0, duration: outward.duration)
        let now = host.sprite.convertTime(CACurrentMediaTime(), from: nil)
        host.show(plan: back, elapsed: 0, coat: .tabby)
        var animations: [(String, CAAnimation)] = []
        for key in host.sprite.animationKeys() ?? [] {
            if let added = host.sprite.animation(forKey: key) { animations.append((key, added)) }
        }
        let begin: CFTimeInterval
        switch delay {
        case .none:
            begin = now
            pin(host.sprite, at: begin)
        case .late:
            begin = now + 0.25
            pin(host.sprite, at: begin)
        case .absent:
            begin = now + 0.25
            host.sprite.removeAllAnimations()
        }
        CATransaction.flush()

        // From before the second leg is shown to after it ends, a twenty-fourth of a second apart.
        var centres: [Double] = []
        var time = now - 0.1
        var added = delay != .absent
        while time < begin + back.duration + 0.2 {
            if !added, time >= begin {
                // The animations arrive: as they were made, and begun now.
                for (key, animation) in animations {
                    guard let copy = animation.copy() as? CAAnimation else { continue }
                    copy.beginTime = begin
                    host.sprite.add(copy, forKey: key)
                }
                CATransaction.flush()
                added = true
            }
            centres.append(try #require(catCentre(offscreen.render(atTime: time), width: 300, height: 26)))
            time += 1.0 / 24
        }
        #expect(centres.count > 50)
        // The most the cat goes in a twenty-fourth of a second is a frame's step, and what the frames' own shapes move the middle of it.
        let longestStep = CatMove.frantic.advance * 12 / 24 + 8
        for (before, after) in zip(centres, centres.dropFirst()) {
            #expect(abs(after - before) <= longestStep, "\(delay): a jump from \(before) to \(after)")
        }
        // For as long as nothing animates the layer, the cat stands where the first leg ended (the sprite's middle is about sixteen points
        // from its left edge); a quarter of a second after the leg is shown it has not moved far from it, in any of the three.
        let leftAt = host.lane.x(at: end) + 16
        #expect(abs(centres[0] - leftAt) <= 14, "\(delay): before the second leg begins the cat is at the end of the first: \(centres[0]) and \(leftAt)")
        #expect(abs(centres[5] - leftAt) <= 14, "\(delay): and a quarter of a second on, with nothing animating it yet: \(centres[5])")
        let turnedAt = host.lane.x(at: start) + 16
        #expect(abs((centres.last ?? 0) - turnedAt) <= 14, "\(delay): and it ends where the second leg goes")
    }

    // MARK: Held when over

    /// A plan is shown some milliseconds after it began, because the stage wakes four times a second, and never at exactly its beginning. What
    /// the tests above do is show it at exactly its beginning, which is the one time at which it makes no difference how an animation is
    /// begun part of the way in. Begun with a `timeOffset` the animation wraps round, and when it is over and held it is held on what it
    /// showed at the offset, which is its first frame and its first place: the cat was seen back at the start of the walk it had just made
    /// for as long as it took the next plan to come, and playing the first steps of it again.
    @Test(arguments: [CatMove.yawn, .lieDown, .sitDown, .standUp, .stretch, .startled, .pounce], [0.002, 0.1])
    func aMovePlayedOnceIsHeldOnItsLastFrameWhenItIsOverWhateverHowFarInItWasShown(move: CatMove, elapsed: TimeInterval) throws {
        let (_, offscreen, begin) = try #require(scene(move: move, facing: .right, elapsed: elapsed))
        let over = begin - elapsed + move.passDuration
        let last = try #require(reference(move: move, facing: .right, frame: move.frameCount - 1)).render(atTime: CACurrentMediaTime())
        for late in [0.03, 0.4, 3] {
            let differing = difference(offscreen.render(atTime: over + late), last)
            #expect(differing == 0, "\(move) shown \(elapsed) in, \(late) after its end: \(differing) bytes differ from its last frame")
        }
    }

    @Test(arguments: [0.002, 0.2], [true, false])
    func aWalkIsHeldAtItsEndWhenItIsOverWhateverHowFarInItWasShown(elapsed: TimeInterval, toTheRight: Bool) throws {
        let stage = CatStage(scheduler: ManualSchedulerStub.make())
        let host = CatSpriteView(stage: stage)
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 26)
        host.layer?.backgroundColor = Self.ground
        let lane = host.lane
        let (start, end) = toTheRight ? (0.1, 1.0) : (0.9, 0.0)
        let distance = abs(end - start) * Double(lane.travel)
        let leg = CatPlan(
            move: .frantic, facing: toTheRight ? .right : .left, from: start, to: end, began: 0, duration: distance / CatMove.frantic.speed
        )
        host.show(plan: leg, elapsed: elapsed, coat: .tabby)
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 300, height: 26)
        root.anchorPoint = .zero
        root.position = .zero
        root.addSublayer(try #require(host.layer))
        let offscreen = try #require(Offscreen(layer: root, width: 300, height: 26))
        // Every animation is begun `elapsed` before the moment it is pinned to, as it was shown.
        let begin = host.sprite.convertTime(CACurrentMediaTime(), from: nil)
        for key in host.sprite.animationKeys() ?? [] {
            guard let added = host.sprite.animation(forKey: key)?.copy() as? CAAnimation else { continue }
            added.beginTime = begin - elapsed
            host.sprite.add(added, forKey: key)
        }
        CATransaction.flush()
        let over = begin - elapsed + leg.duration
        func centre(at time: CFTimeInterval) throws -> Double {
            try #require(catCentre(offscreen.render(atTime: time), width: 300, height: 26))
        }
        // It walks: about half way along at half the time.
        let half = lane.x(at: (start + end) / 2) + 16
        #expect(abs(try centre(at: over - leg.duration / 2) - half) <= 30, "half way along at half the time")
        // And is where the walk ends, for as long as the next plan takes to come.
        let endsAt = lane.x(at: end) + 16
        for late in [0.02, 0.1, 0.5, 3] {
            let at = try centre(at: over + late)
            #expect(abs(at - endsAt) <= 14, "shown \(elapsed) in, \(late) after the walk is over: at \(at), not at its end \(endsAt) (it began at \(lane.x(at: start) + 16))")
        }
    }
}
