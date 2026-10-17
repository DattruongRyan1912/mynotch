import Foundation

/// The capybara, as pictures: on the same board as the cat (30 by 22 pixels, a light rim all round, frames of 32 by 24) so that a lane takes
/// any mix of them, and in the same way: its head is typed out, its body is shapes of letters put one over another by `CatCanvas`.
///
/// It is always side on, facing right (the mirror image is made for left). It is round and brown with a blunt snout, small ears and short
/// legs. The one thing the other characters rely on is where its back is when it sits or soaks: the top of the rump is `backTop`, and
/// what sits on it is where `perchShift` says, whatever the capybara is doing there.
enum CapybaraArt {
    static let width = CatArt.width
    static let height = CatArt.height

    typealias Point = CatArt.Point

    /// The board row of the line round the top of the capybara's rump when it sits, lies in its tub or listens: a rider's feet stand on the
    /// row of rim above it.
    static let backTop = 12
    /// How far, in pixels, a rider's picture is from the capybara's own for it to sit on the rump: not at all, the capybara's rump and the
    /// rider's seat are at the same place in both (and in their mirror images), which is what the rider's art is drawn for.
    static let perchShift = 0.0

    // MARK: The face

    enum Face {
        case open, blink, happy, half, sleep, chewA, chewB, squint, front
    }

    /// The head, 11 by 10, facing right: a small round ear with a pink inside, a forehead that slopes into a long blunt snout with a nostril
    /// on top, a small eye set high. The rows from `joined` down are over the body, which they do not draw a line across.
    static func head(_ face: Face, joined: Int = 10) -> [String] {
        var rows = [
            "...KK......",
            "..KPPKKKK..",
            ".KKPKDDDDK.",
            "KDDDDDDDDDK",
            "KODDDOEOOOK",
            "KOOOOOOOOON",
            ".KOOOOOOWWK",
            "..KOOOOOWWK",
            "...KKOOOOOK",
            ".....KKKKK.",
        ]
        switch face {
        case .open, .front: break
        case .blink, .sleep:
            rows[4] = "KODDDOKKOOK"
        case .half:
            rows[4] = "KODDDOKEOOK"
        case .squint:
            rows[4] = "KODDDOEEOOK"
        case .happy:
            rows[4] = "KODDDKOKOOK"
            rows[5] = "KOOOPOOOOON"
        case .chewA:
            rows[7] = "..KOOOOOWWK"
        case .chewB:
            rows[6] = ".KOOOOOOKWK"
            rows[7] = "..KOOOOKKWK"
        }
        return rows.enumerated().map { index, row in
            guard index >= joined, row.first == "K" else { return row }
            return "." + row.dropFirst()
        }
    }

    // MARK: The body

    /// A long barrel with round ends, which is a capybara's body: from `left` to `right`, `top` to `bottom` (all of them the board's own
    /// coordinates), its ends as round as `radius`.
    struct Barrel {
        var left: Double
        var right: Double
        var top: Double
        var bottom: Double
        var radius: Double

        func contains(_ x: Int, _ y: Int, grown: Double = 0) -> Bool {
            let (px, py) = (Double(x) + 0.5, Double(y) + 0.5)
            let r = radius + grown
            let (l, rt, t, b) = (left - grown, right + grown, top - grown, bottom + grown)
            guard px >= l, px <= rt, py >= t, py <= b else { return false }
            // The corners are quarter circles.
            let cx = px < l + r ? l + r : (px > rt - r ? rt - r : px)
            let cy = py < t + r ? t + r : (py > b - r ? b - r : py)
            return (px - cx) * (px - cx) + (py - cy) * (py - cy) <= r * r + 0.001
        }

        func moved(dy: Double) -> Barrel { Barrel(left: left, right: right, top: top + dy, bottom: bottom + dy, radius: radius) }
    }

    /// The bodies put together, with one line round all of them: a darker back, two rows deep, and a lighter belly.
    static func draw(_ bodies: [Barrel], on canvas: inout CatCanvas) {
        func inside(_ x: Int, _ y: Int) -> Bool { bodies.contains { $0.contains(x, y) } }
        for y in 0..<CatCanvas.height {
            for x in 0..<CatCanvas.width {
                if inside(x, y) {
                    canvas[x, y] = !inside(x, y - 2) ? "D" : (!inside(x, y + 1) ? "W" : "O")
                } else if bodies.contains(where: { $0.contains(x, y, grown: 1) }) {
                    canvas[x, y] = "K"
                }
            }
        }
    }

    /// The walking body.
    static let standing = [Barrel(left: 1.5, right: 20, top: 8, bottom: 17.5, radius: 4.5)]
    /// Sitting, lying in the tub, listening: a long low rump on the floor with the shoulders up over the front legs, and the back is at
    /// `backTop`.
    static let seated = [
        Barrel(left: 1.5, right: 17.5, top: Double(backTop + 1), bottom: 20.5, radius: 3.6),
        Barrel(left: 17, right: 20.5, top: 10, bottom: 20.5, radius: 1.7),
    ]
    /// Lying down: lower than sitting, the head on the floor in front.
    static let lying = [Barrel(left: 1.5, right: 21, top: 14.5, bottom: 20.5, radius: 3)]

