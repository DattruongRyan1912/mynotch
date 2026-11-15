import Foundation

extension PenguinArt {
    /// Every move as its pictures, and how they are played. Built when asked for, a move at a time, as the cat's are.
    static func animation(for move: PenguinMove) -> PixelAnimation {
        PixelAnimation(frames: frames(for: move), fps: move.fps, loops: move.loops, advance: move.advance)
    }

    private static func frames(for move: PenguinMove) -> [PixelFrame] {
        switch move {
        case .stand: (0..<4).map { stand(breath: $0 / 2, face: $0 == 3 ? .blink : .open) }
        case .blink: [stand(face: .blink)]
        case .flap: flapFrames
        case .waddle: waddleFrames
        case .lookTurn: lookTurnFrames
        case .lookFlap: lookFlapFrames
        case .lookBack: Array(lookTurnFrames.reversed())
        case .happy: happyFrames
        case .getUp: getUpFrames
        case .untuck: Array(tuckFrames.reversed())
        case .reel: Array(castFrames.reversed())
        case .bellyDown: bellyDownFrames
        case .slide: slideFrames
        case .lie: lieFrames
        case .slip: slipFrames
        case .dazed: dazedFrames
        case .tuck: tuckFrames
        case .tucked: tuckedFrames
        case .sleep: sleepFrames
        case .cast: castFrames
        case .fish: fishFrames
        case .bite: biteFrames
        case .pull: pullFrames
        case .gulp: gulpFrames
        case .fishHappy: fishHappyFrames
        }
    }

    /// The standing penguin with its eyes open and shut: what one that does not move at all (Reduce Motion) shows.
    static var restingFrames: [PixelFrame] { [stand(), stand(face: .blink)] }

    // MARK: Small tools

    /// `letter` on a finished picture at a place of the board: the rim has moved everything a pixel.
    static func put(_ letter: Character, atX x: Int, y: Int, on frame: inout PixelFrame) {
        guard (0..<CatCanvas.width).contains(x), (-1..<CatCanvas.height).contains(y) else { return }
        frame = frame.setting(letter, atX: x + 1, y: y + 1)
    }

