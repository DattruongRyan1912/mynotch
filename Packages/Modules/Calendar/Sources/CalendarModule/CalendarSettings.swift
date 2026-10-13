import MyNotchCore

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct CalendarSettingsKeys {
    static let meetingLeadRange = 1...30

    /// Reminders due today, and the access request their toggle makes.
    let showReminders: SettingKey<Bool>
    /// How early before a meeting the live activity appears.
    let meetingLeadMinutes: SettingKey<Int>
    /// IDs of calendars whose events never show.
    let hiddenCalendarIDs: SettingKey<[String]>
    let showAllDay: SettingKey<Bool>

    init(_ settings: ModuleSettings) {
        showReminders = settings.key("showReminders", default: false)
        meetingLeadMinutes = settings.key("meetingLeadMinutes", default: 5, clampedTo: Self.meetingLeadRange)
        hiddenCalendarIDs = settings.key("hiddenCalendarIDs", default: [])
        showAllDay = settings.key("showAllDay", default: true)
    }
}

/// All four settings read at once, so the module can tell whether a settings write changed anything it uses.
nonisolated struct CalendarSettings: Equatable, Sendable {
    var showReminders: Bool
    var meetingLeadMinutes: Int
    var hiddenCalendarIDs: [String]
    var showAllDay: Bool

    @MainActor
    init(_ settings: ModuleSettings) {
        let keys = CalendarSettingsKeys(settings)
        showReminders = settings.value(keys.showReminders)
        meetingLeadMinutes = settings.value(keys.meetingLeadMinutes)
        hiddenCalendarIDs = settings.value(keys.hiddenCalendarIDs)
        showAllDay = settings.value(keys.showAllDay)
    }
}
