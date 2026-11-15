import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import CalendarModule

/// The day summary through the module: it follows the calendar, the clock and the settings.
@Suite struct DaySummaryModuleTests {
    let calendar: Calendar
    let source = FakeCalendarDataSource()
    let clock: TestClock
    let module: CalendarModule
    let harness: RegistryHarness

    /// Wednesday 14 October 2026, 08:00, in Ho Chi Minh City.
    init() {
        let calendar = fixedCalendar()
        let clock = TestClock(calendar.on(14, at: 8))
        self.calendar = calendar
        self.clock = clock
        module = CalendarModule(
            dataSource: source, now: { clock.now }, calendar: calendar, openURL: { _ in true },
            dayChangeCenter: NotificationCenter(), wakeCenter: NotificationCenter()
        )
        harness = RegistryHarness([module])
        harness.permissions.statuses[.calendars] = .granted
    }

    var keys: CalendarSettingsKeys { CalendarSettingsKeys(harness.settingsEnvironment(for: "calendar")!.settings) }
    var summary: String? { module.state.daySummary }

    func meeting(_ id: String, _ from: Int, _ to: Int, calendarID: String = "work", day: Int = 14) -> AgendaEvent {
        event(id, calendar.on(day, at: from), calendar.on(day, at: to), calendarID: calendarID)
    }

    func start() async {
        await harness.registry.bootstrap()
        await settle { module.appliedRefreshes >= 1 }
    }

    func tick(to now: Date) async {
        clock.now = now
        let applied = module.appliedRefreshes
        harness.scheduler.advance(by: module.minuteTimerDelay)
        await settle { module.appliedRefreshes > applied }
    }

    // MARK: Showing and updating

    @Test func theSummaryIsThereAfterTheFirstRead() async {
        source.events = [meeting("a", 9, 10), meeting("b", 13, 14)]
        await start()
        #expect(summary == "Hôm nay: 2 sự kiện, rảnh 10:00–13:00, kết thúc lúc 14:00")
    }

    @Test func anEmptyDayStillHasALine() async {
        await start()
        #expect(summary == "Hôm nay: không có sự kiện, rảnh 09:00–18:00")
    }

    @Test func aChangeInTheCalendarUpdatesIt() async {
        source.events = [meeting("a", 9, 10)]
        await start()
        #expect(summary == "Hôm nay: 1 sự kiện, rảnh 10:00–18:00, kết thúc lúc 10:00")
        let applied = module.appliedRefreshes
        source.events = [meeting("a", 9, 10), meeting("b", 10, 18)]
        source.emitChange()
        await settle { module.appliedRefreshes > applied }
        #expect(summary == "Hôm nay: 2 sự kiện, kết thúc lúc 18:00")
    }

    @Test func theClockMovesTheFreeSlot() async {
        source.events = [meeting("a", 9, 10)]
        await start()
        #expect(summary == "Hôm nay: 1 sự kiện, rảnh 10:00–18:00, kết thúc lúc 10:00")
        await tick(to: calendar.on(14, at: 11, 7))
        #expect(summary == "Hôm nay: 1 sự kiện, đã kết thúc lúc 10:00")
        source.events = [meeting("a", 9, 10), meeting("b", 14, 15)]
        await tick(to: calendar.on(14, at: 11, 8))
        #expect(summary == "Hôm nay: 2 sự kiện, rảnh 11:15–14:00, kết thúc lúc 15:00")
    }

    @Test func whenTheDayIsOverItLooksAtTomorrow() async {
        source.events = [meeting("a", 9, 10), meeting("t", 9, 10, day: 15)]
        await start()
        await tick(to: calendar.on(14, at: 12))
        #expect(summary == "Hôm nay: 1 sự kiện, đã kết thúc lúc 10:00, mai bắt đầu lúc 09:00")
    }

    // MARK: What the tab shows is what the summary counts

