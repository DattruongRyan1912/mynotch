import Foundation

/// The frog, as pictures: on the same board as the cat (30 by 22 pixels, a light rim all round, frames of 32 by 24) so that a lane takes any
/// mix of them, and in the same way: a line of dark round it inside a light rim, which is what makes it read on glass of any colour.
///
/// It is green with a pale belly and throat, wide and low, with a big eye standing up on the top of its head, a long mouth, a hind leg folded
/// up under it and a throat that puffs out; and it is drawn from a few ovals put one over another (`Blob`): the body, the head, the eye, the
/// thigh, the belly, the throat. The ovals are one shape with one line round them, so a head is not cut off from a body by a line across;
/// the legs and the tongue are strokes. Every picture is a handful of numbers (`Form`). It is side on facing right (the mirror image is made
/// for left) and stands a little left of the middle of its frame, so that its tongue has room on the right of it, and so that what a hop
/// does to the way it sits in its frame (see `FrogArtMoves`) is what makes it stand still on the ground while the layer moves under it.
///
/// What is a pixel wide (the tongue) has a rim of its own like everything else: a tongue in a colour dark enough to read on glass of any
/// colour, between its two rims.
enum FrogArt {
    static let width = CatArt.width
    static let height = CatArt.height

    /// How far to the right of where the forms put it the frog is drawn: the forms are made for a frog that begins at the left of the board,
    /// and it sits a little in from there, for its legs to trail behind it in a hop.
    static let originShift = 2.0

    /// The ground it sits on, as a row of the board: its feet are on this row and the line under them is the next.
    static let ground = 20.0
    /// How many rows higher it sits on the lily pad: the pad is the three rows under it.
    static let padRise = 3

    typealias Point = (x: Double, y: Double)

    // MARK: Shapes

