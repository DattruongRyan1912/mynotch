import CoreGraphics
import NotchUI

/// Where on the collapsed notch the cat walks.
nonisolated enum LaneMode: Equatable, Sendable {
    /// The notch's right wing, which is where its trailing activity view is.
    case rightWing
    /// Both wings of a hardware notch, behind the camera from one to the other: where the camera is the cat is not drawn.
    case bothWings
    /// Inside a notch that is only drawn, or a pill, which has no camera to keep clear of: the whole of it.
    case inside

    /// The cat has the whole of a screen that has no camera in it, and the right wing of one that has, or both wings when the user
    /// asked: the camera is never walked over, and the choice is only for a screen that has one.
    static func resolve(kind: NotchKind, bothWings: Bool) -> LaneMode {
        switch kind {
        case .hardware: bothWings ? .bothWings : .rightWing
        case .virtual: .inside
        }
    }
}

/// The two wings of one collapsed notch, in the coordinates of its window. Each is the frame of the cat's view in it, so the room the
/// cat has is exactly the room the notch gives its leading and trailing views, whatever the notch's settings are.
nonisolated struct Wings: Equatable, Sendable {
    var leading: CGRect?
    var trailing: CGRect?
}

/// The stretch of the lane where the cat is out of sight, as shares of the lane (0 to 1): the cat that is in it, or stops in it, is seen
/// by nobody. Positions at its two edges are outside it.
nonisolated struct BlindSpan: Equatable, Sendable {
    var low: Double
    var high: Double

    func contains(_ share: Double) -> Bool { share > low && share < high }

    /// Whether going from `start` to `end` is going into the span or across it.
    func meets(from start: Double, to end: Double) -> Bool {
        max(min(start, end), low) < min(max(start, end), high) || contains(start) || contains(end)
    }

    /// The edge of the span that is nearer to `share`.
    func nearestEdge(to share: Double) -> Double { share - low < high - share ? low : high }
}

/// The line the cat walks along: the leftmost and rightmost place the left edge of the sprite goes, in the window's coordinates.
nonisolated struct WalkLane: Equatable, Sendable {
    /// How far a hardware notch's rounded ends are from where the cat may walk.
    static let hardwareEndInset: CGFloat = 8
    /// Between the cat and the camera's side of a wing.
    static let innerInset: CGFloat = 2

    var minX: CGFloat
    var maxX: CGFloat
    /// Whether the cat is drawn only where a wing is: a lane that crosses the camera, which is no place for a cat.
    var clipsToWings: Bool
    /// Where the left edge of the sprite is while the cat sits still without moving at all (Reduce Motion): the middle of the right wing.
    var restingX: CGFloat
    /// The places the left edge of the sprite has when it is hidden at least in part: the camera between two wings, which the cat crosses
    /// and does not stop in, and the middle of a pill, where it may not be drawn at all. Nil when the lane has nothing in it to hide in.
    var blindMinX: CGFloat?
    var blindMaxX: CGFloat?

    /// How far the cat can walk.
    var travel: CGFloat { max(maxX - minX, 0) }

    /// The blind stretch as shares of the lane; nil when there is none, or the lane is too short to have places in it.
    var blind: BlindSpan? {
        guard let blindMinX, let blindMaxX, travel > 0 else { return nil }
        let low = min(max(Double((blindMinX - minX) / travel), 0), 1)
        let high = min(max(Double((blindMaxX - minX) / travel), 0), 1)
        return high > low ? BlindSpan(low: low, high: high) : nil
    }

    /// The sprite's left edge at `fraction` of the way along the lane, 0 to 1.
    func x(at fraction: Double) -> CGFloat {
        minX + travel * CGFloat(min(max(fraction, 0), 1))
    }

    /// nil when there is no wing to walk on yet (the notch has not laid its views out). `roundEnd` is how far the notch's round ends
    /// are from where the cat may go: half the row's height for a pill, whose ends are semicircles.
    static func make(mode: LaneMode, wings: Wings, spriteWidth: CGFloat, roundEnd: CGFloat) -> WalkLane? {
        guard let trailing = wings.trailing else { return nil }
        let outer = max(roundEnd, hardwareEndInset)
        let resting = trailing.midX - spriteWidth / 2
        switch mode {
        case .rightWing:
            return span(from: trailing.minX + innerInset, to: trailing.maxX - outer, spriteWidth: spriteWidth, clips: true, resting: resting)
        case .bothWings:
            guard let leading = wings.leading else {
                return span(from: trailing.minX + innerInset, to: trailing.maxX - outer, spriteWidth: spriteWidth, clips: true, resting: resting)
            }
            return span(
                from: leading.minX + outer, to: trailing.maxX - outer, spriteWidth: spriteWidth, clips: true, resting: resting,
                between: leading, and: trailing
            )
        case .inside:
            let start = (wings.leading?.minX ?? trailing.minX) + outer
            return span(
                from: start, to: trailing.maxX - outer, spriteWidth: spriteWidth, clips: false, resting: resting,
                between: wings.leading, and: trailing
            )
        }
    }

    /// A lane from `start` to `end`, for a sprite `spriteWidth` wide: the sprite's left edge has `end - spriteWidth` as far as it goes.
    /// Too short for the sprite, it is a point and the cat stays where it is.
    private static func span(
        from start: CGFloat, to end: CGFloat, spriteWidth: CGFloat, clips: Bool, resting: CGFloat, between leading: CGRect? = nil,
        and trailing: CGRect? = nil
    ) -> WalkLane {
        let farthest = max(end - spriteWidth, start)
        var lane = WalkLane(minX: start, maxX: farthest, clipsToWings: clips, restingX: resting)
        // Between the wings the cat is out of sight from the moment it is no longer wholly in the left wing to the moment it is wholly
        // in the right one.
        if let leading, let trailing, trailing.minX > leading.maxX {
            lane.blindMinX = leading.maxX - spriteWidth
            lane.blindMaxX = trailing.minX
        }
        return lane
    }
}
