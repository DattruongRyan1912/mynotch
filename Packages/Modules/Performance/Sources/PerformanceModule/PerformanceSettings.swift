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
    /// Whose control the fans are under: Apple's (the default) or the user's curve.
    let fanMode: SettingKey<FanMode>
    /// The curve's two temperatures, in degrees: where the fans start to rise and where they reach their maximum.
    let curveStart: SettingKey<Int>
    let curveFull: SettingKey<Int>

    init(_ settings: ModuleSettings) {
        stripTemperature = settings.key("stripTemperature", default: false)
        stripMemory = settings.key("stripMemory", default: false)
        fanProbe = settings.key("fanProbe", default: FanProbeOutcome.never)
        fanMode = settings.key("fanMode", default: FanMode.apple)
        curveStart = settings.key("curveStart", default: FanCurve.standard.start, clampedTo: FanCurve.startRange)
        curveFull = settings.key("curveFull", default: FanCurve.standard.full, clampedTo: FanCurve.fullRange)
    }

    /// Every setting the module acts on, read at once.
    func values(_ settings: ModuleSettings) -> PerformanceSettingsValues {
        PerformanceSettingsValues(
            stripTemperature: settings.value(stripTemperature), stripMemory: settings.value(stripMemory), fanMode: settings.value(fanMode),
            curve: FanCurve(start: settings.value(curveStart), full: settings.value(curveFull)).normalized, probe: settings.value(fanProbe)
        )
    }
}

/// What the module acts on, read from the settings in one go so that a change of any of them is one change.
struct PerformanceSettingsValues: Equatable, Sendable {
    var stripTemperature: Bool
    var stripMemory: Bool
    var fanMode: FanMode
    var curve: FanCurve
    var probe: FanProbeOutcome
}

/// Plain rows: the Settings page provides the Form and the section.
struct PerformanceSettingsView: View {
    @Binding var stripTemperature: Bool
    @Binding var stripMemory: Bool
    let helper: FanHelperManager
    @Binding var probe: FanProbeOutcome
    @Binding var fanMode: FanMode
    @Binding var curveStart: Int
    @Binding var curveFull: Int
    let curve: FanCurveRunner
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
            FanCurveRows(mode: $fanMode, start: $curveStart, full: $curveFull, runner: curve)
        }
    }
}
