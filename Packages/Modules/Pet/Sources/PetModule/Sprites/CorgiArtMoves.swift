import Foundation

extension CorgiArt {
    /// Every move as its pictures, and how they are played. Built when asked for, a move at a time, as the cat's are.
    static func animation(for move: CorgiMove) -> PixelAnimation {
        PixelAnimation(frames: frames(for: move), fps: move.fps, loops: move.loops, advance: move.advance)
    }

    private static func frames(for move: CorgiMove) -> [PixelFrame] {
        switch move {
        case .stand: (0..<4).map { picture(standForm(breath: Double($0 / 2), ears: earsFor($0), face: $0 == 3 ? .blink : .open)) }
        case .blink: [picture(standForm(face: .blink))]
        case .trot: trotFrames
        case .run: runFrames
        case .wiggle: wiggleFrames
        case .watch: watchFrames
        case .spin: spinFrames
        case .grab: grabFrames
        case .carry: carryFrames
        case .lower: Array(grabFrames.reversed())
        case .sitDown: sitDownFrames
        case .standUp: Array(sitDownFrames.reversed())
        case .sit: (0..<4).map { picture(sitForm(breath: Double($0 / 2), face: $0 == 3 ? .blink : .open, ears: earsFor($0))) }
        case .begUp: begUpFrames
        case .beg: begFrames
        case .begDown: Array(begUpFrames.reversed())
        case .lieDown: lieDownFrames
        case .getUp: Array(lieDownFrames.reversed())
        case .lie: (0..<2).map { picture(lieForm(breath: Double($0), face: $0 == 1 ? .blink : .open)) }
        case .settle: settleFrames
        case .wake: Array(settleFrames.reversed())
        case .sleep: sleepFrames
        }
    }

    /// The standing corgi with its eyes open and shut: what one that does not move at all (Reduce Motion) shows.
    static var restingFrames: [PixelFrame] { [picture(standForm()), picture(standForm(face: .blink))] }

    // MARK: Small tools

    /// A form as a finished picture.
    static func picture(
        _ form: Form, lift: Int = 0, extras: @escaping (inout CatCanvas) -> Void = { _ in }, after: @escaping (inout PixelFrame) -> Void = { _ in }
    ) -> PixelFrame {
        draw(rig(form, lift: lift, extras: extras, after: after))
    }

    /// The ears now and then twitch a little, in step with the breath.
    static func earsFor(_ index: Int) -> (near: Double, far: Double) { index == 1 ? (0.12, -0.05) : (0, 0) }

    /// A heart small enough for the room beside its head.
    static let smallHeart = ["H.H", "HHH", ".H."]
    static let smallSparkle = [".Y.", "YYY", ".Y."]

    // MARK: Going somewhere

    /// Where the four paws are in each picture of a trot: the legs go in diagonal pairs, short and quick, the body bobbing a little.
    static let trotSteps: [(paws: [Paw], bob: Double)] = [
        ([(2.2, 0), (-2.0, 1), (-2.0, 1), (2.2, 0)], 0),
        ([(1.0, 1), (-0.8, 0), (-0.8, 0), (1.0, 1)], -0.6),
        ([(-1.4, 0), (1.4, 0), (1.4, 0), (-1.4, 0)], 0),
        ([(-2.2, 1), (2.0, 0), (2.0, 0), (-2.2, 1)], 0),
        ([(-1.0, 0), (0.8, 1), (0.8, 1), (-1.0, 0)], -0.6),
        ([(1.4, 0), (-1.4, 0), (-1.4, 0), (1.4, 0)], 0),
    ]

    static var trotFrames: [PixelFrame] {
        trotSteps.enumerated().map { index, step in
            picture(standForm(paws: step.paws, tail: index % 2 == 0 ? 0.6 : 0, mouth: index % 3 == 0 ? .open : .shut).bobbed(step.bob))
        }
    }

    /// Trotting with a ball in its mouth: the head is up, and the ball bobs with it.
    static var carryFrames: [PixelFrame] {
        trotSteps.enumerated().map { index, step in
            picture(
                standForm(head: (0.2, -0.6, -4), paws: step.paws, tail: index % 2 == 0 ? 0.8 : 0.2, face: .happy).bobbed(step.bob),
                extras: ballInMouth(rows: 12 + (index % 3 == 1 ? 1 : 0), turn: index)
            )
        }
    }

