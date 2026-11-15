import Foundation

/// What the hamster plays with: a wheel that pops up beside it in a puff of dust, stands, turns at four speeds with it in it, and goes again;
/// and a pile of sunflower seeds.
///
/// The wheel is a ring and nothing more, a whole picture of 32 by 24 like the hamster's, because it is drawn over the hamster: whatever
/// is inside the ring is seen through it, and the hamster, which stands one row higher in it (`HamsterArt.wheelRise`), is in the ring and
/// never covered. What says it is turning is the rungs going round the ring, a tenth of the way round to a picture.
enum HamsterProps {
    /// The ring on the board: its centre, and the radius of its outer line (a ring this big is the whole board's height).
    static let ringCentre = (x: 15.0, y: 11.0)
    static let ringRadius = 11.0

    // MARK: The wheel

    /// The ring with its rungs `turn` pictures of the way round: a line round it, a band inside the line, and in the band a dark rung (with
    /// a tick that points into the ring), a light one and the plain metal between. `radius` and `centre` are what the board holds of it:
    /// less of a ring while it comes up.
    private static func ringCanvas(turn: Int, radius: Double = ringRadius, centre: (x: Double, y: Double) = ringCentre) -> CatCanvas {
        var c = CatCanvas()
        for y in 0..<CatCanvas.height {
            for x in 0..<CatCanvas.width {
                let (dx, dy) = (Double(x) + 0.5 - centre.x, Double(y) + 0.5 - centre.y)
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance <= radius else { continue }
                // Degrees round the ring, 0 to 60: the rungs repeat six times round.
                var angle = atan2(dy, dx) * 180 / .pi + Double(turn) * 10
                angle = angle - (angle / 60).rounded(.down) * 60
                if distance > radius - 1 {
                    c[x, y] = "K"
                } else if distance > radius - 2 {
                    c[x, y] = angle < 20 ? "N" : (angle < 40 ? "B" : "M")
                } else if distance > radius - 3, radius > 6, angle >= 5, angle < 15 {
                    c[x, y] = "N"
                }
            }
        }
        return c
    }

    /// A picture of the ring, with a rim round the outside of it only: the inside is clear, for the hamster, and a rim there would cover it.
    private static func rimmed(_ canvas: CatCanvas, radius: Double?, centre: (x: Double, y: Double) = ringCentre) -> PixelFrame {
        var frame = canvas.frame.rimmed(with: "R")
        guard let radius else { return frame }
        // The rimmed frame is the board with a pixel more on each side.
        for y in 0..<frame.height {
            for x in 0..<frame.width where frame[x, y] == "R" {
                let (dx, dy) = (Double(x) - 0.5 - centre.x, Double(y) - 0.5 - centre.y)
                if (dx * dx + dy * dy).squareRoot() < radius - 0.5 { frame = frame.setting(PixelPalette.clear, atX: x, y: y) }
            }
        }
        return frame
    }

    /// The ring at full size, with the rungs `turn` pictures round, and a rim round it as the hamster has.
    static func wheel(turn: Int = 0) -> PixelFrame {
        rimmed(ringCanvas(turn: turn), radius: ringRadius)
    }

    /// The ring at `scale` of its size, standing on the floor, with a cloud of dust at its foot and sparks if it is whole.
    private static func coming(scale: Double, dust: [String]?, sparks: Bool = false) -> PixelFrame {
        let radius = ringRadius * scale
        var canvas = scale > 0 ? ringCanvas(turn: 0, radius: radius, centre: (ringCentre.x, 22 - radius)) : CatCanvas()
        if let dust { canvas.piece(dust, x: 15 - dust[0].count / 2, y: 22 - dust.count) }
        if sparks { for (x, y) in [(2, 3), (27, 3), (1, 9), (28, 9)] { canvas.piece(["N"], x: x, y: y) } }
        return rimmed(canvas, radius: scale > 0 ? radius : nil, centre: (ringCentre.x, 22 - radius))
    }

    /// The wheel comes up out of a puff of dust: the dust, a small ring in it, a bigger one, and the whole of it with sparks.
    static let appearing: PixelAnimation = PixelAnimation(
        frames: [
            coming(scale: 0, dust: ["..U.U.U..", ".UUUUUUU.", "UUUUUUUUU"]),
            coming(scale: 0.5, dust: [".U.....U.", "UUU...UUU"]),
            coming(scale: 0.8, dust: ["U.......U"]),
            coming(scale: 1, dust: nil, sparks: true),
        ],
        fps: 6, loops: false
    )

    /// The wheel standing, which is its first picture as it turns.
    static let still = PixelAnimation(frames: [wheel()], fps: 1)

    /// The wheel turning: six pictures of a tenth of a turn, which is a sixth of the way between one rung and the next one.
    static func turning(_ fps: Double) -> PixelAnimation { PixelAnimation(frames: (0..<6).map { wheel(turn: $0) }, fps: fps) }

    /// The wheel going again: the same pictures backwards, and then nothing.
    static let going = PixelAnimation(frames: Array(appearing.frames.reversed()) + [PixelFrame(width: 32, height: 24)], fps: 6, loops: false)

    // MARK: Seeds

    private static func small(_ rows: [String]) -> PixelFrame {
        do {
            return try PixelFrame(rows: rows, palette: HamsterArt.palette).rimmed(with: "K").rimmed(with: "R")
        } catch {
            fatalError("The hamster's props are malformed: \(error)")
        }
    }

    /// Three seeds in a pile, then two, then one: each is a pear with a stripe, as the one it picks up.
    static let seeds3 = PixelAnimation(frames: [small(["SVVS.SVVS.SVVS", ".SS...SS...SS."])], fps: 1)
    static let seeds2 = PixelAnimation(frames: [small(["SVVS.SVVS", ".SS...SS."])], fps: 1)
    static let seeds1 = PixelAnimation(frames: [small(HamsterArt.seed)], fps: 1)
}

extension HamsterProps {
    /// What the hamster has out, as pictures.
    static func animation(for prop: HamsterProp) -> PixelAnimation {
        switch prop {
        case .seeds3: seeds3
        case .seeds2: seeds2
        case .seeds1: seeds1
        case .wheelAppearing: appearing
        case .wheelStill: still
        case .wheelLazy: turning(prop.fps)
        case .wheelJog: turning(prop.fps)
        case .wheelRun: turning(prop.fps)
        case .wheelSprint: turning(prop.fps)
        case .wheelGoing: going
        }
    }
}
