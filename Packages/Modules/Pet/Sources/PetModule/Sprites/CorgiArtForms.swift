import Foundation

extension CorgiArt {
    enum Face {
        /// Open, shut, glad.
        case open, blink, happy
        /// No eye shows.
        case hidden
    }

    enum Mouth {
        case shut, open, panting
    }

    /// Which way the corgi is seen: side on, facing right; facing the viewer; or from behind.
    enum Aspect {
        case side, front, back
    }

    /// A leg's paw: how far forward of its hip it is, and how high off the ground.
    typealias Paw = (x: Double, lift: Double)

    /// How a corgi is put together in one picture: the same eight ovals, four white places and four legs whatever it is doing, so that one
    /// way of standing, sitting or lying turns into another by moving the same numbers (`mixed`), and a move is a handful of them.
    struct Form {
        var rump: Blob
        var torso: Blob
        var chest: Blob
        var head: Blob
        var muzzle: Blob
        var earNear: Blob
        var earFar: Blob
        var tail: Blob
        /// The chest, the belly, the muzzle and the fluff of the rear.
        var whites: [Blob]
        /// Near front, far front, near rear, far rear: where each comes out of the body and where the paw is (a stroke of two points).
        var legs: [[Point]]
        var aspect = Aspect.side
        var face = Face.open
        var mouth = Mouth.shut

        var blobs: [Blob] { [rump, torso, chest, head, muzzle, earNear, earFar, tail] }

        init(blobs: [Blob], whites: [Blob], legs: [[Point]]) {
            (rump, torso, chest, head, muzzle, earNear, earFar, tail) = (blobs[0], blobs[1], blobs[2], blobs[3], blobs[4], blobs[5], blobs[6], blobs[7])
            (self.whites, self.legs) = (whites, legs)
        }

        /// The same moved by (`dx`, `dy`).
        func moved(_ dx: Double, _ dy: Double) -> Form {
            var form = Form(blobs: blobs.map { $0.moved(dx, dy) }, whites: whites.map { $0.moved(dx, dy) }, legs: legs.map { $0.map { ($0.x + dx, $0.y + dy) } })
            (form.aspect, form.face, form.mouth) = (aspect, face, mouth)
            return form
        }

        /// The head, with its muzzle and ears, and the whites of the muzzle, turned `radians` (clockwise: nose down) about `pivot`.
        func headTurned(_ radians: Double, about pivot: Point) -> Form {
            var form = self
            form.head = head.turned(radians, about: pivot)
            form.muzzle = muzzle.turned(radians, about: pivot)
            form.earNear = earNear.turned(radians, about: pivot)
            form.earFar = earFar.turned(radians, about: pivot)
            form.whites[2] = whites[2].turned(radians, about: pivot)
            return form
        }

        /// The head and what goes with it moved by (`dx`, `dy`).
        func headMoved(_ dx: Double, _ dy: Double) -> Form {
            var form = self
            form.head = head.moved(dx, dy)
            form.muzzle = muzzle.moved(dx, dy)
            form.earNear = earNear.moved(dx, dy)
            form.earFar = earFar.moved(dx, dy)
            form.whites[2] = whites[2].moved(dx, dy)
            return form
        }

        func earsTurned(near: Double, far: Double) -> Form {
            var form = self
            form.earNear.angle += near
            form.earFar.angle += far
            return form
        }
    }

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    private static func mix(_ a: Blob, _ b: Blob, _ t: Double) -> Blob {
        Blob(mix(a.cx, b.cx, t), mix(a.cy, b.cy, t), mix(a.rx, b.rx, t), mix(a.ry, b.ry, t), angle: mix(a.angle, b.angle, t))
    }

    /// A form `t` of the way from `a` (0) to `b` (1): every oval and every leg, and the face and the way it is seen of whichever is nearer.
    static func mixed(_ a: Form, _ b: Form, _ t: Double) -> Form {
        var form = Form(
            blobs: zip(a.blobs, b.blobs).map { mix($0, $1, t) }, whites: zip(a.whites, b.whites).map { mix($0, $1, t) },
            legs: zip(a.legs, b.legs).map { pair in zip(pair.0, pair.1).map { (mix($0.x, $1.x, t), mix($0.y, $1.y, t)) } }
        )
        let near = t < 0.5 ? a : b
        (form.aspect, form.face, form.mouth) = (near.aspect, near.face, near.mouth)
        return form
    }

