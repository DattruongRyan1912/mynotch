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
    let durationSeconds: SettingKey<Double>

    init(_ settings: ModuleSettings) {
        bluetooth = settings.key("bluetooth", default: true)
        network = settings.key("network", default: true)
        capsLock = settings.key("capsLock", default: true)
        downloads = settings.key("downloads", default: true)
        volume = settings.key("volume", default: true)
        durationSeconds = settings.key("durationSeconds", default: 2.5, clampedTo: Self.durationRange)
    }
}

/// Plain rows: the Settings page provides the Form and the section.
struct SystemActivitiesSettingsView: View {
    let keys: SystemActivitiesKeys
    let settings: ModuleSettings

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
        }
    }
}
