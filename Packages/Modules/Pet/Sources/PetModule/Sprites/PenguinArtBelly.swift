import Foundation

extension PenguinArt {
    // MARK: On its belly

    /// The penguin lying on its belly, head up and forward, feet sticking up behind, its flippers swept back along its sides. `breath` is how
    /// much it fills out, `headUp` how high the head is held, `wiggle` how far the near flipper is moved, `kick` how far the feet are, and
    /// `shift` moves the whole of it on the board.
    static func lieRig(
        breath: Double = 0, headUp: Double = 0, wiggle: Double = 0, kick: Double = 0, shift: Point = (0, 0), face: Face = .open,
        extras: @escaping (inout CatCanvas) -> Void = { _ in }, after: @escaping (inout PixelFrame) -> Void = { _ in }
    ) -> Rig {
        func moved(_ blob: Blob) -> Blob { Blob(blob.cx + shift.x, blob.cy + shift.y, blob.rx, blob.ry, angle: blob.angle, fill: blob.fill) }
        let headAt = (x: 21.6, y: 15.0 - headUp)
        let body = [
            moved(Blob(14.4, 16.6 - breath * 0.3, 8.2, 3.9 + breath * 0.35)), moved(Blob(headAt.x, headAt.y, 3.2, 3.2)),
            moved(Blob(6.6, 18.2, 2.0, 1.2, angle: 0.3)),
        ]
        let belly = [moved(Blob(14.8, 19.7, 8.0, 1.5)), moved(Blob(23.0, 16.8 - headUp, 1.8, 1.7))]
        let feet = [moved(Blob(5.4, 15.2 + kick, 1.1, 1.9, fill: "O")), moved(Blob(7.8, 14.6 - kick, 1.0, 1.7, fill: "o"))]
        let shoulder = (x: 17.6 + shift.x, y: 15.2 + shift.y)
        let tip = (x: 10.8 + wiggle + shift.x, y: 17.6 + shift.y)
        func at(_ dx: Double, _ dy: Double) -> (Int, Int) { (Int((headAt.x + shift.x + dx).rounded(.down)), Int((headAt.y + shift.y + dy).rounded(.down))) }
        var pixels: [Pixel] = []
        for (dx, dy, letter) in [(3.6, 0.0, Character("O")), (4.6, 0, "O"), (5.6, 0, "O"), (6.6, 0, "O"), (3.6, 1, "o"), (4.6, 1, "o"), (5.6, 1, "o")] {
            let p = at(dx, dy)
            pixels.append(Pixel(x: p.0, y: p.1, letter: letter))
        }
        var marks: [Pixel] = []
        switch face {
        case .open:
            let (a, b) = (at(0.8, -1.8), at(1.8, -1.8))
            marks = [Pixel(x: a.0, y: a.1, letter: "E"), Pixel(x: b.0, y: b.1, letter: "K")]
        case .happy:
            let (a, b, c) = (at(-0.2, -1.0), at(0.8, -2.0), at(1.8, -1.0))
            marks = [Pixel(x: a.0, y: a.1, letter: "E"), Pixel(x: b.0, y: b.1, letter: "E"), Pixel(x: c.0, y: c.1, letter: "E")]
        default: break
        }
        return Rig(
            body: body, belly: belly, feet: feet, flippers: [Flipper(points: [shoulder, tip])], pixels: pixels, marks: marks, extras: extras,
            after: after
        )
    }

    /// Flat on its belly, breathing, now and then with its eyes shut.
    static var lieFrames: [PixelFrame] {
        [draw(lieRig()), draw(lieRig(breath: 1, face: .blink))]
    }

    /// Gliding: flat out, the feet kicking, the flipper working, and lines behind it that go by faster than it does.
    static var slideFrames: [PixelFrame] {
        (0..<4).map { index in
            draw(lieRig(headUp: index % 2 == 0 ? 0.6 : 0, wiggle: [0, 1.2, 2.0, 0.8][index], kick: [0, 0.7, 0, -0.7][index], after: { frame in
                speedLines(index, on: &frame)
            }))
        }
    }

    /// Lines of snow over its back that go by to the left: three pixels at the time, each three pixels further on in every picture of four.
    static func speedLines(_ index: Int, on frame: inout PixelFrame) {
        for base in [4, 16, 28] {
            for dx in 0..<3 { put("T", atX: base - 3 * index + dx, y: 9, on: &frame) }
            for dx in 0..<2 { put("T", atX: base + 6 - 3 * index + dx, y: 7, on: &frame) }
        }
        put("T", atX: 0, y: 17 + index % 3, on: &frame)
        put("T", atX: 1, y: 20 - index % 2, on: &frame)
    }

