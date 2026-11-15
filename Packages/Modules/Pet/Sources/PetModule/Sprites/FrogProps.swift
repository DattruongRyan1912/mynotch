import Foundation

/// What the frog sits on: a lily pad floating on a line of water, seen from the side, a flat green disc with a notch in it. It is a whole
/// picture of 32 by 24 like the frog's, drawn over the frog (the prop layer is over the sprite layer), and the frog on it is drawn
/// `FrogArt.padRise` rows higher, so that its feet are on the top of the pad and nothing of the pad lands on the frog. For the same reason the pad
/// has no rim over its top, where the frog sits: the rim of the picture is round the sides and underneath only.
///
/// It rises out of the water (a ripple, the water line, the pad unrolling), stands and ripples a little, dips as the frog lands on it and as
/// it leaves, and sinks again the way it came, and then there is nothing.
enum FrogProps {
    /// The board's rows: the top edge of the pad is `top`, the water is the two rows `top + 2` and `top + 3`.
    static let top = 18

    /// The pad and its water, `size` of its width (0 is only the water's first ripple), `dip` rows down (the frog's weight), and the light
    /// of the ripples: `rings` are how far from the middle, in pixels, a ring of ripple is on each side.
    private static func canvas(size: Double, dip: Int = 0, ripple: Int = 0, rings: [Int] = []) -> CatCanvas {
        var c = CatCanvas()
        let middle = 14.5
        // The water: two rows, wider than the pad, dark at its ends (so that it reads against the rim on light glass) and lit inside.
        let water = max(size, 0.25) * 14.8
        for x in 0..<CatCanvas.width where abs(Double(x) + 0.5 - middle) <= water {
            let edge = abs(Double(x) + 0.5 - middle) > water - 1.8
            c[x, top + 3] = "A"
            c[x, top + 2] = edge ? "A" : ((x + ripple) % 3 == 0 ? "A" : "a")
        }
        for ring in rings {
            for side in [-1.0, 1.0] {
                let x = Int((middle + side * Double(ring)).rounded(.down))
                if (0..<CatCanvas.width).contains(x), c[x, top + 2] != "." { c[x, top + 2] = "A" }
                if (0..<CatCanvas.width).contains(x), c[x, top + 1 + dip] == "." { c[x, top + 1 + dip] = "a" }
            }
        }
        guard size > 0.3 else {
            // The first ripple only: a few bubbles at the middle of the water.
            for x in [13, 15, 17] { c[x, top + 1] = "a" }
            return c
        }
        let half = 9.8 * size
        let (surface, body) = (top + 1 + dip, top + 2 + dip)
        for x in 0..<CatCanvas.width {
            let d = abs(Double(x) + 0.5 - middle)
            guard d <= half else { continue }
            let end = d > half - 1.2
            c[x, top + dip] = end ? "." : "K"
            c[x, surface] = end ? "K" : "v"
            // The notch, cut in the surface at one side.
            if size > 0.9, x == 20 || x == 21 { c[x, surface] = "K" }
            if dip == 0 || surface < top + 3 {
                if body < top + 3 { c[x, body] = end ? "K" : "V" }
            }
            c[x, top + 3] = "K"
        }
        // The ends of the pad are where its outline closes.
        for side in [-1.0, 1.0] {
            let x = Int((middle + side * (half + 0.5)).rounded(.down))
            if (0..<CatCanvas.width).contains(x) {
                c[x, surface] = "K"
                if body < top + 3 { c[x, body] = "K" }
            }
        }
        return c
    }

    /// The picture of it with its rim, round the sides and underneath only: the rim over the top of the pad would cover the frog's feet.
    private static func frame(_ canvas: CatCanvas) -> PixelFrame {
        var frame = canvas.frame.rimmed(with: "R")
        for y in 0..<frame.height where y <= top + 1 {
            for x in 0..<frame.width where frame[x, y] == "R" { frame = frame.setting(PixelPalette.clear, atX: x, y: y) }
        }
        return frame
    }

    private static let everything = PixelFrame(width: 32, height: 24)

    // MARK: Coming and going

    /// A ripple in the water, the water line spreading, the pad unrolling out of it, and the whole pad.
    static let appearing = PixelAnimation(
        frames: [canvas(size: 0.2), canvas(size: 0.45), canvas(size: 0.75), canvas(size: 1)].map { frame($0) }, fps: 6, loops: false
    )

    /// The pad as it lies.
    static let still = PixelAnimation(frames: [frame(canvas(size: 1))], fps: 1)

    /// The pad lying on the water, which moves a little: three pictures that go round.
    static let rippling = PixelAnimation(frames: (0..<3).map { frame(canvas(size: 1, ripple: $0)) }, fps: 2.5)

    /// The frog lands on it: it lies as it lies while the frog is in the air, and goes down under its weight as it lands, which is the last
    /// picture, as the last picture of the hop on is the landing.
    static let landing = PixelAnimation(
        frames: [canvas(size: 1), canvas(size: 1), canvas(size: 1), canvas(size: 1), canvas(size: 1), canvas(size: 1, dip: 1, rings: [12, 14])].map { frame($0) },
        fps: 8, loops: false
    )

    /// The frog leaves it: the pad goes down under the push, comes up, and the rings go out and fade.
    static let leaping = PixelAnimation(
        frames: [
            canvas(size: 1), canvas(size: 1, dip: 1), canvas(size: 1, rings: [11, 13]), canvas(size: 1, rings: [13, 15]),
            canvas(size: 1, rings: [14]), canvas(size: 1),
        ].map { frame($0) },
        fps: 8, loops: false
    )

    /// The pad sinking: the same pictures backwards, and then nothing.
    static let sinking = PixelAnimation(frames: Array(appearing.frames.reversed()) + [everything], fps: 6, loops: false)
}

extension FrogProps {
    /// What the frog has out, as pictures. The moth is the cat's (see `FrogSheets`).
    static func animation(for prop: FrogProp) -> PixelAnimation? {
        switch prop {
        case .padAppearing: appearing
        case .padStill: still
        case .padRippling: rippling
        case .padLanding: landing
        case .padLeaping: leaping
        case .padSinking: sinking
        case .moth, .mothHeld: nil
        }
    }
}
