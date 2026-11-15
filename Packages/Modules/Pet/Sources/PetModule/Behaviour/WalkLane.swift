import CoreGraphics

/// The line the cat walks along: the strip under the notch, less a little at each end. The leftmost and rightmost place the left edge of
/// the sprite goes, in the coordinates of the view that is the strip.
nonisolated struct WalkLane: Equatable, Sendable {
    /// Between the cat and the ends of the strip, which are the round bottom corners of the notch.
    static let endInset: CGFloat = 6

    var minX: CGFloat
    var maxX: CGFloat
    /// Where the sprite's left edge is while the cat sits still without moving at all (Reduce Motion): the middle of the strip.
    var restingX: CGFloat

    /// How far the cat can walk.
    var travel: CGFloat { max(maxX - minX, 0) }

    init(minX: CGFloat, maxX: CGFloat, restingX: CGFloat) {
        self.minX = minX
        self.maxX = maxX
        self.restingX = restingX
    }

    /// The lane of a strip `width` wide for a sprite `spriteWidth` wide. A strip too narrow for the sprite has a lane of one place.
    init(width: CGFloat, spriteWidth: CGFloat, endInset: CGFloat = WalkLane.endInset) {
        let start = min(endInset, max((width - spriteWidth) / 2, 0))
        minX = start
        maxX = max(width - start - spriteWidth, start)
        restingX = max((width - spriteWidth) / 2, 0)
    }

    /// The sprite's left edge at `share` of the way along the lane, 0 to 1 (held to them).
    func x(at share: Double) -> CGFloat {
        minX + travel * CGFloat(min(max(share, 0), 1))
    }

    /// The same, for what may go off either end of the lane: a moth that leaves.
    func unboundedX(at share: Double) -> CGFloat {
        minX + travel * CGFloat(share)
    }
}
