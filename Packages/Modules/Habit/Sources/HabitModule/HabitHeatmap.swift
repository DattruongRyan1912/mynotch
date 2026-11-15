import Foundation
import SwiftUI

/// Bảng màu nhận diện thương hiệu cho từng thói quen trong Habit Studio.
public enum HabitColorPalette: String, CaseIterable, Sendable {
    case emerald = "emerald"
    case oceanSky = "oceanSky"
    case electricViolet = "electricViolet"
    case warmAmber = "warmAmber"
    case roseCoral = "roseCoral"
    case mintTeal = "mintTeal"
    case indigoBlue = "indigoBlue"

    public static func palette(for index: Int) -> HabitColorPalette {
        let all = allCases
        guard !all.isEmpty else { return .emerald }
        let safeIndex = abs(index) % all.count
        return all[safeIndex]
    }

    public var displayName: String {
        switch self {
        case .emerald: return "Ngọc Lục Bảo"
        case .oceanSky: return "Xanh Biển Trời"
        case .electricViolet: return "Tím Neon"
        case .warmAmber: return "Hổ Phách Ấm"
        case .roseCoral: return "San Hô Đỏ"
        case .mintTeal: return "Bạc Hà"
        case .indigoBlue: return "Chàm Đậm"
        }
    }

    public var hexString: String {
        switch self {
        case .emerald: return "#10b981"
        case .oceanSky: return "#0ea5e9"
        case .electricViolet: return "#8b5cf6"
        case .warmAmber: return "#f59e0b"
        case .roseCoral: return "#f43f5e"
        case .mintTeal: return "#14b8a6"
        case .indigoBlue: return "#6366f1"
        }
    }

    public var color: Color {
        switch self {
        case .emerald: return Color(red: 16/255, green: 185/255, blue: 129/255)
        case .oceanSky: return Color(red: 14/255, green: 165/255, blue: 233/255)
        case .electricViolet: return Color(red: 139/255, green: 92/255, blue: 246/255)
        case .warmAmber: return Color(red: 245/255, green: 158/255, blue: 11/255)
        case .roseCoral: return Color(red: 244/255, green: 63/255, blue: 94/255)
        case .mintTeal: return Color(red: 20/255, green: 184/255, blue: 166/255)
        case .indigoBlue: return Color(red: 99/255, green: 102/255, blue: 241/255)
        }
    }
}

/// Dữ liệu của 1 ô ngày trong bảng lưới GitHub Heatmap.
public struct HeatmapDay: Identifiable, Sendable, Equatable, Hashable {
    public var id: String { dayKey.rawValue }
    public let dayKey: DayKey
    public let dayOfWeek: Int // 1 (Sun) .. 7 (Sat) hoặc 1 (Mon) .. 7 (Sun)
    public let isCompleted: Bool
    public let isToday: Bool
    public let isFuture: Bool

    public init(
        dayKey: DayKey,
        dayOfWeek: Int,
        isCompleted: Bool,
        isToday: Bool,
        isFuture: Bool
    ) {
        self.dayKey = dayKey
        self.dayOfWeek = dayOfWeek
        self.isCompleted = isCompleted
        self.isToday = isToday
        self.isFuture = isFuture
    }
}

/// Dữ liệu của 1 cột tuần (7 ngày) trong bảng lưới GitHub Heatmap.
public struct HeatmapWeek: Identifiable, Sendable, Equatable {
    public let id: Int
    public let days: [HeatmapDay]
    public let monthLabel: String?

    public init(id: Int, days: [HeatmapDay], monthLabel: String?) {
        self.id = id
        self.days = days
        self.monthLabel = monthLabel
    }
}

/// Thuật toán xây dựng lưới đóng góp 52 tuần x 7 ngày kiểu GitHub.
public struct HabitHeatmapBuilder: Sendable {

