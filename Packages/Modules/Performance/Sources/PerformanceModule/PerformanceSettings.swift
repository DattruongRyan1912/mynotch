import MyNotchCore
import SwiftUI

/// The module's settings: names and defaults in one place, shared by the running module and the Settings rows.
struct PerformanceSettingsKeys {
    /// The SoC temperature in a strip beside the collapsed notch. Off: it keeps the sensors being read all the time.
    let stripTemperature: SettingKey<Bool>

    init(_ settings: ModuleSettings) {
        stripTemperature = settings.key("stripTemperature", default: false)
    }
}

/// Plain rows: the Settings page provides the Form and the section.
struct PerformanceSettingsView: View {
    @Binding var stripTemperature: Bool

    var body: some View {
        Group {
            Toggle("Hiện nhiệt độ trên notch", isOn: $stripTemperature)
            Text("Cảm biến chỉ được đọc (mỗi 2 giây) khi tab đang mở hoặc khi dải này bật.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
