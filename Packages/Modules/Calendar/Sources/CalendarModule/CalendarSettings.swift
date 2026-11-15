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
    /// The line at the top of the tab: how many events today, when there is free time, when the day ends.
    let showDaySummary: SettingKey<Bool>
    /// Whole hours free time is looked for in; `WorkingHours` makes sense of a pair that does not.
    let workStartHour: SettingKey<Int>
    let workEndHour: SettingKey<Int>
    /// The calendar a quick-added event goes to; empty is the one the system uses for new events. Read when an event
    /// is saved, so it is not part of `CalendarSettings`.
    let defaultCalendarID: SettingKey<String>
    /// What the user answered to the meeting card ("Báo lại", "Bỏ qua"), per occurrence. Not part of
    /// `CalendarSettings`: the module writes it itself, and a write must not make it read the calendar again.
    let meetingReplies: SettingKey<MeetingReplies>

    init(_ settings: ModuleSettings) {
        showReminders = settings.key("showReminders", default: false)
        meetingLeadMinutes = settings.key("meetingLeadMinutes", default: 5, clampedTo: Self.meetingLeadRange)
        hiddenCalendarIDs = settings.key("hiddenCalendarIDs", default: [])
        showAllDay = settings.key("showAllDay", default: true)
        showDaySummary = settings.key("showDaySummary", default: true)
        workStartHour = settings.key("workStartHour", default: 9, clampedTo: 0...23)
        workEndHour = settings.key("workEndHour", default: 18, clampedTo: 1...24)
        defaultCalendarID = settings.key("defaultCalendarID", default: "")
        meetingReplies = settings.key("meetingReplies", default: MeetingReplies())
    }
}

/// The settings the agenda depends on, read at once, so the module can tell whether a settings write changed anything it uses.
nonisolated struct CalendarSettings: Equatable, Sendable {
    var showReminders: Bool
    var meetingLeadMinutes: Int
    var hiddenCalendarIDs: [String]
    var showAllDay: Bool
    var showDaySummary: Bool
    var workingHours: WorkingHours

    @MainActor
    init(_ settings: ModuleSettings) {
        let keys = CalendarSettingsKeys(settings)
        showReminders = settings.value(keys.showReminders)
        meetingLeadMinutes = settings.value(keys.meetingLeadMinutes)
        hiddenCalendarIDs = settings.value(keys.hiddenCalendarIDs)
        showAllDay = settings.value(keys.showAllDay)
        showDaySummary = settings.value(keys.showDaySummary)
        workingHours = WorkingHours(start: settings.value(keys.workStartHour), end: settings.value(keys.workEndHour))
    }
}