    /// Xây dựng mảng tuần `[HeatmapWeek]` kết thúc tại tuần chứa ngày `today`.
    public static func buildGrid(
        completedDays: Set<DayKey>,
        today: DayKey,
        weeksCount: Int = 52,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [HeatmapWeek] {
        guard weeksCount > 0 else { return [] }

        // Phân giải ngày Date từ today
        let parts = today.rawValue.split(separator: "-")
        var todayComponents = DateComponents()
        if parts.count == 3,
           let y = Int(parts[0]),
           let m = Int(parts[1]),
           let d = Int(parts[2]) {
            todayComponents.year = y
            todayComponents.month = m
            todayComponents.day = d
        }
        let todayDate = calendar.date(from: todayComponents) ?? Date()

        // Xác định ngày trong tuần của today (1 = Sunday ... 7 = Saturday theo mặc định Gregorian)
        let weekdayOfToday = calendar.component(.weekday, from: todayDate)
        let firstWeekday = calendar.firstWeekday // thường là 1 (Sunday)
        let daysIntoCurrentWeek = (weekdayOfToday - firstWeekday + 7) % 7

        // Tính ngày bắt đầu của tuần đầu tiên trong lưới (lùi lại (weeksCount - 1) tuần từ đầu tuần hiện tại)
        let totalDaysToStart = ((weeksCount - 1) * 7) + daysIntoCurrentWeek
        guard let gridStartDate = calendar.date(byAdding: .day, value: -totalDaysToStart, to: todayDate) else {
            return []
        }

        var weeks: [HeatmapWeek] = []
        weeks.reserveCapacity(weeksCount)

        var lastRecordedMonth: Int = -1

        for weekIdx in 0..<weeksCount {
            var weekDays: [HeatmapDay] = []
            weekDays.reserveCapacity(7)

            var weekContainsFirstOfMonth: Int? = nil

            for dayOffset in 0..<7 {
                let totalOffset = (weekIdx * 7) + dayOffset
                guard let cellDate = calendar.date(byAdding: .day, value: totalOffset, to: gridStartDate) else {
                    continue
                }

                let cellDayKey = DayKey(date: cellDate, calendar: calendar)
                let cellWeekday = calendar.component(.weekday, from: cellDate)
                let cellDayOfMonth = calendar.component(.day, from: cellDate)
                let cellMonth = calendar.component(.month, from: cellDate)

                let isToday = (cellDayKey == today)
                let isFuture = (cellDayKey > today)
                let isCompleted = completedDays.contains(cellDayKey)

                if cellDayOfMonth == 1 && cellMonth != lastRecordedMonth {
                    weekContainsFirstOfMonth = cellMonth
                    lastRecordedMonth = cellMonth
                }

                weekDays.append(
                    HeatmapDay(
                        dayKey: cellDayKey,
                        dayOfWeek: cellWeekday,
                        isCompleted: isCompleted,
                        isToday: isToday,
                        isFuture: isFuture
                    )
                )
            }

            // Gán nhãn tháng cho tuần
            var monthLabel: String? = nil
            if let month = weekContainsFirstOfMonth {
                monthLabel = formatMonthLabel(month)
            } else if weekIdx == 0 {
                // Tuần đầu tiên luôn hiển thị tháng bắt đầu
                if let firstDate = calendar.date(byAdding: .day, value: (weekIdx * 7), to: gridStartDate) {
                    let firstMonth = calendar.component(.month, from: firstDate)
                    monthLabel = formatMonthLabel(firstMonth)
                    lastRecordedMonth = firstMonth
                }
            }

            weeks.append(HeatmapWeek(id: weekIdx, days: weekDays, monthLabel: monthLabel))
        }

        return weeks
    }

    private static func formatMonthLabel(_ month: Int) -> String {
        switch month {
        case 1: return "Th1"
        case 2: return "Th2"
        case 3: return "Th3"
        case 4: return "Th4"
        case 5: return "Th5"
        case 6: return "Th6"
        case 7: return "Th7"
        case 8: return "Th8"
        case 9: return "Th9"
        case 10: return "Th10"
        case 11: return "Th11"
        case 12: return "Th12"
        default: return "Th\(month)"
        }
    }
}
