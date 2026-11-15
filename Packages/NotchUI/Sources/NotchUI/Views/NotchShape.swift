import SwiftUI

/// The notch's outline. Two forms of the same shape, so that the notch, the pill and the open rounded rectangle are points on one
/// animatable path and nothing jumps when the style changes or the notch opens:
///
/// * The notch (`cornerRadius` 0): concave "ears" at the top that blend into the menu bar, and rounded bottom corners.
/// * The pill (`topRadius` 0, `cornerRadius` > 0): no ears, and every corner convex and as round as `cornerRadius`; a capsule when
///   it is half the height. Ears and convex corners can both be there part-way, which is what an animation between the two passes
///   through: the convex corner first, then a small ear that goes to nothing.
public struct NotchShape: Shape, Equatable {
    /// The radius of the ears, which is also how far the wall is inset from the edge of the frame.
    public var topRadius: CGFloat
    /// The radius of the bottom corners.
    public var bottomRadius: CGFloat
    /// The radius of the two convex corners at the top: 0 for the notch, whose top edge runs ear tip to ear tip.
    public var cornerRadius: CGFloat

    public init(topRadius: CGFloat, bottomRadius: CGFloat, cornerRadius: CGFloat = 0) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        self.cornerRadius = cornerRadius
    }

    public var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(topRadius, AnimatablePair(bottomRadius, cornerRadius)) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second.first
            cornerRadius = newValue.second.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        cornerRadius > 0 ? roundedPath(in: rect) : notchPath(in: rect)
    }

    /// The notch's own outline, as it was before the pill: quadratic corners, ears from tip to tip.
    private func notchPath(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4, rect.height / 2)
        let bottom = min(bottomRadius, rect.height - top, (rect.width - 2 * top) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top), control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY), control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom), control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }

    /// With a convex top corner the outline goes round the rect: the top edge, a circular corner, the ear if there is one (a concave
    /// curve from the corner's end to the wall), the wall, and two circular bottom corners. A circle and not the notch's quadratic
    /// curve, so the capsule is a capsule.
    private func roundedPath(in rect: CGRect) -> Path {
        let corner = max(min(cornerRadius, rect.width / 2, rect.height / 2), 0)
        let ear = max(min(topRadius, rect.width / 4, (rect.height - corner) / 2), 0)
        let left = rect.minX + ear
        let right = rect.maxX - ear
        let bottom = max(min(bottomRadius, rect.height - corner - ear, (right - left) / 2), 0)
        let earTop = rect.minY + corner
        let wallTop = earTop + ear

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addCircularCorner(to: CGPoint(x: rect.maxX, y: earTop), cornerAt: CGPoint(x: rect.maxX, y: rect.minY))
        if ear > 0 { path.addQuadCurve(to: CGPoint(x: right, y: wallTop), control: CGPoint(x: right, y: earTop)) }
        path.addLine(to: CGPoint(x: right, y: rect.maxY - bottom))
        path.addCircularCorner(to: CGPoint(x: right - bottom, y: rect.maxY), cornerAt: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: left + bottom, y: rect.maxY))
        path.addCircularCorner(to: CGPoint(x: left, y: rect.maxY - bottom), cornerAt: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: left, y: wallTop))
        if ear > 0 { path.addQuadCurve(to: CGPoint(x: rect.minX, y: earTop), control: CGPoint(x: left, y: earTop)) }
        path.addCircularCorner(to: CGPoint(x: rect.minX + corner, y: rect.minY), cornerAt: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

nonisolated private extension Path {
    /// How far along each tangent the control points of a cubic that draws a quarter circle sit, as a part of its radius.
    static let quarterCircle: CGFloat = 0.5522847498

    /// A quarter circle from the current point to `end`, the two being the sides of a right angle that meets at `cornerAt`.
    mutating func addCircularCorner(to end: CGPoint, cornerAt corner: CGPoint) {
        guard let start = currentPoint else { return }
        let k = Self.quarterCircle
        addCurve(
            to: end,
            control1: CGPoint(x: start.x + (corner.x - start.x) * k, y: start.y + (corner.y - start.y) * k),
            control2: CGPoint(x: end.x + (corner.x - end.x) * k, y: end.y + (corner.y - end.y) * k)
        )
    }
}
