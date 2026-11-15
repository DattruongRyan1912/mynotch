import MyNotchCore

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct ShortcutsSettingKeys {
    /// Identifiers of the shortcuts shown in the tab, in the order the user picked them.
    let favorites: SettingKey<[String]>

    init(_ settings: ModuleSettings) {
        favorites = settings.key("favorites", default: [])
    }
}