    /// Down onto its belly: over its feet, further over, and flat with a puff of snow where it landed.
    static var bellyDownFrames: [PixelFrame] {
        [
            draw(standRig(tilt: 22, lean: 1.0, arm: -35, near: (1.5, 0), far: (1.0, 0))),
            draw(standRig(tilt: 56, lean: 1.0, arm: -60, near: (0, 0), far: (0, 0), shift: (-4.5, 0))),
            draw(lieRig(headUp: 0.5, after: { frame in
                for (x, y) in [(2, 20), (3, 19), (1, 18), (27, 20), (29, 19)] { put("T", atX: x, y: y, on: &frame) }
            })),
        ]
    }

    /// Up from its belly: the flippers push, it sits up on its tail, rocks forward onto its feet and stands. Ends as it stands.
    static var getUpFrames: [PixelFrame] {
        [
            draw(lieRig(headUp: 1.4, wiggle: -3)),
            draw(standRig(tilt: 52, lean: 0.8, arm: -50, shift: (-4.0, 0))),
            draw(standRig(tilt: 22, lean: 0.8, arm: -20, near: (1.0, 0), far: (0.6, 0), shift: (-0.6, 0))),
            stand(),
        ]
    }

    /// Tripping over its own feet and going down flat: the feet go from under it, the flippers windmill, it goes over, lands on its belly
    /// and bounces.
    static var slipFrames: [PixelFrame] {
        [
            draw(standRig(tilt: -8, lean: -0.6, arm: 120, near: (2.0, 1.5), far: (-1.0, 0))),
            draw(standRig(tilt: 20, lean: 1.0, arm: 150, near: (-1.5, 2), far: (-2.0, 2), shift: (-1.0, -0.4), face: .open, lift: 1)),
            draw(standRig(tilt: 52, lean: 1.0, arm: -70, near: (-1, 1), far: (-2, 1), shift: (-4.0, 0), lift: 0)),
            draw(lieRig(headUp: -0.4, kick: 1.0, after: { frame in
                for (x, y) in [(3, 19), (2, 17), (26, 20), (28, 18), (4, 20)] { put("T", atX: x, y: y, on: &frame) }
            })),
            draw(lieRig(headUp: 1.8, wiggle: 1, kick: -0.6)),
        ]
    }

    /// Lying there seeing stars: two of them going round over its head.
    static var dazedFrames: [PixelFrame] {
        (0..<4).map { index in
            let angle = Double(index) * .pi / 4
            return draw(lieRig(headUp: index % 2 == 0 ? 0 : 0.4, face: .open) { canvas in
                for turn in [0.0, .pi] {
                    let x = 21.6 + 4.2 * cos(angle + turn), y = 8.6 + 1.2 * sin(angle + turn)
                    canvas.outlinedPiece(star, x: Int((x - 1).rounded()), y: Int((y - 1).rounded()))
                }
            })
        }
    }

    /// A star, three pixels across.
    static let star = [".S.", "SSS", ".S."]

    // MARK: Asleep on its feet

    /// Pulling its head down into its shoulders, with its beak in its chest: three pictures; the way out is the same the other way.
    static var tuckFrames: [PixelFrame] {
        [draw(standRig(headDown: 0.4, tuck: 0.3)), draw(standRig(tilt: 2, headDown: 0.4, tuck: 0.7, face: .hidden)), draw(standRig(tilt: 3, tuck: 1, face: .hidden))]
    }

    /// Standing with its head tucked in, breathing.
    static var tuckedFrames: [PixelFrame] {
        (0..<2).map { draw(standRig(breath: $0, tilt: 3, tuck: 1, face: .hidden)) }
    }

    /// Asleep, tucked in, with a sleeper's z's going up.
    static var sleepFrames: [PixelFrame] {
        let zeds: [[(x: Int, y: Int)]] = [[(20, 6)], [(20, 5), (25, 1)], [(25, 2)], [(20, 6), (25, 3)]]
        return (0..<4).map { index in
            draw(standRig(breath: index % 2, tilt: 3, tuck: 1, face: .hidden) { canvas in
                for zed in zeds[index] { canvas.piece(CatArt.zed, x: zed.x, y: zed.y) }
            })
        }
    }
}
