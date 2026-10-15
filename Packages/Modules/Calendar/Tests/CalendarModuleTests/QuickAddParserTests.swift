import Foundation
import Testing
@testable import CalendarModule

/// One phrase and what the parser must make of it. "Now" is Wednesday 14 October 2026, 09:00 in Ho Chi Minh City, unless
/// a case says otherwise, so "thứ 6" is the 16th and "thứ 2 tuần sau" the 19th.
nonisolated struct PhraseCase: Sendable, CustomTestStringConvertible {
    let text: String
    let title: String
    /// "15 15:00" is 15 October 2026 at 15:00; "11/5 09:00" is 5 November; "2027/1/1 09:00" has the year. An all-day
    /// event gives the date alone: "20".
    let start: String
    /// Same form as `start`; nil for an all-day event.
    let end: String?
    /// The "no time found" note is expected: the event is all-day because the phrase had no time.
    let note: Bool
    let now: String

    var testDescription: String { text }

    /// A timed event.
    init(_ text: String, _ title: String, _ start: String, _ end: String, now: String = "14 09:00") {
        self.text = text
        self.title = title
        self.start = start
        self.end = end
        self.note = false
        self.now = now
    }

    /// An all-day event; `note` is whether the phrase gave no time (and the user is told so).
    init(_ text: String, _ title: String, allDay date: String, note: Bool = true, now: String = "14 09:00") {
        self.text = text
        self.title = title
        self.start = date
        self.end = nil
        self.note = note
        self.now = now
    }

    static let table: [PhraseCase] = vietnamese + english + rolling + misc

    // MARK: Vietnamese

    static let vietnamese: [PhraseCase] = [
        PhraseCase("Họp nhóm 3h chiều mai", "Họp nhóm", "15 15:00", "15 16:00"),
        PhraseCase("ăn trưa với Lan 12:30 thứ 6", "ăn trưa với Lan", "16 12:30", "16 13:30"),
        PhraseCase("gym 18h-19h", "gym", "14 18:00", "14 19:00"),
        PhraseCase("Họp 9h sáng mai", "Họp", "15 09:00", "15 10:00"),
        PhraseCase("họp sáng mai 9h", "họp", "15 09:00", "15 10:00"),
        PhraseCase("Khám răng 2 giờ chiều", "Khám răng", "14 14:00", "14 15:00"),
        PhraseCase("Khám răng 2 giờ rưỡi chiều", "Khám răng", "14 14:30", "14 15:30"),
        PhraseCase("Cà phê 8h30 sáng mai", "Cà phê", "15 08:30", "15 09:30"),
        PhraseCase("Họp 12h trưa", "Họp", "14 12:00", "14 13:00"),
        PhraseCase("Họp 0h", "Họp", "15 00:00", "15 01:00"),
        PhraseCase("Họp nửa đêm", "Họp", "15 00:00", "15 01:00"),
        PhraseCase("họp nửa đêm nay", "họp", "15 00:00", "15 01:00"),
        PhraseCase("thứ 2 tuần sau họp 10h", "họp", "19 10:00", "19 11:00"),
        PhraseCase("Họp thứ 2 tuần sau lúc 14h", "Họp", "19 14:00", "19 15:00"),
        PhraseCase("Họp thứ hai tuần tới 14h", "Họp", "19 14:00", "19 15:00"),
        PhraseCase("Đi chơi chủ nhật 10h", "Đi chơi", "18 10:00", "18 11:00"),
        PhraseCase("Họp 14h-16h", "Họp", "14 14:00", "14 16:00"),
        PhraseCase("Họp từ 14h đến 16h", "Họp", "14 14:00", "14 16:00"),
        PhraseCase("họp từ 9h tới 10h30", "họp", "14 09:00", "14 10:30"),
        PhraseCase("Họp 2h-3h chiều", "Họp", "14 14:00", "14 15:00"),
        PhraseCase("họp 9h30 - 10h15", "họp", "14 09:30", "14 10:15"),
        PhraseCase("họp 9h-10h thứ 6 tuần sau", "họp", "23 09:00", "23 10:00"),
        PhraseCase("họp 9h-10h30 sáng mai", "họp", "15 09:00", "15 10:30"),
        PhraseCase("họp 9h 45 phút", "họp", "14 09:00", "14 09:45"),
        PhraseCase("họp 9h 30p", "họp", "14 09:00", "14 09:30"),
        PhraseCase("họp 9h kéo dài 2 tiếng", "họp", "14 09:00", "14 11:00"),
        PhraseCase("Họp 9h trong 1 tiếng rưỡi", "Họp", "14 09:00", "14 10:30"),
        PhraseCase("họp 9h 1,5 tiếng", "họp", "14 09:00", "14 10:30"),
        PhraseCase("Học bài 20h 90 phút", "Học bài", "14 20:00", "14 21:30"),
        PhraseCase("họp 3h chiều mai 2 tiếng", "họp", "15 15:00", "15 17:00"),
        // A second "1h30" after the start time is a length, not another time.
        PhraseCase("Họp 8h tối thứ 6 tuần sau 1h30", "Họp", "23 20:00", "23 21:30"),
        PhraseCase("Họp 1h30 chiều", "Họp", "14 13:30", "14 14:30"),
        PhraseCase("họp 9 giờ 30", "họp", "14 09:30", "14 10:30"),
        PhraseCase("Họp lúc 15h chiều nay", "Họp", "14 15:00", "14 16:00"),
        PhraseCase("Họp tối nay 8h", "Họp", "14 20:00", "14 21:00"),
        PhraseCase("Họp 7h tối nay", "Họp", "14 19:00", "14 20:00"),
        // The word for the part of the day stays in the title when it is part of what the event is.
        PhraseCase("ăn tối 7h", "ăn tối", "14 19:00", "14 20:00"),
        PhraseCase("ăn tối mai 7h", "ăn tối", "15 19:00", "15 20:00"),
        PhraseCase("ăn sáng 7h", "ăn sáng", "15 07:00", "15 08:00"),
        PhraseCase("Đi bơi 6h sáng", "Đi bơi", "15 06:00", "15 07:00"),
        PhraseCase("họp 11h đêm", "họp", "14 23:00", "15 00:00"),
        PhraseCase("họp 12h đêm", "họp", "15 00:00", "15 01:00"),
        PhraseCase("họp 2h đêm", "họp", "15 02:00", "15 03:00"),
        PhraseCase("Họp 15/10 10h", "Họp", "15 10:00", "15 11:00"),
        PhraseCase("Họp ngày 20 lúc 9h", "Họp", "20 09:00", "20 10:00"),
        PhraseCase("Họp ngày 14 10h", "Họp", "14 10:00", "14 11:00"),
        PhraseCase("họp ngày 5 9h", "họp", "11/5 09:00", "11/5 10:00"),
        PhraseCase("Họp 5 tháng 11 9h", "Họp", "11/5 09:00", "11/5 10:00"),
        PhraseCase("Họp 1/1 9h", "Họp", "2027/1/1 09:00", "2027/1/1 10:00"),
        PhraseCase("họp 10/10 9h", "họp", "2027/10/10 09:00", "2027/10/10 10:00"),
        PhraseCase("họp ngày mốt 10h", "họp", "16 10:00", "16 11:00"),
        PhraseCase("họp ngày kia 10h", "họp", "16 10:00", "16 11:00"),
        PhraseCase("Học tiếng Anh 19h30 thứ 3", "Học tiếng Anh", "20 19:30", "20 20:30"),
        PhraseCase("Họp thứ hai 9h", "Họp", "19 09:00", "19 10:00"),
        PhraseCase("Đá bóng thứ bảy 16h", "Đá bóng", "17 16:00", "17 17:00"),
        PhraseCase("họp thứ 4 10h", "họp", "14 10:00", "14 11:00"),
        // Today is that weekday and the time has gone: it is next week's.
        PhraseCase("họp thứ 4 8h", "họp", "21 08:00", "21 09:00"),
        PhraseCase("Gặp Mai 10h", "Gặp Mai", "14 10:00", "14 11:00"),
        PhraseCase("mai họp 9h", "họp", "15 09:00", "15 10:00"),
        PhraseCase("hop nhom 3h chieu mai", "hop nhom", "15 15:00", "15 16:00"),
        PhraseCase("  Họp   nhóm   3h  chiều  mai  ", "Họp nhóm", "15 15:00", "15 16:00"),
        PhraseCase("Họp nhóm, 3h chiều mai", "Họp nhóm", "15 15:00", "15 16:00"),
        // Midnight is the one at the end of the day named.
        PhraseCase("họp nửa đêm mai", "họp", "16 00:00", "16 01:00"),
        PhraseCase("họp 12h đêm thứ 6", "họp", "17 00:00", "17 01:00"),
        PhraseCase("họp tối nay 12h", "họp", "15 00:00", "15 01:00"),
        // "một" is one, "mốt" is the day after tomorrow.
        PhraseCase("họp một lát 9h", "họp một lát", "14 09:00", "14 10:00"),
        PhraseCase("họp mốt 9h", "họp", "16 09:00", "16 10:00"),
        PhraseCase("họp 11h-1h chiều", "họp", "14 11:00", "14 13:00"),
        PhraseCase("họp 9h rồi 14h", "họp rồi 14h", "14 09:00", "14 10:00"),
        // The hour with the part of the day, without "h" or "giờ".
        PhraseCase("Họp nhóm 3 chiều mai", "Họp nhóm", "15 15:00", "15 16:00"),
        PhraseCase("Họp 7 tối nay", "Họp", "14 19:00", "14 20:00"),
        PhraseCase("Họp 3 chiều", "Họp", "14 15:00", "14 16:00"),
        PhraseCase("họp 9-10 sáng mai", "họp", "15 09:00", "15 10:00"),
        // A quarter to ten.
        PhraseCase("họp 10h kém 15", "họp", "14 09:45", "14 10:45", now: "14 08:00"),
        PhraseCase("họp 3 giờ kém 10 chiều", "họp", "14 14:50", "14 15:50"),
        PhraseCase("họp tuần sau thứ 3 9h", "họp", "20 09:00", "20 10:00"),
        PhraseCase("họp tuần sau thứ 2 9h", "họp", "19 09:00", "19 10:00", now: "14 09:00"),
        // A second time is not a length when it is a time of day: it stays in the title.
        PhraseCase("Họp 9h30-10h30 và 14h", "Họp và 14h", "14 09:30", "14 10:30"),
    ]

    // MARK: English

    static let english: [PhraseCase] = [
        PhraseCase("call with Sam tomorrow 9am 30m", "call with Sam", "15 09:00", "15 09:30"),
        PhraseCase("lunch with Anna friday at noon", "lunch with Anna", "16 12:00", "16 13:00"),
        PhraseCase("Dentist 3pm", "Dentist", "14 15:00", "14 16:00"),
        PhraseCase("dentist at 3:30pm tomorrow", "dentist", "15 15:30", "15 16:30"),
        PhraseCase("standup 9:30", "standup", "14 09:30", "14 10:30"),
        PhraseCase("Team sync monday 10am-11am", "Team sync", "19 10:00", "19 11:00"),
        PhraseCase("Review next monday 2pm for 2 hours", "Review", "19 14:00", "19 16:00"),
        PhraseCase("meeting 9-10am tomorrow", "meeting", "15 09:00", "15 10:00"),
        PhraseCase("movie night tonight 8pm", "movie night", "14 20:00", "14 21:00"),
        PhraseCase("party sat 9pm", "party", "17 21:00", "17 22:00"),
        PhraseCase("flight to Hanoi oct 20 7:45am", "flight to Hanoi", "20 07:45", "20 08:45"),
        PhraseCase("pay rent 1 nov 9am", "pay rent", "11/1 09:00", "11/1 10:00"),
        PhraseCase("Call mom 12am", "Call mom", "15 00:00", "15 01:00"),
        PhraseCase("Doctor 12pm", "Doctor", "14 12:00", "14 13:00"),
        PhraseCase("interview midnight", "interview", "15 00:00", "15 01:00"),
        PhraseCase("brunch sunday 11:30am 1h30m", "brunch", "18 11:30", "18 13:00"),
        PhraseCase("sprint planning next week 10am", "sprint planning", "21 10:00", "21 11:00"),
        PhraseCase("retro this friday 4pm", "retro", "16 16:00", "16 17:00"),
        PhraseCase("Coffee on Friday 15:00", "Coffee", "16 15:00", "16 16:00"),
        PhraseCase("Piano 5pm 45 min", "Piano", "14 17:00", "14 17:45"),
        PhraseCase("yoga 7pm for 1h", "yoga", "14 19:00", "14 20:00"),
        PhraseCase("call 9am 1 hour 30 min", "call", "14 09:00", "14 10:30"),
        PhraseCase("call 9am 2hrs", "call", "14 09:00", "14 11:00"),
        PhraseCase("dinner 7pm day after tomorrow", "dinner", "16 19:00", "16 20:00"),
        PhraseCase("board meeting 14:00-15:30 on 20/10", "board meeting", "20 14:00", "20 15:30"),
        PhraseCase("Lunch at 12:30pm", "Lunch", "14 12:30", "14 13:30"),
        PhraseCase("Sync from 2pm to 3pm friday", "Sync", "16 14:00", "16 15:00"),
        PhraseCase("Mon standup 9:30", "standup", "19 09:30", "19 10:30"),
        PhraseCase("1:1 with Sam 3pm", "1:1 with Sam", "14 15:00", "14 16:00"),
        PhraseCase("Call 555-1234 at 3pm", "Call 555-1234", "14 15:00", "14 16:00"),
        PhraseCase("Tue 11am-12pm design review", "design review", "20 11:00", "20 12:00"),
        PhraseCase("dentist 3 p.m.", "dentist", "14 15:00", "14 16:00"),
        PhraseCase("call 9AM tomorrow", "call", "15 09:00", "15 10:00"),
        PhraseCase("workshop 9am-5pm friday", "workshop", "16 09:00", "16 17:00"),
        PhraseCase("movie 7:30 pm sat", "movie", "17 19:30", "17 20:30"),
        PhraseCase("release v2.0 tomorrow 10am", "release v2.0", "15 10:00", "15 11:00"),
        PhraseCase("birthday party on 25 december", "birthday party", allDay: "12/25"),
        PhraseCase("lunch next friday noon", "lunch", "23 12:00", "23 13:00"),
    ]

    // MARK: Times that have gone

    static let rolling: [PhraseCase] = [
        PhraseCase("gym 18h-19h", "gym", "15 18:00", "15 19:00", now: "14 20:00"),
        PhraseCase("họp 9h", "họp", "15 09:00", "15 10:00", now: "14 09:01"),
        PhraseCase("họp 20h", "họp", "14 20:00", "14 21:00", now: "14 20:00"),
        PhraseCase("họp 19h59", "họp", "15 19:59", "15 20:59", now: "14 20:00"),
        PhraseCase("lunch 12pm", "lunch", "15 12:00", "15 13:00", now: "14 12:30"),
        // Saying today out loud keeps today, even if it has gone.
        PhraseCase("họp 9h hôm nay", "họp", "14 09:00", "14 10:00", now: "14 20:00"),
        PhraseCase("họp tối nay 6h", "họp", "14 18:00", "14 19:00", now: "14 20:00"),
        PhraseCase("họp thứ 4 21h", "họp", "14 21:00", "14 22:00", now: "14 20:00"),
        PhraseCase("họp thứ 4 19h", "họp", "21 19:00", "21 20:00", now: "14 20:00"),
        // An end before the start is the afternoon of a morning start, or else the next day.
        PhraseCase("họp 11h-1h", "họp", "14 11:00", "14 13:00"),
        PhraseCase("họp 20h-8h", "họp", "14 20:00", "15 08:00"),
        // Past midnight is already the next day.
        PhraseCase("họp 23h-1h", "họp", "14 23:00", "15 01:00"),
        PhraseCase("họp 23h-1h", "họp", "15 23:00", "16 01:00", now: "14 23:30"),
    ]

    // MARK: No time, odd input

    static let misc: [PhraseCase] = [
        PhraseCase("Họp", "Họp", allDay: "14"),
        PhraseCase("Ăn trưa", "Ăn trưa", allDay: "14"),
        PhraseCase("Sinh nhật Lan 20/10", "Sinh nhật Lan", allDay: "20"),
        PhraseCase("nghỉ phép ngày mai", "nghỉ phép", allDay: "15"),
        PhraseCase("Đi chợ sáng mai", "Đi chợ", allDay: "15"),
        PhraseCase("họp đêm nay", "họp", allDay: "14"),
        PhraseCase("coffee tomorrow", "coffee", allDay: "15"),
        PhraseCase("Read ch 3 tomorrow", "Read ch 3", allDay: "15"),
        // Asking for all day is not a failure to read the time.
        PhraseCase("họp công ty cả ngày thứ 6", "họp công ty", allDay: "16", note: false),
        PhraseCase("all day offsite friday", "offsite", allDay: "16", note: false),
        // Not a time, not a date: they stay in the title.
        PhraseCase("họp 25h", "họp 25h", allDay: "14"),
        PhraseCase("Họp 31/11 9h", "Họp 31/11", "14 09:00", "14 10:00"),
        PhraseCase("họp 10 người", "họp 10 người", allDay: "14"),
        // A length without a start is nothing, and stays in the title.
        PhraseCase("coffee tomorrow 30m", "coffee 30m", allDay: "15"),
    ]
}

