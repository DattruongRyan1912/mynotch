import Foundation
import Testing
@testable import TodoModule

@Suite struct TodoFormatTests {
    let calendar = fixedCalendar()

    @Test func overdueBadgeNamesYesterdayAndThenCountsDays() {
        #expect(TodoFormat.overdueBadge(days: 0) == nil)
        #expect(TodoFormat.overdueBadge(days: 1) == "hôm qua")
        #expect(TodoFormat.overdueBadge(days: 2) == "quá hạn 2 ngày")
        #expect(TodoFormat.overdueBadge(days: 3) == "quá hạn 3 ngày")
        #expect(TodoFormat.overdueBadge(days: 40) == "quá hạn 40 ngày")
    }

    @Test func timeIsShownOnlyForAReminderWithOne() {
        #expect(TodoFormat.time(of: due(14, 15, 30), calendar: calendar) == "15:30")
        #expect(TodoFormat.time(of: due(14, 7, 5), calendar: calendar) == "07:05")
        #expect(TodoFormat.time(of: due(14), calendar: calendar) == nil)
        #expect(TodoFormat.time(of: nil, calendar: calendar) == nil)
    }

    @Test func progressReadsDoneOverTotal() {
        #expect(TodoFormat.progress(TodoProgress(done: 4, total: 7)) == "Xong 4/7")
        #expect(TodoFormat.progress(TodoProgress(done: 0, total: 0)) == "Xong 0/0")
    }

    @Test func remainingSaysHowManyAreLeft() {
        #expect(TodoFormat.remaining(3) == "Còn 3 việc")
        #expect(TodoFormat.remaining(1) == "Còn 1 việc")
    }

    @Test func priorityMarksFollowReminders() {
        #expect(TodoPriority.none.marks == "")
        #expect(TodoPriority.low.marks == "!")
        #expect(TodoPriority.medium.marks == "!!")
        #expect(TodoPriority.high.marks == "!!!")
    }

    @Test func priorityMapsToAndFromEventKitsNumbers() {
        #expect(TodoPriority(eventKit: 0) == .none)
        #expect([1, 2, 3, 4].allSatisfy { TodoPriority(eventKit: $0) == .high })
        #expect(TodoPriority(eventKit: 5) == .medium)
        #expect([6, 7, 8, 9].allSatisfy { TodoPriority(eventKit: $0) == .low })
        #expect(TodoPriority(eventKit: 12) == .none)
        #expect(TodoPriority(eventKit: -1) == .none)
        #expect([TodoPriority.none, .low, .medium, .high].map(\.eventKit) == [0, 9, 5, 1])
        #expect([TodoPriority.none, .low, .medium, .high].allSatisfy { TodoPriority(eventKit: $0.eventKit) == $0 })
    }
}
