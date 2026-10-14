import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct RulerTests {
    @Test func distanceIsTheStraightLineInPixels() {
        #expect(Ruler.distance(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 3, y: 4)) == 5)
        #expect(Ruler.distance(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10)) == 0)
        #expect(Ruler.distance(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 340, y: 50)) == 240)
    }

    @Test func shiftSnapsToTheAxisTheDragMovedMostAlong() {
        let start = CGPoint(x: 10, y: 10)
        #expect(Ruler.snapped(CGPoint(x: 50, y: 18), from: start) == CGPoint(x: 50, y: 10))
        #expect(Ruler.snapped(CGPoint(x: 14, y: 60), from: start) == CGPoint(x: 10, y: 60))
        #expect(Ruler.snapped(CGPoint(x: -30, y: 12), from: start) == CGPoint(x: -30, y: 10))
        // A perfect diagonal goes horizontal rather than flipping between axes.
        #expect(Ruler.snapped(CGPoint(x: 40, y: 40), from: start) == CGPoint(x: 40, y: 10))
    }

    @Test func aPlainScreenShowsOnlyPixels() {
        #expect(Ruler.label(distance: 240, scale: 1) == "240 px")
        #expect(Ruler.label(distance: 0.4, scale: 1) == "0 px")
    }

    @Test func retinaCapturesAddThePointSize() {
        #expect(Ruler.label(distance: 240, scale: 2) == "240 px (120 pt)")
        #expect(Ruler.label(distance: 241, scale: 2) == "241 px (120.5 pt)")
        #expect(Ruler.label(distance: 240, scale: 3) == "240 px (80 pt)")
        #expect(Ruler.label(distance: 100, scale: 1.5) == "100 px (66.7 pt)")
        // The points follow the rounded pixels that are shown.
        #expect(Ruler.label(distance: 240.4, scale: 2) == "240 px (120 pt)")
    }

    @Test func anInvalidScaleIsTreatedAsOne() {
        #expect(Ruler.label(distance: 50, scale: 0) == "50 px")
        #expect(Ruler.label(distance: 50, scale: -2) == "50 px")
    }

    @Test func labelSitsAboveAHorizontalLineAndBesideAVerticalOne() {
        let horizontal = Ruler.layout(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 340, y: 100), lineWidth: 4, fontSize: 16, scale: 2)
        #expect(horizontal.labelRect.maxY < 100)
        #expect(abs(horizontal.labelRect.midX - 220) < 0.5)
        let vertical = Ruler.layout(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 100, y: 340), lineWidth: 4, fontSize: 16, scale: 2)
        #expect(vertical.labelRect.minX > 100)
        #expect(abs(vertical.labelRect.midY - 220) < 0.5)
        // The same line drawn the other way round keeps its label on the same side.
        let reversed = Ruler.layout(from: CGPoint(x: 340, y: 100), to: CGPoint(x: 100, y: 100), lineWidth: 4, fontSize: 16, scale: 2)
        #expect(reversed.labelRect == horizontal.labelRect)
    }

    @Test func boundsCoverTheLineItsEndTicksAndTheLabel() {
        let layout = Ruler.layout(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 340, y: 160), lineWidth: 4, fontSize: 16, scale: 1)
        for point in [CGPoint(x: 100, y: 100), CGPoint(x: 340, y: 160)] { #expect(layout.bounds.contains(point)) }
        #expect(layout.bounds.contains(CGPoint(x: layout.labelRect.minX, y: layout.labelRect.minY)))
        #expect(layout.bounds.contains(CGPoint(x: layout.labelRect.maxX, y: layout.labelRect.maxY)))
        for (a, b) in layout.ticks {
            #expect(layout.bounds.contains(a) && layout.bounds.contains(b))
        }
        #expect(layout.ticks.count == 2)
    }
}
