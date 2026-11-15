import MyNotchCore
import SwiftUI

/// 10-band numeric precision controls with tabular-nums and preamp slider.
public struct EQProfileEditorView: View {
    public let state: EqualizerState

    public init(state: EqualizerState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Preamp Row
            HStack(spacing: 8) {
                Text("Preamp")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 50, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { state.selected?.preamp ?? 0 },
                        set: { state.setPreamp($0) }
                    ),
                    in: EQProfile.preampRange,
                    step: 0.5
                )
                .controlSize(.small)

                Text(String(format: "%+.1f dB", state.selected?.preamp ?? 0))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)

                Button("0 dB") {
                    state.setPreamp(0)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Đặt lại Preamp về 0 dB")
            }

            // 10 Frequency Bands
            if let profile = state.selected {
                HStack(spacing: 4) {
                    ForEach(EQProfile.frequencies.indices, id: \.self) { index in
                        let freq = EQProfile.frequencies[index]
                        let gain = index < profile.gains.count ? profile.gains[index] : 0.0

                        VStack(spacing: 3) {
                            Text(String(format: "%+.1f", gain))
                                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(gain != 0 ? Color.primary : Color.secondary)
                                .frame(height: 12)

                            // Vertical Slider
                            VerticalBandSlider(
                                value: gain,
                                name: frequencyLabel(freq),
                                range: EQProfile.gainRange,
                                onValueChanged: { state.setGain($0, band: index) }
                            )
                            .frame(width: 18, height: 64)

                            Text(frequencyLabel(freq))
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(height: 12)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                )
            }

            // Reset profile action
            HStack {
                Spacer()
                Button("Đặt lại phẳng (0 dB)") {
                    state.resetSelectedToFlat()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Đặt tất cả 10 cần gạt và preamp về 0 dB")
            }
        }
    }

    private func frequencyLabel(_ freq: Double) -> String {
        if freq >= 1000 {
            let k = Int(freq / 1000)
            return "\(k)k"
        } else {
            return "\(Int(freq))"
        }
    }
}
