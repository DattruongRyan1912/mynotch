import Foundation

/// Text for numbers in the tab. Fixed formats rather than the user's locale, so the figures are the same
/// everywhere and a test can pin them down.
nonisolated enum AgentFormat {
    /// `999`, `1.2K`, `12.3K`, `123K`, `1.2M`: three significant digits at most.
    static func tokens(_ count: Int) -> String {
        guard count >= 1_000 else { return String(count) }
        var value = Double(count) / 1_000
        var unit = "K"
        if value >= 999.5 {
            value /= 1_000
            unit = "M"
        }
        let text = String(format: value < 100 ? "%.1f" : "%.0f", value)
        return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + unit
    }

    /// Dollars and cents; a dash when there is no figure (a model without a price).
    static func cost(_ usd: Double?) -> String {
        guard let usd else { return "—" }
        if usd > 0, usd < 0.005 { return "<$0.01" }
        return String(format: "$%.2f", usd)
    }

    /// `m:ss` or `h:mm:ss`, the way the live timers read.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? Int(min(max(seconds, 0), 1e9)) : 0
        let (hours, minutes, rest) = (total / 3_600, total % 3_600 / 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// How a rate-limit window is called, from its length; nil when the length is unknown.
    static func windowName(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        if minutes == 7 * 1_440 { return "Tuần" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440) ngày" }
        if minutes % 60 == 0 { return "\(minutes / 60) giờ" }
        return "\(minutes) phút"
    }

    private static let weekdays = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]

    /// The time of day of a reset, with the weekday when it is not today.
    static func reset(_ date: Date, now: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        let clock = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        guard !calendar.isDate(date, inSameDayAs: now), let weekday = parts.weekday, weekdays.indices.contains(weekday - 1) else { return clock }
        return "\(weekdays[weekday - 1]) \(clock)"
    }
}
