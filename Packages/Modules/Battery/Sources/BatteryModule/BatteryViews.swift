import NotchUI
import SwiftUI

/// The "Battery" tab: the battery itself across the tab, and under it one row of facts about it.
struct BatteryTabView: View {
    static let factsGap: CGFloat = 14
    static let factsHeight: CGFloat = 36
    /// The tab bar's height when there are two or more tabs; `NotchTab.preferredHeight` includes it.
    static let tabBarHeight: CGFloat = 30
    /// The tab's declared height: the battery and its facts, plus what the notch adds around a tab's content.
    static let preferredHeight = BatteryGaugeLayout.height + factsGap + factsHeight + NotchTokens.padding + tabBarHeight

    let state: BatteryState
    let actions: BatteryTabActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear(perform: actions.appeared)
            .onDisappear(perform: actions.disappeared)
    }

    @ViewBuilder private var content: some View {
        if let snapshot = state.snapshot {
            let presentation = BatteryPresentation(
                snapshot: snapshot, details: state.details, isLowPowerMode: state.isLowPowerMode, lowThreshold: state.lowThreshold
            )
            VStack(alignment: .leading, spacing: Self.factsGap) {
                BatteryGauge(
                    percent: snapshot.percent,
                    tone: presentation.tone,
                    isCharging: snapshot.isCharging,
                    isSweeping: BatteryGaugeMotion.isSweeping(isCharging: snapshot.isCharging, isTabVisible: state.isTabVisible, reduceMotion: reduceMotion),
                    accessibilityLabel: presentation.accessibilityLabel
                )
                BatteryFactsRow(facts: presentation.facts)
                    .frame(height: Self.factsHeight, alignment: .top)
            }
        }
    }
}

/// Value over label, left to right. With many columns in a narrow notch the spacing tightens, and as a last resort the
/// whole row shrinks evenly, rather than any text being cut off.
struct BatteryFactsRow: View {
    let facts: [BatteryFact]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(spacing: 26)
            row(spacing: 18)
            ShrinkToFit { row(spacing: 10) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(spacing: CGFloat) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.value)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NotchTokens.primaryText)
                    Text(fact.label)
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTokens.secondaryText)
                }
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(fact.accessibilityLabel)
            }
        }
    }
}

/// Its content at natural size, scaled down evenly (from the top left) when the width on offer is less.
private struct ShrinkToFit<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var naturalWidth: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            content
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { naturalWidth = $0 }
                .scaleEffect(min(1, proxy.size.width / naturalWidth), anchor: .topLeading)
        }
    }
}

/// Lock screen widget: the percent and nothing else.
struct BatteryLockScreenView: View {
    let state: BatteryState

    var body: some View {
        if let snapshot = state.snapshot {
            HStack(spacing: 10) {
                Image(systemName: Self.symbol(for: snapshot))
                    .font(.system(size: 22))
                Text("\(snapshot.percent)%")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(NotchTokens.primaryText)
        }
    }

    static func symbol(for snapshot: PowerSourceSnapshot) -> String {
        if snapshot.isCharging { return "battery.100percent.bolt" }
        return switch snapshot.percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

struct BatteryActivityIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
    }
}

struct BatteryActivityPercent: View {
    let percent: Int
    let tint: Color

    var body: some View {
        Text("\(percent)%")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
    }
}

/// Plain rows: the Settings page provides the Form and the section.
struct BatterySettingsView: View {
    @Binding var lowThreshold: Int
    let lowThresholdRange: ClosedRange<Int>
    @Binding var notifyOnCharge: Bool

    var body: some View {
        Group {
            Stepper("Ngưỡng pin yếu: \(lowThreshold)%", value: $lowThreshold, in: lowThresholdRange, step: 5)
            Toggle("Thông báo khi cắm sạc", isOn: $notifyOnCharge)
        }
    }
}
