import SwiftUI
import Testing
@testable import NotchUI

/// The notch's outline and what the pill adds to it: the same shape, with its ears able to go to nothing and its top corners able to
/// be convex, so the notch, the pill and the open rounded rectangle are points on one animatable path.
@Suite struct NotchShapePillTests {
    /// The outline exactly as it was before the pill: a frozen copy, so a change to the real one cannot move the notch unseen.
    func frozenNotchPath(topRadius: CGFloat, bottomRadius: CGFloat, in rect: CGRect) -> Path {
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

    // MARK: the notch is today's

    @Test func withNoConvexCornerTheOutlineIsExactlyTheNotchesOfBefore() {
        let rects = [
            CGRect(x: 0, y: 0, width: 197, height: 32), CGRect(x: 10, y: 3, width: 325, height: 62), CGRect(x: 0, y: 0, width: 600, height: 222),
            CGRect(x: 0, y: 0, width: 40, height: 8), CGRect(x: 5, y: 5, width: 0, height: 0), CGRect(x: 0, y: 0, width: 12, height: 300),
        ]
        // The radii of every state, and values part-way between them as the spring passes through.
        let radii: [(CGFloat, CGFloat)] = [(6, 10), (8, 24), (7, 17), (6.4, 10.2), (0, 0), (0, 24), (30, 40)]
        for rect in rects {
            for (top, bottom) in radii {
                let shape = NotchShape(topRadius: top, bottomRadius: bottom)
                #expect(shape.cornerRadius == 0)
                #expect(shape.path(in: rect) == frozenNotchPath(topRadius: top, bottomRadius: bottom, in: rect), "\(rect) \(top) \(bottom)")
                #expect(NotchShape(topRadius: top, bottomRadius: bottom, cornerRadius: 0).path(in: rect) == shape.path(in: rect))
            }
        }
    }

    @Test func theNotchesEarsReachTheTopCornersAndInsetTheWall() {
        let rect = CGRect(x: 0, y: 0, width: 197, height: 32)
        let path = NotchShape(topRadius: 6, bottomRadius: 10).path(in: rect)
        #expect(path.boundingRect == rect)
        // The wall is inset by the ear, so just inside the rect's edge at mid height is outside the shape.
        #expect(!path.contains(CGPoint(x: 2, y: 16)))
        #expect(path.contains(CGPoint(x: 7, y: 16)))
    }

    // MARK: the pill

    @Test func thePillHasNoEarsItsWallIsTheRectsEdge() {
        let rect = CGRect(x: 0, y: 0, width: 185, height: 25)
        let path = NotchShape(topRadius: 0, bottomRadius: 12.5, cornerRadius: 12.5).path(in: rect)
        #expect(path.boundingRect == rect)
        #expect(path.contains(CGPoint(x: 0.5, y: 12.5)), "the end of the capsule touches the edge of the rect at mid height")
        #expect(path.contains(CGPoint(x: 92.5, y: 0.5)))
        #expect(path.contains(CGPoint(x: 92.5, y: 24.5)))
        #expect(!path.contains(CGPoint(x: 1, y: 1)), "the corner is round")
        #expect(!path.contains(CGPoint(x: 184, y: 24)))
    }

    @Test func theCollapsedPillIsACircularCapsule() {
        // Compared with the capsule drawn from first principles: inside when the point is within the radius of the segment between
        // the two end centres, except in a thin band around the edge, where the path's own flattening makes either answer fair.
        for (width, height) in [(CGFloat(185), CGFloat(25)), (240, 36), (120, 24), (300, 40)] {
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            let radius = height / 2
            let path = NotchShape(topRadius: 0, bottomRadius: radius, cornerRadius: radius).path(in: rect)
            #expect(path.boundingRect == rect)
            var checked = 0
            for x in stride(from: CGFloat(0.25), to: width, by: 0.5) {
                for y in stride(from: CGFloat(0.25), to: height, by: 0.5) {
                    let nearest = min(max(x, radius), width - radius)
                    let distance = ((x - nearest) * (x - nearest) + (y - radius) * (y - radius)).squareRoot()
                    guard abs(distance - radius) > 0.6 else { continue }
                    checked += 1
                    #expect(path.contains(CGPoint(x: x, y: y)) == (distance < radius), "\(width)x\(height) at \(x),\(y)")
                }
            }
            #expect(checked > 100)
        }
    }

    @Test func aStripUnderThePillMakesARoundedRectangleWithTheSameCornerRadius() {
        let rect = CGRect(x: 0, y: 0, width: 313, height: 55)
        let path = NotchShape(topRadius: 0, bottomRadius: 12.5, cornerRadius: 12.5).path(in: rect)
        #expect(path.boundingRect == rect)
        #expect(path.contains(CGPoint(x: 0.5, y: 27)), "a straight wall between the corners")
        #expect(!path.contains(CGPoint(x: 1, y: 1)))
        #expect(!path.contains(CGPoint(x: 1, y: 54)))
        #expect(path.contains(CGPoint(x: 12.5, y: 12.5)))
    }

    @Test func theOpenPillHasFourRoundedCornersAndNoEars() {
        let rect = CGRect(x: 0, y: 0, width: 600, height: 215)
        let path = NotchShape(topRadius: 0, bottomRadius: 24, cornerRadius: 24).path(in: rect)
        #expect(path.boundingRect == rect)
        for corner in [CGPoint(x: 1, y: 1), CGPoint(x: 599, y: 1), CGPoint(x: 1, y: 214), CGPoint(x: 599, y: 214)] {
            #expect(!path.contains(corner), "\(corner)")
        }
        for centreOfCorner in [CGPoint(x: 24, y: 24), CGPoint(x: 576, y: 24), CGPoint(x: 24, y: 191), CGPoint(x: 576, y: 191)] {
            #expect(path.contains(centreOfCorner), "\(centreOfCorner)")
        }
        // A wall that is the rect's edge at the top as much as at the bottom: no ears.
        for y in [CGFloat(30), 100, 185] {
            #expect(path.contains(CGPoint(x: 0.5, y: y)), "\(y)")
            #expect(path.contains(CGPoint(x: 599.5, y: y)), "\(y)")
        }
    }

    @Test func theRadiusIsHeldToWhatTheRectHasRoomFor() {
        // The spring can pass through a rect smaller than the radius it is going to; the outline stays inside it and closed.
        let rect = CGRect(x: 0, y: 0, width: 30, height: 10)
        let path = NotchShape(topRadius: 0, bottomRadius: 24, cornerRadius: 24).path(in: rect)
        #expect(path.boundingRect.width <= rect.width + 1e-3 && path.boundingRect.height <= rect.height + 1e-3)
        #expect(path.contains(CGPoint(x: 15, y: 5)))
        let none = NotchShape(topRadius: 0, bottomRadius: 12, cornerRadius: 12).path(in: .zero)
        #expect(none.boundingRect.width == 0 && none.boundingRect.height == 0)
    }

    // MARK: one animatable shape

    @Test func theShapeAnimatesAllThreeRadiiAndNothingElse() {
        var shape = NotchShape(topRadius: 6, bottomRadius: 10, cornerRadius: 0)
        let data = shape.animatableData
        #expect(data.first == 6)
        #expect(data.second.first == 10)
        #expect(data.second.second == 0)
        shape.animatableData = AnimatablePair(0, AnimatablePair(12.5, 12.5))
        #expect(shape == NotchShape(topRadius: 0, bottomRadius: 12.5, cornerRadius: 12.5))
    }

    @Test func goingFromTheNotchToThePillNeverLeavesTheRectOrBreaksTheOutline() {
        let rect = CGRect(x: 0, y: 0, width: 197, height: 25)
        let from = NotchShape(topRadius: 6, bottomRadius: 10, cornerRadius: 0)
        let to = NotchShape(topRadius: 0, bottomRadius: 12.5, cornerRadius: 12.5)
        for step in 0...20 {
            let t = CGFloat(step) / 20
            var shape = from
            shape.topRadius = from.topRadius + (to.topRadius - from.topRadius) * t
            shape.bottomRadius = from.bottomRadius + (to.bottomRadius - from.bottomRadius) * t
            shape.cornerRadius = from.cornerRadius + (to.cornerRadius - from.cornerRadius) * t
            let path = shape.path(in: rect)
            let bounds = path.boundingRect
            #expect(bounds.minX >= -1e-3 && bounds.minY >= -1e-3 && bounds.maxX <= rect.maxX + 1e-3 && bounds.maxY <= rect.maxY + 1e-3, "t \(t)")
            #expect(path.contains(CGPoint(x: rect.midX, y: rect.midY)), "t \(t)")
            #expect(!path.contains(CGPoint(x: rect.midX, y: -1)), "t \(t)")
        }
        // The two ends are the two outlines.
        #expect(from.path(in: rect) == frozenNotchPath(topRadius: 6, bottomRadius: 10, in: rect))
        #expect(to.path(in: rect).contains(CGPoint(x: 0.5, y: 12.5)))
    }

    @Test func goingFromTheCollapsedPillToTheOpenOneKeepsTheOutlineValid() {
        // The spring overshoots, so the rect and the radii are not always on the straight line between the two ends.
        for step in 0...20 {
            let t = CGFloat(step) / 20 * 1.1
            let rect = CGRect(x: 0, y: 0, width: 185 + 415 * t, height: 25 + 190 * t)
            let radius = 12.5 + 11.5 * t
            let path = NotchShape(topRadius: 0, bottomRadius: radius, cornerRadius: radius).path(in: rect)
            #expect(path.boundingRect.maxX <= rect.maxX + 1e-3 && path.boundingRect.maxY <= rect.maxY + 1e-3, "t \(t)")
            #expect(path.contains(CGPoint(x: rect.midX, y: rect.midY)), "t \(t)")
            #expect(path.contains(CGPoint(x: 0.5, y: rect.midY)), "no ears at any moment, t \(t)")
        }
    }
}
