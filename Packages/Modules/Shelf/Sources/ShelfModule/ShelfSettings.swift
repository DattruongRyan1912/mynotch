import MyNotchCore

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct ShelfSettingKeys {
    static let maxItemsRange = 10...200
    static let imageQualityRange = 0.1...1.0

    let clearOnQuit: SettingKey<Bool>
    let maxItems: SettingKey<Int>
    let removeAfterDragOut: SettingKey<Bool>
    /// JPEG and HEIC quality of converted, compressed and merged images.
    let imageQuality: SettingKey<Double>
    /// Whether the GPS metadata is left out of the images the actions write.
    let stripLocation: SettingKey<Bool>

    init(_ settings: ModuleSettings) {
        clearOnQuit = settings.key("clearOnQuit", default: false)
        maxItems = settings.key("maxItems", default: 50, clampedTo: Self.maxItemsRange)
        removeAfterDragOut = settings.key("removeAfterDragOut", default: false)
        imageQuality = settings.key("imageQuality", default: 0.85, clampedTo: Self.imageQualityRange)
        stripLocation = settings.key("stripLocation", default: true)
    }
}
