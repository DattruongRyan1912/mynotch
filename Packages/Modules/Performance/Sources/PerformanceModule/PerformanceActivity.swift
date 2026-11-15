import MyNotchCore
import NotchUI
import SwiftUI

/// The strip beside the collapsed notch: the SoC temperature, the share of memory in use, or both. At the lowest priority, so
/// music and everything else with something to say keeps the notch; the strip then shows as a bubble. Its views follow the
/// state, so it is published when it turns on or changes what it shows, not at every read.
enum PerformanceActivity {
    static func strip(state: PerformanceState, temperature: Bool, memory: Bool) -> LiveActivity {
        let glyph = AnyView(PerformanceStripGlyph(state: state, temperature: temperature))
        return LiveActivity(
            id: PerformanceModule.activityID,
            priority: .low,
            leading: glyph,
            trailing: AnyView(PerformanceStripText(state: state, temperature: temperature, memory: memory)),
            minimal: glyph,
            summary: temperature && memory ? "Nhiệt độ SoC và RAM" : temperature ? "Nhiệt độ SoC" : "Dung lượng RAM"
        )
    }
}

struct PerformanceStripGlyph: View {
    let state: PerformanceState
    let temperature: Bool

    var body: some View {
        let tone = temperature ? ThermalPresentation(state.thermal).tone : MemoryPresentation(state.usage).tone
        Image(systemName: temperature ? "thermometer.medium" : "memorychip")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tone?.color ?? NotchTokens.secondaryText)
    }
}

struct PerformanceStripText: View {
    let state: PerformanceState
    let temperature: Bool
    let memory: Bool

    var body: some View {
        HStack(spacing: 6) {
            if temperature {
                let thermal = ThermalPresentation(state.thermal)
                value(thermal.soc, tone: thermal.tone)
            }
            if memory {
                let usage = MemoryPresentation(state.usage)
                value(usage.percent, tone: usage.tone)
            }
        }
    }

    private func value(_ text: String, tone: Tone?) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tone?.color ?? NotchTokens.secondaryText)
    }
}
