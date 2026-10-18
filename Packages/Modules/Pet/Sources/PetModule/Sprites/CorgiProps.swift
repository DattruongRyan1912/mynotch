import Foundation

/// What the corgi plays with: a tennis ball. It is a whole picture of 32 by 24 like the corgi's, with the ball in the middle of it, drawn over
/// the corgi (the prop layer is over the sprite layer) and so the same size as everything else on the lane; the corgi's own pictures, where it
/// has the ball in its mouth, draw it at the place its nose is when the corgi stands at it (`CorgiMove.ballReach`).
///
/// The ball falls in from above the strip and bounces, each bounce lower, and rolls to where it lies: the bounces are in the pictures and the
/// roll across the lane is the path the view moves the whole picture along. It lies still; it is set down and bounces a little; and it is
/// taken up out of sight, and then there is nothing.
enum CorgiProps {
    /// The column of the board the ball's left edge is at in its own picture: the middle of the board less half a ball.
    static let ballColumn = 12
    static let ballSize = 6
    /// The bottom of the ball when it lies on the floor, as a row of the board: the corgi's feet are on it.
    static let floorRow = 20

    /// The ball with its bottom on `bottom` (a row of the board; the floor is `floorRow`), turned `turn`, with a line round it.
    private static func canvas(bottom: Int, turn: Int) -> CatCanvas {
        var canvas = CatCanvas()
        canvas.outlinedPiece(CorgiArt.ball(turn: turn), x: ballColumn, y: bottom - (ballSize - 1))
        return canvas
    }

    /// The picture of it with its rim: where the ball is cut off by the top of the picture there is no line to go round, and no rim.
    private static func frame(bottom: Int, turn: Int) -> PixelFrame {
        var frame = canvas(bottom: bottom, turn: turn).frame.rimmed(with: "R")
        if bottom <= ballSize - 1 {
            for x in 0..<frame.width where frame[x, 0] == "R" { frame = frame.setting(".", atX: x, y: 0) }
        }
        return frame
    }

    /// How high the ball is, bottom row by bottom row, from the top of the picture down: it falls, and bounces three times, each lower, and
    /// then rolls on the floor for the rest of the time.
    static let tossBottoms = [3, 10, 17, 20, 14, 10, 14, 20, 16, 14, 16, 20, 18, 20]

    static let toss = PixelAnimation(
        frames: tossBottoms.enumerated().map { frame(bottom: $1, turn: (tossBottoms.count - 1 - $0) % 4) }, fps: 12, loops: false
    )

    /// Lying on the floor.
    static let rest = PixelAnimation(frames: [frame(bottom: floorRow, turn: 0)], fps: 1)

    /// Set down: it bounces up from where it was let go, and again a little, and lies.
    static let drop = PixelAnimation(
        frames: [(floorRow, 0), (16, 3), (13, 2), (16, 1), (floorRow, 0)].map { frame(bottom: $0, turn: $1) }, fps: 10, loops: false
    )

    /// In its mouth, and so in the corgi's own pictures: nothing to see, and the room held.
    static let held = PixelAnimation(frames: [PixelFrame(width: 32, height: 24)], fps: 1)

    /// Taken up: it rises from the floor, going round, and out of the top of the picture, and then there is nothing.
    static let up = PixelAnimation(
        frames: [(floorRow, 0), (17, 1), (13, 2), (8, 3), (3, 0), (-4, 0)].map { frame(bottom: $0, turn: $1) }, fps: 12, loops: false
    )
}

extension CorgiProps {
    /// What the corgi has out, as pictures.
    static func animation(for prop: CorgiProp) -> PixelAnimation {
        switch prop {
        case .ballToss: toss
        case .ballRest: rest
        case .ballDrop: drop
        case .ballUp: up
        case .ballHeld: held
        }
    }
}
