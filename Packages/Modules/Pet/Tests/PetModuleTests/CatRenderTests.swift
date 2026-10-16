import AppKit
import Metal
import QuartzCore
import Testing
@testable import PetModule

/// The cat as the render server plays it, rendered offscreen by a `CARenderer` into a texture of its own (nothing on the screen, no
/// window): the real view's layer with its real animation, at moments through the loops, against a plain layer showing the one picture
/// that should be there, drawn the way any layer draws an image.
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil), .serialized) @MainActor struct CatRenderTests {
    static let side = 64

    /// Renders `layer` at media times and hands back BGRA bytes, rows as the texture has them.
    final class Offscreen {
        let queue: MTLCommandQueue
        let texture: MTLTexture
        let renderer: CARenderer

        init?(layer: CALayer) {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: CatRenderTests.side, height: CatRenderTests.side, mipmapped: false)
            description.usage = [.renderTarget, .shaderRead]
            description.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: description) else { return nil }
            self.queue = queue
            self.texture = texture
            renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
            renderer.layer = layer
            renderer.bounds = CGRect(x: 0, y: 0, width: CatRenderTests.side, height: CatRenderTests.side)
        }

        func render(atTime time: CFTimeInterval) -> [UInt8] {
            let side = CatRenderTests.side
            renderer.beginFrame(atTime: time, timeStamp: nil)
            renderer.addUpdate(renderer.updateBounds())
            renderer.render()
            renderer.endFrame()
            let fence = queue.makeCommandBuffer()
            fence?.commit()
            fence?.waitUntilCompleted()
            var bytes = [UInt8](repeating: 0, count: side * side * 4)
            texture.getBytes(&bytes, bytesPerRow: side * 4, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
            return bytes
        }
    }

    static let ground = CGColor(gray: 0.1, alpha: 1)

    /// How many bytes differ: a failure says that, not the two textures.
    func difference(_ first: [UInt8], _ second: [UInt8]) -> Int {
        first.count != second.count ? Int.max : zip(first, second).filter { $0 != $1 }.count
    }

    /// The real view, 64 by 64 at 1x, so that a sprite pixel is three texture pixels, with the cat sitting at (2, 2).
    func scene(pose: CatPose, facing: Facing) -> (CatSpriteView, Offscreen, CFTimeInterval)? {
        let stage = CatStage(scheduler: ManualSchedulerStub.make())
        let host = CatSpriteView(stage: stage, role: .trailing)
        host.backingScaleOverride = 1
        host.frame = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        host.layer?.backgroundColor = Self.ground
        let lane = WalkLane(minX: 2, maxX: 2, clipsToWings: true, restingX: 2)
        host.show(plan: CatPlan(pose: pose, facing: facing, from: 0, to: 0, began: 0, duration: 99), lane: lane, elapsed: 0)
        guard let layer = host.layer, let offscreen = Offscreen(layer: layer) else { return nil }
        // Pin the loop to the layer's own time, so that a frame rendered `seconds` later is `seconds` into the animation.
        let begin = host.sprite.convertTime(CACurrentMediaTime(), from: nil)
        guard let frames = host.sprite.animation(forKey: CatSpriteView.framesKey)?.copy() as? CAKeyframeAnimation else { return nil }
        frames.beginTime = begin
        host.sprite.add(frames, forKey: CatSpriteView.framesKey)
        CATransaction.flush()
        return (host, offscreen, begin)
    }

    /// A plain layer with `frame` of the pose's strip as its contents: what showing the right picture looks like.
    func reference(pose: CatPose, facing: Facing, frame: Int) -> Offscreen? {
        let strip = CatSheets.shared.strip(for: pose, facing: facing)
        let cell = strip.frameWidth + 2 * PixelStrip.margin
        let crop = CGRect(x: frame * cell + PixelStrip.margin, y: PixelStrip.margin, width: strip.frameWidth, height: strip.frameHeight)
        guard let picture = strip.image.cropping(to: crop) else { return nil }
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        root.anchorPoint = .zero
        root.position = .zero
        root.backgroundColor = Self.ground
        let sprite = CALayer()
        sprite.anchorPoint = .zero
        sprite.bounds = CGRect(x: 0, y: 0, width: CGFloat(CatArt.width * 3), height: CGFloat(CatArt.height * 3))
        sprite.position = CGPoint(x: 2, y: SpriteMetrics.floor)
        sprite.contents = picture
        sprite.contentsGravity = .resize
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        root.addSublayer(sprite)
        // Handed to a renderer first and committed after, as a layer is that the renderer is to draw.
        let offscreen = Offscreen(layer: root)
        CATransaction.flush()
        return offscreen
    }

    @Test func eachMomentOfEachAnimationShowsTheFrameThatShouldBeThereAndTheSameAsAPlainLayerShowingIt() throws {
        var compared = 0
        for (pose, facing) in [(CatPose.walk, Facing.right), (.walk, .left), (.run, .right), (.sit, .right), (.sleep, .right), (.purr, .left)] {
            let (_, offscreen, begin) = try #require(scene(pose: pose, facing: facing))
            let animation = CatArt.animation(for: pose)
            let slot = animation.duration / Double(animation.frames.count)
            var previous: [UInt8] = []
            var distinct = 0
            // Two loops, in the middle of every frame's turn.
            for index in 0..<(2 * animation.frames.count) {
                let rendered = offscreen.render(atTime: begin + (Double(index) + 0.5) * slot)
                let expected = try #require(reference(pose: pose, facing: facing, frame: index % animation.frames.count))
                    .render(atTime: CACurrentMediaTime())
                let differing = difference(rendered, expected)
                #expect(differing == 0, "\(pose) \(facing) at frame \(index % animation.frames.count) of turn \(index): \(differing) bytes differ")
                if rendered != previous { distinct += 1 }
                previous = rendered
                compared += 1
            }
            #expect(distinct > 1, "\(pose) \(facing) moves")
        }
        #expect(compared == 2 * (4 + 4 + 4 + 6 + 4 + 4))
    }

    @Test func theFramesAreHeldForTheirWholeSlotAndStepAtItsEdge() throws {
        let (_, offscreen, begin) = try #require(scene(pose: .walk, facing: .right))
        let slot = CatArt.walk.duration / 4
        let early = offscreen.render(atTime: begin + 0.1 * slot)
        let late = offscreen.render(atTime: begin + 0.9 * slot)
        let next = offscreen.render(atTime: begin + 1.1 * slot)
        #expect(difference(early, late) == 0, "held, not blended")
        #expect(difference(early, next) > 100, "and a new picture in the next slot")
    }

    @Test func everyPixelOfTheSpriteIsAWholeBlockOfThreeByThreeTexturePixelsOfOneColour() throws {
        let (_, offscreen, begin) = try #require(scene(pose: .sit, facing: .right))
        let bytes = offscreen.render(atTime: begin + 0.01)
        let side = Self.side
        func colour(_ x: Int, _ y: Int) -> [UInt8] { Array(bytes[(y * side + x) * 4..<(y * side + x) * 4 + 4]) }
        // The sprite is 60 by 48 texture pixels at x from 2; which rows depends on the way the renderer lays the texture out, so both
        // are tried, and one of them has to be crisp throughout.
        var crisp = [true, true]
        for (index, top) in [side - 2 - 48, 2].enumerated() {
            for row in 0..<CatArt.height {
                for column in 0..<CatArt.width {
                    let block = (0..<3).flatMap { dy in (0..<3).map { dx in colour(2 + column * 3 + dx, top + row * 3 + dy) } }
                    if Set(block).count != 1 { crisp[index] = false }
                }
            }
        }
        #expect(crisp.contains(true), "no sprite pixel is smeared across its neighbours")
    }

    @Test func theSpritesPixelsAreTheFramesPixelsInThePalettesColours() throws {
        let (_, offscreen, begin) = try #require(scene(pose: .sit, facing: .right))
        let bytes = offscreen.render(atTime: begin + 0.01)
        let side = Self.side
        let frame = CatArt.sit.frames[0]
        // The ground, as the texture has it: the corner is outside the cat.
        let ground = Array(bytes[0..<3])
        func matches(top: Int, flipped: Bool) -> Int {
            var count = 0
            for row in 0..<frame.height {
                for column in 0..<frame.width {
                    let shown = flipped ? frame.height - 1 - row : row
                    let offset = ((top + shown * 3 + 1) * side + 2 + column * 3 + 1) * 4
                    let pixel = Array(bytes[offset..<offset + 4])
                    if let rgb = CatArt.palette.colors[frame[column, row]] {
                        let expected: [UInt8] = [UInt8(rgb & 0xFF), UInt8((rgb >> 8) & 0xFF), UInt8((rgb >> 16) & 0xFF)]
                        // Blue, green, red: within a step or two of the palette's own, since the layer may be colour-managed.
                        if zip(pixel.prefix(3), expected).allSatisfy({ abs(Int($0) - Int($1)) <= 6 }) { count += 1 }
                    } else if Array(pixel.prefix(3)) == ground {
                        count += 1
                    }
                }
            }
            return count
        }
        // The renderer may lay its texture out with the layer's bottom at either end; the picture is the right way up in both.
        let best = max(matches(top: side - 2 - 48, flipped: false), matches(top: 2, flipped: true))
        #expect(best == CatArt.width * CatArt.height, "\(best) of \(CatArt.width * CatArt.height) pixels are the sprite's")
    }

    @Test func aCatThatIsClippedToItsWingIsNotDrawnOutsideIt() throws {
        let stage = CatStage(scheduler: ManualSchedulerStub.make())
        let host = CatSpriteView(stage: stage, role: .trailing)
        host.backingScaleOverride = 1
        // A wing narrower than the cat: 20 points of a cat that is 60 wide.
        host.frame = CGRect(x: 0, y: 0, width: 20, height: Self.side)
        host.layer?.backgroundColor = Self.ground
        let lane = WalkLane(minX: 2, maxX: 2, clipsToWings: true, restingX: 2)
        host.show(plan: CatPlan(pose: .sit, facing: .right, from: 0, to: 0, began: 0, duration: 9), lane: lane, elapsed: 0)
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        root.anchorPoint = .zero
        root.position = .zero
        root.addSublayer(try #require(host.layer))
        let offscreen = try #require(Offscreen(layer: root))
        CATransaction.flush()
        let bytes = offscreen.render(atTime: CACurrentMediaTime())
        let side = Self.side
        // Nothing but the ground past the wing's right edge, at column 20.
        var drawnOutside = 0
        for y in 0..<side {
            for x in 21..<side where bytes[(y * side + x) * 4 + 3] != 0 { drawnOutside += 1 }
        }
        #expect(drawnOutside == 0)
        // And the view's own part does have cat in it.
        var drawnInside = 0
        for y in 0..<side {
            for x in 0..<20 where bytes[(y * side + x) * 4 + 3] != 0 { drawnInside += 1 }
        }
        #expect(drawnInside > 100)
    }
}
