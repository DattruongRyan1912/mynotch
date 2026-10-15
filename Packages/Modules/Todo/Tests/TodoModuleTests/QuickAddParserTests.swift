import Foundation
import Testing
@testable import TodoModule

/// One phrase and what the parser must make of it. "Now" is Wednesday 14 October 2026, 09:00 in Ho Chi Minh City.
nonisolated struct PhraseCase: Sendable, CustomTestStringConvertible {
    let text: String
    let title: String
    /// The day of October 2026 the reminder is due: 14 is today, 15 tomorrow.
    let day: Int
    /// "15:00" for a reminder with a time; nil for one due on a day alone.
    let time: String?
    let priority: TodoPriority

    var testDescription: String { text }

    init(_ text: String, _ title: String, day: Int = 14, time: String? = nil, priority: TodoPriority = .none) {
        self.text = text
        self.title = title
        self.day = day
        self.time = time
        self.priority = priority
    }

    static let table: [PhraseCase] = plain + times + vietnameseTimes + days + both + priorities + staysInTheTitle

    static let plain: [PhraseCase] = [
        PhraseCase("mua sữa", "mua sữa"),
        PhraseCase("Mua sữa cho bé", "Mua sữa cho bé"),
        PhraseCase("  mua   sữa  ", "mua sữa"),
        PhraseCase("buy milk", "buy milk"),
    ]

    static let times: [PhraseCase] = [
        PhraseCase("gọi khách 15h", "gọi khách", time: "15:00"),
        PhraseCase("gọi khách 15h30", "gọi khách", time: "15:30"),
        PhraseCase("gọi khách 15:30", "gọi khách", time: "15:30"),
        PhraseCase("gọi khách 9:05", "gọi khách", time: "09:05"),
        PhraseCase("gọi khách 3pm", "gọi khách", time: "15:00"),
        PhraseCase("gọi khách 3:30pm", "gọi khách", time: "15:30"),
        PhraseCase("gọi khách 3:30 PM", "gọi khách", time: "15:30"),
        PhraseCase("call Sam 9am", "call Sam", time: "09:00"),
        PhraseCase("call Sam at 9am", "call Sam", time: "09:00"),
        PhraseCase("call Sam @ 9am", "call Sam", time: "09:00"),
        PhraseCase("call Sam at 15:00", "call Sam", time: "15:00"),
        PhraseCase("lunch 12pm", "lunch", time: "12:00"),
        PhraseCase("sleep 12am", "sleep", time: "00:00"),
        PhraseCase("9 am standup", "standup", time: "09:00"),
        PhraseCase("gọi khách lúc 15h", "gọi khách", time: "15:00"),
        PhraseCase("gọi khách vào lúc 15h", "gọi khách", time: "15:00"),
        PhraseCase("họp 8h", "họp", time: "08:00"),
    ]

    static let vietnameseTimes: [PhraseCase] = [
        PhraseCase("họp 3h chiều", "họp", time: "15:00"),
        PhraseCase("họp 3 giờ chiều", "họp", time: "15:00"),
        PhraseCase("họp 15 giờ", "họp", time: "15:00"),
        PhraseCase("họp 8h sáng", "họp", time: "08:00"),
        PhraseCase("họp 8 giờ tối", "họp", time: "20:00"),
        PhraseCase("ăn cơm 12h trưa", "ăn cơm", time: "12:00"),
        PhraseCase("ngủ 11 giờ đêm", "ngủ", time: "23:00"),
        PhraseCase("gọi khách 3 giờ 30 chiều", "gọi khách", time: "15:30"),
        PhraseCase("3 giờ chiều gọi khách", "gọi khách", time: "15:00"),
        PhraseCase("goi khach 3h chieu", "goi khach", time: "15:00"),
    ]

    static let days: [PhraseCase] = [
        PhraseCase("mua sữa mai", "mua sữa", day: 15),
        PhraseCase("mai mua sữa", "mua sữa", day: 15),
        PhraseCase("mua sữa ngày mai", "mua sữa", day: 15),
        PhraseCase("mua sữa ngay mai", "mua sữa", day: 15),
        PhraseCase("buy milk tomorrow", "buy milk", day: 15),
        PhraseCase("tomorrow buy milk", "buy milk", day: 15),
        PhraseCase("Buy milk Tomorrow", "Buy milk", day: 15),
        PhraseCase("buy milk tmrw", "buy milk", day: 15),
        PhraseCase("hôm nay mua sữa", "mua sữa"),
        PhraseCase("mua sữa hôm nay", "mua sữa"),
        PhraseCase("buy milk today", "buy milk"),
    ]

    static let both: [PhraseCase] = [
        PhraseCase("mua sữa mai 15h", "mua sữa", day: 15, time: "15:00"),
        PhraseCase("mai 15h mua sữa", "mua sữa", day: 15, time: "15:00"),
        PhraseCase("họp 3h chiều mai", "họp", day: 15, time: "15:00"),
        PhraseCase("họp chiều mai 3h", "họp", day: 15, time: "15:00"),
        PhraseCase("họp tối nay 8h", "họp", day: 14, time: "20:00"),
        PhraseCase("mua sữa 2pm mai", "mua sữa", day: 15, time: "14:00"),
        PhraseCase("call Sam tomorrow 9am", "call Sam", day: 15, time: "09:00"),
        PhraseCase("call Sam tomorrow at 9:30am", "call Sam", day: 15, time: "09:30"),
        PhraseCase("tomorrow 3pm dentist", "dentist", day: 15, time: "15:00"),
    ]

    static let priorities: [PhraseCase] = [
        PhraseCase("!mua sữa", "mua sữa", priority: .low),
        PhraseCase("! mua sữa", "mua sữa", priority: .low),
        PhraseCase("!! mua sữa", "mua sữa", priority: .medium),
        PhraseCase("!!! mua sữa", "mua sữa", priority: .high),
        PhraseCase("!!!mua sữa", "mua sữa", priority: .high),
        PhraseCase("!!! gọi khách 15h mai", "gọi khách", day: 15, time: "15:00", priority: .high),
        PhraseCase("!! pay rent tomorrow", "pay rent", day: 15, priority: .medium),
    ]

    /// What looks like a time or a day but is not one stays in the title.
    static let staysInTheTitle: [PhraseCase] = [
        PhraseCase("mua 3 cái bánh", "mua 3 cái bánh"),
        PhraseCase("25h họp", "25h họp"),
        PhraseCase("họp 13pm", "họp 13pm"),
        PhraseCase("họp 9:75", "họp 9:75"),
        PhraseCase("gọi Mai", "gọi Mai"),
        PhraseCase("gọi mai", "gọi", day: 15),
        PhraseCase("hoa mai đẹp quá", "hoa mai đẹp quá"),
        PhraseCase("mai", "mai"),
        PhraseCase("15h", "15h"),
        PhraseCase("mua sữa !", "mua sữa !"),
        PhraseCase("hello!", "hello!"),
        PhraseCase("!!!! mua sữa", "!!!! mua sữa"),
        PhraseCase("buy tomorrowland tickets", "buy tomorrowland tickets"),
    ]
}

