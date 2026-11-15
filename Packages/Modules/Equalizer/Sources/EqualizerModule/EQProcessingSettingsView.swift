import MyNotchCore
import SwiftUI

/// Limiter Ceiling & Dynamic Loudness processing settings controls.
public struct EQProcessingSettingsView: View {
    public let state: EqualizerState

    public init(state: EqualizerState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: Section B - Limiter & True-Peak Protection
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("BẢO VỆ TRUE-PEAK LIMITER (ITU-R BS.1770-5)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Độ trễ DSP: ~2,25 ms (108 frames @ 48kHz)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Picker("Trần True-Peak", selection: Binding(
                    get: {
                        EqualizerCeilingMode(rawValue: state.ceilingDBTP) ?? .minusHalf
                    },
                    set: {
                        state.ceilingDBTP = $0.rawValue
                    }
                )) {
                    ForEach(EqualizerCeilingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                HStack(spacing: 4) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    Text("Bộ lọc FIR 4x oversampling 12-tap chặn triệt để hiện tượng vỡ tiếng liên mẫu (inter-sample clipping) trên codec Bluetooth AAC/SBC và DAC tai nghe.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )

            // MARK: Section C - Dynamic Loudness Tuning
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("Bù âm khi nghe nhỏ (Dynamic Loudness)", isOn: Binding(
                        get: { state.isLoudnessEnabled },
                        set: { state.isLoudnessEnabled = $0 }
                    ))
                    .font(.system(size: 12, weight: .semibold))
                    .disabled(!state.isEnabled)

                    Spacer()
                }

                if state.isLoudnessEnabled {
                    VStack(spacing: 8) {
                        // Reference Volume
                        HStack(spacing: 8) {
                            Text("Mức tham chiếu")
                                .font(.system(size: 11))
                                .frame(width: 110, alignment: .leading)

                            Slider(
                                value: Binding(
                                    get: { state.loudnessReferenceVolume },
                                    set: { state.loudnessReferenceVolume = $0 }
                                ),
                                in: 0.10...1.00,
                                step: 0.05
                            )
                            .controlSize(.small)

                            Text("\(Int(state.loudnessReferenceVolume * 100))%")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }

                        // Max Bass Boost
                        HStack(spacing: 8) {
                            Text("Tăng Bass tối đa")
                                .font(.system(size: 11))
                                .frame(width: 110, alignment: .leading)

                            Slider(
                                value: Binding(
                                    get: { state.loudnessMaxBassDB },
                                    set: { state.loudnessMaxBassDB = $0 }
                                ),
                                in: 0.0...12.0,
                                step: 0.5
                            )
                            .controlSize(.small)

                            Text(String(format: "%+.1f dB", state.loudnessMaxBassDB))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .frame(width: 60, alignment: .trailing)
                        }

                        // Max Treble Boost
                        HStack(spacing: 8) {
                            Text("Tăng Treble tối đa")
                                .font(.system(size: 11))
                                .frame(width: 110, alignment: .leading)

                            Slider(
                                value: Binding(
                                    get: { state.loudnessMaxTrebleDB },
                                    set: { state.loudnessMaxTrebleDB = $0 }
                                ),
                                in: 0.0...12.0,
                                step: 0.5
                            )
                            .controlSize(.small)

                            Text(String(format: "%+.1f dB", state.loudnessMaxTrebleDB))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                    .padding(.top, 2)
                }

                Text("Tự động nâng dải trầm và cao theo đường cong đẳng âm Fletcher-Munson khi giảm âm lượng thiết bị, đồng thời hạ Preamp tương ứng để bảo toàn âm lượng tổng thể không bị méo tiếng.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )

            // MARK: Section D - Auto-Headroom Mode
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("Tự động chừa headroom (Auto-Headroom)", isOn: Binding(
                        get: { state.isAutoHeadroomEnabled },
                        set: { state.isAutoHeadroomEnabled = $0 }
                    ))
                    .font(.system(size: 12, weight: .semibold))
                    .disabled(!state.isEnabled)

                    Spacer()
                }

                Text("Hạ âm lượng tổng đúng bằng đỉnh đường cong EQ (tối đa -48 dB) để True-Peak Limiter không nén dải trung và dải cao khi tăng mạnh âm trầm; đánh đổi là âm lượng tổng thể sẽ nhỏ hơn.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }
}
