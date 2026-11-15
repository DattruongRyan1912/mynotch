import Foundation

/// The penguin, as pictures: on the same board as the cat (30 by 22 pixels, a light rim all round, frames of 32 by 24) so that a lane takes
/// any mix of them, and in the same way: a line of dark round it inside a light rim, which is what makes it read on glass of any colour.
///
/// It is a tall bird, black and white with an orange beak and orange feet, and it is drawn from a few ovals put one over another (`Blob`,
/// which may be turned): the body, the head, the white belly and throat, the tail, two feet; a flipper is a stroke. The ovals are one shape
/// with one line round them, so a head is not cut off from a body by a line across, and every pose is a handful of numbers. It is side on
/// facing right (the mirror image is made for left) or, to look at the viewer, facing it, and it stands in the middle of its frame so
/// the mirror image stands in the middle too.
///
/// What it fishes with, a rod and its line, is drawn over the rim, one pixel wide (a rim round it would make it three), and so is the
/// snow it kicks up when it glides.
enum PenguinArt {
    static let width = CatArt.width
    static let height = CatArt.height

    /// The ground it stands on, as a row of the board: its feet are on this row and the line under them is the next.
    static let ground = 20.0
    /// Where its feet are, to turn about when it leans or rocks.
    static let pivot = (x: 13.0, y: 20.0)

    // MARK: Shapes

    /// An oval, in the board's own coordinates, turned by `angle` (radians, clockwise), that is part of the penguin; the letter it is filled
    /// with if it is not feathers.
    struct Blob {
        var cx: Double
        var cy: Double
        var rx: Double
        var ry: Double
        var angle = 0.0
        var fill: Character?

        init(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, angle: Double = 0, fill: Character? = nil) {
            (self.cx, self.cy, self.rx, self.ry, self.angle, self.fill) = (cx, cy, rx, ry, angle, fill)
        }

        func contains(_ x: Int, _ y: Int, grown: Double = 0) -> Bool {
            let (dx, dy) = (Double(x) + 0.5 - cx, Double(y) + 0.5 - cy)
            let (c, s) = (cos(angle), sin(angle))
            let (u, v) = ((dx * c + dy * s) / (rx + grown), (-dx * s + dy * c) / (ry + grown))
            return u * u + v * v <= 1
        }

        /// The same turned `radians` (clockwise) about `point`.
        func turned(_ radians: Double, about point: (x: Double, y: Double) = PenguinArt.pivot) -> Blob {
            guard radians != 0 else { return self }
            let moved = PenguinArt.turn((cx, cy), radians, about: point)
            return Blob(moved.x, moved.y, rx, ry, angle: angle + radians, fill: fill)
        }
    }

    typealias Point = (x: Double, y: Double)

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

    /// A flipper: a thick line from the shoulder to the tip.
    struct Flipper {
        var points: [Point]
        var width = 2
    }

    enum Face {
        /// Side on: open, shut, glad.
        case open, blink, happy
        /// Facing the viewer: open, shut, glad.
        case front, frontBlink, frontHappy
        /// No eye shows: tucked in, or asleep.
        case hidden
    }

    /// Everything a picture of the penguin is made of.
    struct Rig {
        /// What is dark: body, head, tail.
        var body: [Blob]
        /// The white of it: belly, throat.
        var belly: [Blob] = []
        /// Orange feet, in front of the body and drawn as part of the shape.
        var feet: [Blob] = []
        var flippers: [Flipper] = []
        /// Beak and other bits that are part of the shape and have a line round them.
        var pixels: [Pixel] = []
        /// Eyes and what is drawn on the face: over everything the penguin is made of.
        var marks: [Pixel] = []
        /// Over the shape, before the rim: what is drawn with the penguin and is rimmed with it (stars, hearts, z's, a fish).
        var extras: (inout CatCanvas) -> Void = { _ in }
        /// Over the rim, which it has none of: a fishing rod, its line, snow.
        var after: (inout PixelFrame) -> Void = { _ in }
        /// How many rows higher the whole of it is drawn (a hop); what goes off the top is cut off.
        var lift = 0
    }

    // MARK: Drawing

