import CoreGraphics

/// Where the cat plays, as one view of it sees it: a line, the places along it the cat's left foot can go, and how this view lies on it.
///
/// The strip under the notch is a line of its own. The top row of a notch is one view across a virtual notch's body, and on a hardware
/// notch two views, one each side of the camera, that lie on one line as if the camera were not between them: the cat walks along the line,
/// and what falls off the edge of one view is in the other, so a cat that walks into the camera's edge goes into a portal there and comes out
/// of the portal at the other. The picture is drawn a whole number of points to the pixel (`scale`), so it stays crisp.
nonisolated struct CatField: Equatable, Sendable {
    nonisolated enum Side: Equatable, Sendable {
        case left, right
    }

    /// What the cat's picture is, in pixels, and what a portal is.
    static let pictureSize = CGSize(width: CatArt.width, height: CatArt.height)
    static let portalWidth = 10
    /// Between the cat's feet and the bottom of the strip, in points.
    static let stripFloor: CGFloat = 1
    /// The room a cat needs to walk about a view: its least travel, in points, before the view makes the picture smaller.
    static let leastTravel: CGFloat = 60
    /// A leg of a walk ends on a whole step, up to half a step from where it was meant to, and a step is at most this many points (a cat that
    /// runs takes six), so a cat that is sent to the end of the crossing may stop this far in it.
    static let leastEndError: CGFloat = 4
    /// The room to walk that a view of one side of the camera has, when it is as small as that, in points, besides the cat and its portal.
    static let leastWingRoom: CGFloat = 24

    /// Points to a pixel of the cat's picture: a whole number, so that every pixel is a block of points and the picture is as crisp as at one.
    var scale: Int
    /// The places the cat's left foot can be at, along the field's line, in points.
    var lane: WalkLane
    /// Where this view's left edge is on the line.
    var origin: CGFloat
    /// The stretch of the line (the cat's left foot) where the cat is part in one view and part in the other, or in a portal. It goes through
    /// it and never stops in it. Nil for a field of one view.
    var crossing: ClosedRange<CGFloat>?

    var spriteWidth: CGFloat { Self.pictureSize.width * CGFloat(scale) }
    var spriteHeight: CGFloat { Self.pictureSize.height * CGFloat(scale) }
    var portalSize: CGSize { CGSize(width: CGFloat(Self.portalWidth * scale), height: spriteHeight) }

    /// The cat's whole picture is a whole number of points to a pixel.
    static func scale(forHeight height: CGFloat) -> Int {
        max(Int((height / pictureSize.height).rounded(.down)), 1)
    }

    /// The strip under the notch: as it always was.
    static func strip(width: CGFloat) -> CatField {
        CatField(scale: 1, lane: WalkLane(width: width, spriteWidth: pictureSize.width), origin: 0, crossing: nil)
    }

    /// One view across the body of a notch: the biggest scale that fits its height, and that leaves the cat room to walk.
    static func lane(width: CGFloat, height: CGFloat) -> CatField {
        var scale = scale(forHeight: height)
        while scale > 1, width - 2 * WalkLane.endInset - pictureSize.width * CGFloat(scale) < leastTravel { scale -= 1 }
        return CatField(
            scale: scale, lane: WalkLane(width: width, spriteWidth: pictureSize.width * CGFloat(scale)), origin: 0, crossing: nil
        )
    }

    /// The field as the view on `side` of the camera sees it, with `own` its size and `partner` the size of the one on the other side (nil
    /// while there is none, which is a view with a lane of its own).
    static func wings(side: Side, own: CGSize, partner: CGSize?) -> CatField {
        guard let partner else { return lane(width: own.width, height: own.height) }
        let (left, right) = side == .left ? (own, partner) : (partner, own)
        var scale = min(scale(forHeight: left.height), scale(forHeight: right.height))
        func room(_ scale: Int) -> CGFloat {
            (pictureSize.width + CGFloat(portalWidth)) * CGFloat(scale) + WalkLane.endInset + leastWingRoom
        }
        while scale > 1, min(left.width, right.width) < room(scale) { scale -= 1 }
        let factor = CGFloat(scale)
        let (sprite, portal) = (pictureSize.width * factor, CGFloat(portalWidth) * factor)
        let seam = left.width.rounded()
        let minX = WalkLane.endInset
        let maxX = max(seam + right.width - WalkLane.endInset - sprite, minX)
        // The cat's foot where its picture reaches the portal, to where its picture has left it.
        let lower = min(max(seam - portal - sprite, minX), maxX)
        let upper = min(max(seam + portal, lower), maxX)
        let lane = WalkLane(minX: minX, maxX: maxX, restingX: ((minX + lower) / 2).rounded())
        return CatField(scale: scale, lane: lane, origin: side == .left ? 0 : seam, crossing: lower < upper ? lower...upper : nil)
    }

    /// Where the cat's left foot is at `share` of the lane, in this view's own coordinates, on a whole point.
    func local(share: Double) -> CGFloat { lane.x(at: share).rounded() - origin }

    /// The same for what may go off either end of the lane: a moth that leaves.
    func local(unbounded share: Double) -> CGFloat { lane.unboundedX(at: share).rounded() - origin }

    /// A place on the line in this view's own coordinates.
    func local(_ x: CGFloat) -> CGFloat { x - origin }

    /// Where the cat is not sent to stop: the crossing and a little more at each end, so that a leg that ends on a whole step short of or
    /// past the end it was sent to still ends outside the crossing.
    var stopFree: ClosedRange<CGFloat>? {
        guard let crossing else { return nil }
        let margin = Self.leastEndError * CGFloat(scale)
        return max(crossing.lowerBound - margin, lane.minX)...min(crossing.upperBound + margin, lane.maxX)
    }

    /// Where the cat is not sent to stop, as shares of the lane, which is what the brain goes by.
    var crossingShares: ClosedRange<Double>? {
        guard let stopFree, lane.travel > 0 else { return nil }
        return Double((stopFree.lowerBound - lane.minX) / lane.travel)...Double((stopFree.upperBound - lane.minX) / lane.travel)
    }

    /// Where, between the picture's bottom and the view's, the cat's feet are: a point in a strip, whose bottom is the notch's own, and in
    /// the middle of a view across a notch's body.
    func baseY(height: CGFloat, isStrip: Bool) -> CGFloat {
        isStrip ? Self.stripFloor : max(((height - spriteHeight) / 2).rounded(.down), 0)
    }
}
