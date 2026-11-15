import Foundation

/// The hamster, as pictures: on the same board as the cat (30 by 22 pixels, a light rim all round, frames of 32 by 24) so that a lane takes
/// any mix of them, and in the same way: a line of dark round it inside a light rim, which is what makes it read on glass of any colour.
///
/// It is small and round, golden with a white belly, and drawn from a few ovals put one over another (`Blob`): the body, the head, a cheek
/// that is fuller each time it stuffs a seed in, four paws. The ovals are one shape with one line round them, so a head is not cut off from
/// a body by a line across, and every pose is a handful of numbers. It is always side on or three quarters, facing right (the mirror image
/// is made for left), standing in the middle of its frame so the mirror image stands in the middle too.
///
/// It is small enough to run in a wheel of 22 pixels (`HamsterProps`): the wheel is drawn over it, and the hamster in it is the same
/// hamster one row higher (`inWheel`), standing on the inside of the ring.
enum HamsterArt {
    static let width = CatArt.width
    static let height = CatArt.height

    /// How many rows higher it stands in the wheel, on the inside of the ring.
    static let wheelRise = 1

    // MARK: Shapes

    /// An oval, in the board's own coordinates, that is part of the hamster, and the letter it is filled with if it is not fur.
    struct Blob {
        var cx: Double
        var cy: Double
        var rx: Double
        var ry: Double
        var fill: Character?

        init(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, fill: Character? = nil) {
            (self.cx, self.cy, self.rx, self.ry, self.fill) = (cx, cy, rx, ry, fill)
        }

        func contains(_ x: Int, _ y: Int, grown: Double = 0) -> Bool {
            let (dx, dy) = ((Double(x) + 0.5 - cx) / (rx + grown), (Double(y) + 0.5 - cy) / (ry + grown))
            return dx * dx + dy * dy <= 1
        }
    }

    enum Face {
        case open, blink, happy, sleep, front
    }

    /// Everything a picture of the hamster is made of.
    struct Rig {
        var body: Blob
        var head: Blob
        /// Fuller from nothing (0) to a pouch as big as the head (3).
        var cheeks = 0
        var face = Face.open
        /// Paws and feet, near ones and far ones: just where they are.
        var paws: [Blob] = []
        /// The pixel the top left of each ear goes on, on the board.
        var ears: [(x: Int, y: Int)] = []
        /// The nose a row higher: a twitch.
        var twitch = false
        /// How many rows higher the whole of it is drawn (a hop); what goes off the top is cut off.
        var lift = 0
        /// Over everything the hamster is made of.
        var extras: (inout CatCanvas) -> Void = { _ in }
    }

    /// The pouch in a cheek, `level` fuller than none: it makes the face round, and bigger every time, down and forward of the eye.
    static func pouch(on head: Blob, level: Int) -> Blob? {
        guard level > 0 else { return nil }
        let size = Double(level)
        return Blob(head.cx + 0.2 + size * 0.2, head.cy + 1.1 + size * 0.35, head.rx - 0.6 + size * 0.65, head.ry - 0.8 + size * 0.55, fill: "L")
    }

    /// The ear on top of a head, towards its back: where its top left goes.
    static func ear(on head: Blob, shift: Double = 0) -> (x: Int, y: Int) {
        (Int((head.cx - 3.6 + shift).rounded()), Int((head.cy - head.ry - 2.2).rounded()))
    }

    // MARK: Drawing

    /// The hamster, put together: the shape of it with one line round it, shaded (a darker back, a white belly and muzzle), its ears, its
    /// face, and whatever it is doing with a seed or a heart.
    static func draw(_ rig: Rig) -> PixelFrame {
        var canvas = CatCanvas()
        let pouch = pouch(on: rig.head, level: rig.cheeks)
        let shape = [rig.body, rig.head] + (pouch.map { [$0] } ?? []) + rig.paws
        func inside(_ x: Int, _ y: Int) -> Bool { shape.contains { $0.contains(x, y) } }
        for y in 0..<CatCanvas.height {
            for x in 0..<CatCanvas.width {
                if inside(x, y) {
                    canvas[x, y] = colour(x, y, rig: rig, pouch: pouch, inside: inside)
                } else if shape.contains(where: { $0.contains(x, y, grown: 1) }) {
                    canvas[x, y] = "K"
                }
            }
        }
        for ear in rig.ears { canvas.piece(earPiece, x: ear.x, y: ear.y) }
        face(rig, on: &canvas)
        rig.extras(&canvas)
        return (rig.lift == 0 ? canvas : canvas.shifted(dy: -rig.lift)).frame.rimmed(with: "R")
    }

