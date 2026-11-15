import AppKit
import Metal
import QuartzCore
import SwiftUI
import Testing
@testable import BatteryModule

/// The sweep as the render server plays it, rendered offscreen by a `CARenderer` into a texture of its own (nothing on the screen, no
/// window), against the band as SwiftUI drew it each frame before: the same fill under it, at moments across a whole sweep.
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil)) struct ChargingSweepRenderTests {
    static let width = 160
    static let height = 36
    static let green = Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
    static let greenLayerColor = CGColor(srgbRed: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1)

    /// The sweep as it was, kept here to show that it looks the same: a gradient of `clear` through a quarter of white to `clear`,
    /// 70 pt wide, offset by the phase of the sweep, over the fill, clipped to the fill's shape.
    struct ReferenceSweep: View {
        let phase: Double
        let ends: Color

        var body: some View {
            let fillWidth = CGFloat(ChargingSweepRenderTests.width)
            RoundedRectangle(cornerRadius: BatteryGaugeLayout.fillRadius)
                .fill(ChargingSweepRenderTests.green)
                .frame(width: fillWidth, height: CGFloat(ChargingSweepRenderTests.height))
                .overlay(alignment: .leading) {
                    LinearGradient(colors: [ends, .white.opacity(0.25), ends], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 70)
                        .offset(x: -70 + phase * (fillWidth + 70))
                }
                .clipShape(RoundedRectangle(cornerRadius: BatteryGaugeLayout.fillRadius))
        }
    }

    /// The pixels of what SwiftUI draws, as 8-bit sRGB, premultiplied, rows from the top.
    static func reference(phase: Double, ends: Color = .clear) -> [UInt8] {
        let renderer = ImageRenderer(content: ReferenceSweep(phase: phase, ends: ends))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return [] }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    /// Renders `layer` at media times and hands back BGRA bytes, rows from the top.
    final class Offscreen {
        let queue: MTLCommandQueue
        let texture: MTLTexture
        let renderer: CARenderer

        init?(layer: CALayer) {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            let description = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: ChargingSweepRenderTests.width, height: ChargingSweepRenderTests.height, mipmapped: false
            )
            description.usage = [.renderTarget, .shaderRead]
            description.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: description) else { return nil }
            self.queue = queue
            self.texture = texture
            renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
            renderer.layer = layer
            renderer.bounds = CGRect(x: 0, y: 0, width: ChargingSweepRenderTests.width, height: ChargingSweepRenderTests.height)
        }

        func render(atTime time: CFTimeInterval) -> [UInt8] {
            let width = ChargingSweepRenderTests.width, height = ChargingSweepRenderTests.height
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

    /// The real view, laid out at the fill's size over a rounded green fill, its sweep begun at `startPhase` of the way through and
    /// pinned to the layer's time, so that a frame rendered `seconds` later is `seconds` into the animation to the microsecond.
    struct Scene {
        let view: ChargingSweepView
        let offscreen: Offscreen
        let begin: CFTimeInterval
        let startPhase: Double

        @MainActor init?(startPhase: Double) {
            let size = CGSize(width: ChargingSweepRenderTests.width, height: ChargingSweepRenderTests.height)
            let date = Date(timeIntervalSinceReferenceDate: 2.6 * 1000 + startPhase * 2.6)
            let view = ChargingSweepView(fillWidth: size.width, now: { date })
            view.frame = CGRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            // What the fill behind the view is, in layers: a rounded rectangle of its own colour.
            view.layer?.backgroundColor = ChargingSweepRenderTests.greenLayerColor
            view.layer?.cornerRadius = BatteryGaugeLayout.fillRadius
            view.layer?.cornerCurve = .continuous
            // AppKit's own layer of a view clips to its bounds; here only the background takes the corners, so that whatever else clips
            // the band is the view's own doing.
            view.layer?.masksToBounds = false
            view.startSweep()
            guard let layer = view.layer, let offscreen = Offscreen(layer: layer) else { return nil }
            let begin = view.band.convertTime(CACurrentMediaTime(), from: nil)
            // The animation as the view added it, begun at a time of the test's choosing.
            guard let added = view.band.animation(forKey: ChargingSweepView.animationKey)?.copy() as? CABasicAnimation else { return nil }
            added.beginTime = begin
            view.band.add(added, forKey: ChargingSweepView.animationKey)
            CATransaction.flush()
            self.view = view
            self.offscreen = offscreen
            self.begin = begin
            self.startPhase = startPhase
        }

        /// The sweep's phase `seconds` after it began, in a whole sweep.
        func phase(after seconds: TimeInterval) -> Double {
            (startPhase + seconds / BatteryGaugeMotion.sweepPeriod).truncatingRemainder(dividingBy: 1)
        }

        func render(after seconds: TimeInterval) -> [UInt8] { offscreen.render(atTime: begin + seconds) }
    }

    struct Difference {
        var colour = 0
        var alpha = 0
    }

    /// Core Animation and SwiftUI antialias a rounded corner a little differently, to the tune of a fifth of a pixel at a radius of 7:
    /// the corner squares (a continuous corner reaches half as far again along the edge as its radius) are left out of the comparison and have a check of their own.
    static let corner = 12

    static func isInACorner(x: Int, y: Int) -> Bool {
        (x < corner || x >= width - corner) && (y < corner || y >= height - corner)
    }

    /// The biggest gap, outside the corners, between the layer's BGRA and the reference's RGBA, in 8-bit steps.
    static func difference(layers: [UInt8], reference: [UInt8]) -> Difference {
        var result = Difference()
        for y in 0..<height {
            for x in 0..<width where !isInACorner(x: x, y: y) {
                let at = (y * width + x) * 4
                let (b, g, r, a) = (Int(layers[at]), Int(layers[at + 1]), Int(layers[at + 2]), Int(layers[at + 3]))
                let (rr, rg, rb, ra) = (Int(reference[at]), Int(reference[at + 1]), Int(reference[at + 2]), Int(reference[at + 3]))
                result.alpha = max(result.alpha, abs(a - ra))
                // The colour only where both are opaque enough for it to be meaningful.
                if a > 250, ra > 250 {
                    result.colour = max(result.colour, abs(r - rr), abs(g - rg), abs(b - rb))
                }
            }
        }
        return result
    }

    @Test func theLayersLookLikeTheSwiftUIBandAtMomentsAcrossWholeSweepsFromAnyStart() throws {
        var worst = Difference()
        var worstMoment = ""
        var moments = 0
        for startPhase in [0.0, 0.4] {
            let scene = try #require(Scene(startPhase: startPhase))
            // A whole sweep and a bit more, so the wrap is in it.
            for step in 0..<56 {
                let seconds = Double(step) * 0.05
                let phase = scene.phase(after: seconds)
                let gap = Self.difference(layers: scene.render(after: seconds), reference: Self.reference(phase: phase))
                if max(gap.colour, gap.alpha) > max(worst.colour, worst.alpha) { worstMoment = "start \(startPhase), \(seconds) s (phase \(phase))" }
                worst.colour = max(worst.colour, gap.colour)
                worst.alpha = max(worst.alpha, gap.alpha)
                moments += 1
            }
        }
        #expect(moments > 100)
        #expect(worst.colour <= 3 && worst.alpha <= 3, "worst at \(worstMoment): colour \(worst.colour), alpha \(worst.alpha)")
    }

    /// Where the band is over a corner of the fill, nothing of it may show outside the rounded shape.
    @Test func theBandIsClippedToTheRoundedCornersOfTheFill() throws {
        // A tenth of the way: the band, from about 47 pt left of the fill to 23 pt into it, is over both left corners.
        let scene = try #require(Scene(startPhase: 0.1))
        let bytes = scene.render(after: 0)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * Self.width + x) * 4 + 3] }
        #expect(alpha(0, 0) == 0)
        #expect(alpha(0, Self.height - 1) == 0)
        #expect(alpha(1, 1) < 8)
        #expect(alpha(1, Self.height - 2) < 8)
        // And the band is there: the fill beside the corner is brighter than the fill alone.
        let lit = Int(bytes[(Self.height / 2 * Self.width + 2) * 4 + 2])
        #expect(lit > 0x34 + 4, "the band lightens the red of the fill by \(lit - 0x34)")
    }
}