@Suite struct QuickAddParserTests {
    static let calendar = fixedCalendar()

    /// "15 15:00", "11/5 09:00" or "2027/1/1 09:00"; a date alone is midnight.
    static func stamp(_ text: String, in calendar: Calendar = calendar) -> Date {
        let parts = text.split(separator: " ")
        let date = parts[0].split(separator: "/").map { Int($0)! }
        let time = parts.count > 1 ? parts[1].split(separator: ":").map { Int($0)! } : [0, 0]
        let components: DateComponents = switch date.count {
        case 1: DateComponents(year: 2026, month: 10, day: date[0])
        case 2: DateComponents(year: 2026, month: date[0], day: date[1])
        default: DateComponents(year: date[0], month: date[1], day: date[2])
        }
        var full = components
        full.hour = time[0]
        full.minute = time[1]
        return calendar.date(from: full)!
    }

    @Test(arguments: PhraseCase.table)
    func readsThePhrase(_ phrase: PhraseCase) throws {
        let calendar = Self.calendar
        let draft = try #require(QuickAddParser.parse(phrase.text, now: Self.stamp(phrase.now), calendar: calendar))
        #expect(draft.title == phrase.title)
        if let end = phrase.end {
            #expect(!draft.isAllDay)
            #expect(draft.start == Self.stamp(phrase.start), "starts \(draft.start)")
            #expect(draft.end == Self.stamp(end), "ends \(draft.end)")
            #expect(draft.note == nil)
        } else {
            #expect(draft.isAllDay)
            #expect(draft.start == Self.stamp(phrase.start), "starts \(draft.start)")
            #expect(draft.end == calendar.date(byAdding: .day, value: 1, to: Self.stamp(phrase.start)))
            #expect((draft.note == .noTime) == phrase.note)
        }
    }