    /// An oval, in the board's own coordinates, turned by `angle` (radians, clockwise), that is part of the frog.
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
            let moved = FrogArt.turn((cx, cy), radians, about: point)
            return Blob(moved.x, moved.y, rx, ry, angle: angle + radians)
        }

        /// The same moved by (`dx`, `dy`).
        func moved(_ dx: Double, _ dy: Double) -> Blob { Blob(cx + dx, cy + dy, rx, ry, angle: angle) }

        /// The same with its two radii scaled.
        func scaled(_ x: Double, _ y: Double) -> Blob { Blob(cx, cy, rx * x, ry * y, angle: angle) }
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

    /// A leg: from where it comes out of the body to its foot, a stroke two pixels wide (the toes are the last pixels of it).
    struct Leg {
        var points: [Point]
        /// On the far side of the body: a shade darker, drawn first.
        var far = false
    }

    /// Everything a picture of the frog is made of.
    struct Rig {
        /// What is green: the whole shape, with one line round it.
        var body: [Blob]
        /// What is pale: the belly, the chin, the throat when it is puffed.
        var pale: [Blob] = []
        /// The thigh, whose edge is drawn in a darker green against the body, which is what makes it a folded leg.
        var thigh: Blob?
        var legs: [Leg] = []
        /// The tongue, from the mouth to its tip: a line with a sticky end.
        var tongue: [Point] = []
        /// The eye, the nostril, the line of the mouth: over everything the frog is made of.
        var marks: [Pixel] = []
        /// Over the shape, before the rim, at the place on the picture that it says (not lifted with the frog): what is drawn with the frog and is
        /// rimmed with it (hearts, z's).
        var extras: (inout CatCanvas) -> Void = { _ in }
        /// How many rows higher the whole of it is drawn (a hop); what goes off the top is cut off.
        var lift = 0
    }

    // MARK: Drawing

    /// The frog, put together: the shape of it with one line round it, shaded (green, a darker back, a pale belly and throat), its legs, its
    /// tongue and its face.
    static func draw(_ rig: Rig) -> PixelFrame {
        var canvas = CatCanvas()
        func inside(_ x: Int, _ y: Int) -> Bool { rig.body.contains { $0.contains(x, y) } }
        for y in 0..<CatCanvas.height {
            for x in 0..<CatCanvas.width {
                if inside(x, y) {
                    canvas[x, y] = colour(x, y, rig: rig, inside: inside)
                } else if rig.body.contains(where: { $0.contains(x, y, grown: 1) }) {
                    canvas[x, y] = "K"
                }
            }
        }
        // A leg has a line round it where it is against the air or another leg, and none where it is over the body.
        let bodyOnly = canvas
        for far in [true, false] {
            for leg in rig.legs where leg.far == far {
                var stroke = CatCanvas()
                stroke.stroke(leg.points, width: 2, fill: far ? "g" : "G", outline: "K", paw: "L", pawLength: 1)
                for y in 0..<CatCanvas.height {
                    for x in 0..<CatCanvas.width where stroke[x, y] != PixelPalette.clear {
                        // Over the body its line is a darker green, which is what makes it a leg and not a patch of the same colour.
                        if stroke[x, y] == "K", "GgWwL".contains(bodyOnly[x, y]) {
                            if bodyOnly[x, y] != "g" { canvas[x, y] = "g" }
                            continue
                        }
                        canvas[x, y] = stroke[x, y]
                    }
                }
            }
        }
        drawTongue(rig.tongue, on: &canvas)
        for mark in rig.marks { canvas[mark.x, mark.y] = mark.letter }
        var lifted = rig.lift == 0 ? canvas : canvas.shifted(dy: -rig.lift)
        // What is drawn with the frog is where the picture says, whatever height the frog is at.
        rig.extras(&lifted)
        return lifted.frame.rimmed(with: "R")
    }

    private static func colour(_ x: Int, _ y: Int, rig: Rig, inside: (Int, Int) -> Bool) -> Character {
        if rig.pale.contains(where: { $0.contains(x, y) }) { return !inside(x, y + 1) || !inside(x + 1, y) ? "w" : "W" }
        // The edge of the thigh against the rest of the body.
        if let thigh = rig.thigh, thigh.contains(x, y), !thigh.contains(x, y, grown: -1.1), y < Int(thigh.cy + 1) { return "g" }
        if !inside(x, y - 1) { return "g" }
        return "G"
    }

    /// The tongue: a line one pixel wide from the mouth to the tip, which is a sticky knob of two.
    private static func drawTongue(_ points: [Point], on canvas: inout CatCanvas) {
        guard let first = points.first, let last = points.last, points.count > 1 else { return }
        for (from, to) in zip(points, points.dropFirst()) {
            let steps = max(Int((max(abs(to.x - from.x), abs(to.y - from.y)) * 2).rounded(.up)), 1)
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                canvas[Int((from.x + (to.x - from.x) * t).rounded(.down)), Int((from.y + (to.y - from.y) * t).rounded(.down))] = "T"
            }
        }
        _ = first
        let (tx, ty) = (Int(last.x.rounded(.down)), Int(last.y.rounded(.down)))
        for (dx, dy) in [(0, 0), (-1, 0), (0, 1), (-1, 1)] where canvas[tx + dx, ty + dy] != "K" || dx == 0 && dy == 0 { canvas[tx + dx, ty + dy] = "t" }
    }
}

extension FrogArt {
    /// Every colour the frog, its lily pad and what it says with are drawn with. The rim and the line inside it are what make it read on
    /// glass of any colour, as the cat's do. The tongue has no line of its own, so it is a colour that reads on dark and on light glass.
    static let palette = PixelPalette(colors: [
        "R": 0xEAF6E2,  // the light rim all round it
        "K": 0x0C2214,  // the dark line inside the rim
        "G": 0x55BE4A,  // green skin
        "g": 0x2E8B3C,  // its shade: the back, the edge of the thigh, the far leg
        "L": 0xB6E36B,  // the webbing of the toes
        "W": 0xFBF3C9,  // belly, chin, throat
        "w": 0xD2C98F,  // the edge of it, in the shade
        "Y": 0xF5C518,  // the eye
        "E": 0x101010,  // the pupil
        "T": 0xB81E52,  // tongue
        "t": 0xD93A72,  // and the sticky end of it
        "H": 0xE11D48,  // a heart
        "Z": 0x2563EB,  // sleep
        "V": 0x1F7A5C,  // the lily pad
        "v": 0x4FB583,  // the light on it
        "A": 0x173F6B,  // the water
        "a": 0x3A7FC4,  // and the light on it
    ])
}
