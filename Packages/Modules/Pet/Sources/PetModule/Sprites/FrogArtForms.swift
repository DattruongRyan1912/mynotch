import Foundation

extension FrogArt {
    enum Eyes {
        /// Looking ahead, looking up (at the pointer, at a moth), half shut, shut (a blink, asleep), glad.
        case open, up, half, shut, happy
    }

    enum Mouth {
        /// Shut, a little open, wide open.
        case shut, ajar, wide
    }

    /// How a frog is put together in one picture: the same blobs and strokes whatever it is doing, so that one way of sitting turns into
    /// another by moving the same numbers (`mixed`), and a move is a handful of them.
    struct Form {
        var body: Blob
        var head: Blob
        var eye: Blob
        var thigh: Blob
        var belly: Blob
        var chin: Blob
        /// The hind foot, folded flat on the ground under it; nil when the leg is stretched out (`hind`).
        var foot: Blob
        /// The hind leg stretched out behind it, from the hip to the toes, and the near front leg from the shoulder to the paw.
        var hind: [Point]
        var arm: [Point]
        /// How far the hind leg is stretched out: 0 folded (the thigh and the foot are drawn), 1 stretched (the stroke is).
        var stretch = 0.0
        /// The throat puffed out: the radius of it, 0 for none.
        var sac = 0.0
        var eyes = Eyes.open
        var mouth = Mouth.shut
        /// The tongue from the mouth to its tip; empty for none.
        var tongue: [Point] = []
        /// Rows the eye is pulled down into the head (a frog swallows with its eyes shut and sunk).
        var sink = 0.0

        /// The same moved by (`dx`, `dy`).
        func moved(_ dx: Double, _ dy: Double) -> Form {
            var form = self
            form.body = body.moved(dx, dy)
            form.head = head.moved(dx, dy)
            form.eye = eye.moved(dx, dy)
            form.thigh = thigh.moved(dx, dy)
            form.belly = belly.moved(dx, dy)
            form.chin = chin.moved(dx, dy)
            form.foot = foot.moved(dx, dy)
            form.hind = hind.map { ($0.x + dx, $0.y + dy) }
            form.arm = arm.map { ($0.x + dx, $0.y + dy) }
            form.tongue = tongue.map { ($0.x + dx, $0.y + dy) }
            return form
        }

        /// The whole frog turned `radians` (clockwise: nose down) about `pivot`.
        func turned(_ radians: Double, about pivot: Point) -> Form {
            guard radians != 0 else { return self }
            var form = self
            form.body = body.turned(radians, about: pivot)
            form.head = head.turned(radians, about: pivot)
            form.eye = eye.turned(radians, about: pivot)
            form.thigh = thigh.turned(radians, about: pivot)
            form.belly = belly.turned(radians, about: pivot)
            form.chin = chin.turned(radians, about: pivot)
            form.foot = foot.turned(radians, about: pivot)
            form.hind = hind.map { FrogArt.turn($0, radians, about: pivot) }
            form.arm = arm.map { FrogArt.turn($0, radians, about: pivot) }
            form.tongue = tongue.map { FrogArt.turn($0, radians, about: pivot) }
            return form
        }

        /// The head and the eye and the throat, with what goes with them, turned `radians` (clockwise: nose down) about the neck.
        func headTurned(_ radians: Double, about pivot: Point = FrogArt.neck) -> Form {
            guard radians != 0 else { return self }
            var form = self
            form.head = head.turned(radians, about: pivot)
            form.eye = eye.turned(radians, about: pivot)
            form.chin = chin.turned(radians, about: pivot)
            form.tongue = tongue.map { FrogArt.turn($0, radians, about: pivot) }
            return form
        }

        /// The head and what goes with it moved by (`dx`, `dy`).
        func headMoved(_ dx: Double, _ dy: Double) -> Form {
            var form = self
            form.head = head.moved(dx, dy)
            form.eye = eye.moved(dx, dy)
            form.chin = chin.moved(dx, dy)
            form.tongue = tongue.map { ($0.x + dx, $0.y + dy) }
            return form
        }

        /// The body and the hips lower or higher by `dy` with the feet left where they are (the crouch).
        func crouched(_ dy: Double) -> Form {
            var form = self
            form.body = body.moved(0, dy)
            form.thigh = thigh.moved(0, dy * 0.5)
            form.belly = belly.moved(0, dy)
            form.head = head.moved(0, dy)
            form.eye = eye.moved(0, dy)
            form.chin = chin.moved(0, dy)
            form.tongue = tongue.map { ($0.x, $0.y + dy) }
            return form
        }
    }

    /// Where its neck is: what the head turns about.
    static let neck: Point = (14.0, 15.0)
    /// Where its feet are, which is what it leans about.
    static let feet: Point = (12.0, 20.0)

