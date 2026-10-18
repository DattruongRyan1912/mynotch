import Foundation
import MyNotchCore

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct ScreenshotSettingKeys {
    static let keepCountRange = 5...200
    /// How far a click zooms in: the editor's slider keeps the same limits.
    static let zoomScaleRange = 1.25...3.0
    /// Seconds without activity before a zoom goes back out.
    static let zoomHoldRange = 0.5...5.0

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
    /// "default", "off" or a microphone's ID (`MicrophoneChoice`).
    let recordMicrophone: SettingKey<String>
    /// What the system plays goes into the recording as a second sound.
    let recordSystemAudio: SettingKey<Bool>
    /// Three seconds of counting before a recording starts.
    let recordCountdown: SettingKey<Bool>
    /// What a new recording is edited with at first: how far a click zooms, how long a zoom stays after the last activity, the ring
    /// at every click and the export level. The editor changes them per recording.
    let zoomScale: SettingKey<Double>
    let zoomHoldSeconds: SettingKey<Double>
    let clickEffect: SettingKey<Bool>
    let exportLevel: SettingKey<ExportLevel>

    init(_ settings: ModuleSettings) {
        copyToClipboard = settings.key("copyToClipboard", default: true)
        keepCount = settings.key("keepCount", default: 30, clampedTo: Self.keepCountRange)
        saveLocation = settings.key("saveLocation", default: .desktop)
        windowShadow = settings.key("windowShadow", default: true)
        ocrLanguages = settings.key("ocrLanguages", default: OCRService.defaultLanguages)
        showCaptureChip = settings.key("showCapturedActivity", default: true)
        copyWhenDone = settings.key("copyWhenDone", default: true)
        canvasFill = settings.key("canvasFill", default: .standard)
        recordMicrophone = settings.key("recordMicrophone", default: MicrophoneChoice.systemDefault)
        recordSystemAudio = settings.key("recordSystemAudio", default: false)
        recordCountdown = settings.key("recordCountdown", default: true)
        zoomScale = settings.key("zoomScale", default: ZoomRules.standard.scale, clampedTo: Self.zoomScaleRange)
        zoomHoldSeconds = settings.key("zoomHoldSeconds", default: ZoomRules.standard.idleTimeout, clampedTo: Self.zoomHoldRange)
        clickEffect = settings.key("clickEffect", default: true)
        exportLevel = settings.key("exportLevel", default: .chat)
    }
}
