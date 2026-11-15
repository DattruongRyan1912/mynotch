import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import HabitModule

final class FakeClock: @unchecked Sendable {
    var date = Date(timeIntervalSinceReferenceDate: 100_000)
    func advance(days: Int) {
        date = date.addingTimeInterval(TimeInterval(days * 86_400))
    }
}

@MainActor
struct HabitFixture {
    let clock = FakeClock()
    let calendar = Calendar(identifier: .gregorian)
    let dayChangeCenter = NotificationCenter()
    let wakeCenter = NotificationCenter()
    let module: HabitModule
    let harness: RegistryHarness

    init() {
        let clock = clock, calendar = calendar, dayChangeCenter = dayChangeCenter, wakeCenter = wakeCenter
        module = HabitModule(
            now: { clock.date },
            calendar: calendar,
            dayChangeCenter: dayChangeCenter,
            wakeCenter: wakeCenter
        )
        harness = RegistryHarness([module])
    }

    var fileURL: URL {
        harness.storageRoot.storage(for: "habit").directory.appending(path: "habits.json")
    }

    func start() async {
        await harness.registry.bootstrap()
    }

    var settings: ModuleSettings {
        harness.settingsEnvironment(for: "habit")!.settings
    }

    var keys: HabitSettingsKeys {
        HabitSettingsKeys(settings)
    }

    func enableShowRemaining(_ enabled: Bool = true) {
        settings.set(enabled, for: keys.showRemaining)
    }
}

@Suite("HabitModule Tests")
@MainActor
struct HabitModuleTests {

    @Test func descriptorAndTab() async throws {
        let fixture = HabitFixture()
        let desc = fixture.module.descriptor
        #expect(desc.id == "habit")
        #expect(desc.displayName == "Thói quen")
        #expect(desc.systemImage == "arrow.triangle.2.circlepath")
        #expect(desc.defaultEnabled == true)
        #expect(desc.order == 660)

        await fixture.start()
        let tab = try #require(fixture.module.makeTab())
        #expect(tab.id == "habit")
        #expect(tab.title == "Thói quen")
        #expect(tab.systemImage == "arrow.triangle.2.circlepath")
        #expect(tab.preferredHeight == HabitTabView.height)
        #expect(tab.preferredHeight! <= NotchTab.heightRange.upperBound)
        #expect(tab.acceptsKeyboard == true)
    }

    @Test func streakCalculation() {
        let calendar = Calendar(identifier: .gregorian)
        let today = DayKey(date: Date(timeIntervalSinceReferenceDate: 100_000), calendar: calendar)

        var habit = Habit(title: "Đọc sách")
        #expect(habit.streak(on: today, calendar: calendar) == 0)

        // Hoàn thành hôm nay: streak = 1
        habit.toggle(on: today)
        #expect(habit.isCompleted(on: today))
        #expect(habit.streak(on: today, calendar: calendar) == 1)

        // Hoàn thành thêm hôm qua và hôm kia: streak = 3
        let yesterday = today.addingDays(-1, calendar: calendar)
        let twoDaysAgo = today.addingDays(-2, calendar: calendar)
        habit.toggle(on: yesterday)
        habit.toggle(on: twoDaysAgo)
        #expect(habit.streak(on: today, calendar: calendar) == 3)

        // Bỏ tick hôm nay: streak hôm qua (2 ngày) vẫn được giữ để hiển thị trong ngày
        habit.toggle(on: today)
        #expect(!habit.isCompleted(on: today))
        #expect(habit.streak(on: today, calendar: calendar) == 2)

        // Bỏ tick hôm qua: đứt chuỗi liên tiếp -> streak = 0
        habit.toggle(on: yesterday)
        #expect(habit.streak(on: today, calendar: calendar) == 0)
    }

    @Test func sevenDayHeatmap() {
        let calendar = Calendar(identifier: .gregorian)
        let today = DayKey(date: Date(timeIntervalSinceReferenceDate: 100_000), calendar: calendar)

        var habit = Habit(title: "Uống nước")
        habit.toggle(on: today) // index 6 (hôm nay)
        habit.toggle(on: today.addingDays(-2, calendar: calendar)) // index 4

        let days = habit.lastSevenDays(endingOn: today, calendar: calendar)
        #expect(days.count == 7)
        #expect(days[6] == true)  // Hôm nay
        #expect(days[5] == false) // Hôm qua
        #expect(days[4] == true)  // 2 ngày trước
        #expect(days[3] == false)
        #expect(days[2] == false)
        #expect(days[1] == false)
        #expect(days[0] == false) // 6 ngày trước
    }