    @Test func aTimeIsNotGoneUntilItsMinuteIsOver() throws {
        let calendar = Self.calendar
        let thirtySecondsPast = calendar.on(14, at: 20, 0, 30)
        let today = try #require(QuickAddParser.parse("họp 20h", now: thirtySecondsPast, calendar: calendar))
        #expect(today.start == calendar.on(14, at: 20))
        let aMinuteLater = try #require(QuickAddParser.parse("họp 20h", now: calendar.on(14, at: 20, 1), calendar: calendar))
        #expect(aMinuteLater.start == calendar.on(15, at: 20))
    }

    @Test func commasAroundTheTimeAreNotPartOfIt() throws {
        let draft = try #require(QuickAddParser.parse("Họp nhóm,9h,phòng 4B", now: Self.stamp("14 08:00"), calendar: Self.calendar))
        #expect(draft.title == "Họp nhóm,,phòng 4B")
        #expect(draft.start == Self.stamp("14 09:00"))
    }

    @Test func theTableHasFortyPhrasesAndMore() {
        #expect(PhraseCase.table.count >= 40)
        #expect(PhraseCase.vietnamese.count >= 20)
        #expect(PhraseCase.english.count >= 20)
    }

    // MARK: Nothing to read

    /// Whatever is typed, there is an event to show for it, it never ends before it starts, and nothing crashes.
    @Test func anyLineMakesAnEventWithSensibleTimes() {
        let pieces = [
            "họp", "gym", "call", "9h", "3h chiều", "12h trưa", "0h", "25h", "10:30", "9am", "3 pm", "noon", "midnight", "nửa đêm",
            "mai", "ngày mai", "hôm nay", "tonight", "thứ 6", "thứ 2 tuần sau", "monday", "next friday", "20/10", "ngày 5", "5 tháng 11",
            "oct 3", "1/1/2030", "30/2", "-", "–", "đến", "to", "từ", "at", "lúc", "30m", "2 tiếng", "1h30", "90 phút", "cả ngày", "all day",
            "😀", "é", "\u{0301}", " ", "  ", ",", ":", "/", ".", "99999999999999999999", "1,5", "kém", "rưỡi", "Mai", "tối", "sáng",
        ]
        var random = SeededGenerator(seed: 2026)
        let calendar = Self.calendar
        let now = Self.stamp("14 09:00")
        for _ in 0..<3_000 {
            let line = (0..<Int.random(in: 1...8, using: &random)).map { _ in pieces.randomElement(using: &random)! }.joined(separator: Bool.random(using: &random) ? " " : "")
            guard let draft = QuickAddParser.parse(line, now: now, calendar: calendar) else {
                let isBlank = line.allSatisfy { $0.isWhitespace }
                #expect(isBlank, "no event for \(line.debugDescription)")
                continue
            }
            #expect(draft.start < draft.end, "\(line.debugDescription) starts \(draft.start), ends \(draft.end)")
            #expect(draft.end.timeIntervalSince(draft.start) <= 48 * 3_600, "\(line.debugDescription) lasts too long")
            if draft.isAllDay {
                #expect(draft.start == calendar.startOfDay(for: draft.start), "\(line.debugDescription) is all-day but starts \(draft.start)")
                let saidSo = line.contains("cả ngày") || line.lowercased().contains("all day")
                #expect(draft.note == .noTime || saidSo, "\(line.debugDescription) is all-day without a note")
            }
        }
    }

