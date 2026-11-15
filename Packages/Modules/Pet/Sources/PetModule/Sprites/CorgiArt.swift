import Foundation

/// The corgi, as pictures: on the same board as the cat (30 by 22 pixels, a light rim all round, frames of 32 by 24) so that a lane takes any
/// mix of them, and in the same way: a line of dark round it inside a light rim, which is what makes it read on glass of any colour.
///
/// It is orange and white, long and low, with short legs in white socks, big pointed ears and a fluffy rear, and it is drawn from a few
/// ovals put one over another (`Blob`): the rump, the body, the chest, the head, the muzzle, the ears and a stub of a tail. The ovals are
/// one shape with one line round them, so a head is not cut off from a body by a line across; the legs are strokes, one orange row and the
/// white of the socks. Every picture is a handful of numbers (`Rig`), which is what lets a move have as many different frames as it needs.
/// It is side on facing right (the mirror image is made for left) and, to look at the viewer or turn its back, facing it, and it stands
/// in the middle of its frame so the mirror image stands in the middle too.
///
/// What is a pixel wide (the dust it kicks up when it runs) is drawn over the rim: a rim round it would make it three.
enum CorgiArt {
    static let width = CatArt.width
    static let height = CatArt.height

    /// The ground it stands on, as a row of the board: its feet are on this row and the line under them is the next.
    static let ground = 20.0

    typealias Point = (x: Double, y: Double)

    // MARK: Shapes

    /// An oval, in the board's own coordinates, turned by `angle` (radians, clockwise), that is part of the corgi.
    struct Blob {
        var cx: Double
        var cy: Double
        var rx: Double
        var ry: Double
        var angle = 0.0

        init(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, angle: Double = 0) {
            (self.cx, self.cy, self.rx, self.ry, self.angle) = (cx, cy, rx, ry, angle)
        }

        func contains(_ x: Int, _ y: Int, grown: Double = 0) -> Bool {
            let (dx, dy) = (Double(x) + 0.5 - cx, Double(y) + 0.5 - cy)
            let (c, s) = (cos(angle), sin(angle))
            let (u, v) = ((dx * c + dy * s) / (rx + grown), (-dx * s + dy * c) / (ry + grown))
            return u * u + v * v <= 1
        }

        /// The same turned `radians` (clockwise) about `point`.
        func turned(_ radians: Double, about point: Point) -> Blob {
            guard radians != 0 else { return self }
            let moved = CorgiArt.turn((cx, cy), radians, about: point)
            return Blob(moved.x, moved.y, rx, ry, angle: angle + radians)
        }

        /// The same moved by (`dx`, `dy`).
        func moved(_ dx: Double, _ dy: Double) -> Blob { Blob(cx + dx, cy + dy, rx, ry, angle: angle) }
    }

    static func turn(_ point: Point, _ radians: Double, about centre: Point) -> Point {
        let (dx, dy) = (point.x - centre.x, point.y - centre.y)
        let (c, s) = (cos(radians), sin(radians))
        return (centre.x + dx * c - dy * s, centre.y + dx * s + dy * c)
    }

    struct Pixel {
        var x: Int
        var y: Int
        var letter: Character
    }

    /// A leg: from where it comes out of the body to its paw, a stroke two pixels wide with white socks at the end of it.
    struct Leg {
        var points: [Point]
        /// On the far side of the body: a shade darker, drawn first.
        var far = false
    }

    /// Everything a picture of the corgi is made of.
    struct Rig {
        /// What is orange (and, where it is on `white`, white): the whole shape, with one line round it.
        var body: [Blob]
        /// What is part of the shape and is behind it: the far ear, which is a shade darker where nothing of the near side is over it.
        var behind: [Blob] = []
        var white: [Blob] = []
        var legs: [Leg] = []
        /// The eye, the nose, the inside of an ear, the tongue: over everything the corgi is made of.
        var marks: [Pixel] = []
        /// Over the shape, before the rim: what is drawn with the corgi and is rimmed with it (hearts, z's, the ball it carries).
        var extras: (inout CatCanvas) -> Void = { _ in }
        /// Over the rim, which it has none of: dust.
        var after: (inout PixelFrame) -> Void = { _ in }
        /// How many rows higher the whole of it is drawn (a hop); what goes off the top is cut off.
        var lift = 0
    }

    // MARK: Drawing

    /// The corgi, put together: the shape of it with one line round it, shaded (orange, white chest, muzzle and belly), its legs and what it
    /// is doing with its face and with a ball.
    static func draw(_ rig: Rig) -> PixelFrame {
        var canvas = CatCanvas()
        let shape = rig.body + rig.behind
        func inside(_ x: Int, _ y: Int) -> Bool { shape.contains { $0.contains(x, y) } }
        for y in 0..<CatCanvas.height {
            for x in 0..<CatCanvas.width {
                if inside(x, y) {
                    if rig.white.contains(where: { $0.contains(x, y) }) && rig.body.contains(where: { $0.contains(x, y) }) {
                        canvas[x, y] = !inside(x, y + 1) ? "w" : "W"
                    } else {
                        canvas[x, y] = rig.body.contains(where: { $0.contains(x, y) }) ? "C" : "c"
                    }
                } else if shape.contains(where: { $0.contains(x, y, grown: 1) }) {
                    canvas[x, y] = "K"
                }
            }
        }
        // A leg has a line round it where it is against the air or another leg, and none where it is over the body, which is what makes a
        // paw laid on the chest a paw and not a dark scar.
        let bodyOnly = canvas
        for far in [true, false] {
            for leg in rig.legs where leg.far == far {
                var stroke = CatCanvas()
                stroke.stroke(leg.points, width: 2, fill: far ? "c" : "C", outline: "K", paw: far ? "w" : "W", pawLength: 1)
                for y in 0..<CatCanvas.height {
                    for x in 0..<CatCanvas.width where stroke[x, y] != PixelPalette.clear {
                        if stroke[x, y] == "K", "CcWw".contains(bodyOnly[x, y]) { continue }
                        canvas[x, y] = stroke[x, y]
                    }
                }
            }
        }
        for mark in rig.marks { canvas[mark.x, mark.y] = mark.letter }
        rig.extras(&canvas)
        var frame = (rig.lift == 0 ? canvas : canvas.shifted(dy: -rig.lift)).frame.rimmed(with: "R")
        rig.after(&frame)
        return frame
    }
}

extension CorgiArt {
    /// Every colour the corgi, its ball and what it says with are drawn with. The rim and the line inside it are what make it read on glass
    /// of any colour, as the cat's do.
    static let palette = PixelPalette(colors: [
        "R": 0xEAF2FB,  // the light rim all round it
        "K": 0x0B1020,  // the dark line inside the rim
        "C": 0xE98A2E,  // orange fur
        "c": 0xB9631C,  // its shade: the top of the back, the far legs
        "W": 0xFFF8EC,  // white: chest, muzzle, belly, socks
        "w": 0xD9CDB9,  // the edge of it, in the shade
        "P": 0xF2A5A0,  // inside an ear
        "e": 0x1C1C26,  // eye
        "N": 0x23232E,  // nose
        "T": 0xFF6B8B,  // tongue
        "H": 0xE11D48,  // a heart
        "Z": 0x2563EB,  // sleep
        "B": 0xC8DD3D,  // the ball
        "b": 0xF6FAD2,  // and the seam on it
        "D": 0x857A6B,  // the dust it kicks up
        "Y": 0xFFD23F,  // a sparkle
    ])
}