    // MARK: Putting a form on the board

    private static func rotated(_ dx: Double, _ dy: Double, by angle: Double) -> Point {
        (dx * cos(angle) - dy * sin(angle), dx * sin(angle) + dy * cos(angle))
    }

    /// The form as something to draw: its marks (the eye, the nose, the inside of the ear and the tongue) are worked out from where its
    /// ovals are, so that a head that is moved or turned takes them with it.
    static func rig(
        _ form: Form, lift: Int = 0, extras: @escaping (inout CatCanvas) -> Void = { _ in }, after: @escaping (inout PixelFrame) -> Void = { _ in }
    ) -> Rig {
        var marks: [Pixel] = []
        func mark(_ x: Double, _ y: Double, _ letter: Character) {
            marks.append(Pixel(x: Int(x.rounded(.down)), y: Int(y.rounded(.down)), letter: letter))
        }
        func eye(_ x: Double, _ y: Double) {
            switch form.face {
            case .open: mark(x, y, "e")
            case .blink: mark(x - 0.6, y + 0.8, "e"); mark(x + 0.6, y + 0.8, "e")
            case .happy: mark(x - 1.0, y + 0.7, "e"); mark(x, y - 0.3, "e"); mark(x + 1.0, y + 0.7, "e")
            case .hidden: break
            }
        }
        switch form.aspect {
        case .side:
            let head = form.head, muzzle = form.muzzle
            let at = { (dx: Double, dy: Double) -> Point in
                let r = rotated(dx, dy, by: head.angle)
                return (head.cx + r.x, head.cy + r.y)
            }
            let eyeAt = at(1.6, -0.9)
            eye(eyeAt.x, eyeAt.y)
            let tip = rotated(muzzle.rx - 0.6, -0.5, by: muzzle.angle)
            mark(muzzle.cx + tip.x, muzzle.cy + tip.y, "N")
            mark(muzzle.cx + tip.x - 1.0, muzzle.cy + tip.y - 0.3, "N")
            if form.mouth != .shut {
                let tongue = rotated(1.2, muzzle.ry + 0.7, by: muzzle.angle)
                mark(muzzle.cx + tongue.x, muzzle.cy + tongue.y, "T")
                mark(muzzle.cx + tongue.x + 1.0, muzzle.cy + tongue.y, "T")
                if form.mouth == .panting { mark(muzzle.cx + tongue.x + 1.0, muzzle.cy + tongue.y + 1.0, "T") }
            }
            let ear = rotated(0, 0.2, by: form.earNear.angle)
            mark(form.earNear.cx + ear.x, form.earNear.cy + ear.y, "P")
            let inner = rotated(0, 1.2, by: form.earNear.angle)
            mark(form.earNear.cx + inner.x, form.earNear.cy + inner.y, "P")
        case .front:
            let head = form.head
            eye(head.cx - 2.0, head.cy - 0.3)
            eye(head.cx + 2.0, head.cy - 0.3)
            let m = form.muzzle
            mark(m.cx - 0.5, m.cy - 0.6, "N")
            mark(m.cx + 0.5, m.cy - 0.6, "N")
            if form.mouth != .shut {
                mark(m.cx - 0.5, m.cy + m.ry + 0.3, "T")
                mark(m.cx + 0.5, m.cy + m.ry + 0.3, "T")
                if form.mouth == .panting { mark(m.cx + 0.5, m.cy + m.ry + 1.3, "T") }
            }
            for ear in [form.earNear, form.earFar] {
                mark(ear.cx, ear.cy + 0.2, "P")
                mark(ear.cx, ear.cy + 1.2, "P")
            }
        case .back: break
        }
        let sides = form.aspect == .side
        var legs: [Leg] = []
        for (index, points) in form.legs.enumerated() { legs.append(Leg(points: points, far: index % 2 == 1)) }
        return Rig(
            body: [form.rump, form.torso, form.chest, form.head, form.muzzle, form.earNear, form.tail] + (sides ? [] : [form.earFar]),
            behind: sides ? [form.earFar] : [], white: form.whites, legs: legs, marks: marks, extras: extras, after: after, lift: lift
        )
    }