    @Test func anEmptyLineIsNothing() {
        #expect(QuickAddParser.parse("", now: Self.stamp("14 09:00"), calendar: Self.calendar) == nil)
        #expect(QuickAddParser.parse("   \n ", now: Self.stamp("14 09:00"), calendar: Self.calendar) == nil)
    }

    @Test func aLineOfOnlyATimeHasNoTitleYet() throws {
        let draft = try #require(QuickAddParser.parse("3h chiều mai", now: Self.stamp("14 09:00"), calendar: Self.calendar))
        #expect(draft.title.isEmpty)
        #expect(draft.start == Self.stamp("15 15:00"))
    }

    // MARK: The title is what the user typed

    @Test func theTitleKeepsTheUsersWordsAndCase() throws {
        let draft = try #require(QuickAddParser.parse("iPhone launch với Hà Nội team 10:00", now: Self.stamp("14 09:00"), calendar: Self.calendar))
        #expect(draft.title == "iPhone launch với Hà Nội team")
    }

    @Test func textTypedAsSeparateAccentsIsReadAsTheSameLetters() throws {
        let typed = "Ho\u{0323}p nho\u{0301}m 3h chie\u{0300}u mai"
        let draft = try #require(QuickAddParser.parse(typed, now: Self.stamp("14 09:00"), calendar: Self.calendar))
        #expect(draft.title == "Họp nhóm")
        #expect(draft.start == Self.stamp("15 15:00"))
    }

