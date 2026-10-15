import Foundation
import Testing
@testable import TodoModule

/// Which reminders belong on today's list, in which order, and how late they are. All of it on plain values.
@Suite struct TodoTodayTests {
    /// Wednesday 14 October 2026, 09:00, in Ho Chi Minh City.
    let calendar = fixedCalendar()
    var now: Date { calendar.on(14, at: 9) }
    let rules = TodoRules(defaultListID: "inbox")

    func ids(_ reminders: [TodoReminder], rules: TodoRules? = nil, now: Date? = nil) -> [String] {
        TodoToday.items(from: reminders, rules: rules ?? self.rules, now: now ?? self.now, calendar: calendar).map(\.id)
    }

    // MARK: What belongs

    @Test func dueTodayAndOverdueBelongAndLaterDaysDoNot() {
        let reminders = [
            todo("today", due: due(14)), todo("yesterday", due: due(13)), todo("lastWeek", due: due(7)),
            todo("tomorrow", due: due(15)), todo("nextMonth", due: due(30)),
        ]
        #expect(Set(ids(reminders)) == ["today", "yesterday", "lastWeek"])
    }

    @Test func aTimedReminderBelongsToItsDayWhetherOrNotTheTimeHasGone() {
        let reminders = [todo("past", due: due(14, 7)), todo("later", due: due(14, 18)), todo("tomorrowMorning", due: due(15, 0, 30))]
        #expect(Set(ids(reminders)) == ["past", "later"])
    }

    @Test func undatedRemindersCountOnlyFromTheDefaultList() {
        let reminders = [todo("mine"), todo("other", list: "work")]
        #expect(ids(reminders) == ["mine"])
    }

    @Test func undatedRemindersAreLeftOutWhenTheSettingIsOff() {
        var off = rules
        off.includeUndated = false
        #expect(ids([todo("mine"), todo("dated", due: due(14))], rules: off) == ["dated"])
    }

    @Test func withoutADefaultListNoUndatedReminderCounts() {
        var none = rules
        none.defaultListID = nil
        #expect(ids([todo("mine")], rules: none).isEmpty)
    }

    @Test func datedRemindersComeFromEveryListThatIsNotHidden() {
        let reminders = [todo("a", due: due(14), list: "inbox"), todo("b", due: due(14), list: "work"), todo("c", due: due(14), list: "home")]
        var hidden = rules
        hidden.hiddenListIDs = ["work"]
        #expect(Set(ids(reminders, rules: hidden)) == ["a", "c"])
    }

    @Test func hidingTheDefaultListHidesItsUndatedRemindersToo() {
        var hidden = rules
        hidden.hiddenListIDs = ["inbox"]
        #expect(ids([todo("mine"), todo("dated", due: due(14), list: "work")], rules: hidden) == ["dated"])
    }

    // MARK: Completed today

    @Test func completedTodayStaysAsADoneItem() throws {
        let items = TodoToday.items(
            from: [todo("open", due: due(14)), todo("done", due: due(14), done: calendar.on(14, at: 8))],
            rules: rules, now: now, calendar: calendar
        )
        #expect(items.map(\.id) == ["open", "done"] || items.map(\.id) == ["done", "open"])
        #expect(try #require(items.first { $0.id == "done" }).reminder.isCompleted)
        #expect(TodoToday.progress(of: items) == TodoProgress(done: 1, total: 2))
    }

    @Test func completedYesterdayDoesNotCount() {
        #expect(ids([todo("old", due: due(13), done: calendar.on(13, at: 20))]).isEmpty)
    }

    @Test func completedTodayButDueLaterDoesNotCount() {
        #expect(ids([todo("early", due: due(16), done: calendar.on(14, at: 8))]).isEmpty)
    }

    @Test func anOverdueReminderCompletedTodayCounts() {
        #expect(ids([todo("late", due: due(10), done: calendar.on(14, at: 8))]) == ["late"])
    }

    @Test func undatedCompletedTodayFollowsTheUndatedRules() {
        let reminders = [todo("mine", done: calendar.on(14, at: 8)), todo("other", list: "work", done: calendar.on(14, at: 8))]
        #expect(ids(reminders) == ["mine"])
    }

    @Test func aCompletedReminderWithoutADateIsNotToday() {
        var reminder = todo("odd", due: due(14))
        reminder.isCompleted = true
        #expect(ids([reminder]).isEmpty)
    }

    @Test func progressCountsDoneAgainstEverythingOnTheList() {
        let items = TodoToday.items(
            from: [
                todo("a", due: due(14)), todo("b", due: due(13)), todo("c"),
                todo("d", due: due(14), done: calendar.on(14, at: 8)), todo("e", due: due(14), done: calendar.on(14, at: 8)),
            ],
            rules: rules, now: now, calendar: calendar
        )
        let progress = TodoToday.progress(of: items)
        #expect(progress == TodoProgress(done: 2, total: 5))
        #expect(progress.remaining == 3)
    }

    // MARK: How late