    // MARK: Standing

    /// Where the legs come out of the body: near front, far front, near rear, far rear.
    static let hips: [Double] = [16.1, 13.9, 5.9, 8.1]
    /// The head turns about the neck.
    static let neck: Point = (16.3, 11.5)

    /// A standing corgi, side on, facing right. `rump` is how far the rear end is moved (a wiggle), `head` how far the head is moved (and,
    /// in degrees, turned nose down), `ears` how far each ear is turned from upright (forward is more), `paws` where the four feet are
    /// (near front, far front, near rear, far rear), `tail` how high the stub of a tail is held and `breath` how far the front of it is down.
    static func standForm(
        breath: Double = 0, rump: Point = (0, 0), head: (dx: Double, dy: Double, turn: Double) = (0, 0, 0), ears: (near: Double, far: Double) = (0, 0),
        paws: [Paw] = [(0, 0), (0, 0), (0, 0), (0, 0)], tail: Double = 0, face: Face = .open, mouth: Mouth = .shut
    ) -> Form {
        var legs: [[Point]] = []
        for index in 0..<4 {
            let hip = hips[index] + (index >= 2 ? rump.x : 0)
            legs.append([(hip, 18.5 + (index >= 2 ? rump.y : 0)), (hip + paws[index].x, ground - paws[index].lift)])
        }
        var form = Form(
            blobs: [
                Blob(6.9, 13.4, 4.6, 4.0).moved(rump.x, rump.y), Blob(12.1, 13.9, 5.9, 3.5), Blob(16.9, 13.4 + breath * 0.3, 3.3, 3.9),
                Blob(20.1, 9.0 + breath * 0.6, 4.2, 3.5), Blob(23.7, 10.6 + breath * 0.6, 2.6, 1.7),
                Blob(21.1, 4.3 + breath * 0.6, 1.7, 2.8, angle: 0.18), Blob(17.3, 4.9 + breath * 0.6, 1.6, 2.6, angle: -0.22),
                Blob(1.9, 11.6 - tail, 1.3, 1.2).moved(rump.x, rump.y),
            ],
            whites: [Blob(17.4, 14.6, 2.6, 3.0), Blob(11.0, 16.9, 5.4, 1.1), Blob(23.9, 11.0 + breath * 0.6, 2.6, 1.5), Blob(5.3, 16.2, 3.0, 1.8).moved(rump.x, rump.y)],
            legs: legs
        )
        (form.face, form.mouth) = (face, mouth)
        return form.headMoved(head.dx, head.dy).headTurned(head.turn * .pi / 180, about: (neck.x + head.dx, neck.y + head.dy)).earsTurned(near: ears.near, far: ears.far)
    }

    // MARK: Sitting

    /// How far to the right a sitting corgi is drawn, to be in the middle of its picture: it is not so long as it is standing.
    static let sittingShift = 2.5

    /// Sitting, the rump on the ground, the back sloping up to the shoulders, the head up, the front legs straight.
    static func sitForm(breath: Double = 0, face: Face = .open, mouth: Mouth = .shut, ears: (near: Double, far: Double) = (0, 0)) -> Form {
        var form = Form(
            blobs: [
                Blob(7.8, 16.6, 5.0, 4.0), Blob(10.6, 13.0, 3.8, 5.0, angle: 0.5), Blob(13.3, 13.2, 3.0, 4.2, angle: 0.1),
                Blob(15.2, 7.4 + breath * 0.5, 4.2, 3.5), Blob(18.9, 9.0 + breath * 0.5, 2.6, 1.7),
                Blob(16.2, 3.2 + breath * 0.5, 1.7, 2.8, angle: 0.18), Blob(12.6, 3.8 + breath * 0.5, 1.6, 2.6, angle: -0.22), Blob(2.6, 18.4, 1.3, 1.1),
            ],
            whites: [Blob(13.9, 14.2, 2.4, 3.2), Blob(10.4, 17.8, 3.0, 1.0), Blob(19.1, 9.4 + breath * 0.5, 2.6, 1.5), Blob(5.2, 18.6, 3.2, 1.4)],
            legs: [[(13.6, 15.4), (15.6, 20)], [(11.6, 15.4), (13.4, 20)], [(7.8, 19.0), (11.4, 20)], [(6.6, 19.2), (10.2, 20)]]
        )
        (form.face, form.mouth) = (face, mouth)
        return form.earsTurned(near: ears.near, far: ears.far).moved(sittingShift, 0)
    }

