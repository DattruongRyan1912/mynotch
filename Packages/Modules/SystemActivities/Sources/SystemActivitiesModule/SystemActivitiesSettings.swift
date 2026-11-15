import MyNotchCore
import SwiftUI

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct SystemActivitiesKeys {
    static let durationRange = 1.0...6.0

    let bluetooth: SettingKey<Bool>
    let network: SettingKey<Bool>
    let capsLock: SettingKey<Bool>
    let downloads: SettingKey<Bool>
    let volume: SettingKey<Bool>
    /// Off by default: it swallows the keys, which takes a permission.
    let replaceHUD: SettingKey<Bool>
    let hudVolume: SettingKey<Bool>
    let hudBrightness: SettingKey<Bool>
    let hudKeyboardLight: SettingKey<Bool>
    let durationSeconds: SettingKey<Double>

    init(_ settings: ModuleSettings) {
        bluetooth = settings.key("bluetooth", default: true)
        network = settings.key("network", default: true)
        capsLock = settings.key("capsLock", default: true)
        downloads = settings.key("downloads", default: true)
        volume = settings.key("volume", default: true)
        replaceHUD = settings.key("replaceHUD", default: false)
        hudVolume = settings.key("hudVolume", default: true)
        hudBrightness = settings.key("hudBrightness", default: true)
        hudKeyboardLight = settings.key("hudKeyboardLight", default: true)
        durationSeconds = settings.key("durationSeconds", default: 2.5, clampedTo: Self.durationRange)
    }
}

extension SystemActivitiesKeys {
    /// The kinds of media key the HUD takes over, as the sub-toggles are set now.
    func mediaKeySelection(_ settings: ModuleSettings) -> MediaKeySelection {
        MediaKeySelection(
            volume: settings.value(hudVolume), brightness: settings.value(hudBrightness),
            keyboardLight: settings.value(hudKeyboardLight))
    }
}

/// Plain rows: the Settings page provides the Form and the section.
struct SystemActivitiesSettingsView: View {
    let keys: SystemActivitiesKeys
    let settings: ModuleSettings
    @State private var accessibility: MediaKeyAccessibility

    init(keys: SystemActivitiesKeys, settings: ModuleSettings, permissions: any PermissionCenter) {
        self.keys = keys
        self.settings = settings
        _accessibility = State(initialValue: MediaKeyAccessibility(permissions: permissions, isWanted: { settings.value(keys.replaceHUD) }))
    }

    var body: some View {
        Group {
            Toggle(isOn: settings.binding(keys.bluetooth)) {
                Text("Thiết bị Bluetooth kết nối hoặc ngắt")
                Text("Lần đầu bật, macOS sẽ hỏi quyền Bluetooth. Pin chỉ hiện khi thiết bị báo được.")
            }
            Toggle("Mạng có hoặc mất", isOn: settings.binding(keys.network))
            Toggle("Caps Lock bật hoặc tắt", isOn: settings.binding(keys.capsLock))
            Toggle(isOn: settings.binding(keys.downloads)) {
                Text("Tải xuống hoàn tất")
                Text("Lần đầu theo dõi, macOS sẽ hỏi quyền truy cập thư mục Tải xuống. Nếu đã từ chối, hãy cấp lại trong Cài đặt Hệ thống > Quyền riêng tư & Bảo mật > Tệp và Thư mục.")
            }
            Toggle(isOn: settings.binding(keys.volume)) {
                Text("Thay đổi âm lượng")
                Text("Hiện song song với bảng âm lượng của hệ thống, không thay thế nó.")
            }
            Stepper(value: settings.binding(keys.durationSeconds), in: SystemActivitiesKeys.durationRange, step: 0.5) {
                Text("Hiện trong \(settings.value(keys.durationSeconds).formatted(.number.precision(.fractionLength(0...1)))) giây")
            }
            Toggle(isOn: settings.binding(keys.replaceHUD)) {
                Text("Thay HUD của macOS")
                Text("Bắt phím âm lượng, độ sáng và đèn bàn phím để hiện thanh của MyNotch thay cho HUD của macOS. Cần quyền Accessibility.")
            }
            // While this row is shown: when it appears and when the switch changes, then every 2 s, so the hint goes
            // by itself once the permission is allowed.
            .task(id: settings.value(keys.replaceHUD)) {
                while !Task.isCancelled {
                    accessibility.refresh()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            if settings.value(keys.replaceHUD) {
                if accessibility.isMissing {
                    MediaKeyAccessibilityHint { Task { await accessibility.grant() } }
                }
                Toggle("Âm lượng", isOn: settings.binding(keys.hudVolume))
                Toggle("Độ sáng", isOn: settings.binding(keys.hudBrightness))
                Toggle("Đèn bàn phím", isOn: settings.binding(keys.hudKeyboardLight))
            }
        }
    }
}
