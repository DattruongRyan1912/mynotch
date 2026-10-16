import MyNotchCore
import NotchUI
import SwiftUI

/// The strip beside the collapsed notch: the SoC temperature. At the lowest priority, so music and everything else with
/// something to say keeps the notch; the temperature then shows as a bubble. Its views follow the state, so it is published once.
enum PerformanceActivity {
    static func strip(state: PerformanceState) -> LiveActivity {
        let glyph = AnyView(PerformanceStripGlyph(state: state))
        return LiveActivity(
            id: PerformanceModule.activityID,
            priority: .low,
            leading: glyph,
            trailing: AnyView(PerformanceStripText(state: state)),
            minimal: glyph,
            summary: "Nhiệt độ SoC"
        )
    }
}

struct PerformanceStripGlyph: View {
    let state: PerformanceState

    var body: some View {
        Image(systemName: "thermometer.medium")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ThermalPresentation(state.thermal).tone?.color ?? NotchTokens.secondaryText)
    }
}

struct PerformanceStripText: View {
    let state: PerformanceState

    var body: some View {
        let presentation = ThermalPresentation(state.thermal)
        Text(presentation.soc)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(presentation.tone?.color ?? NotchTokens.secondaryText)
    }
}
