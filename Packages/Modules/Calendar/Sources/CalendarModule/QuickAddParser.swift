import Foundation

/// Turns one line, in Vietnamese or English, into an event: "Họp nhóm 3h chiều mai", "call with Sam tomorrow 9am 30m",
/// "gym 18h-19h". Rules only, no network and nothing learned. It finds the date, the time, the length and the
/// little words that go with them, and what is left is the title. What it could not read stays in the title.
nonisolated enum QuickAddParser {
    /// How long an event lasts when the line gives no end and no length.
    static let defaultDuration: TimeInterval = 3_600
    /// More than a line of the field ever holds; longer text is cut so a pasted page cannot slow typing down.
    static let maxLength = 500
    /// The longest event a bare "2h" after the start can mean; more is another time of day.
    private static let maxGuessedHours = 8

    /// The draft for `text`, or nil for an empty line. A line with no readable time becomes an all-day event with a note.
    static func parse(_ text: String, now: Date, calendar: Calendar) -> QuickAddDraft? {
        var scan = QuickAddScan(String(text.prefix(maxLength)))
        guard !scan.isBlank else { return nil }
        let days = Days(now: now, calendar: calendar)

        let isAllDay = takeAllDay(&scan)
        let midnight = readMidnight(&scan)
        var hint: Period?
        let day = readDay(&scan, days: days, hint: &hint)
        let length = readLengths(&scan)
        let time = midnight ?? readTime(&scan, hint: hint, hasLength: length != nil)

        let isTimed = time != nil && !isAllDay
        if !isTimed { scan.releaseLengths() }
        scan.takeConnectors(QuickAddPatterns.connector)
        let title = scan.title

        let date = day?.date ?? days.today
        guard isTimed, let time else {
            let end = days.calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
            return QuickAddDraft(title: title, start: date, end: end, isAllDay: true, note: isAllDay ? nil : .noTime)
        }
        return timedDraft(title: title, time: time, length: length ?? time.length, day: day, now: now, days: days)
    }

    private static func timedDraft(
        title: String, time: TimeOfDay, length: TimeInterval?, day: Day?, now: Date, days: Days
    ) -> QuickAddDraft {
        var date = day?.date ?? days.today
        if time.endsTheDay { date = days.adding(1, to: date) }
        var start = days.at(time.start, on: date)
        // A time that has gone means the next one, unless the day was named. 09:00 is not gone at 09:00:30.
        let roll = day?.roll ?? .day
        let thisMinute = days.calendar.dateInterval(of: .minute, for: now)?.start ?? now
        if roll != .none, start < thisMinute {
            date = days.adding(roll == .day ? 1 : 7, to: date)
            start = days.at(time.start, on: date)
        }
        var end = start.addingTimeInterval(length ?? defaultDuration)
        if let endMinutes = time.end {
            end = days.at(endMinutes, on: date)
            if end <= start {
                // "11h-1h" is eleven to one o'clock in the afternoon; "23h-1h" ends the next day.
                let afternoon = end.addingTimeInterval(12 * 3_600)
                end = time.start < 12 * 60 && afternoon > start ? afternoon : days.at(endMinutes, on: days.adding(1, to: date))
            }
        }
        return QuickAddDraft(title: title, start: start, end: end, isAllDay: false, note: nil)
    }
}

// MARK: - Days

private nonisolated extension QuickAddParser {
    /// What the days are measured in: the calendar the user lives by.
    struct Days {
        let now: Date
        let calendar: Calendar
        let today: Date

        init(now: Date, calendar: Calendar) {
            self.now = now
            self.calendar = calendar
            today = calendar.startOfDay(for: now)
        }

        func adding(_ days: Int, to date: Date) -> Date {
            calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
        }

        func at(_ minutes: Int, on date: Date) -> Date {
            calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date) ?? date
        }

        /// 0 for Monday: weeks begin on Monday here.
        var weekdayIndex: Int { (calendar.component(.weekday, from: today) + 5) % 7 }

        /// The date, or nil when the month has no such day.
        func date(year: Int, month: Int, day: Int) -> Date? {
            let components = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: components) else { return nil }
            let read = calendar.dateComponents([.year, .month, .day], from: date)
            return read.year == year && read.month == month && read.day == day ? date : nil
        }
    }

    enum Roll { case none, day, week }

    /// A day the line named, and what happens to it when the time on it has gone.
    struct Day {
        var date: Date
        var roll: Roll
    }

    enum Period {
        case morning, noon, afternoon, evening, night

        init?(_ word: String) {
            switch word {
            case "sang": self = .morning
            case "trua": self = .noon
            case "chieu": self = .afternoon
            case "toi": self = .evening
            case "dem", "khuya": self = .night
            default: return nil
            }
        }
    }

    enum Meridiem { case am, pm }

    struct TimeOfDay {
        /// Minutes after midnight.
        var start: Int
        var end: Int?
        /// "12h đêm", "nửa đêm": the midnight at the end of the day named, which is the next day's 00:00.
        var endsTheDay = false
        /// A "1h30" after the start, taken as how long the event lasts.
        var length: TimeInterval?
    }
}