    // MARK: Legs

    /// Four short legs, the far ones darker and behind.
    static func legs(phase: Double, stride: Double = 2.4, lift: Double = 2.2, hipY: Double = 16.5) -> [CatArt.Leg] {
        func leg(_ hip: Double, _ offset: Double, far: Bool) -> CatArt.Leg {
            CatArt.Leg(hip: (hip, hipY), foot: CatArt.foot(phase: phase + offset, hipX: hip, stride: stride, lift: lift), far: far)
        }
        return [leg(5, 0, far: true), leg(15.5, 0.5, far: true), leg(7.5, 0.5, far: false), leg(18, 0, far: false)]
    }

    /// Standing still: the four feet down.
    static let stillLegs: [CatArt.Leg] = [
        CatArt.Leg(hip: (5, 16.5), foot: (5, 20), far: true), CatArt.Leg(hip: (15.5, 16.5), foot: (15.5, 20), far: true),
        CatArt.Leg(hip: (7.5, 16.5), foot: (7.5, 20)), CatArt.Leg(hip: (18, 16.5), foot: (18, 20)),
    ]

    /// The legs of a capybara sitting: the front ones straight down, and the thigh and foot of a hind leg folded under the rump.
    static func sittingLegs(on canvas: inout CatCanvas) {
        canvas.stroke([(16.5, 17), (16.5, 20)], width: 2, fill: "D", outline: "K", paw: "D")
        canvas.stroke([(19, 17), (19, 20)], width: 2, fill: "O", outline: "K", paw: "D")
        canvas.ellipse(cx: 7, cy: 17.6, rx: 4.2, ry: 2.8, fill: "O", outline: "K")
        canvas.piece(["DDDD", "KKKK"], x: 8, y: 19)
    }

    // MARK: Putting it together

    /// The capybara: legs behind the body, the body, the near legs, the head over them, and whatever it carries. `lift` is how many rows
    /// the whole of it is drawn above where it stands (a hop); what goes off the top is cut off.
    static func capybara(
        body: [Barrel] = standing, legs: [CatArt.Leg] = stillLegs, sitting: Bool = false, head at: (x: Int, y: Int) = (16, 6),
        face: Face = .open, joined: Int = 3, lift: Int = 0, headRows: [String]? = nil, extras: (inout CatCanvas) -> Void = { _ in }
    ) -> PixelFrame {
        var c = CatCanvas()
        for leg in legs where leg.far { c.stroke([leg.hip, leg.foot], width: 2, fill: "D", outline: "K", paw: "D") }
        draw(body, on: &c)
        for leg in legs where !leg.far { c.stroke([leg.hip, leg.foot], width: 2, fill: "O", outline: "K", paw: "D") }
        if sitting { sittingLegs(on: &c) }
        c.piece(headRows ?? head(face, joined: joined), x: at.x, y: at.y)
        extras(&c)
        return (lift == 0 ? c : c.shifted(dy: -lift)).frame.rimmed(with: "R")
    }
}

extension CatCanvas {
    /// The same drawing `dy` rows lower (higher when it is negative); what goes off the board is cut off.
    func shifted(dy: Int) -> CatCanvas {
        var moved = CatCanvas()
        for y in 0..<Self.height {
            for x in 0..<Self.width where self[x, y] != PixelPalette.clear { moved[x, y + dy] = self[x, y] }
        }
        return moved
    }
}

extension CapybaraArt {
    /// Every colour the capybara, its tub, its orange and what it says with are drawn with. The rim and the line inside it are what make it
    /// read on glass of any colour, as the cat's do.
    static let palette = PixelPalette(colors: [
        "R": 0xFFF4DC,  // the light rim all round it
        "K": 0x3A2415,  // the dark line inside the rim
        "O": 0xA9703F,  // fur
        "D": 0x7B4A28,  // the darker back, ears, feet
        "W": 0xD9A877,  // belly and muzzle
        "E": 0x1A100B,  // eye
        "N": 0x24160F,  // nostril
        "P": 0xE08E7A,  // the inside of an ear, a cheek
        "H": 0xE11D48,  // a heart
        "Z": 0x2563EB,  // sleep
        "Q": 0x2563EB,  // the ring of a sleep bubble
        "I": 0xDBEAFE,  // and the shine in it
        "S": 0x0369A1,  // a sweat drop
        "G": 0xFB923C,  // an orange
        "X": 0xFFC27A,  // and the light on it
        "F": 0xC2410C,  // and its shadow, and the peel's inside
        "Y": 0x4ADE80,  // and its leaf
        "T": 0xC4824B,  // the wood of the tub
        "U": 0x8A5530,  // and its darker boards
        "A": 0x7DD3FC,  // water
        "B": 0xE6F7FF,  // and the light on it
        "C": 0x38A3D8,  // and its depth
        "J": 0x5B4636,  // the hoops round the tub
    ])
}
