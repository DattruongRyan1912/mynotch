import Foundation
import Testing
@testable import TodoModule

@Suite struct EisenhowerQuadrantTests {
    let now = Date(timeIntervalSince1970: 1_791_972_000) // Wed 14 Oct 2026 09:00:00 UTC
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return cal
    }

    private func dueToday() -> DateComponents {
        DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: 14)
    }

    // MARK: - 1. Truth Table Classification (12/12 Cases)

    @Test func truthTableClassify() {
        // High priority
        #expect(EisenhowerQuadrant.classify(priority: .high, hasDue: true, overdueDays: 1) == .doFirst)
        #expect(EisenhowerQuadrant.classify(priority: .high, hasDue: true, overdueDays: 0) == .doFirst)
        #expect(EisenhowerQuadrant.classify(priority: .high, hasDue: false, overdueDays: 0) == .schedule)

        // Medium priority
        #expect(EisenhowerQuadrant.classify(priority: .medium, hasDue: true, overdueDays: 2) == .doFirst)
        #expect(EisenhowerQuadrant.classify(priority: .medium, hasDue: true, overdueDays: 0) == .doFirst)
        #expect(EisenhowerQuadrant.classify(priority: .medium, hasDue: false, overdueDays: 0) == .schedule)

        // Low priority
        #expect(EisenhowerQuadrant.classify(priority: .low, hasDue: true, overdueDays: 1) == .delegate)
        #expect(EisenhowerQuadrant.classify(priority: .low, hasDue: true, overdueDays: 0) == .delegate)
        #expect(EisenhowerQuadrant.classify(priority: .low, hasDue: false, overdueDays: 0) == .eliminate)

        // None priority
        #expect(EisenhowerQuadrant.classify(priority: .none, hasDue: true, overdueDays: 3) == .delegate)
        #expect(EisenhowerQuadrant.classify(priority: .none, hasDue: true, overdueDays: 0) == .delegate)
        #expect(EisenhowerQuadrant.classify(priority: .none, hasDue: false, overdueDays: 0) == .eliminate)
    }

    // MARK: - 2. Partitioning

    @Test func partitionPreservesOrderAndLingering() {
        let reminder1 = todo("1", due: dueToday(), priority: .high)
        let reminder2 = todo("2", due: dueToday(), priority: .high)
        let reminder3 = todo("3", due: nil, priority: .high)
        let reminder4 = todo("4", due: dueToday(), priority: .none)
        var reminder5 = todo("5", due: nil, priority: .none)
        reminder5.isCompleted = true

        let items = [
            TodoItem(reminder: reminder1, overdueDays: 0),
            TodoItem(reminder: reminder2, overdueDays: 0),
            TodoItem(reminder: reminder3, overdueDays: 0),
            TodoItem(reminder: reminder4, overdueDays: 0),
            TodoItem(reminder: reminder5, overdueDays: 0)
        ]

        let partitioned = EisenhowerQuadrant.partition(items)
        #expect(partitioned[.doFirst]?.map(\.id) == ["1", "2"])
        #expect(partitioned[.schedule]?.map(\.id) == ["3"])
        #expect(partitioned[.delegate]?.map(\.id) == ["4"])
        #expect(partitioned[.eliminate]?.map(\.id) == ["5"])
    }

    // MARK: - 3. Quick-Add Parser Tags (9 Spec Cases)

    @Test func quickAddParserCases() throws {
        // Case 1: !q1 gọi khách 15h
        let p1 = try #require(TodoQuickAddParser.parse("!q1 gọi khách 15h", now: now, calendar: calendar))
        #expect(p1.quadrant == .doFirst)
        #expect(p1.title == "gọi khách")
        #expect(p1.priority == .high)
        #expect(p1.due?.hour == 15)
        #expect(p1.due?.minute == 0)

        // Case 2: mua sữa #q4
        let p2 = try #require(TodoQuickAddParser.parse("mua sữa #q4", now: now, calendar: calendar))
        #expect(p2.quadrant == .eliminate)
        #expect(p2.title == "mua sữa")
        #expect(p2.priority == .none)
        #expect(p2.due == nil)

        // Case 3: #Q3 gửi báo cáo
        let p3 = try #require(TodoQuickAddParser.parse("#Q3 gửi báo cáo", now: now, calendar: calendar))
        #expect(p3.quadrant == .delegate)
        #expect(p3.title == "gửi báo cáo")
        #expect(p3.priority == .none)
        #expect(p3.due != nil)

        // Case 4: fix #q1 bug
        let p4 = try #require(TodoQuickAddParser.parse("fix #q1 bug", now: now, calendar: calendar))
        #expect(p4.quadrant == nil)
        #expect(p4.title == "fix #q1 bug")

        // Case 5: !q1
        let p5 = try #require(TodoQuickAddParser.parse("!q1", now: now, calendar: calendar))
        #expect(p5.quadrant == nil)
        #expect(p5.title == "!q1")

        // Case 6: !q5 x
        let p6 = try #require(TodoQuickAddParser.parse("!q5 x", now: now, calendar: calendar))
        #expect(p6.quadrant == nil)
        #expect(p6.priority == .low)
        #expect(p6.title == "q5 x")

        // Case 7: !!q1 abc
        let p7 = try #require(TodoQuickAddParser.parse("!!q1 abc", now: now, calendar: calendar))
        #expect(p7.quadrant == nil)
        #expect(p7.priority == .medium)
        #expect(p7.title == "q1 abc")

        // Case 8: !q2 mai 9h họp
        let p8 = try #require(TodoQuickAddParser.parse("!q2 mai 9h họp", now: now, calendar: calendar))
        #expect(p8.quadrant == .schedule)
        #expect(p8.title == "họp")
        #expect(p8.priority == .high)
        #expect(p8.due?.hour == 9)
        #expect(p8.due?.day == 15) // tomorrow

        // Case 9: mua hoa mai
        let p9 = try #require(TodoQuickAddParser.parse("mua hoa mai", now: now, calendar: calendar))
        #expect(p9.due?.day == 14) // today, not tomorrow!
        #expect(p9.title == "mua hoa mai")
    }

    // MARK: - 4. Hint Formatting

    @Test func hintFormatting() throws {
        let p1 = try #require(TodoQuickAddParser.parse("!q1 gọi khách 15h", now: now, calendar: calendar))
        let h1 = TodoFormat.hint(for: p1, now: now, calendar: calendar)
        #expect(h1 == "15:00 · !!! · Q1 · Làm ngay")

        let p2 = try #require(TodoQuickAddParser.parse("mua sữa #q4", now: now, calendar: calendar))
        let h2 = TodoFormat.hint(for: p2, now: now, calendar: calendar)
        #expect(h2 == "Q4 · Xóa bỏ")

        let p8 = try #require(TodoQuickAddParser.parse("!q2 mai 9h họp", now: now, calendar: calendar))
        let h8 = TodoFormat.hint(for: p8, now: now, calendar: calendar)
        #expect(h8 == "Ngày mai · 09:00 · !!!")
    }
}
