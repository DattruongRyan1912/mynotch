import MyNotchCore
import SwiftUI

/// The module's settings: names and defaults in one place, shared by the running module and the Settings rows.
struct PerformanceSettingsKeys {
    /// The SoC temperature in a strip beside the collapsed notch. Off: it keeps the sensors being read all the time.
    let stripTemperature: SettingKey<Bool>
    /// The share of memory in use, in the same strip.
    let stripMemory: SettingKey<Bool>
    /// What the last probe of the fans found, to choose the way the curve sets them.
    let fanProbe: SettingKey<FanProbeOutcome>

    init(_ settings: ModuleSettings) {
        stripTemperature = settings.key("stripTemperature", default: false)
        stripMemory = settings.key("stripMemory", default: false)
        fanProbe = settings.key("fanProbe", default: FanProbeOutcome.never)
    }
}

/// Plain rows: the Settings page provides the Form and the section.
struct PerformanceSettingsView: View {
    @Binding var stripTemperature: Bool
    @Binding var stripMemory: Bool
    let helper: FanHelperManager
    @Binding var probe: FanProbeOutcome
    let readAppFans: () async -> [FanReading]

    var body: some View {
        Group {
            Toggle("Hiện nhiệt độ trên notch", isOn: $stripTemperature)
            Toggle("Hiện dung lượng RAM trên notch", isOn: $stripMemory)
            Text("Số liệu chỉ được đọc (mỗi 2 giây) khi tab đang mở hoặc khi một trong hai dải này bật.")
                .font(.caption)
                .foregroundStyle(.secondary)
            FanHelperSettingsRows(helper: helper, readAppFans: readAppFans)
            FanProbeRows(helper: helper, outcome: $probe)
        }
    }
}