    @Test func emojiAndTheirNeighboursSurvive() throws {
        let draft = try #require(QuickAddParser.parse("🏋️ gym 😀 6pm", now: Self.stamp("14 09:00"), calendar: Self.calendar))
        #expect(draft.title == "🏋️ gym 😀")
        #expect(draft.start == Self.stamp("14 18:00"))
    }

    // MARK: The calendar decides where days begin

    @Test func daysFollowTheCalendarsTimeZone() throws {
        let newYork = fixedCalendar("America/New_York")
        let now = newYork.on(14, at: 9)
        let draft = try #require(QuickAddParser.parse("Họp nhóm 3h chiều mai", now: now, calendar: newYork))
        #expect(draft.start == newYork.on(15, at: 15))
        #expect(draft.end == newYork.on(15, at: 16))
    }

    @Test func tomorrowIsTomorrowInTheCalendarsZoneNotInGreenwich() throws {
        // 01:00 on the 14th in Ho Chi Minh City is still the 13th in UTC.
        let calendar = Self.calendar
        let now = calendar.on(14, at: 1)
        let draft = try #require(QuickAddParser.parse("họp mai 8h", now: now, calendar: calendar))
        #expect(draft.start == calendar.on(15, at: 8))
    }
}

/// The same "random" lines every run.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // SplitMix64.
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