    /// The zoomies: stretched out flat, the legs reaching forward and back, the ears blown back and flapping, the tongue out, and dust behind.
    static var runFrames: [PixelFrame] {
        let steps: [(paws: [Paw], hop: Double, ears: (near: Double, far: Double))] = [
            ([(3.4, 1), (2.0, 2), (-3.4, 1), (-2.0, 2)], 0, (-0.8, -0.7)),
            ([(1.6, 2), (3.4, 1), (-1.6, 2), (-3.4, 1)], -1, (-1.1, -1.0)),
            ([(-0.6, 2), (1.6, 2), (0.6, 3), (-1.6, 2)], -1, (-0.7, -0.6)),
            ([(-3.0, 1), (-1.6, 2), (3.0, 1), (1.6, 2)], 0, (-1.1, -1.0)),
            ([(-1.6, 2), (-3.0, 1), (1.6, 2), (3.0, 1)], -1, (-0.8, -0.7)),
            ([(0.6, 2), (-1.6, 2), (-0.6, 3), (1.6, 2)], -1, (-1.1, -1.0)),
        ]
        return steps.enumerated().map { index, step in
            picture(
                standForm(head: (0.8, 0.4 + step.hop * 0.3, 5), ears: step.ears, paws: step.paws, face: .happy, mouth: index % 2 == 0 ? .panting : .open)
                    .bobbed(step.hop),
                after: dust(index)
            )
        }
    }

    /// Puffs of dust behind a running corgi: over the rim, a pixel wide.
    static func dust(_ index: Int) -> (inout PixelFrame) -> Void {
        let puffs: [[(Int, Int)]] = [[(2, 21), (0, 22)], [(1, 20), (3, 22)], [(0, 21), (2, 19)], [(2, 22), (0, 20)], [(1, 21), (3, 19)], [(0, 22), (2, 20)]]
        return { frame in for (x, y) in puffs[index % puffs.count] { frame = frame.setting("D", atX: x, y: y) } }
    }

    // MARK: Standing about

    /// Wiggling its rear: the back end goes from side to side (up and down, from the side), the stub of a tail going, the head still.
    static var wiggleFrames: [PixelFrame] {
        let swings: [(dx: Double, dy: Double, tail: Double, rearA: Paw, rearB: Paw)] = [
            (-1.4, 0, 1.2, (-1.4, 0), (1.0, 0)), (-0.6, -0.8, 0.2, (-0.6, 0), (0.4, 0)), (0.8, 0, 1.2, (1.0, 0), (-0.8, 0)),
            (1.6, -0.4, 0.4, (1.6, 0), (-1.2, 0)), (0.4, -0.8, 1.0, (0.4, 0), (0, 0)), (-0.8, 0, 0, (-1.0, 0), (0.8, 0)),
        ]
        return swings.map { swing in
            picture(standForm(rump: (swing.dx, swing.dy), paws: [(0, 0), (0, 0), swing.rearA, swing.rearB], tail: swing.tail, face: .happy, mouth: .open))
        }
    }

    /// Looking up, as at a ball in the air: the head goes up and back, the ears straight up, and the head follows it down again.
    static var watchFrames: [PixelFrame] {
        [(-8.0, -0.4), (-16, -1.2), (-12, -0.8), (0, 0)].map { turn, dy in
            picture(standForm(head: (0, dy, turn), ears: (0.1, 0.1)))
        }
    }

    // MARK: A ball

    /// A ball in its mouth, in the corgi's own pictures: hung from its mouth, whose front is at the right of the board.
    static func ballInMouth(rows y: Int, turn: Int, x: Int = 22) -> (inout CatCanvas) -> Void {
        { canvas in canvas.outlinedPiece(ball(turn: turn), x: x, y: y) }
    }

    /// The ball: a round of six by six, with a seam that goes round it as it rolls.
    static func ball(turn: Int) -> [String] {
        let seams: [[String]] = [
            [".BBBB.", "BbbBBB", "BBBbBB", "BBBbBB", "BbbBBB", ".BBBB."],
            [".BBBB.", "BBBBbB", "BbbbBB", "BBBBBB", "BBbbbB", ".BBBB."],
            [".BBBB.", "BBbbBB", "BBBBbB", "BBBBbB", "BBbbBB", ".BBBB."],
            [".BBbB.", "BBbBBB", "BbBBBB", "BBBBBB", "BBBBBB", ".BBBB."],
        ]
        return seams[((turn % 4) + 4) % 4]
    }

    /// Where the ball lies on the board when the corgi is standing at it with its nose over it, on the picture of the corgi that faces right:
    /// `CorgiMove.ballReach` pixels along from where the ball's own picture has it.
    static let ballOnTheFloor = (x: CorgiProps.ballColumn + Int(CorgiMove.ballReach), y: 15)