    @Test func hiddenCalendarsAreNotCounted() async {
        source.events = [meeting("a", 9, 10), meeting("b", 11, 12, calendarID: "personal")]
        harness.settings.set(["personal"], for: keys.hiddenCalendarIDs)
        await start()
        #expect(summary == "Hôm nay: 1 sự kiện, rảnh 10:00–18:00, kết thúc lúc 10:00")
    }

    @Test func allDayEventsCountOnlyWhenTheyAreShown() async {
        source.events = [allDayEvent("holiday", on: 14, in: calendar), meeting("a", 9, 10)]
        await start()
        #expect(summary == "Hôm nay: 2 sự kiện, rảnh 10:00–18:00, kết thúc lúc 10:00")
        let applied = module.appliedRefreshes
        harness.settings.set(false, for: keys.showAllDay)
        await settle { module.appliedRefreshes > applied }
        #expect(summary == "Hôm nay: 1 sự kiện, rảnh 10:00–18:00, kết thúc lúc 10:00")
    }

    // MARK: Settings

    @Test func theSettingHidesTheLineAndBringsItBack() async {
        source.events = [meeting("a", 9, 10)]
        await start()
        #expect(summary != nil)
        var applied = module.appliedRefreshes
        harness.settings.set(false, for: keys.showDaySummary)
        await settle { module.appliedRefreshes > applied }
        #expect(summary == nil)
        applied = module.appliedRefreshes
        harness.settings.set(true, for: keys.showDaySummary)
        await settle { module.appliedRefreshes > applied }
        #expect(summary == "Hôm nay: 1 sự kiện, rảnh 10:00–18:00, kết thúc lúc 10:00")
    }

    @Test func workingHoursComeFromTheSettings() async {
        source.events = [meeting("a", 9, 10)]
        await start()
        harness.settings.set(10, for: keys.workStartHour)
        harness.settings.set(12, for: keys.workEndHour)
        await settle { summary == "Hôm nay: 1 sự kiện, rảnh 10:00–12:00, kết thúc lúc 10:00" }
        #expect(summary == "Hôm nay: 1 sự kiện, rảnh 10:00–12:00, kết thúc lúc 10:00")
        // A pair that makes no sense is the standard day, not a broken line.
        harness.settings.set(20, for: keys.workStartHour)
        harness.settings.set(10, for: keys.workEndHour)
        await settle { summary == "Hôm nay: 1 sự kiện, rảnh 10:00–18:00, kết thúc lúc 10:00" }
        #expect(summary == "Hôm nay: 1 sự kiện, rảnh 10:00–18:00, kết thúc lúc 10:00")
    }

    @Test func theNewSettingsHaveTheirDefaultsAndLimits() {
        let settings = harness.settingsEnvironment(for: "calendar")!.settings
        #expect(settings.value(keys.showDaySummary))
        #expect(settings.value(keys.workStartHour) == 9)
        #expect(settings.value(keys.workEndHour) == 18)
        #expect(settings.value(keys.defaultCalendarID) == "")
        settings.set(-4, for: keys.workStartHour)
        settings.set(40, for: keys.workEndHour)
        #expect(settings.value(keys.workStartHour) == 0)
        #expect(settings.value(keys.workEndHour) == 24)
        settings.set(30, for: keys.workStartHour)
        settings.set(-1, for: keys.workEndHour)
        #expect(settings.value(keys.workStartHour) == 23)
        #expect(settings.value(keys.workEndHour) == 1)
    }

    @Test func choosingTheDefaultCalendarReadsNoCalendar() async {
        await start()
        let reads = source.eventFetchCount
        harness.settings.set("work", for: keys.defaultCalendarID)
        await letAnythingPending()
        #expect(source.eventFetchCount == reads)
    }

    // MARK: Stopping

    @Test func stoppingTheModuleClearsTheLine() async {
        await start()
        #expect(summary != nil)
        await harness.registry.setEnabled(false, for: "calendar")
        #expect(summary == nil)
    }
}
