import Foundation

extension HamsterArt {
    /// Every move as its pictures, and how they are played. Built when asked for, a move at a time, as the cat's are.
    static func animation(for move: HamsterMove) -> PixelAnimation {
        PixelAnimation(frames: frames(for: move), fps: move.fps, loops: move.loops, advance: move.advance)
    }

    private static func frames(for move: HamsterMove) -> [PixelFrame] {
        switch move {
        case .sit: (0..<4).map { sit(breath: $0 / 2, face: $0 == 3 ? .blink : .open) }
        case .blink: [sit(face: .blink)]
        case .groom: groomFrames
        case .freeze: freezeFrames()
        case .happy: happyFrames()
        case .stuffA: stuffFrames(level: 1)
        case .stuffB: stuffFrames(level: 2)
        case .stuffC: stuffFrames(level: 3)
        case .puffed: puffedFrames
        case .unstuff: unstuffFrames
        case .curl: curlFrames
        case .uncurl: Array(curlFrames.reversed())
        case .ball: (0..<2).map { draw(ballRig(1, breath: Double($0), face: .sleep)) }
        case .sleep: sleepFrames
        case .scurry: scurryFrames
        case .sitDown: sitDownFrames
        case .standUp: Array(sitDownFrames.reversed())
        case .hopIn: hopInFrames
        case .hopOut: Array(hopInFrames.reversed())
        case .wheelSit: (0..<2).map { sit(breath: $0, lift: wheelRise) }
        case .wheelLazy: runFrames(.lazy)
        case .wheelJog: runFrames(.jog)
        case .wheelRun: runFrames(.run)
        case .wheelSprint: runFrames(.sprint)
        case .wheelWatch: freezeFrames(lift: wheelRise)
        case .wheelHappy: happyFrames(lift: wheelRise, height: 2, hearts: false)
        }
    }

    /// The sitting hamster with its eyes open and shut: what one that does not move at all (Reduce Motion) shows.
    static var restingFrames: [PixelFrame] { [sit(), sit(face: .blink)] }

    // MARK: Sitting up

    /// Where its head is when it sits: a row lower for each `breath`, lower and further forward when it crouches, leans or looks down.
    static func sitHead(breath: Int = 0, crouch: Double = 0, lean: Double = 0, down: Double = 0) -> Blob {
        Blob(17.2 + lean, 11.6 + Double(breath) + 1.8 * crouch + down, 3.9, 3.4)
    }

    /// Sitting up like a potato, its paws on its chest. `crouch` squashes it down to spring, `lean` and `down` put the head forward and
    /// lower, `cheeks` is how full the pouches are.
    static func sitRig(
        breath: Int = 0, crouch: Double = 0, lean: Double = 0, down: Double = 0, cheeks: Int = 0, face: Face = .open, lift: Int = 0,
        paws chest: Bool = true, inWheel: Bool = false, extras: @escaping (inout CatCanvas) -> Void = { _ in }
    ) -> Rig {
        let head = sitHead(breath: breath, crouch: crouch, lean: lean, down: down)
        let feet = [Blob(17.0 + lean * 0.3, 20, 2.3, 0.95, fill: "P"), Blob(10.4, 20, 2.3, 0.95, fill: "D")]
        return Rig(
            body: Blob(13.8 + lean * 0.3, 16.5 + 0.9 * crouch, 5.0 + 0.5 * crouch, 4.4 - 0.9 * crouch),
            head: head,
            cheeks: cheeks,
            face: face,
            paws: inWheel ? feet.map(curved) : feet,
            ears: [ear(on: head)],
            lift: lift,
            extras: { canvas in
                // Both paws on its chest, under its chin.
                if chest { canvas.piece(["PP"], x: Int((head.cx - 0.4).rounded()), y: Int((head.cy + 3.9).rounded())) }
                extras(&canvas)
            }
        )
    }

