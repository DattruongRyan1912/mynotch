import MyNotchCore
import SwiftUI

/// Comprehensive Equalizer Management Interface:
/// Section A: Preset Studio & Library (CRUD, 10-band precision numeric controls, response curve preview)
/// Section B: Limiter & True-Peak Headroom (BS.1770 ceiling selector, lookahead stats)
/// Section C: Dynamic Loudness Tuning (Reference volume, max bass/treble boost)
/// Section D: Signal Path & Device Telemetry (Active devices, status, CoreAudio permissions)
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
        VStack(alignment: .leading, spacing: 18) {
            // Master Switch
            HStack {
                Toggle("Bật Equalizer", isOn: Binding(
                    get: { state.isEnabled },
                    set: { state.isEnabled = $0 }
                ))
                .font(.system(size: 13, weight: .semibold))

                Spacer()

                if state.isEnabled {
                    Text("ĐANG HOẠT ĐỘNG")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            Divider()

            // Section A: Preset Studio & Library
            VStack(alignment: .leading, spacing: 12) {
                EQPresetLibraryView(state: state)

                if let profile = state.selected {
                    EQResponseCurveView(profile: profile)

                    EQProfileEditorView(state: state)
                }
            }
            .opacity(state.isEnabled ? 1.0 : 0.6)
            .disabled(!state.isEnabled)

            Divider()

            // Section B & C: Processing Settings (Limiter True-Peak + Dynamic Loudness)
            EQProcessingSettingsView(state: state)
                .opacity(state.isEnabled ? 1.0 : 0.6)
                .disabled(!state.isEnabled)

            Divider()

            // Section D: Active Device Telemetry & Signal Path
            EQDeviceTelemetryView(
                status: status,
                isRunning: isRunning,
                openSettings: openSettings,
                retry: retry
            )
        }
        .padding(.vertical, 4)
    }
}
