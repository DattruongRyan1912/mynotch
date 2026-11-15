import AppKit
import Metal
import QuartzCore
import Testing
@testable import MediaModule

/// The made-up motion as the render server plays it, rendered offscreen by a `CARenderer` into a texture of its own (nothing on the
/// screen, no window): the animation the bars hand to Core Animation, on four layers laid out like the bars, at moments through a
/// whole loop and past its end, and the height each bar has there, counted in pixels of the texture.
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil)) struct SpectrumAnimationRenderTests {
    let width = 18
    let height = 14

    /// Brightness of one column of the texture, top to bottom, as the sum of the coverage of its pixels: the bar's height in points.
    func covered(_ bytes: [UInt8], column: Int) -> Double {
        (0..<height).reduce(0) { $0 + Double(bytes[($1 * width + column) * 4]) / 255 }
    }

    @Test func eachBarIsAsTallAsItsLevelWasAtTheStartOfItsThirtiethOfASecondThroughTheWholeLoopAndPastIt() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        description.usage = [.renderTarget, .shaderRead]
        description.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: description))
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])

        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        root.anchorPoint = .zero
        root.position = .zero
        root.backgroundColor = CGColor(gray: 0, alpha: 1)
        let bars = (0..<NowPlayingBars.barCount).map { index -> CALayer in
            let bar = CALayer()
            bar.backgroundColor = CGColor(gray: 1, alpha: 1)
            bar.bounds = CGRect(x: 0, y: 0, width: NowPlayingBars.barWidth, height: NowPlayingBars.minHeight)
            bar.position = CGPoint(x: CGFloat(index) * (NowPlayingBars.barWidth + NowPlayingBars.spacing) + NowPlayingBars.barWidth / 2, y: CGFloat(height) / 2)
            root.addSublayer(bar)
            return bar
        }
        renderer.layer = root
        renderer.bounds = root.bounds

        // The loop begins part-way in, as it does for a wall clock that is anywhere in it.
        let phase = 12.34
        let begin = bars[0].convertTime(CACurrentMediaTime(), from: nil)
        for (index, bar) in bars.enumerated() {
            let loop = SpectrumBarsView.madeUpAnimation(bar: index, phase: phase)
            loop.beginTime = begin
            bar.add(loop, forKey: SpectrumBarsView.madeUpKey)
        }
        CATransaction.flush()

        func render(after seconds: TimeInterval) -> [UInt8] {
            renderer.beginFrame(atTime: begin + seconds, timeStamp: nil)
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

        let step = NowPlayingBars.madeUpLoop / Double(NowPlayingBars.madeUpKeyframeCount)
        var checked = 0
        var changes = 0
        var last: [Double] = []
        // The middle of every thirty-sixth step across a loop and a bit more, so the wrap is in it.
        for index in stride(from: 0, to: NowPlayingBars.madeUpKeyframeCount + 80, by: 7) {
            let seconds = (Double(index) + 0.5) * step
            let bytes = render(after: seconds)
            let keyframe = Int(((phase + seconds).truncatingRemainder(dividingBy: NowPlayingBars.madeUpLoop)) / step) % NowPlayingBars.madeUpKeyframeCount
            var shown: [Double] = []
            for bar in 0..<NowPlayingBars.barCount {
                let expected = NowPlayingBars.madeUpHeights(bar: bar)[keyframe]
                let column = bar * 5 + 1
                let actual = covered(bytes, column: column)
                shown.append(actual)
                #expect(abs(actual - expected) < 0.35, "bar \(bar) at \(seconds) s (keyframe \(keyframe)): \(actual) pt, expected \(expected)")
                checked += 1
            }
            if shown != last { changes += 1 }
            last = shown
        }
        #expect(checked > 300)
        #expect(changes > checked / NowPlayingBars.barCount / 2, "the bars move")
    }
}
