import AppKit
import Foundation
import SwiftUI

/// Bảng màu dành cho vẽ đồ hoạ HabitHeatmap trên Canvas.
public struct HabitCanvasPalette: Equatable, Sendable {
    public let accentColor: NSColor
    public let emptyColor: NSColor
    public let borderColor: NSColor
    public let textColor: NSColor

    public init(
        accentColor: NSColor,
        emptyColor: NSColor,
        borderColor: NSColor,
        textColor: NSColor
    ) {
        self.accentColor = accentColor
        self.emptyColor = emptyColor
        self.borderColor = borderColor
        self.textColor = textColor
    }

    public static func from(
        palette: HabitColorPalette,
        isDark: Bool = false
    ) -> HabitCanvasPalette {
        let accent = NSColor(palette.color)
        if isDark {
            return HabitCanvasPalette(
                accentColor: accent,
                emptyColor: NSColor(red: 39.0 / 255.0, green: 39.0 / 255.0, blue: 42.0 / 255.0, alpha: 1.0),
                borderColor: NSColor(red: 63.0 / 255.0, green: 63.0 / 255.0, blue: 70.0 / 255.0, alpha: 1.0),
                textColor: NSColor(white: 0.65, alpha: 1.0)
            )
        } else {
            return HabitCanvasPalette(
                accentColor: accent,
                emptyColor: NSColor(red: 235.0 / 255.0, green: 238.0 / 255.0, blue: 242.0 / 255.0, alpha: 1.0),
                borderColor: NSColor(red: 226.0 / 255.0, green: 232.0 / 255.0, blue: 240.0 / 255.0, alpha: 1.0),
                textColor: NSColor(red: 100.0 / 255.0, green: 116.0 / 255.0, blue: 139.0 / 255.0, alpha: 1.0)
            )
        }
    }
}

/// Toạ độ và kích thước hình học chuẩn hoá cho Habit Heatmap 52 tuần x 7 ngày.
public enum HabitHeatmapGeometry {
    public static let cellSize: CGFloat = 11.0
    public static let cellGap: CGFloat = 3.0
    public static let weekPitch: CGFloat = cellSize + cellGap // 14.0
    public static let dayPitch: CGFloat = cellSize + cellGap  // 14.0
    public static let gridOriginX: CGFloat = 27.0
    public static let gridOriginY: CGFloat = 16.0
    public static let cellCornerRadius: CGFloat = 2.0

    /// Vị trí đặt nhãn tháng trên đầu lưới.
    public struct MonthLabelPlacement: Equatable, Sendable {
        public let text: String
        public let x: CGFloat
        public let weekIndex: Int

        public init(text: String, x: CGFloat, weekIndex: Int) {
            self.text = text
            self.x = x
            self.weekIndex = weekIndex
        }
    }

    /// Tính kích thước toàn phần của khung nhìn Heatmap dựa trên số tuần.
    public static func size(weeksCount: Int) -> CGSize {
        guard weeksCount > 0 else {
            return CGSize(width: 0, height: 0)
        }
        let width = gridOriginX + CGFloat(weeksCount) * weekPitch - cellGap
        let height = gridOriginY + 7.0 * dayPitch - cellGap
        return CGSize(width: width, height: height)
    }

    /// Xác định chính xác `DayKey` được click hoặc hover tại toạ độ điểm `point`.
    public static func hitTest(point: CGPoint, weeks: [HeatmapWeek]) -> DayKey? {
        guard !point.x.isNaN, !point.y.isNaN,
              !point.x.isInfinite, !point.y.isInfinite else {
            return nil
        }
        guard point.x >= gridOriginX, point.y >= gridOriginY else {
            return nil
        }

        let relX = point.x - gridOriginX
        let relY = point.y - gridOriginY

        let wIdx = Int(floor(relX / weekPitch))
        let dIdx = Int(floor(relY / dayPitch))

        guard wIdx >= 0, wIdx < weeks.count else { return nil }
        let week = weeks[wIdx]
        guard dIdx >= 0, dIdx < week.days.count else { return nil }

        // Kiểm tra xem điểm có nằm trong thân cell hay rơi vào khe hở (gap)
        let inCellX = relX - CGFloat(wIdx) * weekPitch
        let inCellY = relY - CGFloat(dIdx) * dayPitch
        guard inCellX >= 0, inCellX <= cellSize,
              inCellY >= 0, inCellY <= cellSize else {
            return nil
        }

        let day = week.days[dIdx]
        if day.isFuture {
            return nil
        }
        return day.dayKey
    }

    /// Trả về dictionary nhãn ngày trong tuần cho các hàng hiển thị (Thứ 2, Thứ 4, Thứ 6).
    public static func dayLabels(firstWeekday: Int) -> [Int: String] {
        let mondayRow = (2 - firstWeekday + 7) % 7
        let wednesdayRow = (4 - firstWeekday + 7) % 7
        let fridayRow = (6 - firstWeekday + 7) % 7

        return [
            mondayRow: "T2",
            wednesdayRow: "T4",
            fridayRow: "T6"
        ]
    }

