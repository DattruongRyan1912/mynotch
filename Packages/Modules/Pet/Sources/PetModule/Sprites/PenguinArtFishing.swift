import Foundation

extension PenguinArt {
    // MARK: Fishing

    /// The column of the board its line comes down on: the hole in the ice, which `PenguinMove.holeReach` pixels on, has its middle there.
    static let lineColumn = 27
    /// The row the line goes down to, which is as far as the far lip of the hole.
    static let lineEnd = 17.0
    /// Where its flipper holds the rod when it is held out in front of it.
    static let grip: Point = (19.6, 12.2)
    /// Where the tip of the rod is when it waits.
    static let restingTip: Point = (27.0, 5.0)

    /// A fish hanging by its mouth from the line, head up (3 by 6); and one in its beak, tail out (5 by 3).
    static let hanging = [".F.", "FFF", "FfF", "FfF", ".F.", "F.F"]
    static let caught = ["F.FF", "FFFF", "F.FF"]

    /// The rod in a flipper held out, the line from its tip down to `lineTo` (nil for none), over the rim: a single pixel wide. `bend` is
    /// how far the middle of the rod is below the straight line from the grip to the tip, and `lift` how many rows the penguin is up.
    static func rod(grip: Point = grip, tip: Point = restingTip, bend: Double = 0, lineTo: Point? = (Double(lineColumn), lineEnd), lift: Int = 0)
        -> (inout PixelFrame) -> Void
    {
        { frame in
            let base = (x: grip.x, y: grip.y - Double(lift))
            let end = (x: tip.x, y: tip.y)
            let middle = (x: (base.x + end.x) / 2, y: (base.y + end.y) / 2 + bend)
            for pixel in linePixels(from: base, to: middle) + linePixels(from: middle, to: end) { put("J", atX: pixel.x, y: pixel.y, on: &frame) }
            guard let lineTo else { return }
            for pixel in linePixels(from: (end.x, end.y + 1), to: lineTo) { put("L", atX: pixel.x, y: pixel.y, on: &frame) }
        }
    }

    /// The penguin holding a rod out over the hole: its flipper forward, its head a little down towards the hole.
    static func fishRig(
        breath: Int = 0, tilt: Double = 0, headDown: Double = 0, lean: Double = 0, grip: Point = grip, tip: Point = restingTip, bend: Double = 0,
        lineTo: Point? = (Double(lineColumn), lineEnd), face: Face = .open, lift: Int = 0, extras: @escaping (inout CatCanvas) -> Void = { _ in }
    ) -> Rig {
        standRig(
            breath: breath, tilt: tilt, lean: lean, headDown: headDown, armTip: grip, face: face, lift: lift, extras: extras,
            after: rod(grip: grip, tip: tip, bend: bend, lineTo: lineTo, lift: lift)
        )
    }

    /// Swinging the rod out: back over its shoulder, up, out, and the line down in the hole. Ends as it waits; taking it in is the same
    /// the other way.
    static var castFrames: [PixelFrame] {
        [
            draw(fishRig(tilt: -3, grip: (16.6, 9.8), tip: (11.0, 2.5), lineTo: (10.0, 7.5))),
            draw(fishRig(grip: (18.2, 10.8), tip: (19.5, 1.5), lineTo: (21.0, 6.5))),
            draw(fishRig(tilt: 2, headDown: 0.4, grip: (19.2, 11.6), tip: (25.0, 3.5), lineTo: (26.0, 12.0))),
            draw(fishRig(headDown: 0.4)),
        ]
    }

    /// Waiting for a bite, the line still, now and then a blink.
    static var fishFrames: [PixelFrame] {
        [(5.0, 0, Face.open), (5.0, 0, .open), (5.5, 1, .open), (5.0, 1, .blink)].map { step in
            draw(fishRig(breath: step.1, headDown: 0.4, tip: (27.0, step.0), face: step.2))
        }
    }

    /// The line jerks and the rod bends: it leans over, holding on.
    static var biteFrames: [PixelFrame] {
        [(5.0, 7.5, 1.0), (7.0, 9.0, 1.6)].map { step in
            draw(fishRig(tilt: step.0, headDown: step.2, lean: 0.4, tip: (27.0, step.1), bend: 1.6))
        }
    }

    /// Hauling the fish out: the rod goes up and back, and the fish comes up out of the hole on the line, swinging, to just in front of
    /// its beak.
    static var pullFrames: [PixelFrame] {
        let steps: [(tip: Point, mouth: Point, tilt: Double, arm: Point)] = [
            ((25.0, 2.0), (26.0, 13.0), -2, (17.6, 10.8)), ((24.0, 1.5), (25.0, 9.5), -4, (17.0, 10.4)), ((23.0, 1.5), (24.0, 6.5), -3, (17.2, 10.6)),
            ((22.5, 2.5), (24.0, 5.0), 0, (18.0, 11.2)), ((22.5, 3.0), (23.5, 5.5), 2, (18.4, 11.4)),
        ]
        return steps.map { step in
            draw(fishRig(
                tilt: step.tilt, grip: step.arm, tip: step.tip, bend: 0.8, lineTo: (step.mouth.x, step.mouth.y - 1),
                extras: { canvas in canvas.outlinedPiece(hanging, x: Int(step.mouth.x.rounded()) - 1, y: Int(step.mouth.y.rounded())) }
            ))
        }
    }

    /// Catching the fish: the head goes to it, takes it in its beak, throws its head back, swallows (a lump goes down its neck) and is pleased.
    static var gulpFrames: [PixelFrame] {
        [
            draw(fishRig(headDown: 0.4, lean: 1.4, tip: (24.0, 4.5), lineTo: (24.0, 7.0), extras: { $0.outlinedPiece(hanging, x: 22, y: 5) })),
            draw(fishRig(headDown: -0.4, lean: 0.8, tip: (24.0, 4.5), lineTo: nil, extras: { $0.outlinedPiece(caught, x: 21, y: 6) })),
            draw(fishRig(headDown: -1.4, lean: -0.2, tip: (24.0, 4.5), lineTo: nil, extras: { $0.outlinedPiece(["FF"], x: 21, y: 4) })),
            draw(fishRig(breath: 1, headDown: -0.4, tip: (26.0, 5.0), lineTo: nil, extras: { $0.piece(["ww"], x: 14, y: 11) })),
            draw(fishRig(breath: 1, headDown: 0.4, face: .happy)),
        ]
    }

    /// A jump for joy with the rod still in its flipper and the line still in the hole.
    static var fishHappyFrames: [PixelFrame] {
        [(0, 0), (2, 0), (3, 1), (2, 1), (1, 0), (0, 1)].enumerated().map { index, step in
            draw(fishRig(breath: step.1, headDown: 0.4, face: index == 0 ? .open : .happy, lift: step.0))
        }
    }
}
