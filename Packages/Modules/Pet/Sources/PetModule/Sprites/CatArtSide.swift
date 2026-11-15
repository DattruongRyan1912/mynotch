import Foundation

// MARK: Side on, facing right

extension CatArt {
    /// An ellipse of body.
    struct Body {
        var cx: Double
        var cy: Double
        var rx: Double
        var ry: Double

        func lifted(_ lift: Double) -> Body { Body(cx: cx, cy: cy - lift, rx: rx, ry: ry) }
    }

    /// One leg, hip to foot; the far ones are drawn darker and behind the body.
    struct Leg {
        var hip: Point
        var foot: Point
        var far = false
        var paw = true
    }

    static let walkingBody = Body(cx: 13.5, cy: 12, rx: 8.5, ry: 4.6)
    static let tailRaised: [Point] = [(5.5, 11), (3, 10), (1.5, 7.5), (2, 4.5), (4, 2.5)]
    static let tailLow: [Point] = [(5, 11.5), (3, 11), (1.5, 10.5)]

    /// The cat side on, facing right, with its head turned to the viewer.
    static func side(
        legs: [Leg], bodies: [Body] = [walkingBody], tail: [Point] = tailRaised, tailWidth: Int = 2, face: Face = .open,
        head: (x: Int, y: Int) = (16, 3), lift: Double = 0, extras: (inout CatCanvas) -> Void = { _ in }
    ) -> PixelFrame {
        var c = CatCanvas()
        c.stroke(tail.map { ($0.x, $0.y - lift) }, width: tailWidth, fill: "O", outline: "K")
        for leg in legs where leg.far {
            c.stroke([(leg.hip.x, leg.hip.y - lift), leg.foot], width: 2, fill: "D", outline: "K", paw: leg.paw ? "D" : nil)
        }
        for body in bodies { c.ellipse(cx: body.cx, cy: body.cy - lift, rx: body.rx, ry: body.ry, fill: "O", outline: "K") }
        if let first = bodies.first {
            stripes(&c, xs: [Int(first.cx) - 4, Int(first.cx) - 1, Int(first.cx) + 2, Int(first.cx) + 5], top: Int(first.cy - lift - first.ry) + 1, length: 3)
        }
        for leg in legs where !leg.far {
            c.stroke([(leg.hip.x, leg.hip.y - lift), leg.foot], width: 2, fill: "O", outline: "K", paw: leg.paw ? "W" : nil)
        }
        c.piece(CatArt.head(face), x: head.x, y: head.y - Int(lift.rounded()))
        extras(&c)
        return finish(c, head: (head.x, head.y - Int(lift.rounded())), whiskers: .right)
    }

    // MARK: Walking and running

    /// Where one foot is, a share `phase` of the way through a stride: it slides back along the ground for half of it and comes forward,
    /// lifted, for the other half.
    static func foot(phase: Double, hipX: Double, stride: Double, lift: Double, ground: Double = 20) -> Point {
        let q = phase - phase.rounded(.down)
        if q < 0.5 { return (hipX + stride * (1 - 4 * q), ground) }
        let t = (q - 0.5) * 2
        return (hipX + stride * (-1 + 2 * t), ground - lift * sin(Double.pi * t))
    }

    /// Four legs in a stride, the diagonal pairs together.
    static func legs(phase: Double, stride: Double, lift: Double) -> [Leg] {
        let (frontX, backX, hipY) = (19.0, 7.5, 15.0)
        func leg(_ hip: Double, _ offset: Double, far: Bool) -> Leg {
            Leg(hip: (hip, hipY), foot: foot(phase: phase + offset, hipX: hip, stride: stride, lift: lift), far: far)
        }
        return [leg(backX - 1, 0, far: true), leg(frontX - 1, 0.5, far: true), leg(backX + 1.5, 0.5, far: false), leg(frontX + 1.5, 0, far: false)]
    }

    static var walkFrames: [PixelFrame] {
        (0..<8).map { index in
            let phase = Double(index) / 8
            let bob = index % 2 == 1 ? 1.0 : 0
            let sway = 1.2 * sin(2 * Double.pi * phase)
            let tail: [Point] = [(5.5, 11), (3, 10), (1.5, 7.5 + sway * 0.4), (2 + sway * 0.5, 4.5), (4 + sway, 2.5)]
            return side(legs: legs(phase: phase, stride: 3, lift: 3), tail: tail, lift: bob)
        }
    }

    static var trotFrames: [PixelFrame] {
        (0..<6).map { index in
            let phase = Double(index) / 6
            let bob = [0.0, 1, 1, 0, 1, 1][index]
            let tail: [Point] = [(5.5, 11), (3, 9.5), (1.5, 8.5), (2, 6.5)]
            return side(legs: legs(phase: phase, stride: 5, lift: 4.5), tail: tail, lift: bob)
        }
    }

    /// A gallop: the front legs reach as the back ones push, then they all come in under the body.
    static func gallop(_ index: Int, face: Face, extras: (inout CatCanvas) -> Void = { _ in }) -> PixelFrame {
        let theta = 2 * Double.pi * Double(index) / 6
        let reach = (1 + cos(theta)) / 2
        func foot(_ hipX: Double, _ direction: Double, _ offset: Double) -> Point {
            (hipX + direction * (6.5 * cos(theta + offset) - 1), 20 - 4 * (1 + cos(theta + offset)) / 2)
        }
        let legs = [
            Leg(hip: (6.5, 15), foot: foot(6.5, -1, 0.5), far: true), Leg(hip: (18, 15), foot: foot(18, 1, 0.5), far: true),
            Leg(hip: (9, 15), foot: foot(9, -1, 0), far: false), Leg(hip: (20.5, 15), foot: foot(20.5, 1, 0), far: false),
        ]
        let body = Body(cx: 13.5, cy: 12, rx: 8.8 + reach, ry: 4.3)
        return side(legs: legs, bodies: [body], tail: tailLow, face: face, lift: 1 + 2 * reach, extras: extras)
    }

    static var chaseFrames: [PixelFrame] { (0..<6).map { gallop($0, face: .open) } }

    /// Running for its life: wide eyes and a drop of sweat that flies off.
    static var franticFrames: [PixelFrame] {
        (0..<6).map { index in
            gallop(index, face: .wide) { canvas in
                canvas.piece(sweat, x: 11, y: [0, 1, 2, 0, 1, 2][index])
            }
        }
    }
}
