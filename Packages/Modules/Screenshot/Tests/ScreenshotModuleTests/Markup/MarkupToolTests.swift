import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct MarkupToolTests {
    func options(_ pixelsPerPoint: CGFloat = 2, thickness: StrokeThickness = .medium, color: RGBAColor = .red) -> DrawingOptions {
        DrawingOptions(color: color, thickness: thickness, pixelsPerPoint: pixelsPerPoint)
    }

    @Test func theNewToolsFollowTheOldOnesInToolbarOrder() {
        #expect(MarkupTool.allCases == [.arrow, .rectangle, .text, .highlighter, .step, .magnifier, .ruler, .redact, .erase, .crop])
        #expect(MarkupTool.allCases.map(\.title) == [
            "Mũi tên", "Hình chữ nhật", "Chữ", "Bút dạ quang", "Đánh số bước", "Kính lúp", "Thước đo", "Che vùng", "Xoá thông minh", "Cắt",
        ])
        #expect(Set(MarkupTool.allCases.map(\.systemImage)).count == MarkupTool.allCases.count)
    }

    @Test func onlyRedactionErasingAndCroppingIgnoreColourAndThickness() {
        #expect(MarkupTool.allCases.filter { !$0.usesStyle } == [.redact, .erase, .crop])
    }

    @Test func theEraseTooltipSaysWhatItDoesWhenTheBorderIsNotOneColour() {
        let hint = MarkupTool.erase.hint
        #expect(hint.contains("màu viền"))
        #expect(hint.contains("làm nhoè") || hint.contains("pixel"))
        #expect(MarkupTool.arrow.hint == MarkupTool.arrow.title)
        #expect(MarkupTool.step.hint.contains("⌥"))
    }

    @Test func aStepBadgeLandsWhereTheDragEndsWithTheNextNumberAndTheThicknessAsSize() {
        var settings = options(2, thickness: .thick, color: .green)
        settings.nextStep = 4
        let badge = MarkupTool.step.annotation(through: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 40)], options: settings)
        #expect(badge == .step(number: 4, at: CGPoint(x: 30, y: 40), radius: StrokeThickness.thick.badgeRadius * 2, color: .green))
        // A click is just a drag that did not move.
        let click = MarkupTool.step.annotation(through: [CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 10)], options: settings)
        #expect(click == .step(number: 4, at: CGPoint(x: 10, y: 10), radius: StrokeThickness.thick.badgeRadius * 2, color: .green))
        #expect(StrokeThickness.allCases.map(\.badgeRadius) == [10, 14, 20])
    }

    @Test func aLensIsCentredWhereTheDragStartedAndReachesTheDragEnd() {
        var settings = options(2, thickness: .medium, color: .blue)
        settings.magnification = 3
        let lens = MarkupTool.magnifier.annotation(through: [CGPoint(x: 100, y: 100), CGPoint(x: 130, y: 140)], options: settings)
        #expect(lens == .magnifier(center: CGPoint(x: 100, y: 100), radius: 50, zoom: 3, style: .init(color: .blue, width: 8)))
        #expect(MarkupTool.magnifier.annotation(through: [CGPoint(x: 100, y: 100), CGPoint(x: 103, y: 102)], options: settings) == nil)
    }

    @Test func theMagnificationStaysBetweenOnePointFiveAndFour() {
        #expect(DrawingOptions.magnificationRange == 1.5...4)
        var settings = options()
        for (asked, used) in [(1.0, 1.5), (1.5, 1.5), (2.5, 2.5), (4.0, 4.0), (9.0, 4.0)] as [(CGFloat, CGFloat)] {
            settings.magnification = asked
            let lens = MarkupTool.magnifier.annotation(through: [CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 100)], options: settings)
            guard case .magnifier(_, _, let zoom, _) = lens else { Issue.record("no lens"); return }
            #expect(zoom == used)
        }
    }

    @Test func aRulerMeasuresBetweenTheEndsAndCarriesTheCapturesScale() {
        var settings = options(2, thickness: .medium, color: .red)
        settings.pointScale = 2
        let ruler = MarkupTool.ruler.annotation(through: [CGPoint(x: 10, y: 10), CGPoint(x: 70, y: 90)], options: settings)
        #expect(ruler == .ruler(
            from: CGPoint(x: 10, y: 10), to: CGPoint(x: 70, y: 90), style: .init(color: .red, width: 8),
            fontSize: StrokeThickness.medium.fontSize * 0.6 * 2, scale: 2
        ))
        #expect(MarkupTool.ruler.annotation(through: [CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 11)], options: settings) == nil)
    }

    @Test func shiftSnapsTheRulerToAnAxis() {
        var settings = options(1)
        settings.snapsToAxis = true
        let horizontal = MarkupTool.ruler.annotation(through: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 22)], options: settings)
        guard case .ruler(_, let end, _, _, _) = horizontal else { Issue.record("no ruler"); return }
        #expect(end == CGPoint(x: 90, y: 10))
        let vertical = MarkupTool.ruler.annotation(through: [CGPoint(x: 10, y: 10), CGPoint(x: 18, y: 90)], options: settings)
        guard case .ruler(_, let down, _, _, _) = vertical else { Issue.record("no ruler"); return }
        #expect(down == CGPoint(x: 10, y: 90))
        // Without ⇧ the line goes where the pointer is.
        settings.snapsToAxis = false
        let free = MarkupTool.ruler.annotation(through: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 22)], options: settings)
        guard case .ruler(_, let freeEnd, _, _, _) = free else { Issue.record("no ruler"); return }
        #expect(freeEnd == CGPoint(x: 90, y: 22))
    }

    @Test func aSnappedRulerTooShortToSeeIsDropped() {
        var settings = options(1)
        settings.snapsToAxis = true
        #expect(MarkupTool.ruler.annotation(through: [CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 80)], options: settings)?.isRuler == true)
        #expect(MarkupTool.ruler.annotation(through: [CGPoint(x: 10, y: 10), CGPoint(x: 11, y: 12)], options: settings) == nil)
    }

    @Test func eraseTakesTheDraggedRectangleLikeRedaction() {
        let rect = MarkupTool.erase.annotation(through: [CGPoint(x: 90, y: 70), CGPoint(x: 10, y: 20)], options: options())
        #expect(rect == .erase(CGRect(x: 10, y: 20, width: 80, height: 50)))
        #expect(MarkupTool.erase.annotation(through: [CGPoint(x: 10, y: 20), CGPoint(x: 100, y: 22)], options: options()) == nil)
    }
}

extension Annotation {
    var isRuler: Bool { if case .ruler = self { true } else { false } }
}