    /// Trả về danh sách vị trí nhãn tháng cho các cột tuần.
    public static func monthLabels(weeks: [HeatmapWeek]) -> [MonthLabelPlacement] {
        var placements: [MonthLabelPlacement] = []
        for (index, week) in weeks.enumerated() {
            if let label = week.monthLabel {
                let x = gridOriginX + CGFloat(index) * weekPitch
                placements.append(MonthLabelPlacement(text: label, x: x, weekIndex: index))
            }
        }
        return placements
    }
}

/// SwiftUI View dựng lưới GitHub Heatmap bằng Canvas duy nhất cho toàn bộ 52 tuần x 7 ngày (364 ô),
/// thay thế hoàn toàn việc lồng 1,000+ View structs để giữ vững tốc độ khung hình 120Hz ProMotion khi cuộn.
public struct HabitHeatmapCanvas: View, Equatable {
    public let weeks: [HeatmapWeek]
    public let palette: HabitCanvasPalette
    public var hoveredDayKey: DayKey?
    public var onSelectDay: ((DayKey) -> Void)?

    public init(
        weeks: [HeatmapWeek],
        palette: HabitCanvasPalette,
        hoveredDayKey: DayKey? = nil,
        onSelectDay: ((DayKey) -> Void)? = nil
    ) {
        self.weeks = weeks
        self.palette = palette
        self.hoveredDayKey = hoveredDayKey
        self.onSelectDay = onSelectDay
    }

    public static func == (lhs: HabitHeatmapCanvas, rhs: HabitHeatmapCanvas) -> Bool {
        lhs.weeks == rhs.weeks &&
        lhs.palette == rhs.palette &&
        lhs.hoveredDayKey == rhs.hoveredDayKey
    }

    public var body: some View {
        let canvasSize = HabitHeatmapGeometry.size(weeksCount: weeks.count)
        let firstWeekday = weeks.first?.days.first?.dayOfWeek ?? 1
        let dayLabels = HabitHeatmapGeometry.dayLabels(firstWeekday: firstWeekday)
        let monthPlacements = HabitHeatmapGeometry.monthLabels(weeks: weeks)

        Canvas { context, _ in
            // 1. Vẽ các nhãn tháng
            for placement in monthPlacements {
                let text = Text(placement.text)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(nsColor: palette.textColor))
                context.draw(text, at: CGPoint(x: placement.x, y: 1), anchor: .topLeading)
            }

            // 2. Vẽ các nhãn thứ (T2, T4, T6)
            for (row, label) in dayLabels {
                let y = HabitHeatmapGeometry.gridOriginY + CGFloat(row) * HabitHeatmapGeometry.dayPitch + HabitHeatmapGeometry.cellSize / 2.0
                let text = Text(label)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundColor(Color(nsColor: palette.textColor))
                context.draw(text, at: CGPoint(x: 24, y: y), anchor: .trailing)
            }

            // 3. Vẽ 52 tuần x 7 ngày
            let accentColor = Color(nsColor: palette.accentColor)
            let emptyColor = Color(nsColor: palette.emptyColor)
            let borderColor = Color(nsColor: palette.borderColor)

            for (wIdx, week) in weeks.enumerated() {
                let colX = HabitHeatmapGeometry.gridOriginX + CGFloat(wIdx) * HabitHeatmapGeometry.weekPitch

                for (dIdx, day) in week.days.enumerated() {
                    let rowY = HabitHeatmapGeometry.gridOriginY + CGFloat(dIdx) * HabitHeatmapGeometry.dayPitch
                    let rect = CGRect(
                        x: colX,
                        y: rowY,
                        width: HabitHeatmapGeometry.cellSize,
                        height: HabitHeatmapGeometry.cellSize
                    )
                    let cellPath = Path(roundedRect: rect, cornerRadius: HabitHeatmapGeometry.cellCornerRadius)

                    if day.isFuture {
                        // Ngày tương lai: không vẽ hoặc vẽ viền mờ
                        continue
                    }

                    if day.isCompleted {
                        context.fill(cellPath, with: .color(accentColor))
                    } else {
                        context.fill(cellPath, with: .color(emptyColor))
                        context.stroke(cellPath, with: .color(borderColor), lineWidth: 0.75)
                    }

                    if day.isToday {
                        context.stroke(cellPath, with: .color(accentColor), lineWidth: 1.5)
                    }

                    if let hovered = hoveredDayKey, hovered == day.dayKey {
                        context.stroke(cellPath, with: .color(.white), lineWidth: 1.5)
                    }
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            if let dayKey = HabitHeatmapGeometry.hitTest(point: location, weeks: weeks) {
                onSelectDay?(dayKey)
            }
        }
    }
}