    @Test func persistenceAndStateManagement() async throws {
        let fixture = HabitFixture()
        await fixture.start()

        let state = fixture.module.state
        #expect(state.habits.isEmpty)

        // Thêm thói quen hợp lệ
        let added = state.addHabit(title: "Chạy bộ 5km")
        #expect(added != nil)
        #expect(state.habits.count == 1)
        #expect(state.habits.first?.title == "Chạy bộ 5km")

        // Bỏ qua tiêu đề rỗng
        #expect(state.addHabit(title: "   ") == nil)
        #expect(state.habits.count == 1)

        // Lưu xuống đĩa
        fixture.module.save()
        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path(percentEncoded: false)))

        // Đọc lại từ file
        let reloaded = HabitModule.load(from: fixture.fileURL)
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.title == "Chạy bộ 5km")

        // Toggle hôm nay và kiểm tra tiến độ
        let habitID = state.habits[0].id
        #expect(state.progress.done == 0)
        #expect(state.progress.total == 1)
        #expect(state.progress.remaining == 1)

        state.toggleToday(id: habitID)
        #expect(state.progress.done == 1)
        #expect(state.progress.remaining == 0)

        // Xoá thói quen
        state.deleteHabit(id: habitID)
        #expect(state.habits.isEmpty)
        #expect(state.progress.total == 0)
    }

    @Test func liveActivityPublishing() async {
        let fixture = HabitFixture()
        await fixture.start()

        let state = fixture.module.state
        state.addHabit(title: "Viết code Swift")

        // Mặc định showRemaining là false: không publish
        #expect(fixture.harness.activities.current == nil)

        // Bật showRemaining: tự động publish activity qua Observations mà không cần gọi publish thủ công
        fixture.enableShowRemaining(true)
        await Task.yield()

        let current = fixture.harness.activities.current
        #expect(current != nil)
        #expect(current?.activity.id == HabitModule.activityID)
        #expect(current?.activity.priority == .low)

        // Hoàn thành thói quen: tự động withdraw activity khi lưu
        state.toggleToday(id: state.habits[0].id)
        fixture.module.save()
        #expect(fixture.harness.activities.current == nil)
    }

    @Test func dayChangeNotificationUpdatesToday() async {
        let fixture = HabitFixture()
        await fixture.start()

        let initialToday = fixture.module.state.today

        // Đồng hồ tiến thêm 1 ngày
        fixture.clock.advance(days: 1)

        // Bắn notification sang ngày mới
        fixture.dayChangeCenter.post(name: .NSCalendarDayChanged, object: nil)

        let updatedToday = fixture.module.state.today
        #expect(updatedToday != initialToday)
    }

    @Test func headerProductivityMetricsComputation() async {
        let fixture = HabitFixture()
        await fixture.start()

        let state = fixture.module.state
        let h1 = state.addHabit(title: "Đọc sách")!
        let h2 = state.addHabit(title: "Chạy bộ")!
        _ = state.addHabit(title: "Uống nước")!

        let today = state.today
        let cal = fixture.calendar

        // Hoàn thành 2 trong 3 thói quen hôm nay trực tiếp trong state
        state.toggleToday(id: h1.id)
        state.toggleToday(id: h2.id)

        // Giả lập streak liên tiếp 5 ngày cho h1 trực tiếp trong state
        for dayOffset in 1...4 {
            let pastDay = today.addingDays(-dayOffset, calendar: cal)
            state.toggle(id: h1.id, on: pastDay)
        }

        let metrics = state.headerMetrics(today: today, calendar: cal)

        #expect(metrics.totalHabits == 3)
        #expect(metrics.doneToday == 2)
        #expect(metrics.maxStreak == 5)
    }

    @Test func headerProductivityMetricsEdgeCases() async {
        let fixture = HabitFixture()
        await fixture.start()

        let state = fixture.module.state
        let today = state.today
        let cal = fixture.calendar

        // Kịch bản A: Không có habit nào
        let emptyMetrics = state.headerMetrics(today: today, calendar: cal)
        #expect(emptyMetrics.totalHabits == 0)
        #expect(emptyMetrics.doneToday == 0)
        #expect(emptyMetrics.maxStreak == 0)

        // Kịch bản B: Hoàn thành 100%
        let h1 = state.addHabit(title: "Thói quen 1")!
        let h2 = state.addHabit(title: "Thói quen 2")!
        state.toggleToday(id: h1.id)
        state.toggleToday(id: h2.id)

        let allMetrics = state.headerMetrics(today: today, calendar: cal)
        #expect(allMetrics.totalHabits == 2)
        #expect(allMetrics.doneToday == allMetrics.totalHabits)
        #expect(allMetrics.maxStreak >= 1)
    }
}
