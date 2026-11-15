import Foundation

/// Where the module sends the user to see an event.
nonisolated enum CalendarLinks {
    /// What Calendar.app opens an event from. The scheme is not documented, so `open` falls back to `calendarApp`.
    static func eventURL(calendarItemIdentifier: String) -> URL? {
        // `/` and `?` would end the path early, so only characters a path segment can hold stay as they are.
        let segment = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let escaped = calendarItemIdentifier.addingPercentEncoding(withAllowedCharacters: segment) else { return nil }
        return URL(string: "ical://ekevent/\(escaped)")
    }

    static let calendarApp = URL(filePath: "/System/Applications/Calendar.app")
}
