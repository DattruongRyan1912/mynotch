import Foundation

/// What time conversions need to know about the moment and the user.
nonisolated struct TimeEnvironment {
    var now: Date
    /// The zone of the Mac: where a time without a zone is, and the first result for one with a zone.
    var local: TimeZone
    /// The two zones the user chose in Settings.
    var zones: [TimeZone]
}

nonisolated enum TimeConversion {
    /// The time in the user's zone and the chosen ones, with the day it falls on when that is not the day it was written
    /// for. The day is today's date in the zone the time was written in, so "3pm PST" is the 3pm of the Pacific
    /// calendar day now, and daylight saving is the one in force on that day.
    static func conversion(for query: TimeQuery, source text: String, in environment: TimeEnvironment) -> Conversion {
        let source = query.zone
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = source
        var day = sourceCalendar.dateComponents([.year, .month, .day], from: environment.now)
        day.hour = query.hour
        day.minute = query.minute
        guard let instant = sourceCalendar.date(from: day) else { return Conversion(source: text, outcome: .lines([])) }
        let sourceOffset = source.secondsFromGMT(for: instant)

        var targets: [(zone: TimeZone, label: String)] = [
            (environment.local, "Giờ máy · " + TimeZoneCatalog.offsetText(environment.local.secondsFromGMT(for: instant)))
        ]
        targets += environment.zones.map { ($0, TimeZoneCatalog.label(for: $0, at: instant)) }

        var lines: [ConversionLine] = []
        var shownOffsets: Set<Int> = [sourceOffset]
        for target in targets {
            // The same clock as the original, or as a line above, says nothing new.
            guard shownOffsets.insert(target.zone.secondsFromGMT(for: instant)).inserted else { continue }
            lines.append(ConversionLine(label: target.label, text: clock(of: instant, in: target.zone, comparedWith: day)))
        }
        let note = "Hiểu là " + String(format: "%02d:%02d", query.hour, query.minute) + ", " + TimeZoneCatalog.label(for: source, at: instant)
        return Conversion(source: text, outcome: .lines(lines), note: note)
    }

    /// "07:00", with " (hôm sau)", " (hôm trước)" or " (+2 ngày)" when the date is not that of `day`.
    private static func clock(of instant: Date, in zone: TimeZone, comparedWith day: DateComponents) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        let shift = dayNumber(parts) - dayNumber(day)
        switch shift {
        case 0: return time
        case 1: return time + " (hôm sau)"
        case -1: return time + " (hôm trước)"
        default: return time + " (\(shift > 0 ? "+" : "−")\(abs(shift)) ngày)"
        }
    }

    /// Days since a fixed date, for the difference between two calendar dates.
    private static func dayNumber(_ parts: DateComponents) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        let date = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))!
        return Int((date.timeIntervalSince1970 / 86_400).rounded())
    }
}
