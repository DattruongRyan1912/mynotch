import Foundation

// MARK: Facing the viewer

extension CatArt {
    static let tailDown: [Point] = [(21, 19.5), (24.5, 19), (27, 16.5), (27.5, 13)]
    static let tailFlat: [Point] = [(21, 19.5), (25, 20), (28.5, 19)]

    /// A tail with its tip `swing` (-1 to 1) across: out to the side and up, the way a sitting cat's goes.
    static func tailSwing(_ swing: Double) -> [Point] {
        [(21, 19.5), (24.5, 19), (26.5 + swing * 1.5, 15.5), (26 + swing * 2.5, 11.5 - abs(swing))]
    }

    /// How the sitting body is shaped, from sitting up (0) to lying down as a loaf (1).
    struct Slump {
        var amount: Double
        var hipsCY: Double { 17 + 0.6 * amount }
        var hipsRY: Double { 4.6 - 0.2 * amount }
        var hipsRX: Double { 8 + 1.6 * amount }
        var chestCY: Double { 14 + 3.6 * amount }
        var chestRY: Double { 4.2 - 1.2 * amount }
        var chestRX: Double { 5.2 + 3.4 * amount }
        var headY: Int { 1 + Int((4 * amount).rounded()) }
    }

    /// The cat sitting (or, with `slump`, getting down) facing the viewer: a chest over a pair of haunches, two white paws, a tail round the
    /// side.
    static func sitting(
        face: Face = .open, headDX: Int = 0, headDY: Int = 0, tail: [Point] = tailDown, slump: Double = 0, dy: Double = 0,
        rightPaw: [Point]? = nil, pawWidth: Int = 2, hindLeg: [Point]? = nil, whiskers: Whiskers = .both, extras: (inout CatCanvas) -> Void = { _ in }
    ) -> PixelFrame {
        let shape = Slump(amount: slump)
        var c = CatCanvas()
        c.stroke(tail, width: 2, fill: "O", outline: "K")
        c.ellipse(cx: 14.5, cy: shape.hipsCY + dy, rx: shape.hipsRX, ry: shape.hipsRY, fill: "O", outline: "K")
        c.ellipse(cx: 14.5, cy: shape.chestCY + dy, rx: shape.chestRX, ry: shape.chestRY, fill: "O", outline: "K")
        let chestTop = Double(Int(shape.chestCY + dy))
        c.piece(["WWW", "WWW", "WWW"], x: 13, y: Int(chestTop) - 1)
        if slump < 0.5 {
            // The two front legs, one paw each, down to the floor.
            c.stroke([(12.5, chestTop + 2), (12.5, 19.5)], width: 3, fill: "W", outline: "K")
            if rightPaw == nil { c.stroke([(16.5, chestTop + 2), (16.5, 19.5)], width: 3, fill: "W", outline: "K") }
        } else {
            // Lying down, the paws are two white rounds in front.
            c.piece(["KWWK", "WWWW", "KKKK"], x: 10, y: 19)
            c.piece(["KWWK", "WWWW", "KKKK"], x: 16, y: 19)
        }
        stripes(&c, xs: [8, 10, 19, 21], top: Int(shape.hipsCY + dy) - 1)
        let head = (x: 8 + headDX, y: shape.headY + headDY)
        c.piece(CatArt.head(face), x: head.x, y: head.y)
        extras(&c)
        if let hindLeg { c.stroke(hindLeg, width: 2, fill: "O", outline: "K", paw: "W", pawLength: 3) }
        if let rightPaw { c.stroke(rightPaw, width: pawWidth, fill: "O", outline: "K", paw: "W", pawLength: 3) }
        return finish(c, head: head, whiskers: whiskers)
    }

    static func sit(breath: Int = 0, face: Face = .open) -> PixelFrame { sitting(face: face, headDY: breath) }

    static var sitFrames: [PixelFrame] { [sit(), sit(), sit(breath: 1), sit(breath: 1)] }

    static var blinkFrames: [PixelFrame] { [sit(face: .blink)] }

    static var tailSwishFrames: [PixelFrame] {
        [-1, -0.45, 0.1, 0.65, 1, 0.3].map { sitting(tail: tailSwing($0)) }
    }

    /// A paw to the cheek and down again, over and over, eyes shut with the pleasure of it.
    static var groomFrames: [PixelFrame] {
        let paws: [Double] = [11, 9.5, 8, 6.5, 8.5, 10]
        return paws.enumerated().map { index, height in
            sitting(
                face: index == 2 || index == 3 ? .happy : .blink, headDX: index == 3 ? 1 : 0,
                rightPaw: [(16.5, 16), (17 + (index % 2 == 0 ? 0 : 0.5), height)], pawWidth: 3
            )
        }
    }

