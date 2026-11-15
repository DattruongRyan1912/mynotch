import MyNotchCore

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct TodoSettingsKeys {
    /// IDs of lists whose reminders never show. It stores what is hidden, so a list added later shows up by itself.
    let hiddenListIDs: SettingKey<[String]>
    /// Whether reminders with no date count as today's, when they are in the default list.
    let includeUndated: SettingKey<Bool>
    /// The list a quick-added reminder goes to, and the one undated reminders are read from; empty is the one the system
    /// uses for new reminders.
    let defaultListID: SettingKey<String>
    /// The collapsed notch's "Còn 3 việc".
    let showRemaining: SettingKey<Bool>

    init(_ settings: ModuleSettings) {
        hiddenListIDs = settings.key("hiddenListIDs", default: [])
        includeUndated = settings.key("includeUndated", default: true)
        defaultListID = settings.key("defaultListID", default: "")
        showRemaining = settings.key("showRemaining", default: false)
    }
}

/// The settings the list depends on, read at once, so the module can tell whether a settings write changed anything it uses.
nonisolated struct TodoSettings: Equatable, Sendable {
    var hiddenListIDs: [String]
    var includeUndated: Bool
    var defaultListID: String
    var showRemaining: Bool

    @MainActor
    init(_ settings: ModuleSettings) {
        let keys = TodoSettingsKeys(settings)
        hiddenListIDs = settings.value(keys.hiddenListIDs)
        includeUndated = settings.value(keys.includeUndated)
        defaultListID = settings.value(keys.defaultListID)
        showRemaining = settings.value(keys.showRemaining)
    }

    /// Whether the reminders have to be read again for `other`: which lists show and where the undated ones come from are
    /// part of what is read, the notch line is only a way of showing what has been.
    func readsSameReminders(as other: TodoSettings?) -> Bool {
        guard let other else { return false }
        return (hiddenListIDs, includeUndated, defaultListID) == (other.hiddenListIDs, other.includeUndated, other.defaultListID)
    }
}
