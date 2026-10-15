import Foundation

/// The words and shapes the quick-add line is read by. They run on `QuickAddScan`'s copy of the text, which is lower
/// case and has no accents ("thứ" is "thu", "đêm" is "dem"), so a Vietnamese phrase typed without accents reads the same.
nonisolated enum QuickAddPatterns {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    /// Not in the middle of a word or a number.
    private static let edge = #"(?<![a-z0-9])"#
    private static let period = #"sang|trua|chieu|toi|dem|khuya"#
    private static let months = #"january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec"#
    private static let weekdays = #"thu\s*[2-7]|thu\s+(?:hai|ba|tu|nam|sau|bay)|chu nhat|monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|friday|fri|saturday|sat|sunday|sun"#
    private static let weeks = #"tuan sau|tuan toi|tuan nay|next week|this week"#
    /// Not followed by a letter, nor by a dot and a letter: the "p" of "3 p.m." is not a minute.
    private static let minuteUnit = #"(?:phut|ph|p|minutes|minute|mins|min|m)(?![a-z]|\.[a-z])"#
    private static let hourUnit = #"(?:hours|hour|hrs|hr|tieng)"#
    /// What introduces a length: "for 2 hours", "trong 2 tiếng", "kéo dài 90 phút".
    private static let lengthCue = #"(?:for|trong|keo dai|dai|lasting)"#
    private static let lengthEdge = #"(?<![a-z0-9:./,])"#

    // MARK: Days

    static let allDay = regex(#"\#(edge)(?:ca ngay|all[ -]?day)(?![a-z0-9])"#)
    /// "20/10", "20/10/2026", "ngày 20/10".
    static let slashDate = regex(#"(?<![\d/])(?:ngay\s+)?(?<d>\d{1,2})/(?<m>\d{1,2})(?:/(?<y>\d{4}|\d{2}))?(?![\d/])"#)
    /// "ngày 20", "ngày 20 tháng 10".
    static let ngayDate = regex(#"\#(edge)ngay\s+(?<d>\d{1,2})(?:\s+thang\s+(?<m>\d{1,2}))?(?![\d/])"#)
    static let thangDate = regex(#"(?<![\d/])(?<d>\d{1,2})\s+thang\s+(?<m>\d{1,2})(?![\d/])"#)
    /// "oct 20", "october 20th".
    static let monthDay = regex(#"\#(edge)(?<mon>\#(months))\.?\s+(?<d>\d{1,2})(?:st|nd|rd|th)?(?![\d:a-z])"#)
    /// "20 oct", "1st of november".
    static let dayMonth = regex(#"(?<![\d/])(?<d>\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(?<mon>\#(months))(?![a-z])"#)
    /// "chiều mai", "tối nay": a part of a day and the day, with an hour in front of it: "3 chiều mai".
    static let periodDay = regex(#"(?<![a-z0-9:./,])(?:(?<h>\d{1,2})\s+)?(?<p>\#(period))\s+(?<w>nay|mai)(?![a-z0-9])"#)
    static let relativeDay = regex(
        #"\#(edge)(?<w>day after tomorrow|hom nay|ngay mai|ngay mot|ngay kia|tomorrow|tmrw|tmr|today|tonight|this morning|this afternoon|this evening|mai|mot)(?![a-z0-9])"#
    )
    /// "thứ 6", "chủ nhật", "friday", with "next", "this" or "tuần sau" around it.
    static let weekday = regex(
        #"\#(edge)(?:(?<p>\#(period))\s+)?(?:(?<mod>next|this|coming|\#(weeks))\s+)?(?<day>\#(weekdays))(?:\s+(?<after>\#(weeks)))?(?![a-z0-9])"#
    )
    static let week = regex(#"\#(edge)(?:tuan sau|tuan toi|next week)(?![a-z0-9])"#)
    /// What stands before a part of the day to say it is part of what the event is: "ăn trưa", "bữa tối".
    static let mealBefore = regex(#"\#(edge)(?:an|bua|com)\s+$"#)

    // MARK: Times

    static let midnight = regex(#"\#(edge)(?:nua dem(?:\s+nay)?|midnight)(?![a-z0-9])"#)
    static let colonTime = regex(#"(?<h>\d{1,2}):(?<m>[0-5]\d)(?!\d)(?:\s?(?<ap>a\.?m|p\.?m)\.?(?![a-z]))?"#)
    /// "9h", "9h30", "9 giờ 30", "9h rưỡi", "10h kém 15" (a quarter to ten).
    static let hourTime = regex(
        #"(?<h>\d{1,2})\s?(?:h|gio)(?![a-z])(?:\s?(?<m>[0-5]\d)(?!\d)|\s?(?<half>ruoi)(?![a-z])|\s+kem\s+(?<less>[1-5]?\d)(?!\d))?"#
    )
    static let ampmTime = regex(#"(?<h>\d{1,2})\s?(?<ap>a\.?m|p\.?m)\.?(?![a-z])"#)
    /// "3 chiều": the hour and the part of the day, without "h" or "giờ".
    static let periodTime = regex(#"(?<h>\d{1,2})\s(?<p>sang|trua|chieu|dem|khuya|toi(?!\s*\d))(?![a-z0-9])"#)
    static let noon = regex(#"(?:noon|midday)(?![a-z0-9])"#)
    static let bareTime = regex(#"(?<h>\d{1,2})(?!\d)"#)
    /// "toi" is also "tới", the "to" of a range: it is only a part of the day when no number follows.
    static let periodSuffix = regex(#"\s?(?<p>sang|trua|chieu|dem|khuya|toi(?!\s*\d))(?![a-z0-9])"#)
    static let periodBefore = regex(#"\#(edge)(?<p>\#(period))\s*$"#)
    static let separator = regex(#"\s*(?:-|–|—|den|toi|to|until|till)\s*"#)

    // MARK: Lengths

    /// "1h30m", written close together. With a space ("9h 45 phút") the "9h" is a time and the minutes a length.
    static let hoursAndMinutes = regex(
        #"\#(lengthEdge)(?:\#(lengthCue)\s+)?(?<h>\d{1,2})(?:h|gio)(?<m>\d{1,2})\s?\#(minuteUnit)"#
    )
    /// "2 hours", "1 tiếng rưỡi", "1,5 tiếng".
    static let hours = regex(
        #"\#(lengthEdge)(?:\#(lengthCue)\s+)?(?<n>\d+(?:[.,]\d+)?)\s?\#(hourUnit)(?![a-z])(?<half>\s?ruoi(?![a-z]))?"#
    )
    /// "1.5h" can only be a length.
    static let decimalHours = regex(#"\#(lengthEdge)(?:\#(lengthCue)\s+)?(?<n>\d+[.,]\d+)\s?(?:h|gio)(?![a-z])"#)
    /// "for 2h", "kéo dài 1h30": a length by the word in front of it.
    static let cuedHours = regex(
        #"\#(lengthEdge)\#(lengthCue)\s+(?<h>\d{1,2})\s?(?:h|gio)(?![a-z])(?:\s?(?<m>[0-5]\d)(?!\d)|(?<half>\s?ruoi(?![a-z])))?"#
    )
    /// "30m", "45 phút", "30 min".
    static let minutes = regex(#"\#(lengthEdge)(?:\#(lengthCue)\s+)?(?<n>\d{1,3})\s?\#(minuteUnit)"#)

    // MARK: Around what was read

    /// The little words in front of a date or a time, which go with it: "lúc 9h", "vào thứ 6", "on friday", "from 2pm".
    static let connector = regex(#"\#(edge)(?<word>vao luc|vao|luc|at|on|from|tu|@)\s*$"#)
}
