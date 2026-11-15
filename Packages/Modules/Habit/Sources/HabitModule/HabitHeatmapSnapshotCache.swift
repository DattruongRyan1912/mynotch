import Foundation

/// Snapshot dữ liệu và thống kê đã tính toán của 1 Habit Heatmap.
public struct HabitHeatmapSnapshot: Sendable, Equatable {
    public let habitId: UUID
    public let weeks: [HeatmapWeek]
    public let totalCompletions: Int
    public let currentStreak: Int
    public let isDoneToday: Bool
    public let completionRate: Int
    public let paletteIndex: Int

    public init(
        habitId: UUID,
        weeks: [HeatmapWeek],
        totalCompletions: Int,
        currentStreak: Int,
        isDoneToday: Bool,
        completionRate: Int,
        paletteIndex: Int
    ) {
        self.habitId = habitId
        self.weeks = weeks
        self.totalCompletions = totalCompletions
        self.currentStreak = currentStreak
        self.isDoneToday = isDoneToday
        self.completionRate = completionRate
        self.paletteIndex = paletteIndex
    }
}

/// Cache ghi nhớ (memoization) tính toán lưới Habit Heatmap để duy trì 120Hz ProMotion khi cuộn.
@MainActor
public final class HabitHeatmapSnapshotCache {

    private struct CacheKey: Hashable {
        let habitId: UUID
        let completedDays: Set<DayKey>
        let today: DayKey
        let firstWeekday: Int
        let paletteIndex: Int
    }

    private var storage: [UUID: (key: CacheKey, snapshot: HabitHeatmapSnapshot)] = [:]

    /// Số lần thực thi thuật toán `HabitHeatmapBuilder.buildGrid` (dùng để đo lường và kiểm thử cache hit/miss).
    public private(set) var buildCount: Int = 0

    public init() {}

    /// Trả về snapshot từ cache nếu hợp lệ, hoặc tính toán mới và lưu cache.
    public func snapshot(
        habit: Habit,
        today: DayKey,
        calendar: Calendar = .autoupdatingCurrent,
        paletteIndex: Int = 0
    ) -> HabitHeatmapSnapshot {
        let key = CacheKey(
            habitId: habit.id,
            completedDays: habit.completedDays,
            today: today,
            firstWeekday: calendar.firstWeekday,
            paletteIndex: paletteIndex
        )

        if let existing = storage[habit.id], existing.key == key {
            return existing.snapshot
        }

        // Cache miss -> Tính toán mới
        buildCount += 1

        let weeks = HabitHeatmapBuilder.buildGrid(
            completedDays: habit.completedDays,
            today: today,
            weeksCount: 52,
            calendar: calendar
        )

        let totalCompletions = habit.completedDays.count
        let currentStreak = habit.streak(on: today, calendar: calendar)
        let isDoneToday = habit.isCompleted(on: today)
        let completionRate = min(100, Int((Double(totalCompletions) / 365.0) * 100.0))

        let newSnapshot = HabitHeatmapSnapshot(
            habitId: habit.id,
            weeks: weeks,
            totalCompletions: totalCompletions,
            currentStreak: currentStreak,
            isDoneToday: isDoneToday,
            completionRate: completionRate,
            paletteIndex: paletteIndex
        )

        storage[habit.id] = (key: key, snapshot: newSnapshot)
        return newSnapshot
    }

    /// Dọn dẹp cache cho các thói quen đã bị xoá khỏi danh sách.
    public func prune(keeping habitIds: Set<UUID>) {
        storage = storage.filter { habitIds.contains($0.key) }
    }

    /// Xoá toàn bộ cache.
    public func clear() {
        storage.removeAll()
    }
}