    /// Sitting up on its haunches to beg: the back nearly upright, the head up and the ears laid back, and the front paws together at its
    /// chest. `paws` is how high the paws are held (rows); `lean` is how far the back is from sitting (0) to begging (1).
    static func begForm(paws: Double = 0, face: Face = .open, mouth: Mouth = .open, ears: (near: Double, far: Double) = (0, 0)) -> Form {
        var form = Form(
            blobs: [
                Blob(7.6, 16.7, 4.7, 3.7), Blob(9.6, 12.4, 3.6, 5.4, angle: 0.2), Blob(11.6, 11.8, 3.0, 4.0, angle: 0.05),
                Blob(13.2, 6.0, 4.2, 3.5), Blob(16.9, 7.6, 2.6, 1.7),
                Blob(14.2, 2.8, 1.7, 2.6, angle: -0.6), Blob(10.8, 3.2, 1.6, 2.4, angle: -0.8), Blob(2.6, 18.4, 1.3, 1.1),
            ],
            whites: [Blob(12.2, 12.8, 2.4, 3.2), Blob(10.0, 17.8, 3.0, 1.0), Blob(17.1, 8.0, 2.6, 1.5), Blob(5.2, 18.6, 3.2, 1.4)],
            legs: [
                [(11.8, 11.4 - paws), (18.2, 12.8 - paws)], [(10.8, 11.0 - paws), (17.2, 12.0 - paws)],
                [(7.8, 19.0), (11.4, 20)], [(6.6, 19.2), (10.2, 20)],
            ]
        )
        (form.face, form.mouth) = (face, mouth)
        return form.earsTurned(near: ears.near, far: ears.far).moved(sittingShift, 0)
    }

    // MARK: Lying

    /// Lying with its chin on its front paws, which are stretched out in front of it, the hind legs folded, the ears relaxed.
    static func lieForm(breath: Double = 0, face: Face = .open, ears: (near: Double, far: Double) = (0, 0)) -> Form {
        var form = Form(
            blobs: [
                Blob(7.2, 17.6, 4.8, 3.1), Blob(12.2, 17.9 - breath * 0.3, 5.6, 2.8 + breath * 0.3), Blob(16.4, 18.0, 3.0, 2.6),
                Blob(19.8, 16.2 + breath * 0.3, 3.9, 3.2), Blob(23.0, 17.8 + breath * 0.3, 2.4, 1.5),
                Blob(18.6, 13.0 + breath * 0.3, 1.7, 2.4, angle: -0.55), Blob(16.4, 13.8 + breath * 0.3, 1.6, 2.2, angle: -0.75), Blob(2.2, 17.2, 1.3, 1.2),
            ],
            whites: [Blob(16.4, 18.6, 2.4, 1.4), Blob(11.0, 19.9, 4.6, 0.8), Blob(23.1, 18.0 + breath * 0.3, 2.4, 1.2), Blob(5.0, 19.4, 3.0, 1.1)],
            legs: [[(15.0, 20.0), (26.2, 20.0)], [(13.6, 20.0), (24.4, 20.0)], [(7.0, 20.0), (10.4, 20.0)], [(5.8, 20.0), (9.2, 20.0)]]
        )
        form.face = face
        return form.earsTurned(near: ears.near, far: ears.far)
    }