private nonisolated extension QuickAddParser {
    // MARK: All-day and midnight

    static func takeAllDay(_ scan: inout QuickAddScan) -> Bool {
        let found = scan.matches(QuickAddPatterns.allDay)
        for match in found { scan.take(match.range) }
        return !found.isEmpty
    }

    static func readMidnight(_ scan: inout QuickAddScan) -> TimeOfDay? {
        guard let match = scan.matches(QuickAddPatterns.midnight).first else { return nil }
        scan.take(match.range)
        return TimeOfDay(start: 0, endsTheDay: true)
    }

    // MARK: Day

    /// The first kind of date the line has: a number date, a word like "mai", a weekday, then "next week".
    /// The first kind of date the line has: a number date, a word like "mai", a weekday, then "next week".
    static func readDay(_ scan: inout QuickAddScan, days: Days, hint: inout Period?) -> Day? {
        if let day = readNumberDate(&scan, days: days) { return day }
        if let day = readNamedDay(&scan, days: days, hint: &hint) { return day }
        if let day = readWeekday(&scan, days: days, hint: &hint) { return day }
        if let match = scan.matches(QuickAddPatterns.week).first {
            scan.take(match.range)
            return Day(date: days.adding(7, to: days.today), roll: .none)
        }
        return nil
    }

    static func readNumberDate(_ scan: inout QuickAddScan, days: Days) -> Day? {
        let patterns = [
            QuickAddPatterns.slashDate, QuickAddPatterns.ngayDate, QuickAddPatterns.thangDate,
            QuickAddPatterns.monthDay, QuickAddPatterns.dayMonth,
        ]
        for pattern in patterns {
            for match in scan.matches(pattern) {
                func number(_ name: String) -> Int? { scan.group(name, of: match).flatMap { Int($0) } }
                let month = number("m") ?? scan.group("mon", of: match).flatMap(monthNumber)
                guard let day = number("d"), let date = date(day: day, month: month, year: number("y"), days: days) else { continue }
                scan.take(match.range)
                return Day(date: date, roll: .none)
            }
        }
        return nil
    }

    static func monthNumber(_ name: String) -> Int? {
        ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            .firstIndex(of: String(name.prefix(3))).map { $0 + 1 }
    }

    /// The next day, from today on, that is `day` of `month` (of any month if none is given). A year said out loud is
    /// taken as it is, past or not.
    static func date(day: Int, month: Int?, year: Int?, days: Days) -> Date? {
        let today = days.calendar.dateComponents([.year, .month], from: days.today)
        guard let thisYear = today.year, let thisMonth = today.month else { return nil }
        if let year {
            guard let month else { return nil }
            return days.date(year: year < 100 ? 2000 + year : year, month: month, day: day)
        }
        if let month {
            return (0...4).lazy.compactMap { days.date(year: thisYear + $0, month: month, day: day) }.first { $0 >= days.today }
        }
        return (0...12).lazy.compactMap { offset -> Date? in
            let index = thisMonth - 1 + offset
            return days.date(year: thisYear + index / 12, month: index % 12 + 1, day: day)
        }.first { $0 >= days.today }
    }

    /// "hôm nay", "mai", "chiều mai", "tomorrow", "tonight".
    static func readNamedDay(_ scan: inout QuickAddScan, days: Days, hint: inout Period?) -> Day? {
        for match in scan.matches(QuickAddPatterns.periodDay) {
            guard let word = scan.range(of: "w", in: match), let period = scan.range(of: "p", in: match),
                  let offset = dayOffset(of: scan.string(in: word), typed: scan.typed(in: word)),
                  let part = Period(scan.string(in: period))
            else { continue }
            hint = part
            if scan.range(of: "h", in: match) != nil {
                // "3 chiều mai": the day is read here, and "3 chiều" is left for the time.
                scan.take(word)
            } else {
                takeWithPeriod(&scan, whole: match.range, period: period, rest: word)
            }
            return Day(date: days.adding(offset, to: days.today), roll: .none)
        }
        for match in scan.matches(QuickAddPatterns.relativeDay) {
            let word = scan.string(in: match.range)
            guard let offset = dayOffset(of: word, typed: scan.typed(in: match.range)) else { continue }
            switch word {
            case "tonight", "this evening": hint = .evening
            case "this morning": hint = .morning
            case "this afternoon": hint = .afternoon
            default: break
            }
            scan.take(match.range)
            return Day(date: days.adding(offset, to: days.today), roll: .none)
        }
        return nil
    }

    /// Days from today. "Mai" with a capital is a name and "một" is one, not "mốt", so those two read the typed text.
    static func dayOffset(of word: String, typed: String) -> Int? {
        switch word {
        case "nay", "hom nay", "today", "tonight", "this morning", "this afternoon", "this evening": 0
        case "mai": typed == "mai" ? 1 : nil
        case "ngay mai", "tomorrow", "tmrw", "tmr": 1
        case "mot": typed == "mốt" ? 2 : nil
        case "ngay mot", "ngay kia", "day after tomorrow": 2
        default: nil
        }
    }

    /// Takes a part of the day and the word after it, except when the part of the day is what the event is: "ăn tối nay"
    /// is a dinner, so "tối" stays in the title.
    static func takeWithPeriod(_ scan: inout QuickAddScan, whole: NSRange, period: NSRange, rest: NSRange) {
        let isMeal = scan.lastWord(before: period.location, in: QuickAddPatterns.mealBefore) != nil
        scan.take(isMeal ? rest : whole)
    }

    static func readWeekday(_ scan: inout QuickAddScan, days: Days, hint: inout Period?) -> Day? {
        guard let match = scan.matches(QuickAddPatterns.weekday).first,
              let dayRange = scan.range(of: "day", in: match), let index = weekdayIndex(scan.string(in: dayRange))
        else { return nil }
        // Read before taking: what is taken is blanked out.
        let week = scan.group("after", of: match) ?? scan.group("mod", of: match)
        if let period = scan.range(of: "p", in: match) {
            hint = Period(scan.string(in: period))
            let rest = NSRange(location: dayRange.location, length: match.range.location + match.range.length - dayRange.location)
            takeWithPeriod(&scan, whole: match.range, period: period, rest: rest)
        } else {
            scan.take(match.range)
        }
        let monday = days.adding(-days.weekdayIndex, to: days.today)
        switch week {
        case "tuan sau", "tuan toi", "next week", "next":
            return Day(date: days.adding(7 + index, to: monday), roll: .none)
        case "tuan nay", "this week":
            return Day(date: days.adding(index, to: monday), roll: .none)
        default:
            return Day(date: days.adding((index - days.weekdayIndex + 7) % 7, to: days.today), roll: .week)
        }
    }

    /// 0 for Monday.
    static func weekdayIndex(_ word: String) -> Int? {
        let compact = word.replacingOccurrences(of: " ", with: "")
        // "thu" is also the start of "thursday".
        if compact.hasPrefix("thu") {
            switch compact.dropFirst(3) {
            case "2", "hai": return 0
            case "3", "ba": return 1
            case "4", "tu": return 2
            case "5", "nam": return 3
            case "6", "sau": return 4
            case "7", "bay": return 5
            default: break
            }
        }
        if compact == "chunhat" { return 6 }
        return ["mon", "tue", "wed", "thu", "fri", "sat", "sun"].firstIndex(of: String(compact.prefix(3)))
    }
}