    static func sit(
        breath: Int = 0, cheeks: Int = 0, face: Face = .open, lift: Int = 0, extras: @escaping (inout CatCanvas) -> Void = { _ in }
    ) -> PixelFrame {
        draw(sitRig(breath: breath, cheeks: cheeks, face: face, lift: lift, inWheel: lift == wheelRise, extras: extras))
    }

    /// Washing its face: both paws going over it, its eyes shut when they are up.
    static var groomFrames: [PixelFrame] {
        (0..<4).map { index in
            let head = sitHead(down: 0.5)
            let up = index % 2 == 1
            let rig = sitRig(down: 0.5, face: up ? .blink : .open, paws: false) { canvas in
                canvas.piece(["PP", "PP"], x: Int((head.cx + (up ? 1.2 : 0.2)).rounded()), y: Int((head.cy + (up ? -1.2 : 0.6)).rounded()))
                canvas.piece(["K"], x: Int((head.cx + (up ? 1.2 : 0.2)).rounded()) + 2, y: Int((head.cy + (up ? -0.2 : 1.6)).rounded()))
            }
            return draw(rig)
        }
    }

    /// Up and alert, facing the viewer with both ears up, its nose going: it has seen something.
    static func freezeFrames(lift: Int = 0) -> [PixelFrame] {
        (0..<2).map { index in
            let head = Blob(15.4, 10.9, 4.3, 3.5)
            var rig = sitRig(breath: -1, face: .front, lift: lift, inWheel: lift == wheelRise)
            rig.head = head
            rig.ears = [ear(on: head, shift: -0.6), ear(on: head, shift: 3.3)]
            rig.twitch = index == 1
            return draw(rig)
        }
    }

    /// A happy hop on the spot: down, up with its eyes shut, a heart that goes up over it, and down again.
    static func happyFrames(lift: Int = 0, height: Int = 4, hearts: Bool = true) -> [PixelFrame] {
        let steps: [(crouch: Double, up: Int, face: Face, heart: Int?)] = [
            (1, 0, .open, nil), (0, height / 2, .happy, nil), (0, height, .happy, 1), (0, height / 2 + 1, .happy, 2), (0.6, 0, .happy, 3), (0, 0, .happy, 4),
        ]
        return steps.map { step in
            draw(sitRig(crouch: step.crouch, face: step.face, lift: lift + step.up, inWheel: lift == wheelRise && step.up == 0) { canvas in
                // The heart is where it is on the finished picture: it goes up with the hamster and stays a little above it.
                if hearts, let heart = step.heart { canvas.piece(CatArt.heart, x: 4, y: 6 - heart + lift + step.up) }
            })
        }
    }

    // MARK: Cheeks

    /// A sunflower seed: a little pear with a stripe.
    static let seed = ["SVVS", ".SS."]

    /// Taking a seed from the pile, bringing it to its mouth, nibbling and stuffing it in a cheek: the cheek is one size fuller than it was
    /// at the beginning when it is over.
    static func stuffFrames(level: Int) -> [PixelFrame] {
        let before = level - 1
        let stages: [(lean: Double, down: Double, cheeks: Int, face: Face)] = [
            (1.2, 1.2, before, .open), (1.2, 1.6, before, .open), (0.6, 0.4, before, .open), (0.3, 0.2, before, .blink),
            (0, 0, level, .open), (0, 0, level, .happy),
        ]
        return stages.enumerated().map { index, stage in
            let head = sitHead(lean: stage.lean, down: stage.down)
            return draw(sitRig(lean: stage.lean, down: stage.down, cheeks: stage.cheeks, face: stage.face, paws: index >= 4) { canvas in
                switch index {
                case 0: canvas.piece(["PP"], x: 20, y: 17)
                case 1:
                    canvas.piece(["PP"], x: 19, y: 17)
                    canvas.piece(seed, x: 21, y: 17)
                case 2:
                    canvas.piece(["PP"], x: Int((head.cx + 0.4).rounded()), y: Int((head.cy + 3.0).rounded()))
                    canvas.piece(seed, x: Int((head.cx + 2.6).rounded()), y: Int((head.cy + 2.0).rounded()))
                case 3:
                    canvas.piece(["PP"], x: Int((head.cx + 0.8).rounded()), y: Int((head.cy + 3.0).rounded()))
                    canvas.piece(["SV"], x: Int((head.cx + 3.0).rounded()), y: Int((head.cy + 2.0).rounded()))
                default: break
                }
            })
        }
    }

