import Foundation
import Observation

/// Trạng thái reactive quản lý danh sách thói quen và ngày làm việc hiện hành.
@Observable
public final class HabitState {
    public var habits: [Habit]
    public var today: DayKey
    public var calendar: Calendar

    public init(
        habits: [Habit] = [],
        today: DayKey = DayKey(date: .now),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.habits = habits
        self.today = today
        self.calendar = calendar
    }

    /// Tiến độ tổng thể trong ngày hôm nay.
    public var progress: HabitProgress {
        let done = habits.filter { $0.isCompleted(on: today) }.count
        return HabitProgress(done: done, total: habits.count)
    }

    /// Thêm một thói quen mới lên đầu danh sách.
    @discardableResult
    public func addHabit(title: String) -> Habit? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let habit = Habit(title: trimmed)
        habits.insert(habit, at: 0)
        return habit
    }

    /// Đảo trạng thái hoàn thành của một thói quen trong ngày hôm nay.
    public func toggleToday(id: UUID) {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return }
        habits[index].toggle(on: today)
    }

    /// Đảo trạng thái hoàn thành vào một ngày bất kỳ (VD click vào mini-heatmap).
    public func toggle(id: UUID, on day: DayKey) {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return }
        habits[index].toggle(on: day)
    }

    /// Xoá một thói quen khỏi danh sách.
    public func deleteHabit(id: UUID) {
        habits.removeAll { $0.id == id }
    }

    /// Cập nhật ngày hôm nay khi chuyển ngày hoặc máy thức dậy.
    public func updateToday(date: Date = .now) {
        let newKey = DayKey(date: date, calendar: calendar)
        if newKey != today {
            today = newKey
        }
    }

    /// Tính toán telemetry metrics hiển thị trên Top Header (doneToday, totalHabits, maxStreak).
    public func headerMetrics(today: DayKey? = nil, calendar: Calendar? = nil) -> (doneToday: Int, totalHabits: Int, maxStreak: Int) {
        let currentToday = today ?? self.today
        let currentCalendar = calendar ?? self.calendar
        let doneToday = habits.filter { $0.isCompleted(on: currentToday) }.count
        let totalHabits = habits.count
        let maxStreak = habits.map { $0.streak(on: currentToday, calendar: currentCalendar) }.max() ?? 0
        return (doneToday, totalHabits, maxStreak)
    }
}
