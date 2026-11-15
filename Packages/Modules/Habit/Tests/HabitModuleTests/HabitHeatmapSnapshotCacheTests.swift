import Foundation
import Testing
@testable import HabitModule

@Suite
@MainActor
struct HabitHeatmapSnapshotCacheTests {

    private func makeCalendar(firstWeekday: Int = 1) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "vi_VN")
        cal.firstWeekday = firstWeekday
        return cal
    }

    // HC-1: Happy Path - snapshot called 100 times with same input only computes buildGrid once (buildCount == 1)
    @Test
    func test_HC1_cacheHit_computesOnlyOnce() {
        let cache = HabitHeatmapSnapshotCache()
        let habitId = UUID()
        let day1 = DayKey(date: Date())
        let habit = Habit(id: habitId, title: "Đọc sách", completedDays: [day1])
        let today = day1
        let calendar = makeCalendar()

        var snapshot1: HabitHeatmapSnapshot?
        for _ in 0..<100 {
            snapshot1 = cache.snapshot(
                habit: habit,
                today: today,
                calendar: calendar,
                paletteIndex: 0
            )
        }

        #expect(cache.buildCount == 1)
        #expect(snapshot1 != nil)

        // Verify snapshot values
        let directWeeks = HabitHeatmapBuilder.buildGrid(
            completedDays: habit.completedDays,
            today: today,
            weeksCount: 52,
            calendar: calendar
        )
        #expect(snapshot1?.weeks == directWeeks)
        #expect(snapshot1?.totalCompletions == 1)
        #expect(snapshot1?.currentStreak == 1)
        #expect(snapshot1?.isDoneToday == true)
        let expectedRate = min(100, Int((Double(1) / 365.0) * 100.0))
        #expect(snapshot1?.completionRate == expectedRate)
    }

    // HC-2: Cache Invalidation when inputs change
    @Test
    func test_HC2_cacheInvalidation_onDataChange() {
        let cache = HabitHeatmapSnapshotCache()
        let habitId = UUID()
        let calendar = makeCalendar()
        let today = DayKey(date: Date())

        // 1. Initial snapshot
        var habit = Habit(id: habitId, title: "Tập gym", completedDays: [])
        _ = cache.snapshot(habit: habit, today: today, calendar: calendar, paletteIndex: 0)
        #expect(cache.buildCount == 1)

        // 2. Add completed day -> buildCount increments to 2
        habit.completedDays.insert(today)
        _ = cache.snapshot(habit: habit, today: today, calendar: calendar, paletteIndex: 0)
        #expect(cache.buildCount == 2)

        // 3. Change today -> buildCount increments to 3
        let yesterday = DayKey(date: Date().addingTimeInterval(-86400))
        _ = cache.snapshot(habit: habit, today: yesterday, calendar: calendar, paletteIndex: 0)
        #expect(cache.buildCount == 3)

        // 4. Change calendar firstWeekday -> buildCount increments to 4
        let calMonday = makeCalendar(firstWeekday: 2)
        _ = cache.snapshot(habit: habit, today: yesterday, calendar: calMonday, paletteIndex: 0)
        #expect(cache.buildCount == 4)

        // 5. Different habit -> separate entry
        let otherHabit = Habit(id: UUID(), title: "Uống nước", completedDays: [])
        _ = cache.snapshot(habit: otherHabit, today: yesterday, calendar: calMonday, paletteIndex: 1)
        #expect(cache.buildCount == 5)

        // 6. Prune keeping only original habitId
        cache.prune(keeping: [habitId])
        // Requesting otherHabit again should rebuild since it was pruned
        _ = cache.snapshot(habit: otherHabit, today: yesterday, calendar: calMonday, paletteIndex: 1)
        #expect(cache.buildCount == 6)
    }
}