    private static func colour(_ x: Int, _ y: Int, rig: Rig, pouch: Blob?, inside: (Int, Int) -> Bool) -> Character {
        let (body, head) = (rig.body, rig.head)
        let inHead = head.contains(x, y)
        if let paw = rig.paws.first(where: { $0.contains(x, y) && $0.fill != nil }), !body.contains(x, y), !inHead, !(pouch?.contains(x, y) ?? false) {
            return paw.fill ?? "O"
        }
        // The very front of the face is white, whatever is in the cheeks.
        if inHead, Double(x) + 0.5 > head.cx + head.rx * (pouch == nil ? 0.4 : 0.6), Double(y) + 0.5 > head.cy + head.ry * 0.25 { return "W" }
        if let pouch, pouch.contains(x, y), !inHead || Double(y) + 0.5 > head.cy + 0.6 { return !inside(x, y - 1) ? "D" : "L" }
        // The belly: the low part of the body, under the chest.
        if body.contains(x, y), !inHead, Double(y) + 0.5 > body.cy + body.ry * 0.35 { return "W" }
        if !inside(x, y - 1) { return "D" }
        return "O"
    }

    /// A small round ear with pink in it, its top left at the point given: the head's own line goes round the lower half.
    static let earPiece = [".KK.", "KDDK", "KPPK", ".PP."]

    /// The eye, the nose and the mouth of the face the hamster has on, relative to its head.
    private static func face(_ rig: Rig, on canvas: inout CatCanvas) {
        let head = rig.head
        let (ex, ey) = (Int((head.cx + head.rx * 0.38).rounded(.down)), Int((head.cy - head.ry * 0.38).rounded(.down)))
        let (nx, ny) = (Int((head.cx + head.rx - 0.8).rounded(.down)), Int((head.cy + head.ry * 0.1).rounded(.down)))
        switch rig.face {
        case .open:
            canvas[ex, ey] = "E"
            canvas[ex, ey + 1] = "E"
        case .blink, .sleep:
            canvas[ex - 1, ey + 1] = "K"
            canvas[ex, ey + 1] = "K"
        case .happy:
            canvas[ex - 1, ey + 1] = "K"
            canvas[ex, ey] = "K"
            canvas[ex + 1, ey + 1] = "K"
        case .front:
            // Facing the viewer: two eyes, and the nose between them, low.
            let (left, right) = (Int((head.cx - 2.4).rounded(.down)), Int((head.cx + 1.4).rounded(.down)))
            for x in [left, right] {
                canvas[x, ey] = "E"
                canvas[x, ey + 1] = "E"
            }
            let (mx, my) = (Int((head.cx - 0.9).rounded(.down)), Int((head.cy + 1.1).rounded(.down)) - (rig.twitch ? 1 : 0))
            canvas[mx, my] = "P"
            canvas[mx + 1, my] = "P"
            canvas.piece(["WWWW"], x: mx - 1, y: my + 1)
            return
        }
        canvas[nx, ny - (rig.twitch ? 1 : 0)] = "P"
        canvas[nx + 1, ny - (rig.twitch ? 1 : 0)] = "K"
    }
}

extension HamsterArt {
    /// Every colour the hamster, its wheel, its seeds and what it says with are drawn with. The rim and the line inside it are what make it
    /// read on glass of any colour, as the cat's do.
    static let palette = PixelPalette(colors: [
        "R": 0xFFF4DC,  // the light rim all round it
        "K": 0x3A2415,  // the dark line inside the rim
        "O": 0xE3A24A,  // golden fur
        "D": 0xB9742A,  // the darker back, the far paws
        "L": 0xF4C57B,  // a cheek that is full
        "W": 0xFFF6E4,  // belly, muzzle, chin
        "P": 0xF0A6A0,  // the inside of an ear, the nose, paws
        "E": 0x1A100B,  // eye
        "H": 0xE11D48,  // a heart
        "Z": 0x2563EB,  // sleep
        "S": 0x4B3F34,  // a seed
        "V": 0xE8DFCB,  // and the stripe on it
        "M": 0x8FA3B8,  // the wheel's ring
        "N": 0x5E7088,  // and its darker rungs
        "B": 0xDCE9F5,  // and its lighter ones, and a spark
        "U": 0x80796F,  // the dust it comes in a cloud of
        "X": 0x586A82,  // the lines that say how fast
    ])
}
