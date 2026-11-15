import Foundation

/// Chuỗi khoá định danh ngày theo định dạng ISO "YYYY-MM-DD" dựa trên Calendar cục bộ.
public struct DayKey: RawRepresentable, Codable, Comparable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        self.rawValue = String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { rawValue }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Tính ngày dịch chuyển theo số ngày offset (+ hoặc -) thông qua Calendar.
    public func addingDays(_ offset: Int, calendar: Calendar = .autoupdatingCurrent) -> DayKey {
        guard offset != 0, let date = toDate(calendar: calendar) else { return self }
        guard let newDate = calendar.date(byAdding: .day, value: offset, to: date) else { return self }
        return DayKey(date: newDate, calendar: calendar)
    }

    private func toDate(calendar: Calendar) -> Date? {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else { return nil }
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        return calendar.date(from: components)
    }
}

/// Một thói quen được người dùng theo dõi.
public struct Habit: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var completedDays: Set<DayKey>

    public init(id: UUID = UUID(), title: String, createdAt: Date = .now, completedDays: Set<DayKey> = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.completedDays = completedDays
    }

    /// Kiểm tra xem thói quen đã hoàn thành vào ngày chỉ định chưa.
    public func isCompleted(on day: DayKey) -> Bool {
        completedDays.contains(day)
    }

    /// Đảo trạng thái hoàn thành vào ngày chỉ định.
    public mutating func toggle(on day: DayKey) {
        if completedDays.contains(day) {
            completedDays.remove(day)
        } else {
            completedDays.insert(day)
        }
    }

    /// Tính số ngày hoàn thành liên tiếp (streak) tính tới ngày chỉ định.
    /// Nếu hôm nay đã hoàn thành, đếm từ hôm nay lùi về quá khứ.
    /// Nếu hôm nay chưa hoàn thành, đếm từ ngày hôm qua để bảo toàn chuỗi streak hiện tại.
    public func streak(on today: DayKey, calendar: Calendar = .autoupdatingCurrent) -> Int {
        if isCompleted(on: today) {
            var count = 1
            var checkDay = today.addingDays(-1, calendar: calendar)
            while isCompleted(on: checkDay) {
                count += 1
                checkDay = checkDay.addingDays(-1, calendar: calendar)
            }
            return count
        } else {
            var count = 0
            var checkDay = today.addingDays(-1, calendar: calendar)
            while isCompleted(on: checkDay) {
                count += 1
                checkDay = checkDay.addingDays(-1, calendar: calendar)
            }
            return count
        }
    }

    /// Trả về mảng 7 giá trị boolean cho 7 ngày gần nhất (từ today - 6 đến today).
    public func lastSevenDays(endingOn today: DayKey, calendar: Calendar = .autoupdatingCurrent) -> [Bool] {
        var days: [Bool] = []
        days.reserveCapacity(7)
        for offset in stride(from: -6, through: 0, by: 1) {
            let day = today.addingDays(offset, calendar: calendar)
            days.append(isCompleted(on: day))
        }
        return days
    }
}

/// Cấu trúc lưu trữ JSON bền vững.
public struct HabitStoreData: Codable, Sendable {
    public var habits: [Habit]

    public init(habits: [Habit] = []) {
        self.habits = habits
    }
}

/// Tiến độ hoàn thành các thói quen trong ngày.
public struct HabitProgress: Equatable, Sendable {
    public let done: Int
    public let total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    public var remaining: Int {
        max(0, total - done)
    }

    public var fraction: Double {
        total > 0 ? Double(done) / Double(total) : 0
    }

    public var formattedText: String {
        "\(done)/\(total) hôm nay"
    }
}
