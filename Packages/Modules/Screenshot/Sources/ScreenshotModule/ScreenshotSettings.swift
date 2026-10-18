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
    /// The chip with the new capture's thumbnail, "Sửa" and "Chép" (the key keeps the name of the activity it replaced).
    let showCaptureChip: SettingKey<Bool>
    /// "Xong" in the editor also copies the edited image, so it can be pasted straight into a chat.
    let copyWhenDone: SettingKey<Bool>
    /// What fills the canvas where the markup editor grew it past the capture.
    let canvasFill: SettingKey<CanvasFill>

    init(_ settings: ModuleSettings) {
        copyToClipboard = settings.key("copyToClipboard", default: true)
        keepCount = settings.key("keepCount", default: 30, clampedTo: Self.keepCountRange)
        saveLocation = settings.key("saveLocation", default: .desktop)
        windowShadow = settings.key("windowShadow", default: true)
        ocrLanguages = settings.key("ocrLanguages", default: OCRService.defaultLanguages)
        showCaptureChip = settings.key("showCapturedActivity", default: true)
        copyWhenDone = settings.key("copyWhenDone", default: true)
        canvasFill = settings.key("canvasFill", default: .standard)
    }
}