    /// Sitting with its cheeks full, looking about, pleased with itself.
    static var puffedFrames: [PixelFrame] {
        [sit(breath: 0, cheeks: 3), sit(breath: 1, cheeks: 3), sit(breath: 1, cheeks: 3, face: .blink), sit(breath: 0, cheeks: 3, face: .happy)]
    }

    /// The cheeks going down, a size at a time.
    static var unstuffFrames: [PixelFrame] {
        [(3, Face.happy), (2, .happy), (1, .open), (0, .open), (0, .happy)].map { sit(cheeks: $0.0, face: $0.1) }
    }

    // MARK: Curling up

    /// Between sitting up (`t` 0) and a ball (`t` 1): the head tucks in under it, and the back rounds.
    static func ballRig(_ t: Double, breath: Double = 0, face: Face = .open, extras: @escaping (inout CatCanvas) -> Void = { _ in }) -> Rig {
        func mix(_ from: Double, _ to: Double) -> Double { from + (to - from) * t }
        let head = Blob(mix(17.2, 19.2), mix(11.6, 16.6), mix(3.9, 3.0), mix(3.4, 2.7))
        return Rig(
            body: Blob(mix(13.8, 14.0), mix(16.5, 15.7), mix(5.0, 6.0) + breath * 0.5, mix(4.4, 5.2) + breath * 0.45),
            head: head,
            face: face,
            paws: [Blob(mix(17.0, 19.0), 20, mix(2.3, 1.8), 0.95, fill: "P"), Blob(mix(10.4, 9.4), 20, mix(2.3, 1.8), 0.95, fill: "D")],
            ears: [ear(on: head, shift: t * 0.4)],
            extras: extras
        )
    }

    static var curlFrames: [PixelFrame] {
        [0.25, 0.5, 0.78, 1.0].map { draw(ballRig($0, face: $0 > 0.7 ? .blink : .open)) }
    }

    /// Asleep in a ball, breathing, with a sleeper's z's going up.
    static var sleepFrames: [PixelFrame] {
        let zeds: [[(x: Int, y: Int)]] = [[(21, 8)], [(21, 7), (25, 3)], [(25, 4)], [(21, 8), (25, 5)]]
        return (0..<4).map { index in
            draw(ballRig(1, breath: index % 2 == 0 ? 0 : 1, face: .sleep) { canvas in
                for zed in zeds[index] { canvas.piece(CatArt.zed, x: zed.x, y: zed.y) }
            })
        }
    }

    // MARK: On its feet

    /// Where its paws are in a stride, at `phase` (0 to 1): four small paws under a long low body.
    static func paws(phase: Double, stride: Double = 1.8, lift: Double = 1.4) -> [Blob] {
        func paw(_ hip: Double, _ offset: Double, far: Bool) -> Blob {
            let foot = CatArt.foot(phase: phase + offset, hipX: hip, stride: stride, lift: lift, ground: 19.6)
            return Blob(foot.x, foot.y, 1.3, 0.95, fill: far ? "D" : "P")
        }
        return [paw(9.5, 0, far: true), paw(16.5, 0.5, far: true), paw(11.5, 0.5, far: false), paw(18.4, 0, far: false)]
    }

    /// The paw, no lower than the inside of the ring is where it is: a hamster in a wheel stands on a curve, and its feet that are away from
    /// the middle are higher. (The drawing is a row higher in the wheel, which is allowed for.)
    static func curved(_ paw: Blob) -> Blob {
        let across = paw.cx - HamsterProps.ringCentre.x
        let radius = HamsterProps.ringRadius - 2.2
        let floor = HamsterProps.ringCentre.y + (max(radius * radius - across * across, 0)).squareRoot() + Double(wheelRise) - paw.ry - 0.2
        return Blob(paw.cx, min(paw.cy, floor), paw.rx, paw.ry, fill: paw.fill)
    }

