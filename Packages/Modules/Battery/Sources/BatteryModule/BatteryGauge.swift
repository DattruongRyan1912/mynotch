import AppKit
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
    @Environment(\.notchSurface) private var surface

    /// The outline and the terminal. Read in the body, not kept once, so it follows the look.
    private var outline: Color { NotchTokens.fill(0.35) }

    private static let terminalGap: CGFloat = 2

    /// The number when it sits inside the fill: black on the coloured fills and on the classic notch's white one. On Liquid Glass
    /// the plain fill is the primary colour (black on light glass), so the number takes the opposite, the window's background.
    static func insideLabel(for tone: BatteryFillTone, onGlass: Bool) -> Color {
        tone == .normal && onGlass ? Color(nsColor: .windowBackgroundColor) : Color.black
    }

    var body: some View {
        HStack(spacing: Self.terminalGap) {
            bodyShape
            RoundedRectangle(cornerRadius: 2)
                .fill(outline)
                .frame(width: Metrics.nubSize.width, height: Metrics.nubSize.height)
        }
        .frame(height: Metrics.height)
        // On the body's right outline, beside the terminal: the glyph is wider than the terminal and its gap, so it
        // covers the outline there and stays clear of the number, which ends 10 pt inside the fill.
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
                    .fill(NotchTokens.fill(0.08))
                fill(layout)
                label(layout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(Metrics.outlineWidth + Metrics.inset)
            .animation(NotchTokens.spring, value: percent)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .strokeBorder(outline, lineWidth: Metrics.outlineWidth)
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
            .foregroundStyle(layout.labelFitsInside(labelWidth: labelWidth) ? Self.insideLabel(for: tone, onGlass: surface.isLiquidGlass) : NotchTokens.primaryText)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
            .offset(x: layout.labelOffset(labelWidth: labelWidth))
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