    /// The penguin, put together: the shape of it with one line round it, shaded (dark back, white belly and throat, orange feet), its
    /// flippers, its beak and eyes, and whatever it is doing with a rod or a fish.
    static func draw(_ rig: Rig) -> PixelFrame {
        var canvas = CatCanvas()
        let shape = rig.body + rig.feet
        let bits = Dictionary(rig.pixels.map { ($0.y * CatCanvas.width + $0.x, $0.letter) }, uniquingKeysWith: { $1 })
        func isBit(_ x: Int, _ y: Int) -> Bool { (0..<CatCanvas.width).contains(x) && (0..<CatCanvas.height).contains(y) && bits[y * CatCanvas.width + x] != nil }
        func inside(_ x: Int, _ y: Int) -> Bool { shape.contains { $0.contains(x, y) } || isBit(x, y) }
        for y in 0..<CatCanvas.height {
            for x in 0..<CatCanvas.width {
                if inside(x, y) {
                    canvas[x, y] = colour(x, y, rig: rig, bits: bits, inside: inside)
                } else if shape.contains(where: { $0.contains(x, y, grown: 1) }) || [(-1, 0), (1, 0), (0, -1), (0, 1)].contains(where: { isBit(x + $0.0, y + $0.1) }) {
                    canvas[x, y] = "K"
                }
            }
        }
        for flipper in rig.flippers { canvas.stroke(flipper.points, width: flipper.width, fill: "n", outline: "K") }
        for mark in rig.marks { canvas[mark.x, mark.y] = mark.letter }
        rig.extras(&canvas)
        var frame = (rig.lift == 0 ? canvas : canvas.shifted(dy: -rig.lift)).frame.rimmed(with: "R")
        rig.after(&frame)
        return frame
    }

    private static func colour(_ x: Int, _ y: Int, rig: Rig, bits: [Int: Character], inside: (Int, Int) -> Bool) -> Character {
        if let bit = bits[y * CatCanvas.width + x] { return bit }
        let inBody = rig.body.contains { $0.contains(x, y) }
        if !inBody, let foot = rig.feet.first(where: { $0.contains(x, y) }) { return foot.fill ?? "O" }
        if rig.belly.contains(where: { $0.contains(x, y) }) { return !inside(x, y + 1) || !inside(x + 1, y) ? "w" : "W" }
        return "N"
    }
}

extension PenguinArt {
    /// Every colour the penguin, its hole in the ice, its fish and what it says with are drawn with. The rim and the line inside it are
    /// what make it read on glass of any colour, as the cat's do; its black is a dark slate, which is lighter than the line round it.
    static let palette = PixelPalette(colors: [
        "R": 0xEAF2FB,  // the light rim all round it
        "K": 0x0B1020,  // the dark line inside the rim
        "N": 0x2E3A57,  // black feathers
        "n": 0x4A5B82,  // a flipper
        "W": 0xF8FAFD,  // belly and throat
        "w": 0xC4D2E6,  // the edge of it, in the shade
        "O": 0xF59A23,  // beak and feet
        "o": 0xC4620F,  // the lower beak, the far foot
        "E": 0xFFFFFF,  // eye
        "F": 0x7CC4F0,  // a fish
        "f": 0xDDEEF8,  // its belly
        "H": 0xE11D48,  // a heart
        "Z": 0x2563EB,  // sleep
        "S": 0xFFD23F,  // the stars it sees
        "J": 0x9C6B3E,  // the rod
        "L": 0x6C7B91,  // its line
        "T": 0x8FA9C4,  // the snow it kicks up
        "I": 0xD7ECFA,  // ice
        "i": 0x9CC4E0,  // and its shade
        "A": 0x1B4F82,  // the water in the hole
        "a": 0x4C8DC8,  // and the light on it
    ])
}

extension CatCanvas {
    /// `rows` with a dark line round them (4 ways, not corners), the line outside where the piece is: a fish, a star.
    mutating func outlinedPiece(_ rows: [String], x: Int, y: Int) {
        let (width, height) = (rows.map(\.count).max() ?? 0, rows.count)
        let ink = rows.map { Array($0) }
        func solid(_ column: Int, _ row: Int) -> Bool {
            row >= 0 && row < height && column >= 0 && column < ink[row].count && ink[row][column] != PixelPalette.clear
        }
        for row in -1...height {
            for column in -1...width where !solid(column, row) {
                if [(-1, 0), (1, 0), (0, -1), (0, 1)].contains(where: { solid(column + $0.0, row + $0.1) }) { self[x + column, y + row] = "K" }
            }
        }
        piece(rows, x: x, y: y)
    }
}