    /// Standing on its four feet. `bob` is a row higher, `stretch` is how far it is stretched out forward, `down` how low its head is.
    static func standRig(
        paws: [Blob], bob: Double = 0, stretch: Double = 0, down: Double = 0, face: Face = .open, lift: Int = 0,
        extras: @escaping (inout CatCanvas) -> Void = { _ in }
    ) -> Rig {
        let head = Blob(18.8 + stretch * 0.8, 14.6 - bob + down, 3.5, 3.1)
        return Rig(
            body: Blob(13.4 - stretch * 0.4, 15.4 - bob + down * 0.5, 5.6 + stretch * 0.4, 3.6),
            head: head,
            face: face,
            paws: paws,
            ears: [ear(on: head, shift: 0.2)],
            lift: lift,
            extras: extras
        )
    }

    static var stillPaws: [Blob] { paws(phase: 0.25, stride: 0, lift: 0) }

    static var scurryFrames: [PixelFrame] {
        (0..<6).map { draw(standRig(paws: paws(phase: Double($0) / 6), bob: $0 % 3 == 1 ? 0.8 : 0)) }
    }

    /// Up from four feet onto its haunches, which is the way to sit; the way to stand is the same pictures the other way.
    static var sitDownFrames: [PixelFrame] {
        let mid = Rig(
            body: Blob(13.6, 16.0, 5.3, 4.3),
            head: Blob(17.8, 12.9, 3.8, 3.3),
            paws: [Blob(17.0, 20, 2.3, 0.95, fill: "P"), Blob(10.4, 20, 2.3, 0.95, fill: "D")],
            ears: [ear(on: Blob(17.8, 12.9, 3.8, 3.3))]
        )
        return [draw(standRig(paws: stillPaws)), draw(mid), sit()]
    }

    // MARK: In and out of the wheel

    /// Springing from sitting up over the ring into the wheel: down to spring, up and over, tucked at the top, down inside it. The way out is
    /// the same pictures the other way.
    static var hopInFrames: [PixelFrame] {
        [
            draw(sitRig(crouch: 1)),
            draw(sitRig(crouch: 0, lean: 1.2, lift: 2)),
            draw(sitRig(crouch: 0.2, lean: 1.6, down: 0.6, lift: 4, paws: false)),
            draw(sitRig(crouch: 0.8, lift: wheelRise, inWheel: true)),
        ]
    }

    // MARK: Running in the wheel

    /// A pace of running: how far it strides, how high it lifts its feet, how stretched out and low it runs, how much it bobs. The faster
    /// it goes, the more of each, and the lines over its back that say so.
    static func runFrames(_ pace: WheelPace) -> [PixelFrame] {
        let (stride, lift, stretch, down, bob): (Double, Double, Double, Double, Double) = switch pace {
        case .lazy: (1.3, 1.0, 0, 0, 0.5)
        case .jog: (1.8, 1.4, 0.2, 0.1, 0.6)
        case .run: (2.3, 1.8, 0.7, 0.4, 0.8)
        case .sprint: (2.9, 2.2, 1.3, 0.9, 1.0)
        }
        return (0..<4).map { index in
            draw(standRig(
                paws: paws(phase: Double(index) / 4, stride: stride, lift: lift).map(curved), bob: index % 2 == 1 ? bob : 0, stretch: stretch, down: down,
                lift: wheelRise
            ) { canvas in
                guard pace >= .run else { return }
                let lines = [(8, 8, 3), (6, 10, 2), (9, 12, 2)]
                for (row, line) in lines.enumerated() where pace == .sprint || row == 0 {
                    canvas.piece([String(repeating: "X", count: line.2)], x: line.0 - (index + row) % 3, y: line.1 + (index % 2))
                }
            })
        }
    }
}
