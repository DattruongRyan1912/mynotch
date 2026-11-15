import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct StepBadgesTests {
    static func step(_ number: Int, at x: CGFloat = 0, color: RGBAColor = .red) -> Annotation {
        .step(number: number, at: CGPoint(x: x, y: 0), radius: 10, color: color)
    }

    static let rectangle = Annotation.rectangle(CGRect(x: 0, y: 0, width: 5, height: 5), style: .init(color: .red, width: 2))

    static func numbers(_ annotations: [Annotation]) -> [Int] {
        annotations.compactMap { if case .step(let number, _, _, _) = $0 { number } else { nil } }
    }

    @Test func theNextBadgeIsOnePastTheBadgesAlreadyPlaced() {
        #expect(StepBadges.nextNumber(in: []) == 1)
        #expect(StepBadges.nextNumber(in: [Self.rectangle]) == 1)
        #expect(StepBadges.nextNumber(in: [Self.step(1), Self.rectangle, Self.step(2)]) == 3)
    }

    @Test func renumberingCountsBadgesInDrawingOrderAndLeavesOtherShapesAlone() {
        let renumbered = StepBadges.renumbered([Self.step(1, at: 0), Self.rectangle, Self.step(3, at: 20), Self.step(7, at: 40, color: .blue)])
        #expect(Self.numbers(renumbered) == [1, 2, 3])
        #expect(renumbered[1] == Self.rectangle)
        #expect(renumbered[3] == Self.step(3, at: 40, color: .blue))
    }

    @Test func removingAMiddleBadgeClosesTheGap() {
        var annotations = [Self.step(1, at: 0), Self.step(2, at: 20), Self.step(3, at: 40)]
        annotations.remove(at: 1)
        #expect(Self.numbers(StepBadges.renumbered(annotations)) == [1, 2])
    }

    @Test func findsTheBadgeUnderAPointPreferringTheOneDrawnLast() {
        let annotations = [Self.step(1, at: 100), Self.rectangle, Self.step(2, at: 105)]
        #expect(StepBadges.indexOfTopmost(at: CGPoint(x: 104, y: 3), in: annotations) == 2)
        #expect(StepBadges.indexOfTopmost(at: CGPoint(x: 92, y: 0), in: annotations) == 0)
        #expect(StepBadges.indexOfTopmost(at: CGPoint(x: 100, y: 11), in: annotations) == nil)
        #expect(StepBadges.indexOfTopmost(at: CGPoint(x: 300, y: 0), in: annotations) == nil)
    }
}
