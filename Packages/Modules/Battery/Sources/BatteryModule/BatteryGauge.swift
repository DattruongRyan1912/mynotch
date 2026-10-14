import NotchUI
import SwiftUI

/// The battery, drawn across the tab: an outline with a terminal, a fill that grows from the left, and the number
/// on the fill. While it charges, a highlight sweeps across the fill.
struct BatteryGauge: View {
    private typealias Metrics = BatteryGaugeLayout

    let percent: Int
    let tone: BatteryFillTone
    let isCharging: Bool
    let isSweeping: Bool
    let accessibilityLabel: String

    /// Measured from the number itself, so the "does it fit" rule holds for two and for three digits.
    @State private var labelWidth: CGFloat = 80

    private static let outline = Color.white.opacity(0.35)
    private static let terminalGap: CGFloat = 2

    var body: some View {
        HStack(spacing: Self.terminalGap) {
            bodyShape
            RoundedRectangle(cornerRadius: 2)
                .fill(Self.outline)
                .frame(width: Metrics.nubSize.width, height: Metrics.nubSize.height)
        }
        .frame(height: Metrics.height)
        // Over the terminal, reaching a little onto the body, so it is white on the fill when the battery is full.
        .overlay(alignment: .trailing) {
            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                    .padding(.trailing, 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var bodyShape: some View {
        GeometryReader { proxy in
            let layout = Metrics(percent: percent, bodyWidth: proxy.size.width)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Metrics.fillRadius)
                    .fill(Color.white.opacity(0.08))
                fill(layout)
                label(layout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(Metrics.outlineWidth + Metrics.inset)
            .animation(NotchTokens.spring, value: percent)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .strokeBorder(Self.outline, lineWidth: Metrics.outlineWidth)
        }
    }

    private func fill(_ layout: Metrics) -> some View {
        RoundedRectangle(cornerRadius: Metrics.fillRadius)
            .fill(tone.color)
            .frame(width: layout.fillWidth)
            .overlay(alignment: .leading) {
                if isSweeping { ChargingSweep(fillWidth: layout.fillWidth) }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.fillRadius))
    }

    private func label(_ layout: Metrics) -> some View {
        Text("\(percent)%")
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(layout.labelFitsInside(labelWidth: labelWidth) ? Color.black : NotchTokens.primaryText)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
            .offset(x: layout.labelOffset(labelWidth: labelWidth))
    }
}

/// A soft band of light crossing the fill from left to right, over and over.
private struct ChargingSweep: View {
    let fillWidth: CGFloat

    private static let bandWidth: CGFloat = 70

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            let phase = BatteryGaugeMotion.sweepPhase(at: timeline.date.timeIntervalSinceReferenceDate)
            LinearGradient(colors: [.clear, .white.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.bandWidth)
                .offset(x: -Self.bandWidth + phase * (fillWidth + Self.bandWidth))
        }
    }
}

extension BatteryFillTone {
    /// The system's own battery colours: green charging, yellow in Low Power Mode, red when low.
    var color: Color {
        switch self {
        case .normal: NotchTokens.primaryText
        case .charging: Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
        case .lowPower: Color(red: 1, green: 0xD6 / 255, blue: 0x0A / 255)
        case .low: Color(red: 1, green: 0x45 / 255, blue: 0x3A / 255)
        }
    }
}