    /// The pixels of a straight line from one place to another, ends included.
    static func linePixels(from a: Point, to b: Point) -> [(x: Int, y: Int)] {
        let steps = max(Int(max(abs(b.x - a.x), abs(b.y - a.y)).rounded(.up)), 1)
        var seen: [(x: Int, y: Int)] = []
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let p = (x: Int((a.x + (b.x - a.x) * t).rounded()), y: Int((a.y + (b.y - a.y) * t).rounded()))
            if !seen.contains(where: { $0 == p }) { seen.append(p) }
        }
        return seen
    }

    // MARK: Standing

    /// The beak, relative to the middle of the head: a long top and a shorter, darker bottom.
    static let beakRows: [(Double, Double, Character)] = [
        (4, 0, "O"), (5, 0, "O"), (6, 0, "O"), (7, 0, "O"), (4, 1, "o"), (5, 1, "o"), (6, 1, "o"),
    ]

    /// What a standing penguin is made of. `tilt` is how far it leans over its feet, in degrees (forward is more), `lean` how far its head
    /// is forward of that, `headDown` how low the head is held, `tuck` how far the head is down in its shoulders (0 to 1), `breath` a row
    /// of the head's, `arm` how far its near flipper is swung back from hanging (degrees), or `armTip` where it is held if it is held out,
    /// `near` and `far` where its feet are (how far forward, and how high off the ground), and `shift` how far the whole of it is
    /// moved on the board.
    static func standRig(
        breath: Int = 0, tilt: Double = 0, lean: Double = 0, headDown: Double = 0, tuck: Double = 0, arm: Double = 24, armLength: Double = 7.0,
        armTip: Point? = nil, near: (x: Double, lift: Double) = (0, 0), far: (x: Double, lift: Double) = (0, 0), shift: Point = (0, 0),
        face: Face = .open, lift: Int = 0, extras: @escaping (inout CatCanvas) -> Void = { _ in },
        after: @escaping (inout PixelFrame) -> Void = { _ in }
    ) -> Rig {
        let rad = tilt * .pi / 180
        let drop = Double(breath) * 0.8 + headDown + tuck * 2.6
        func moved(_ blob: Blob) -> Blob { Blob(blob.cx + shift.x, blob.cy + shift.y, blob.rx, blob.ry, angle: blob.angle, fill: blob.fill) }
        func place(_ point: Point) -> Point {
            let turned = turn(point, rad, about: pivot)
            return (turned.x + shift.x, turned.y + shift.y)
        }
        let headAt = (x: 14.2 + lean - tuck * 0.7, y: 7.8 + drop)
        let head = moved(Blob(headAt.x, headAt.y, 4.0 - tuck * 0.2, 3.6 - tuck * 0.4).turned(rad))
        let body = [
            moved(Blob(13.0 + lean * 0.4, 14.0, 5.5, 6.0).turned(rad)), head, moved(Blob(7.5, 18.8, 2.3, 1.3, angle: -0.35).turned(rad)),
        ]
        let belly = [
            moved(Blob(16.2 + lean * 0.5, 14.8, 4.3, 5.0).turned(rad)),
            moved(Blob(16.4 + lean - tuck * 1.2, 9.6 + drop, 2.7, 2.3 - tuck * 0.3).turned(rad)),
        ]
        let feet = [
            moved(Blob(10.8 + far.x, ground - far.lift, 2.3, 0.9, fill: "o")), moved(Blob(15.8 + near.x, ground - near.lift, 2.7, 0.95, fill: "O")),
        ]
        let shoulder = place((11.8 + lean * 0.4, 10.6))
        var tip: Point
        if let armTip {
            tip = armTip
        } else {
            let swing = arm * .pi / 180
            tip = (x: shoulder.x - armLength * sin(swing), y: shoulder.y + armLength * cos(swing))
        }
        func at(_ dx: Double, _ dy: Double) -> (Int, Int) {
            let p = place((headAt.x + dx, headAt.y + dy))
            return (Int(p.x.rounded(.down)), Int(p.y.rounded(.down)))
        }
        var pixels: [Pixel] = []
        for (dx, dy, letter) in tuck > 0.8 ? tuckedBeak : beakRows {
            let p = at(dx, dy)
            pixels.append(Pixel(x: p.0, y: p.1, letter: letter))
        }
        var marks: [Pixel] = []
        switch face {
        case .open:
            let (a, b) = (at(0.8, -2.0), at(1.8, -2.0))
            marks = [Pixel(x: a.0, y: a.1, letter: "E"), Pixel(x: b.0, y: b.1, letter: "K")]
        case .happy:
            let (a, b, c) = (at(-0.2, -1.2), at(0.8, -2.2), at(1.8, -1.2))
            marks = [Pixel(x: a.0, y: a.1, letter: "E"), Pixel(x: b.0, y: b.1, letter: "E"), Pixel(x: c.0, y: c.1, letter: "E")]
        default: break
        }
        return Rig(
            body: body, belly: belly, feet: feet, flippers: [Flipper(points: [shoulder, tip])], pixels: pixels, marks: marks, extras: extras,
            after: after, lift: lift
        )
    }

    /// The beak of a head that is tucked in: the tip of it, pointing down into its chest.
    static let tuckedBeak: [(Double, Double, Character)] = [(3.3, 1.0, "O"), (4.3, 1.0, "O"), (4.3, 2.0, "o")]

    static func stand(
        breath: Int = 0, face: Face = .open, arm: Double = 24, lift: Int = 0, extras: @escaping (inout CatCanvas) -> Void = { _ in }
    ) -> PixelFrame {
        draw(standRig(breath: breath, arm: arm, face: face, lift: lift, extras: extras))
    }

    /// Rocking from one foot to the other: over to the front, upright, over to the back, upright, a step to a rock, the near flipper
    /// swinging against the feet.
    static var waddleFrames: [PixelFrame] {
        let steps: [(tilt: Double, near: (x: Double, lift: Double), far: (x: Double, lift: Double), arm: Double)] = [
            (7, (2.2, 0), (-1.8, 1), 40), (3, (1, 1), (-0.6, 0), 28), (-5, (-1.2, 0), (1.6, 0), 12),
            (-7, (-2.2, 0), (1.8, 1), 4), (-3, (-1, 1), (0.6, 0), 14), (5, (1.2, 0), (-1.6, 0), 34),
        ]
        return steps.map { step in draw(standRig(tilt: step.tilt, arm: step.arm, near: step.near, far: step.far)) }
    }

    /// Flapping its flippers: the near one up and back and down again, quicker than anything else it does, its head up.
    static var flapFrames: [PixelFrame] {
        [24.0, 62, 112, 70, 120, 44].enumerated().map { index, arm in draw(standRig(breath: index % 2, arm: arm, armLength: 7.4)) }
    }

    // MARK: Facing the viewer

    /// The penguin turned `turn` of the way (0 side on, facing right; 1 facing the viewer): a blend of the one and the other, with the
    /// flippers `arms` out (degrees from hanging, left and right as the viewer sees it), `lift` rows up, and `crouch` rows down.
    static func frontRig(
        turn t: Double, arms: (left: Double, right: Double) = (12, 12), lift: Int = 0, crouch: Double = 0, face: Face = .front, breath: Int = 0,
        extras: @escaping (inout CatCanvas) -> Void = { _ in }
    ) -> Rig {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        let down = crouch + Double(breath) * 0.6
        let head = Blob(mix(14.2, 15.0), 7.8 + down, mix(4.0, 4.4), 3.6)
        var body = [Blob(mix(13.0, 15.0), 14.0 + down * 0.5, mix(5.5, 6.2), 6.0 - crouch * 0.3), head]
        if t < 0.7 { body.append(Blob(mix(7.5, 11.0), 18.8, 2.3, 1.3, angle: -0.35)) }
        let belly = [Blob(mix(16.2, 15.0), 14.8 + down * 0.4, mix(4.3, 3.9), 5.0), Blob(mix(16.4, 15.0), 9.6 + down, mix(2.7, 3.2), mix(2.3, 2.3))]
        let feet = [Blob(mix(10.8, 11.4), ground, 2.4, 0.9, fill: mix(0, 1) > 0.5 ? "O" : "o"), Blob(mix(15.8, 18.6), ground, 2.5, 0.95, fill: "O")]
        let (hx, hy) = (head.cx, head.cy)
        func at(_ dx: Double, _ dy: Double) -> Pixel { Pixel(x: Int((hx + dx).rounded(.down)), y: Int((hy + dy).rounded(.down)), letter: ".") }
        var pixels: [Pixel] = []
        let beak: [(Double, Double, Character)]
        if t < 0.5 {
            beak = [(4, 0, "O"), (5, 0, "O"), (6, 0, "O"), (4, 1, "o"), (5, 1, "o")]
        } else if t < 0.9 {
            beak = [(1.5, 1, "O"), (2.5, 1, "O"), (3.5, 1, "O"), (1.5, 2, "o"), (2.5, 2, "o")]
        } else {
            beak = [(-0.5, 1, "O"), (0.5, 1, "O"), (-0.5, 2, "o"), (0.5, 2, "o")]
        }
        for (dx, dy, letter) in beak {
            let p = at(dx, dy)
            pixels.append(Pixel(x: p.x, y: p.y, letter: letter))
        }
        var marks: [Pixel] = []
        func mark(_ dx: Double, _ dy: Double, _ letter: Character) {
            let p = at(dx, dy)
            marks.append(Pixel(x: p.x, y: p.y, letter: letter))
        }
        switch face {
        case .front:
            if t < 0.5 {
                mark(0.8, -2, "E"); mark(1.8, -2, "K")
            } else if t < 0.9 {
                mark(-0.6, -2, "E"); mark(-0.6, -1, "K"); mark(2.4, -2, "E"); mark(2.4, -1, "K")
            } else {
                mark(-3.0, -2, "E"); mark(-3.0, -1, "K"); mark(2.0, -2, "E"); mark(2.0, -1, "K")
            }
        case .frontHappy:
            for (dx, dy) in [(-3.0, -1.0), (-2.0, -2.0), (-1.0, -1.0), (1.0, -1.0), (2.0, -2.0), (3.0, -1.0)] { mark(dx, dy, "E") }
        default: break
        }
        let hang = { (degrees: Double) -> Double in degrees * .pi / 180 }
        var flippers: [Flipper] = []
        let leftShoulder = (x: mix(11.8, 9.4), y: 10.8 + down * 0.5), rightShoulder = (x: 20.6, y: 10.8 + down * 0.5)
        flippers.append(Flipper(points: [leftShoulder, (leftShoulder.x - 7 * sin(hang(arms.left)), leftShoulder.y + 7 * cos(hang(arms.left)))]))
        if t >= 0.6 {
            flippers.append(Flipper(points: [rightShoulder, (rightShoulder.x + 7 * sin(hang(arms.right)), rightShoulder.y + 7 * cos(hang(arms.right)))]))
        }
        return Rig(body: body, belly: belly, feet: feet, flippers: flippers, pixels: pixels, marks: marks, extras: extras, lift: lift)
    }

    /// Turning from side on to face the viewer, in three pictures; the way back is the same pictures the other way.
    static var lookTurnFrames: [PixelFrame] {
        [draw(frontRig(turn: 0.3, face: .front)), draw(frontRig(turn: 0.7, face: .front)), draw(frontRig(turn: 1, face: .front))]
    }

    /// Facing the viewer and flapping: two quick flaps and a rest, so that it looks pleased without being in a state.
    static var lookFlapFrames: [PixelFrame] {
        [(12.0, 12.0), (70, 70), (128, 128), (70, 70), (128, 128), (40, 40)].enumerated().map { index, arms in
            draw(frontRig(turn: 1, arms: arms, face: index == 5 ? .frontBlink : .front, breath: index == 5 ? 1 : 0))
        }
    }

    /// A heart small enough for the room beside its head.
    static let smallHeart = ["H.H", "HHH", ".H."]

    /// A jump for joy facing the viewer, its flippers up and a heart that goes up over it.
    static var happyFrames: [PixelFrame] {
        let steps: [(arms: Double, lift: Int, crouch: Double, heart: Int?)] = [
            (30, 0, 1.2, nil), (100, 2, 0, nil), (140, 3, 0, 1), (140, 3, 0, 2), (90, 1, 0, 3), (40, 0, 0.8, nil),
        ]
        return steps.map { step in
            draw(frontRig(turn: 1, arms: (step.arms, step.arms), lift: step.lift, crouch: step.crouch, face: .frontHappy) { canvas in
                if let heart = step.heart { canvas.piece(smallHeart, x: 22, y: 3 - heart + step.lift) }
            })
        }
    }
}
