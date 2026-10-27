import MyNotchCore
import SwiftUI

/// The module's Settings rows: the switch (the one the tab and the Nhạc tab show), what the EQ needs, and what it is doing.
/// Plain rows: the Settings page provides the Form and the section.
struct EqualizerSettingsView: View {
    let state: EqualizerState
    let status: EqualizerStatus
    /// Whether the module runs; the status means nothing when it does not.
    let isRunning: Bool
    let openSettings: () -> Void
    let retry: () -> Void

    /// What the rows under the switch show.
    struct Plan: Equatable {
        /// The status and its buttons; nil when it means nothing: the module is not running, or the switch is off.
        var status: EqualizerStatus.Line?
        /// The permission row's own "Mở System Settings". A hint for a missing permission has one, so the row does not add a second.
        var rowOffersSettings: Bool
    }

    static func plan(line: EqualizerStatus.Line, isRunning: Bool, isEnabled: Bool) -> Plan {
        let shown = isRunning && isEnabled ? line : nil
        return Plan(status: shown, rowOffersSettings: !(shown?.actions.contains(.openSettings) ?? false))
    }

    var body: some View {
        let plan = Self.plan(line: status.line, isRunning: isRunning, isEnabled: state.isEnabled)
        Group {
            Toggle("Bật EQ", isOn: Binding(get: { state.isEnabled }, set: { state.isEnabled = $0 }))
            Toggle("Bù âm khi nghe nhỏ", isOn: Binding(get: { state.isLoudnessEnabled }, set: { state.isLoudnessEnabled = $0 }))
                .disabled(!state.isEnabled)
            Text("Dưới 60% âm lượng, tăng dần bass (tới +8,5 dB) và treble (tới +4 dB) theo âm lượng của từng thiết bị, đồng thời hạ preamp tương ứng để không vỡ tiếng. Từ 60% trở lên không đổi gì.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let line = plan.status {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line.text)
                        .font(.caption)
                        .foregroundStyle(line.isWarning ? Color.orange : Color.secondary)
                    Spacer(minLength: 8)
                    ForEach(line.actions, id: \.self) { action in
                        Button(action.title) { perform(action) }
                    }
                }
            }
            LabeledContent("Ghi âm thanh hệ thống") {
                if plan.rowOffersSettings {
                    Button(EqualizerStatus.Action.openSettings.title, action: openSettings)
                }
            }
            Text("Cần để EQ nghe và phát lại âm thanh của máy. Không có quyền này thì EQ tự dừng và âm thanh vẫn phát bình thường.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("EQ làm âm thanh trễ thêm một chút. Tai nghe và loa Bluetooth vốn đã trễ nên có thể thấy rõ hơn khi xem phim hoặc họp.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func perform(_ action: EqualizerStatus.Action) {
        switch action {
        case .openSettings: openSettings()
        case .retry: retry()
        }
    }
}