    /// Asleep on its side: lower and flatter than lying with its chin on its paws, the head on the floor, the legs stretched out.
    static func sleepForm(breath: Double = 0) -> Form {
        var form = Form(
            blobs: [
                Blob(7.2, 18.0, 4.8, 2.8), Blob(12.2, 18.3 - breath * 0.3, 5.6, 2.5 + breath * 0.3), Blob(16.6, 18.4, 3.0, 2.3),
                Blob(19.8, 17.8 + breath * 0.2, 3.9, 2.9, angle: 0.12), Blob(23.0, 18.9 + breath * 0.2, 2.4, 1.3, angle: 0.15),
                Blob(18.2, 15.4, 1.7, 2.1, angle: -1.0), Blob(16.0, 16.0, 1.6, 2.0, angle: -1.2), Blob(2.2, 18.4, 1.3, 1.1),
            ],
            whites: [Blob(16.6, 18.9, 2.4, 1.4), Blob(11.0, 19.9, 4.6, 0.8), Blob(23.1, 19.2 + breath * 0.2, 2.4, 1.0), Blob(5.0, 19.5, 3.0, 1.1)],
            legs: [[(15.4, 20.0), (25.8, 20.0)], [(14.0, 20.0), (24.4, 20.0)], [(6.2, 20.0), (1.8, 20.0)], [(7.4, 20.0), (3.6, 20.0)]]
        )
        form.face = .blink
        return form
    }

    // MARK: Facing the viewer, and from behind

    /// Facing the viewer: the body is a round behind the head, the ears are up either side of it, the white muzzle and chest are in the
    /// middle and the front legs are side by side.
    static func frontForm(face: Face = .open, mouth: Mouth = .shut, lift: Double = 0) -> Form {
        var form = Form(
            blobs: [
                Blob(14.5, 14.2, 5.6, 4.2), Blob(14.5, 14.2, 5.0, 3.6), Blob(14.5, 14.6, 3.2, 3.2),
                Blob(14.5, 8.8, 4.4, 3.6), Blob(14.5, 10.6, 2.5, 1.7),
                Blob(18.2, 4.2, 1.8, 2.8, angle: 0.2), Blob(10.8, 4.2, 1.8, 2.8, angle: -0.2), Blob(14.5, 14.0, 0.8, 0.8),
            ],
            whites: [Blob(14.5, 15.2, 2.8, 3.0), Blob(14.5, 17.2, 3.0, 0.8), Blob(14.5, 10.9, 2.7, 2.0), Blob(14.5, 17.4, 4.0, 1.0)],
            legs: [[(16.6, 17.8), (16.8, 20)], [(12.2, 17.8), (12.0, 20)], [(19.0, 18.0), (19.4, 20)], [(10.0, 18.0), (9.6, 20)]]
        )
        form.aspect = .front
        (form.face, form.mouth) = (face, mouth)
        return lift == 0 ? form : form.moved(0, -lift)
    }

    /// From behind: the big round of the rear with the stub of a tail on it, the ears up over the back of the head, the hind paws.
    static func backForm() -> Form {
        var form = Form(
            blobs: [
                Blob(14.5, 14.4, 5.8, 4.6), Blob(14.5, 12.4, 4.8, 3.6), Blob(14.5, 12.0, 2.0, 2.0),
                Blob(14.5, 8.6, 4.2, 3.4), Blob(14.5, 9.4, 1.2, 1.0),
                Blob(18.0, 4.2, 1.8, 2.8, angle: 0.2), Blob(11.0, 4.2, 1.8, 2.8, angle: -0.2), Blob(14.5, 11.6, 1.5, 1.2),
            ],
            whites: [Blob(14.5, 12.4, 0.8, 0.8), Blob(14.5, 17.6, 5.0, 1.0), Blob(14.5, 9.4, 0.8, 0.8), Blob(14.5, 16.4, 4.4, 1.9)],
            legs: [[(17.6, 18.0), (17.8, 20)], [(11.4, 18.0), (11.2, 20)], [(17.6, 18.0), (17.8, 20)], [(11.4, 18.0), (11.2, 20)]]
        )
        form.aspect = .back
        form.face = .hidden
        return form
    }
}