    /// Taking the ball up: the head goes down to it, the mouth closes on it, and the head comes up with it.
    static var grabFrames: [PixelFrame] {
        let floor = ballOnTheFloor
        let steps: [(turn: Double, dy: Double, mouth: Mouth, ball: Int, paws: [Paw])] = [
            (24, 0.6, .open, floor.y, [(1.0, 0), (0.4, 0), (0, 0), (0, 0)]),
            (46, 2.0, .open, floor.y, [(1.6, 0), (0.8, 0), (0, 0), (0, 0)]),
            (34, 1.2, .shut, floor.y - 1, [(1.2, 0), (0.6, 0), (0, 0), (0, 0)]),
            (-4, -0.6, .shut, 12, [(0, 0), (0, 0), (0, 0), (0, 0)]),
        ]
        return steps.enumerated().map { index, step in
            picture(
                standForm(head: (index == 3 ? 0.2 : 0, step.dy, step.turn), paws: step.paws, face: index == 3 ? .happy : .open, mouth: step.mouth),
                extras: ballInMouth(rows: step.ball, turn: index >= 2 ? index : 0, x: index == 3 ? 22 : floor.x)
            )
        }
    }

    // MARK: The happy spin

    /// A spin for joy: side on, turning to face the viewer with a hop and a heart, round to the other side, to its back, and round to where
    /// it began. The pictures of the other side are the mirror image of this one's.
    static var spinFrames: [PixelFrame] {
        let side = standForm(face: .happy, mouth: .open)
        let front = frontForm(face: .happy, mouth: .open)
        let back = backForm()
        let threeQuarters = mixed(side, front, 0.5)
        let behind = mixed(side, back, 0.5)
        let heart: (inout CatCanvas) -> Void = { canvas in canvas.outlinedPiece(smallHeart, x: 23, y: 1) }
        func sparkle(_ x: Int, _ y: Int) -> (inout CatCanvas) -> Void { { canvas in canvas.outlinedPiece(smallSparkle, x: x, y: y) } }
        return [
            picture(standForm()), picture(threeQuarters.moved(0, -1), extras: sparkle(25, 2)), picture(front.moved(0, -0.6), extras: heart),
            picture(threeQuarters.moved(0, -1), extras: heart).mirrored, picture(side, extras: sparkle(25, 3)).mirrored,
            picture(behind.moved(0, -1), extras: sparkle(24, 1)).mirrored, picture(back.moved(0, -1)), picture(behind.moved(0, -1), extras: sparkle(0, 2)),
            picture(standForm()),
        ]
    }

    // MARK: Sitting

    static var sitDownFrames: [PixelFrame] {
        let (stand, sit) = (standForm(), sitForm())
        return [mixed(stand, sit, 0.35), mixed(stand, sit, 0.7), sit].map { picture($0) }
    }

    static var begUpFrames: [PixelFrame] {
        let (sit, beg) = (sitForm(mouth: .open), begForm(paws: 0))
        return [mixed(sit, beg, 0.35), mixed(sit, beg, 0.7), beg].map { picture($0) }
    }

    /// Begging: sitting up with its paws together, bobbing them up and down, its tongue out, its ears twitching.
    static var begFrames: [PixelFrame] {
        (0..<4).map { index in
            picture(begForm(
                paws: [0, 1, 0, 1][index], face: index == 3 ? .blink : .open, mouth: index % 2 == 0 ? .open : .shut,
                ears: [(0, 0), (0.15, 0.1), (-0.1, 0), (0, 0)][index]
            ))
        }
    }

    // MARK: Lying

    static var lieDownFrames: [PixelFrame] {
        let (stand, sit, lie) = (standForm(), sitForm(), lieForm())
        return [mixed(stand, sit, 0.5), mixed(sit, lie, 0.4), mixed(sit, lie, 0.75), lie].map { picture($0) }
    }

    /// Settling onto its side: the head goes down, the eyes shut, and it stretches out, and the z's begin.
    static var settleFrames: [PixelFrame] {
        let (lie, sleep) = (lieForm(), sleepForm())
        return [picture(mixed(lie, sleep, 0.4)), picture(mixed(lie, sleep, 0.75)), sleepPicture(0)]
    }

    /// Asleep, breathing, with the z's going up from it.
    static var sleepFrames: [PixelFrame] { (0..<4).map(sleepPicture) }

    static func sleepPicture(_ index: Int) -> PixelFrame {
        let zeds: [[(x: Int, y: Int)]] = [[(21, 10)], [(21, 9), (26, 5)], [(26, 6)], [(21, 10), (26, 6)]]
        return picture(sleepForm(breath: Double(index / 2)), extras: { canvas in for zed in zeds[index] { canvas.piece(CatArt.zed, x: zed.x, y: zed.y) } })
    }
}

extension CorgiArt.Form {
    /// The body moved by `dy` rows with the paws left on the ground (the legs reach up or down to meet the body).
    func bobbed(_ dy: Double) -> CorgiArt.Form {
        guard dy != 0 else { return self }
        var form = moved(0, dy)
        for index in form.legs.indices { form.legs[index][1] = legs[index][1] }
        return form
    }
}
