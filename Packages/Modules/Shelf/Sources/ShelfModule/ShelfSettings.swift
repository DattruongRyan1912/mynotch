import MyNotchCore

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct ShelfSettingKeys {
    static let maxItemsRange = 10...200

    let clearOnQuit: SettingKey<Bool>
    let maxItems: SettingKey<Int>
    let removeAfterDragOut: SettingKey<Bool>

    init(_ settings: ModuleSettings) {
        clearOnQuit = settings.key("clearOnQuit", default: false)
        maxItems = settings.key("maxItems", default: 50, clampedTo: Self.maxItemsRange)
        removeAfterDragOut = settings.key("removeAfterDragOut", default: false)
    }
}