// MARK: - Lengths and times

private nonisolated extension QuickAddParser {
    /// How long the event lasts when the line says so with a word that cannot be a time: "30m", "2 hours", "90 phút".
    /// Several add up ("1 hour 30 min"). They leave the title only if a start turns up for them to belong to.
    static func readLengths(_ scan: inout QuickAddScan) -> TimeInterval? {
        typealias Reader = (QuickAddScan, NSTextCheckingResult) -> Double
        let readers: [(NSRegularExpression, Reader)] = [
            (QuickAddPatterns.hoursAndMinutes, { value("h", $0, $1) * 60 + value("m", $0, $1) }),
            (QuickAddPatterns.hours, { value("n", $0, $1) * 60 + half($0, $1) }),
            (QuickAddPatterns.decimalHours, { value("n", $0, $1) * 60 }),
            (QuickAddPatterns.cuedHours, { value("h", $0, $1) * 60 + value("m", $0, $1) + half($0, $1) }),
            (QuickAddPatterns.minutes, { value("n", $0, $1) }),
        ]
        var total = 0.0
        for (pattern, minutes) in readers {
            for match in scan.matches(pattern) {
                let length = minutes(scan, match)
                guard length > 0, length <= 24 * 60 else { continue }
                scan.take(match.range, as: .length)
                total += length
            }
        }
        return total > 0 ? total * 60 : nil
    }

    /// A number a pattern read, with a comma allowed for the decimal point; 0 when the group took no part.
    static func value(_ name: String, _ scan: QuickAddScan, _ match: NSTextCheckingResult) -> Double {
        scan.group(name, of: match).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) } ?? 0
    }

    /// "rưỡi" adds half an hour.
    static func half(_ scan: QuickAddScan, _ match: NSTextCheckingResult) -> Double {
        scan.range(of: "half", in: match) == nil ? 0 : 30
    }

    /// One time on the line as it was written, before the part of the day is applied.
    struct Atom {
        var range: NSRange
        var hour: Int
        var minute: Int
        var meridiem: Meridiem?
        var period: Period?
        /// A number alone, as in the "9" of "9-10am": only the start of a range can be one.
        var isBare = false
        /// "9h30": the same shape as a length of time, which is what it is when it comes after a start.
        var isHourForm = false

        var end: Int { range.location + range.length }
    }

    /// A time, or a range of two, with the part of the day each says. Later ones may be a length ("1h30" after a start).
    static func readTime(_ scan: inout QuickAddScan, hint: Period?, hasLength: Bool) -> TimeOfDay? {
        var items: [(first: Atom, second: Atom?)] = []
        var location = 0
        while location < scan.count {
            guard !scan.isInsideWord(at: location), let first = atom(in: scan, at: location, allowBare: true) else {
                location += 1
                continue
            }
            if let separator = scan.match(QuickAddPatterns.separator, at: first.end),
               let second = atom(in: scan, at: separator.range.location + separator.range.length, allowBare: false) {
                items.append((first, second))
                location = second.end
            } else if first.isBare {
                location += 1
            } else {
                items.append((first, nil))
                location = first.end
            }
        }
        guard let head = items.first else { return nil }

        let before = scan.lastWord(before: head.first.range.location, in: QuickAddPatterns.periodBefore)
            .flatMap { scan.group("p", of: $0) }.flatMap(Period.init)
        let part = hint ?? before
        var time = resolve(head.first, head.second, part: part)
        let last = head.second ?? head.first
        scan.take(NSRange(location: head.first.range.location, length: last.end - head.first.range.location))

        // A second "1h30" is how long it lasts, unless something else already said so. A range has its end, and
        // a "14h" after a start is another time, not fourteen hours.
        if !hasLength, head.second == nil,
           let item = items.dropFirst().first(where: { $0.second == nil && $0.first.isHourForm && $0.first.period == nil && $0.first.hour <= maxGuessedHours }) {
            let minutes = item.first.hour * 60 + item.first.minute
            if minutes > 0 {
                time.length = TimeInterval(minutes * 60)
                scan.take(item.first.range)
            }
        }
        return time
    }

    static func atom(in scan: QuickAddScan, at location: Int, allowBare: Bool) -> Atom? {
        func number(_ name: String, in match: NSTextCheckingResult) -> Int? { scan.group(name, of: match).flatMap { Int($0) } }
        func meridiem(in match: NSTextCheckingResult) -> Meridiem? { scan.group("ap", of: match).map { $0.hasPrefix("a") ? .am : .pm } }

        func colon() -> Atom? {
            guard let match = scan.match(QuickAddPatterns.colonTime, at: location), let hour = number("h", in: match) else { return nil }
            let meridiem = meridiem(in: match)
            guard meridiem == nil ? hour <= 23 : (1...12).contains(hour) else { return nil }
            return Atom(range: match.range, hour: hour, minute: number("m", in: match) ?? 0, meridiem: meridiem)
        }
        func hours() -> Atom? {
            guard let match = scan.match(QuickAddPatterns.hourTime, at: location), let hour = number("h", in: match), hour <= 23 else { return nil }
            // "10h kém 15" is a quarter to ten.
            let minute = number("less", in: match).map { -$0 } ?? (scan.range(of: "half", in: match) == nil ? number("m", in: match) ?? 0 : 30)
            return Atom(range: match.range, hour: hour, minute: minute, isHourForm: true)
        }
        func ampm() -> Atom? {
            guard let match = scan.match(QuickAddPatterns.ampmTime, at: location), let hour = number("h", in: match),
                  (1...12).contains(hour) else { return nil }
            return Atom(range: match.range, hour: hour, minute: 0, meridiem: meridiem(in: match))
        }
        func partOfDay() -> Atom? {
            guard let match = scan.match(QuickAddPatterns.periodTime, at: location), let hour = number("h", in: match),
                  (1...12).contains(hour), let period = scan.group("p", of: match).flatMap(Period.init) else { return nil }
            return Atom(range: match.range, hour: hour, minute: 0, period: period)
        }
        func noon() -> Atom? {
            scan.match(QuickAddPatterns.noon, at: location).map { Atom(range: $0.range, hour: 12, minute: 0) }
        }
        func bare() -> Atom? {
            guard allowBare, let match = scan.match(QuickAddPatterns.bareTime, at: location), let hour = number("h", in: match),
                  hour <= 23 else { return nil }
            return Atom(range: match.range, hour: hour, minute: 0, isBare: true)
        }

        guard var atom = colon() ?? hours() ?? ampm() ?? partOfDay() ?? noon() ?? bare() else { return nil }
        // "3h chiều": the part of the day after the time belongs to it.
        if atom.meridiem == nil, atom.period == nil, !atom.isBare, let match = scan.match(QuickAddPatterns.periodSuffix, at: atom.end),
           let period = scan.group("p", of: match).flatMap(Period.init) {
            atom.period = period
            atom.range.length = match.range.location + match.range.length - atom.range.location
        }
        return atom
    }

    /// The start, and the end if the line has one, as minutes after midnight.
    static func resolve(_ first: Atom, _ second: Atom?, part: Period?) -> TimeOfDay {
        // "2h-3h chiều" and "9-10am" say it once, for both.
        let shared = second.flatMap { $0.hour >= first.hour ? $0 : nil }
        let startMeridiem = first.meridiem ?? (first.period == nil ? shared?.meridiem : nil)
        let startPeriod = first.period ?? (startMeridiem == nil ? shared?.period : nil) ?? part
        let start = minutes(of: first, meridiem: startMeridiem, period: startPeriod)
        var time = TimeOfDay(start: start.minutes, endsTheDay: start.endsTheDay)
        if let second {
            time.end = minutes(of: second, meridiem: second.meridiem, period: second.period ?? part).minutes
        }
        return time
    }

    /// "3h" is 03:00 unless it says "chiều" or "pm". Hours from 13 are already a 24-hour clock and ignore the word.
    static func minutes(of atom: Atom, meridiem: Meridiem?, period: Period?) -> (minutes: Int, endsTheDay: Bool) {
        var hour = atom.hour
        var endsTheDay = false
        if let meridiem {
            hour = hour % 12 + (meridiem == .pm ? 12 : 0)
        } else if let period, (1...12).contains(hour) {
            switch period {
            case .morning: hour = hour == 12 ? 0 : hour
            case .noon: hour = (1...4).contains(hour) ? hour + 12 : hour
            case .afternoon: hour = hour < 12 ? hour + 12 : hour
            case .evening, .night:
                if hour == 12 {
                    hour = 0
                    endsTheDay = true
                } else if period == .evening || hour > 5 {
                    hour += 12
                }
            }
        }
        let total = hour * 60 + atom.minute
        return (total < 0 ? total + 24 * 60 : total, endsTheDay)
    }
}