    @Test func overdueDaysCountWholeDaysFromTheDueDay() throws {
        let reminders = [
            todo("today", due: due(14)), todo("yesterday", due: due(13)), todo("three", due: due(11)),
            todo("timedYesterday", due: due(13, 23, 30)), todo("timedToday", due: due(14, 7)),
        ]
        let items = TodoToday.items(from: reminders, rules: rules, now: now, calendar: calendar)
        func days(_ id: String) throws -> Int { try #require(items.first { $0.id == id }).overdueDays }
        #expect(try days("today") == 0)
        #expect(try days("yesterday") == 1)
        #expect(try days("three") == 3)
        #expect(try days("timedYesterday") == 1)
        #expect(try days("timedToday") == 0)
    }

    @Test func aReminderFromAnotherMonthStillCountsDays() throws {
        var reminder = todo("old")
        reminder.due = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 9, day: 28)
        let items = TodoToday.items(from: [reminder], rules: rules, now: now, calendar: calendar)
        #expect(try #require(items.first).overdueDays == 16)
    }

    // MARK: Order

    @Test func overdueComesFirstOldestFirstThenTodayByTime() {
        let reminders = [
            todo("evening", due: due(14, 18)), todo("noon", due: due(14, 12)), todo("yesterday", due: due(13)),
            todo("lastWeek", due: due(7)), todo("morning", due: due(14, 8)),
        ]
        #expect(ids(reminders) == ["lastWeek", "yesterday", "morning", "noon", "evening"])
    }

    @Test func todayGoesTimedThenAllDayThenUndated() {
        let reminders = [todo("undated"), todo("allDay", due: due(14)), todo("timed", due: due(14, 17))]
        #expect(ids(reminders) == ["timed", "allDay", "undated"])
    }

    @Test func priorityBreaksATieOfTimeHighestFirst() {
        let reminders = [
            todo("none", due: due(14)), todo("low", due: due(14), priority: .low), todo("high", due: due(14), priority: .high),
            todo("medium", due: due(14), priority: .medium),
        ]
        #expect(ids(reminders) == ["high", "medium", "low", "none"])
    }

    @Test func priorityDoesNotOutrankTime() {
        let reminders = [todo("urgentLater", due: due(14, 17), priority: .high), todo("calmEarlier", due: due(14, 8))]
        #expect(ids(reminders) == ["calmEarlier", "urgentLater"])
    }

    @Test func priorityDoesNotLiftTodayAboveOverdue() {
        #expect(ids([todo("urgent", due: due(14, 8), priority: .high), todo("late", due: due(13))]) == ["late", "urgent"])
    }

    @Test func equalRemindersKeepAFixedOrderWhateverOrderTheyCameIn() {
        let reminders = [todo("b", due: due(14)), todo("c", due: due(14)), todo("a", due: due(14))]
        #expect(ids(reminders) == ["a", "b", "c"])
        #expect(ids(reminders.reversed()) == ["a", "b", "c"])
    }

    @Test func aDoneItemKeepsItsPlaceAmongTheOthers() {
        let reminders = [todo("a", due: due(14, 8)), todo("b", due: due(14, 10), done: calendar.on(14, at: 9)), todo("c", due: due(14, 12))]
        #expect(ids(reminders) == ["a", "b", "c"])
    }

    // MARK: Days change

    @Test func whatWasLeftUndoneCarriesOverToTheNextDay() throws {
        let reminders = [todo("left", due: due(14)), todo("finished", due: due(14), done: calendar.on(14, at: 17)), todo("dated", due: due(15))]
        let tomorrow = calendar.on(15, at: 0, 5)
        let items = TodoToday.items(from: reminders, rules: rules, now: tomorrow, calendar: calendar)
        #expect(items.map(\.id) == ["left", "dated"])
        #expect(try #require(items.first).overdueDays == 1)
        #expect(TodoToday.progress(of: items) == TodoProgress(done: 0, total: 2))
    }

    @Test func theDayIsTheCalendarsNotUTCs() {
        // 23:30 on the 14th in Ho Chi Minh City is still the 14th there, though it is 16:30 UTC.
        let late = calendar.on(14, at: 23, 30)
        #expect(ids([todo("today", due: due(14)), todo("tomorrow", due: due(15))], now: late) == ["today"])
        #expect(ids([todo("today", due: due(14)), todo("tomorrow", due: due(15))], now: late.addingTimeInterval(31 * 60)) == ["today", "tomorrow"])
    }

    @Test func aDueTimeInAnotherZoneIsPlacedOnTheDayItFallsOnHere() {
        // 18:00 on the 13th in New York is 05:00 on the 14th in Ho Chi Minh City.
        var reminder = todo("travelling")
        reminder.due = DateComponents(
            calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "America/New_York"), year: 2026, month: 10, day: 13, hour: 18
        )
        let items = TodoToday.items(from: [reminder], rules: rules, now: now, calendar: calendar)
        #expect(items.map(\.overdueDays) == [0])
    }
}
