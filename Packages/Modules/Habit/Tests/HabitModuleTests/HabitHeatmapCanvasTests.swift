import AppKit
import SwiftUI
import Testing
@testable import HabitModule

@Suite
@MainActor
struct HabitHeatmapCanvasTests {

    private func makeCalendar(firstWeekday: Int = 1) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "vi_VN")
        cal.firstWeekday = firstWeekday
        return cal
    }

    private func makeTestWeeks() -> [HeatmapWeek] {
        let cal = makeCalendar()
        let today = DayKey(date: Date())
        return HabitHeatmapBuilder.buildGrid(
            completedDays: [today],
            today: today,
            weeksCount: 52,
            calendar: cal
        )
    }

    // HC-3: Geometry Hit Testing
    @Test
    func test_HC3_geometry_hitTestingCellsAndGaps() {
        let weeks = makeTestWeeks()

        // 1. Center of non-future cells must hit correct dayKey
        for (wIdx, week) in weeks.enumerated() {
            for (dIdx, day) in week.days.enumerated() {
                let centerPt = CGPoint(
                    x: HabitHeatmapGeometry.gridOriginX + CGFloat(wIdx) * HabitHeatmapGeometry.weekPitch + HabitHeatmapGeometry.cellSize / 2.0,
                    y: HabitHeatmapGeometry.gridOriginY + CGFloat(dIdx) * HabitHeatmapGeometry.dayPitch + HabitHeatmapGeometry.cellSize / 2.0
                )
                let hitKey = HabitHeatmapGeometry.hitTest(point: centerPt, weeks: weeks)
                if day.isFuture {
                    #expect(hitKey == nil)
                } else {
                    #expect(hitKey == day.dayKey)
                }
            }
        }

        // 2. Gap between column 0 and 1 (x in gap)
        let gapPt = CGPoint(
            x: HabitHeatmapGeometry.gridOriginX + HabitHeatmapGeometry.cellSize + 1.5,
            y: HabitHeatmapGeometry.gridOriginY + 5.5
        )
        #expect(HabitHeatmapGeometry.hitTest(point: gapPt, weeks: weeks) == nil)

        // 3. Left labels column (x < gridOriginX)
        let labelColPt = CGPoint(x: 10, y: HabitHeatmapGeometry.gridOriginY + 5.5)
        #expect(HabitHeatmapGeometry.hitTest(point: labelColPt, weeks: weeks) == nil)

        // 4. Month labels row (y < gridOriginY)
        let monthRowPt = CGPoint(x: HabitHeatmapGeometry.gridOriginX + 5.5, y: 5)
        #expect(HabitHeatmapGeometry.hitTest(point: monthRowPt, weeks: weeks) == nil)

        // 5. Out of bounds & degenerate inputs
        #expect(HabitHeatmapGeometry.hitTest(point: CGPoint(x: -10, y: -10), weeks: weeks) == nil)
        #expect(HabitHeatmapGeometry.hitTest(point: CGPoint(x: 1000, y: 1000), weeks: weeks) == nil)
        #expect(HabitHeatmapGeometry.hitTest(point: CGPoint(x: CGFloat.nan, y: 0), weeks: weeks) == nil)
        #expect(HabitHeatmapGeometry.hitTest(point: CGPoint(x: 0, y: CGFloat.infinity), weeks: weeks) == nil)
    }

    // HC-4: Geometry Sizing
    @Test
    func test_HC4_geometry_sizeCalculation() {
        let size52 = HabitHeatmapGeometry.size(weeksCount: 52)
        // gridOriginX (27) + 52 * 14 (728) - 3 (gap) = 752. gridOriginY (16) + 7 * 14 (98) - 3 = 111
        #expect(size52 == CGSize(width: 752, height: 111))

        // size(0) does not crash and returns minimum dimensions
        let size0 = HabitHeatmapGeometry.size(weeksCount: 0)
        #expect(size0.width >= 0)
        #expect(size0.height >= 0)
    }

    // HC-5: Day and Month Labels
    @Test
    func test_HC5_labels_dayOfWeekAndMonth() {
        let weeks = makeTestWeeks()

        // With firstWeekday = 1 (Sunday): rows 1, 3, 5 are Mon (T2), Wed (T4), Fri (T6)
        let labelsSun = HabitHeatmapGeometry.dayLabels(firstWeekday: 1)
        #expect(labelsSun[1] == "T2")
        #expect(labelsSun[3] == "T4")
        #expect(labelsSun[5] == "T6")

        // With firstWeekday = 2 (Monday): rows 0, 2, 4 are Mon (T2), Wed (T4), Fri (T6)
        let labelsMon = HabitHeatmapGeometry.dayLabels(firstWeekday: 2)
        #expect(labelsMon[0] == "T2")
        #expect(labelsMon[2] == "T4")
        #expect(labelsMon[4] == "T6")

        // Month labels placement
        let monthPlacements = HabitHeatmapGeometry.monthLabels(weeks: weeks)
        let expectedCount = weeks.filter { $0.monthLabel != nil }.count
        #expect(monthPlacements.count == expectedCount)
        for placement in monthPlacements {
            let expectedX = HabitHeatmapGeometry.gridOriginX + CGFloat(placement.weekIndex) * HabitHeatmapGeometry.weekPitch
            #expect(placement.x == expectedX)
        }
    }

    // HC-6: Empirical Canvas Render
    @Test
    func test_HC6_canvas_renderVisualInspection() {
        let weeks = makeTestWeeks()
        let palette = HabitCanvasPalette(
            accentColor: NSColor(red: 0.1, green: 0.7, blue: 0.4, alpha: 1.0),
            emptyColor: NSColor(white: 0.9, alpha: 1.0),
            borderColor: NSColor(white: 0.8, alpha: 1.0),
            textColor: NSColor(white: 0.5, alpha: 1.0)
        )

        let canvasView = HabitHeatmapCanvas(
            weeks: weeks,
            palette: palette,
            hoveredDayKey: nil,
            onSelectDay: { _ in }
        )

        let hosting = NSHostingView(rootView: canvasView)
        let expectedSize = HabitHeatmapGeometry.size(weeksCount: 52)
        hosting.frame = NSRect(origin: .zero, size: expectedSize)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("Failed to create bitmap representation for HabitHeatmapCanvas")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        // Verify non-empty rendering with distinct colors
        var uniqueColors = Set<Int>()
        for x in stride(from: 10, to: Int(expectedSize.width) - 10, by: 20) {
            for y in stride(from: 10, to: Int(expectedSize.height) - 10, by: 10) {
                if let color = rep.colorAt(x: x, y: y) {
                    let hashVal = Int(color.redComponent * 100) + Int(color.greenComponent * 1000)
                    uniqueColors.insert(hashVal)
                }
            }
        }
        #expect(uniqueColors.count >= 3)
    }

    // HC-7: Equatable Conformance
    @Test
    func test_HC7_equatable_conformance() {
        let weeks1 = makeTestWeeks()
        let palette1 = HabitCanvasPalette(
            accentColor: .blue,
            emptyColor: .lightGray,
            borderColor: .gray,
            textColor: .darkGray
        )
        let palette2 = HabitCanvasPalette(
            accentColor: .green,
            emptyColor: .lightGray,
            borderColor: .gray,
            textColor: .darkGray
        )

        let canvasA = HabitHeatmapCanvas(weeks: weeks1, palette: palette1, hoveredDayKey: nil, onSelectDay: { _ in })
        let canvasB = HabitHeatmapCanvas(weeks: weeks1, palette: palette1, hoveredDayKey: nil, onSelectDay: { _ in print("different") })
        let canvasC = HabitHeatmapCanvas(weeks: weeks1, palette: palette2, hoveredDayKey: nil, onSelectDay: { _ in })

        #expect(canvasA == canvasB)
        #expect(canvasA != canvasC)
    }
}
