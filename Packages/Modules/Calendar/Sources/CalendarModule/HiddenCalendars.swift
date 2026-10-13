import Foundation

/// The "hidden calendars" setting stores what is hidden, so a calendar added later shows up by itself.
nonisolated enum HiddenCalendars {
    static func isVisible(_ id: String, hidden: [String]) -> Bool {
        !hidden.contains(id)
    }

    /// `hidden` with `id` added or removed; hiding twice adds it once.
    static func setting(_ id: String, visible: Bool, in hidden: [String]) -> [String] {
        if visible { return hidden.filter { $0 != id } }
        return hidden.contains(id) ? hidden : hidden + [id]
    }

    /// By title as the user would sort them, then by id so equal titles keep a fixed order.
    static func sorted(_ calendars: [CalendarInfo]) -> [CalendarInfo] {
        calendars.sorted {
            switch $0.title.localizedStandardCompare($1.title) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.id < $1.id
            }
        }
    }
}