@Suite struct QuickAddParserTests {
    let calendar = fixedCalendar()
    var now: Date { calendar.on(14, at: 9) }

    func parse(_ text: String) -> TodoDraft? {
        TodoQuickAddParser.parse(text, now: now, calendar: calendar)
    }

    @Test(arguments: PhraseCase.table)
    func readsThePhrase(_ phrase: PhraseCase) throws {
        let draft = try #require(parse(phrase.text))
        #expect(draft.title == phrase.title)
        #expect(draft.due.day == phrase.day)
        #expect(draft.due.month == 10 && draft.due.year == 2026)
        #expect(draft.priority == phrase.priority)
        let time = draft.due.hour.map { String(format: "%02d:%02d", $0, draft.due.minute ?? 0) }
        #expect(time == phrase.time)
    }

    @Test func theTableHasEnoughPhrases() {
        #expect(PhraseCase.table.count >= 30)
    }

    @Test func aBlankLineIsNothing() {
        #expect(parse("") == nil)
        #expect(parse("   \n ") == nil)
    }

    @Test func priorityMarksAloneLeaveNoTitleToSave() throws {
        let draft = try #require(parse("!!!"))
        #expect(draft.title.isEmpty)
        #expect(draft.priority == .high)
    }

    @Test func aDayAloneIsDueAllDayAndNeverCarriesATime() throws {
        let due = try #require(parse("mua sữa")).due
        #expect(due.hour == nil)
        #expect(due.minute == nil)
        #expect(due.timeZone == nil)
        #expect(due.calendar?.identifier == .gregorian)
    }

    @Test func aTimeThatHasGoneStaysToday() throws {
        // Said at 09:00, "8h" is this morning, already late: the list shows it overdue by the clock, not moved to tomorrow.
        let draft = try #require(parse("họp 8h"))
        #expect(draft.due.day == 14)
        #expect(draft.due.hour == 8)
    }

    @Test func theDayIsTheCalendarsNotUTCs() throws {
        // 23:30 in Ho Chi Minh City is still the 14th, though it is already the 15th somewhere east of there.
        let late = calendar.on(14, at: 23, 30)
        let today = try #require(TodoQuickAddParser.parse("việc", now: late, calendar: calendar))
        let tomorrow = try #require(TodoQuickAddParser.parse("việc mai", now: late, calendar: calendar))
        #expect(today.due.day == 14)
        #expect(tomorrow.due.day == 15)
    }

    @Test func tomorrowCrossesTheEndOfAMonth() throws {
        let lastDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9))!
        let draft = try #require(TodoQuickAddParser.parse("việc mai", now: lastDay, calendar: calendar))
        #expect(draft.due.month == 11)
        #expect(draft.due.day == 1)
    }

    @Test func aVeryLongLineIsCutSoTypingStaysQuick() throws {
        let draft = try #require(parse(String(repeating: "a", count: 5_000)))
        #expect(draft.title.count == TodoQuickAddParser.maxLength)
    }

    @Test func theHintSaysOnlyWhatTheLineChanged() throws {
        func hint(_ text: String) throws -> String? {
            TodoFormat.hint(for: try #require(parse(text)), now: now, calendar: calendar)
        }
        #expect(try hint("mua sữa") == nil)
        #expect(try hint("mua sữa 15h") == "15:00")
        #expect(try hint("mua sữa mai") == "Ngày mai")
        #expect(try hint("mua sữa mai 15h30") == "Ngày mai · 15:30")
        #expect(try hint("!! mua sữa mai 15h") == "Ngày mai · 15:00 · !!")
        #expect(try hint("!!! mua sữa") == "!!!")
    }
}