    /// A hind leg up to the ear, scratching, the head tipped into it.
    static var scratchFrames: [PixelFrame] {
        let feet: [Point] = [(26, 8), (25, 5.5), (26.5, 8.5), (25, 5), (26.5, 7), (25.5, 6)]
        return feet.enumerated().map { index, foot in
            sitting(face: index % 2 == 0 ? .squint : .blink, headDX: index < 4 ? 1 : 0, tail: tailFlat, hindLeg: [(20, 18.5), (26.5, 14), foot])
        }
    }

    /// Squinting in the heat of a busy Mac, a drop of sweat forming by the head, running down and falling.
    static var sweatFrames: [PixelFrame] {
        let drops: [(x: Int, y: Int)] = [(21, 2), (22, 5), (22, 8), (22, 11)]
        return drops.enumerated().map { index, drop in
            sitting(face: index == 3 ? .blink : .squint, headDY: index % 2, tail: tailFlat) { canvas in
                canvas.piece(sweat, x: drop.x, y: drop.y)
            }
        }
    }

    static var yawnFrames: [PixelFrame] {
        [sit(face: .squint), sitting(face: .yawn), sitting(face: .yawn, headDY: -1), sit(face: .blink)]
    }

    static var purrFrames: [PixelFrame] {
        (0..<4).map { index in
            sitting(face: .happy, headDY: index % 2, tail: tailSwing(index % 2 == 0 ? -0.5 : 0.5)) { canvas in
                canvas.piece(heart, x: 2 + (index % 2) * 2, y: 8 - index * 2)
            }
        }
    }

    static var danceFrames: [PixelFrame] {
        let sway = [-2, -1, 1, 2, 1, -1]
        return sway.enumerated().map { index, dx in
            sitting(face: .happy, headDX: dx, headDY: index % 2 == 0 ? 0 : 1, tail: tailSwing(Double(dx) / 2), whiskers: .both) { canvas in
                canvas.piece(note, x: 1 + (index * 2) % 5, y: 9 - (index % 3) * 3)
            }
        }
    }

    // MARK: Lying down

    /// The cat curled up asleep: a long low body, its head on its paws, its tail round the front. `breath` swells the body.
    static func asleep(breath: Double, twitch: Bool = false, zeds: [(x: Int, y: Int)] = []) -> PixelFrame {
        var c = CatCanvas()
        c.ellipse(cx: 12.5, cy: 15.5, rx: 10, ry: 4.6 + breath, fill: "O", outline: "K")
        stripes(&c, xs: [5, 8, 11], top: 11, length: 3)
        c.stroke([(3.5, 16), (5, 19.5), (13, 19.5), (21, 19)], width: 2, fill: "O", outline: "K")
        c.piece(["KWWK", "WWWW", "KKKK"], x: 19, y: 17)
        var face = head(.sleep)
        if twitch { face[0] = ".KK.........."; face[1] = "KPPK.....KKK." }
        c.piece(face, x: 14, y: 4)
        for zed in zeds { c.piece(Self.zed, x: zed.x, y: zed.y - 1) }
        return finish(c, head: (14, 4))
    }

    static var sleepFrames: [PixelFrame] {
        [
            asleep(breath: 0, zeds: [(3, 6)]), asleep(breath: 0.5, zeds: [(3, 6), (7, 1)]),
            asleep(breath: 1, twitch: true, zeds: [(7, 1)]), asleep(breath: 0.5),
        ]
    }

    static func loafing(face: Face = .open, breath: Double = 0) -> PixelFrame {
        var c = CatCanvas()
        c.stroke([(23, 20.5), (27, 19), (28, 16)], width: 2, fill: "O", outline: "K")
        c.ellipse(cx: 14.5, cy: 17.6, rx: 9.6, ry: 4.4 + breath, fill: "O", outline: "K")
        stripes(&c, xs: [8, 10, 19, 21], top: 14, length: 2)
        c.piece(["KWWK", "WWWW", "KKKK"], x: 10, y: 19)
        c.piece(["KWWK", "WWWW", "KKKK"], x: 16, y: 19)
        c.piece(head(face), x: 8, y: 5)
        return finish(c, head: (8, 5))
    }

    static var loafFrames: [PixelFrame] { [loafing(), loafing(face: .squint, breath: 0.6)] }

    /// Getting down: sitting, lowering, the head going down, a loaf.
    static var lieDownFrames: [PixelFrame] {
        [sitting(slump: 0.3, dy: 0), sitting(slump: 0.6), sitting(face: .squint, slump: 0.85), loafing()]
    }
}
