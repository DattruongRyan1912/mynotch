import Foundation
import MyNotchCore

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct ScreenshotSettingKeys {
    static let keepCountRange = 5...200

    let copyToClipboard: SettingKey<Bool>
    let keepCount: SettingKey<Int>
    let saveLocation: SettingKey<SaveLocation>
    let windowShadow: SettingKey<Bool>
    /// BCP 47 identifiers, most important first; see `OCRLanguages`.
    let ocrLanguages: SettingKey<[String]>
    let showCapturedActivity: SettingKey<Bool>

    init(_ settings: ModuleSettings) {
        copyToClipboard = settings.key("copyToClipboard", default: true)
        keepCount = settings.key("keepCount", default: 30, clampedTo: Self.keepCountRange)
        saveLocation = settings.key("saveLocation", default: .desktop)
        windowShadow = settings.key("windowShadow", default: true)
        ocrLanguages = settings.key("ocrLanguages", default: OCRService.defaultLanguages)
        showCapturedActivity = settings.key("showCapturedActivity", default: true)
    }
}
