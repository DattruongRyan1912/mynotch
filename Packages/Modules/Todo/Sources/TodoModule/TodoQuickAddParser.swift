import Foundation

/// What the quick-add line says: a title, the day and time it is due, and how urgent it is.
nonisolated struct TodoDraft: Equatable, Sendable {
    var title: String
    /// Always set: a day alone, or a day with a time. Gregorian, with no time zone, as Reminders keeps them.
    var due: DateComponents
    var priority: TodoPriority
}

/// Turns one line, in Vietnamese or English, into a reminder: "!! gọi khách 15h mai", "buy milk tomorrow 3pm". Rules only,
/// kept small on purpose. Only these are read, and only what is plainly one: a leading "!", "!!" or "!!!"; a time written
/// "15h", "15h30", "15:30", "3 giờ chiều", "3pm"; and "mai", "ngày mai", "tomorrow" or "hôm nay", "today" at the start or end
/// of the line. A bare number is never a time, and a day word in the middle of a sentence ("hoa mai") is left alone. What is
/// not read stays in the title, which is never emptied by it. Accents and capitals do not matter ("goi khach 3h chieu").
nonisolated enum TodoQuickAddParser {
    /// More than a line of the field ever holds; longer text is cut so a pasted page cannot slow typing down.
    static let maxLength = 500

    /// The draft for `text`, or nil for a blank line. With no readable day the reminder is due today.
    static func parse(_ text: String, now: Date, calendar: Calendar) -> TodoDraft? {
        let line = String(text.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        let (priority, rest) = leadingPriority(of: line)
        var tokens = rest.split(whereSeparator: \.isWhitespace).map(Token.init)
        let typed = tokens
        let time = findTime(in: tokens)
        if let time { tokens.removeSubrange(time.range) }
        let day = findDay(in: tokens)
        if let day { tokens.removeSubrange(day.range) }

        var title = join(tokens)
        var offset = day?.offset ?? 0
        var due: (hour: Int, minute: Int)? = time.map { ($0.hour(in: day?.period), $0.minute) }
        if title.isEmpty, !typed.isEmpty {
            // The whole line was a time or a day: that is what the reminder is called.
            title = typed.map(\.text).joined(separator: " ")
            (offset, due) = (0, nil)
        }
        return TodoDraft(title: title, due: dueComponents(dayOffset: offset, clock: due, now: now, calendar: calendar), priority: priority)
    }

    // MARK: Priority

    /// "!", "!!" or "!!!" at the start of the line, and the line without them. Four or more are the user's own punctuation.
    private static func leadingPriority(of line: String) -> (TodoPriority, String) {
        let marks = line.prefix { $0 == "!" }.count
        guard (1...3).contains(marks) else { return (.none, line) }
        let rest = line.dropFirst(marks).trimmingCharacters(in: .whitespaces)
        return (TodoPriority(rawValue: marks) ?? .none, rest)
    }

    // MARK: Words

    /// A word as typed, and as the patterns see it: lower case, no accents ("giờ" is "gio", "đêm" is "dem").
    private struct Token {
        let text: String
        let folded: String

        init(_ text: Substring) {
            self.text = String(text)
            folded = Self.fold(self.text)
        }

        private static func fold(_ text: String) -> String {
            text.lowercased().replacingOccurrences(of: "đ", with: "d").folding(options: .diacriticInsensitive, locale: nil)
        }
    }

    private enum Period: String {
        case sang, trua, chieu, toi, dem, khuya

        /// What the hour as written ("3" in "3 giờ chiều") means on a 24-hour clock.
        func hour(_ hour: Int) -> Int {
            switch self {
            case .sang: hour
            case .trua: (1...5).contains(hour) ? hour + 12 : hour
            case .chieu, .toi: hour < 12 ? hour + 12 : hour
            case .dem, .khuya: (6...11).contains(hour) ? hour + 12 : hour == 12 ? 0 : hour
            }
        }
    }

    private static func join(_ tokens: [Token]) -> String {
        tokens.map(\.text).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",;:-–—@ "))
    }

    // MARK: Time

    private struct TimeMatch {
        var range: Range<Int>
        var hour: Int
        var minute: Int
        /// Set when the time said am or pm: the hour is already on a 24-hour clock.
        var isExact: Bool
        var period: Period?

        /// `fallback` is the part of the day the line named elsewhere ("chiều mai 3h"), for an hour that names none.
        func hour(in fallback: Period?) -> Int {
            isExact ? hour : (period ?? fallback)?.hour(hour) ?? hour
        }
    }

    private static func findTime(in tokens: [Token]) -> TimeMatch? {
        for start in tokens.indices {
            guard var match = time(at: start, in: tokens) else { continue }
            let next = match.range.upperBound
            if !match.isExact, next < tokens.count, let period = Period(rawValue: tokens[next].folded) {
                match.period = period
                match.range = match.range.lowerBound ..< next + 1
            }
            match.range = includingConnector(before: match.range, in: tokens)
            return match
        }
        return nil
    }

    /// "15h", "15h30", "15:30", "3pm", "3:30 pm", "3 giờ", "3 giờ 30", "3 pm" starting at `start`.
    private static func time(at start: Int, in tokens: [Token]) -> TimeMatch? {
        let word = tokens[start].folded
        let following = start + 1 < tokens.count ? tokens[start + 1].folded : ""
        let isPM = word.hasSuffix("pm") || following == "pm"
        /// `exact`: written with am or pm, so 1...12 and turned into the 24-hour clock here.
        func match(_ length: Int, _ hour: Int, _ minute: Int, exact: Bool) -> TimeMatch? {
            guard (exact ? 1...12 : 0...23).contains(hour), (0...59).contains(minute) else { return nil }
            let hour24 = exact ? hour % 12 + (isPM ? 12 : 0) : hour
            return TimeMatch(range: start ..< start + length, hour: hour24, minute: minute, isExact: exact, period: nil)
        }
        if let (hour, minute) = split(word, on: "h") { return match(1, hour, minute, exact: false) }
        if let meridiem = ["am", "pm"].first(where: word.hasSuffix) {
            guard let (hour, minute) = clock(String(word.dropLast(meridiem.count))) else { return nil }
            return match(1, hour, minute, exact: true)
        }
        if let (hour, minute) = split(word, on: ":") {
            if ["am", "pm"].contains(following) { return match(2, hour, minute, exact: true) }
            return match(1, hour, minute, exact: false)
        }
        guard let hour = number(word, digits: 1...2) else { return nil }
        if ["am", "pm"].contains(following) { return match(2, hour, 0, exact: true) }
        guard following == "gio" else { return nil }
        if start + 2 < tokens.count, let minute = number(tokens[start + 2].folded, digits: 2...2) {
            return match(3, hour, minute, exact: false)
        }
        return match(2, hour, 0, exact: false)
    }

    /// "9" or "9:30" as an hour and a minute.
    private static func clock(_ word: String) -> (Int, Int)? {
        if let hour = number(word, digits: 1...2) { return (hour, 0) }
        return split(word, on: ":")
    }

    /// "15h30" or "15:30" as 15 and 30; "15h" as 15 and 0.
    private static func split(_ word: String, on separator: Character) -> (Int, Int)? {
        guard let at = word.firstIndex(of: separator), let hour = number(word[..<at], digits: 1...2) else { return nil }
        let minute = word[word.index(after: at)...]
        if minute.isEmpty { return separator == "h" ? (hour, 0) : nil }
        guard let minutes = number(minute, digits: 2...2) else { return nil }
        return (hour, minutes)
    }

    private static func number(_ text: some StringProtocol, digits: ClosedRange<Int>) -> Int? {
        guard digits.contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }

    /// The little words that go with a time and leave the title with it: "lúc 15h", "vào lúc 15h", "at 9am", "@ 9am".
    private static func includingConnector(before range: Range<Int>, in tokens: [Token]) -> Range<Int> {
        var start = range.lowerBound
        guard start > 0 else { return range }
        switch tokens[start - 1].folded {
        case "at", "@": start -= 1
        case "luc":
            start -= 1
            if start > 0, tokens[start - 1].folded == "vao" { start -= 1 }
        default: break
        }
        return start ..< range.upperBound
    }

    // MARK: Day

    private struct DayMatch {
        var range: Range<Int>
        /// 0 is today, 1 tomorrow.
        var offset: Int
        var period: Period?
    }

    private static let days = ["hom nay": 0, "today": 0, "ngay mai": 1, "tomorrow": 1, "tmrw": 1, "tmr": 1, "mai": 1]

    /// A day phrase at the start of the line, else at its end. One in the middle of a sentence is not read.
    private static func findDay(in tokens: [Token]) -> DayMatch? {
        guard !tokens.isEmpty else { return nil }
        for length in (1...min(2, tokens.count)).reversed() {
            if let match = day(in: 0 ..< length, of: tokens) { return match }
            if let match = day(in: tokens.count - length ..< tokens.count, of: tokens) { return match }
        }
        return nil
    }

    /// "mai", "ngày mai", "tomorrow", "hôm nay", "today", or a part of the day before "mai" or "nay": "chiều mai", "tối nay".
    /// "mai" must be typed in lower case: "Mai" is a name.
    private static func day(in range: Range<Int>, of tokens: [Token]) -> DayMatch? {
        let words = tokens[range]
        if range.count == 2, let period = Period(rawValue: words.first!.folded) {
            let last = words.last!
            if last.text == "mai" { return DayMatch(range: range, offset: 1, period: period) }
            if last.folded == "nay" { return DayMatch(range: range, offset: 0, period: period) }
            return nil
        }
        guard let offset = days[words.map(\.folded).joined(separator: " ")] else { return nil }
        if words.last!.folded == "mai", words.last!.text != "mai", range.count == 1 { return nil }
        return DayMatch(range: range, offset: offset, period: nil)
    }

    // MARK: Due date

    private static func dueComponents(
        dayOffset: Int, clock: (hour: Int, minute: Int)?, now: Date, calendar: Calendar
    ) -> DateComponents {
        let today = calendar.startOfDay(for: now)
        let date = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return DateComponents(
            calendar: Calendar(identifier: .gregorian), year: day.year, month: day.month, day: day.day,
            hour: clock?.hour, minute: clock?.minute
        )
    }
}
