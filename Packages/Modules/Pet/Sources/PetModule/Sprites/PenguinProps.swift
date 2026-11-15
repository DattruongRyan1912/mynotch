import Foundation

/// What the penguin fishes in: a hole in the ice, flat on the floor in front of it. It is a whole picture of 32 by 24 like the penguin's, drawn
/// over the penguin (the prop layer is over the sprite layer), and the penguin's fishing line, which comes down in the middle of it, goes
/// into it: the line is lost behind the far lip of it.
///
/// It cracks open, with chips of ice flying, and is there; its water ripples round the line while the penguin waits, is stirred up when a fish
/// bites, and splashes when it is pulled out; and it closes the way it opened, and then there is nothing.
enum PenguinProps {
    /// The middle of the hole on the board: its column is the middle of the picture, which is where the penguin's line comes down on the
    /// picture of the penguin `PenguinMove.holeReach` pixels along.
    static let centre = (x: 15.5, y: 18.9)

    /// The hole at `scale` of its size, with a line round it; nothing for none. `dots` are drops of water over it.
    private static func canvas(scale: Double, ripples: [(Int, Int)] = [], dots: [(Int, Int)] = []) -> CatCanvas {
        var c = CatCanvas()
        let ice = PenguinArt.Blob(centre.x, centre.y, 6.6 * scale, 2.0 * scale)
        let water = PenguinArt.Blob(centre.x, centre.y + 0.1, 4.6 * scale, 1.2 * scale)
        for y in 0..<CatCanvas.height {
            for x in 0..<CatCanvas.width {
                if water.contains(x, y) {
                    c[x, y] = "A"
                } else if ice.contains(x, y) {
                    c[x, y] = !ice.contains(x, y + 1) ? "i" : "I"
                } else if scale > 0.3, ice.contains(x, y, grown: 1) {
                    c[x, y] = "K"
                }
            }
        }
        for (x, y) in ripples where c[x, y] == "A" { c[x, y] = "a" }
        for (x, y) in dots { c[x, y] = "A" }
        return c
    }

    private static func frame(_ canvas: CatCanvas) -> PixelFrame { canvas.frame.rimmed(with: "R") }

    // MARK: Opening and closing

    /// The ice cracks along a line, a hole opens in it with chips flying, and then it is open.
    private static func crack(_ chips: [(Int, Int)]) -> CatCanvas {
        var c = CatCanvas()
        for (x, y) in [(9, 20), (10, 19), (11, 19), (12, 20), (13, 19), (14, 19), (15, 20), (16, 19), (17, 19), (18, 20), (19, 19), (20, 20), (21, 20)] { c[x, y] = "K" }
        for (x, y) in chips { c[x, y] = "A" }
        return c
    }

    static let opening = PixelAnimation(
        frames: [
            frame(crack([(12, 18), (17, 18)])),
            frame(withChips(canvas(scale: 0.5), [(8, 16), (22, 16), (12, 15)])),
            frame(withChips(canvas(scale: 0.8), [(7, 15), (23, 14)])),
            frame(canvas(scale: 1)),
        ],
        fps: 6, loops: false
    )

    private static func withChips(_ canvas: CatCanvas, _ chips: [(Int, Int)]) -> CatCanvas {
        var c = canvas
        for (x, y) in chips { c[x, y] = "A" }
        return c
    }

    /// The hole standing, which is how it is the moment it has opened.
    static let still = PixelAnimation(frames: [frame(canvas(scale: 1))], fps: 1)

    /// Rings going out from where the line is: three pictures that go round.
    static let rippling = PixelAnimation(
        frames: [
            frame(canvas(scale: 1, ripples: [(14, 19), (16, 19), (11, 18), (19, 19)])),
            frame(canvas(scale: 1, ripples: [(13, 19), (17, 19), (14, 18), (16, 18), (18, 18)])),
            frame(canvas(scale: 1, ripples: [(12, 19), (18, 19), (13, 18), (17, 18), (11, 19)])),
        ],
        fps: 2.5
    )

    /// Stirred up, with drops jumping: two pictures, quick.
    static let churning = PixelAnimation(
        frames: [
            frame(canvas(scale: 1, ripples: [(12, 18), (14, 19), (16, 18), (18, 19), (13, 19), (17, 19)], dots: [(13, 16), (18, 15)])),
            frame(canvas(scale: 1, ripples: [(13, 18), (15, 19), (17, 18), (11, 19), (19, 19), (14, 19)], dots: [(12, 15), (15, 14), (17, 16)])),
        ],
        fps: 8
    )

    /// The fish comes out: a fountain of drops, going up and coming down.
    static let splashing = PixelAnimation(
        frames: [
            frame(canvas(scale: 1, ripples: [(14, 18), (16, 18), (12, 19), (18, 19)], dots: [(14, 15), (17, 14), (15, 13)])),
            frame(canvas(scale: 1, ripples: [(13, 18), (17, 18), (15, 19)], dots: [(12, 13), (15, 11), (18, 12), (14, 15), (17, 15)])),
            frame(canvas(scale: 1, ripples: [(12, 18), (18, 18), (14, 19), (16, 19)], dots: [(11, 14), (19, 13), (14, 12), (16, 12)])),
            frame(canvas(scale: 1, ripples: [(11, 18), (19, 18), (13, 19), (17, 19)], dots: [(10, 16), (20, 15)])),
        ],
        fps: 8, loops: false
    )

    /// The hole closing: the same pictures backwards, and then nothing.
    static let closing = PixelAnimation(frames: Array(opening.frames.reversed()) + [PixelFrame(width: 32, height: 24)], fps: 6, loops: false)
}

extension PenguinProps {
    /// What the penguin has out, as pictures.
    static func animation(for prop: PenguinProp) -> PixelAnimation {
        switch prop {
        case .holeOpening: opening
        case .holeStill: still
        case .holeRippling: rippling
        case .holeChurning: churning
        case .holeSplashing: splashing
        case .holeClosing: closing
        }
    }
}