    /// The form of sitting, side on, facing right: the back arched over a folded hind leg, the arm straight down, the eye on the top of the
    /// head. `breath` swells the body and the throat a little.
    static func sitForm(breath: Double = 0, eyes: Eyes = .open, mouth: Mouth = .shut) -> Form {
        Form(
            body: Blob(9.5, 15.5 - breath * 0.2, 6.8, 4.7 + breath * 0.25),
            head: Blob(16.2, 15.6, 5.3, 3.0),
            eye: Blob(15.3, 11.6, 2.5, 2.5),
            thigh: Blob(6.4, 16.6, 4.4, 3.4),
            belly: Blob(9.5, 19.4, 5.2, 2.1),
            chin: Blob(17.6, 18.2, 4.0, 1.5),
            foot: Blob(12.2, 19.5, 4.6, 1.2),
            hind: [(6.0, 16.0), (2.0, 19.5), (-1.0, 20.0)],
            arm: [(13.6, 17.5), (14.4, 20.0)],
            eyes: eyes,
            mouth: mouth
        )
    }

    /// A form as a rig: the blobs, the pale places, the legs and the face.
    static func rig(_ form: Form, lift: Int = 0, extras: @escaping (inout CatCanvas) -> Void = { _ in }) -> Rig {
        let sinking = form.sink
        let eye = form.eye.moved(0, sinking)
        var body = [form.body, form.head, eye]
        var pale = [form.belly, form.chin]
        let sac = form.sac
        if sac > 0 {
            // (Hanging in front of the chest, and no lower than the ground it sits on.)
            let blob = Blob(form.chin.cx + form.chin.rx * 0.45, min(form.chin.cy + 0.4 + sac * 0.35, FrogArt.ground + 0.9 - sac), sac * 1.15, sac)
            body.append(blob)
            pale.append(blob)
        }
        var legs: [Leg] = [Leg(points: form.arm)]
        if form.stretch < 0.5 {
            body += [form.foot]
            body += [form.thigh]
        } else {
            legs.append(Leg(points: form.hind))
        }
        var rig = Rig(body: body, pale: pale, thigh: form.stretch < 0.5 ? form.thigh : nil, legs: legs, tongue: form.tongue, lift: lift)
        rig.marks = face(form, eye: eye)
        rig.extras = extras
        return rig
    }

    /// The eye, the nostril and the mouth of the face the frog has on.
    private static func face(_ form: Form, eye: Blob) -> [Pixel] {
        var marks: [Pixel] = []
        let (ex, ey) = (Int(eye.cx.rounded(.down)), Int(eye.cy.rounded(.down)))
        func mark(_ dx: Int, _ dy: Int, _ letter: Character) { marks.append(Pixel(x: ex + dx, y: ey + dy, letter: letter)) }
        switch form.eyes {
        case .open:
            for dx in -1...1 { for dy in -1...1 { mark(dx, dy, "Y") } }
            mark(1, 0, "E")
        case .up:
            for dx in -1...1 { for dy in -1...1 { mark(dx, dy, "Y") } }
            mark(1, -1, "E")
        case .half:
            for dx in -1...1 { for dy in 0...1 { mark(dx, dy, "Y") } }
            mark(1, 0, "E")
            for dx in -1...1 { mark(dx, -1, "g") }
        case .shut:
            for dx in -1...1 { mark(dx, 0, "K") }
        case .happy:
            mark(-1, 0, "K")
            mark(0, -1, "K")
            mark(1, 0, "K")
        }
        // The nostril, on the top of the snout, and the line of the mouth from the corner of it to the tip of the snout.
        let head = form.head
        let (nx, ny) = (Int((head.cx + head.rx * 0.62).rounded(.down)), Int((head.cy - head.ry * 0.55).rounded(.down)))
        marks.append(Pixel(x: nx, y: ny, letter: "K"))
        let mouthY = head.cy + head.ry * 0.15
        let corner = head.cx - head.rx * 0.35
        let tip = head.cx + head.rx - 0.6
        let (left, right) = (Int(corner.rounded(.down)), Int(tip.rounded(.down)))
        let row = Int(mouthY.rounded(.down))
        switch form.mouth {
        case .shut:
            for x in left...right { marks.append(Pixel(x: x, y: row, letter: "K")) }
        case .ajar:
            for x in left...right { marks.append(Pixel(x: x, y: row, letter: "K")) }
            for x in (left + 2)...right { marks.append(Pixel(x: x, y: row + 1, letter: "T")) }
            for x in (left + 2)...right { marks.append(Pixel(x: x, y: row + 2, letter: "K")) }
        case .wide:
            for x in left...right { marks.append(Pixel(x: x, y: row - 1, letter: "K")) }
            for x in (left + 1)...right { marks.append(Pixel(x: x, y: row, letter: "T")) }
            for x in (left + 1)...right { marks.append(Pixel(x: x, y: row + 1, letter: "T")) }
            for x in (left + 1)...right { marks.append(Pixel(x: x, y: row + 2, letter: "K")) }
        }
        return marks
    }
}
