import NotchUI
import SwiftUI

/// Below the sessions: today's tokens and cost per agent, and Codex's rate-limit windows.
struct AgentUsageFooter: View {
    let usage: [AgentTabState.UsageLine]
    let limits: [AgentTabState.LimitBar]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(Color.white.opacity(0.12))
            if !usage.isEmpty {
                HStack(spacing: 14) {
                    ForEach(usage) { UsageSummary(line: $0) }
                    Spacer(minLength: 0)
                }
            }
            if !limits.isEmpty {
                HStack(spacing: 12) {
                    Text(AgentSource.codex.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTokens.secondaryText)
                    ForEach(limits) { LimitBarView(bar: $0) }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct UsageSummary: View {
    let line: AgentTabState.UsageLine

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: line.source.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text("\(line.source.displayName) \(line.tokens) token · \(line.cost)")
            if line.isEstimated {
                Text(UsageCalculator.estimateLabel)
                    .foregroundStyle(NotchTokens.secondaryText.opacity(0.7))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(NotchTokens.secondaryText)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// A window's name, a bar of how much is used and when it resets.
private struct LimitBarView: View {
    static let barWidth: CGFloat = 48

    let bar: AgentTabState.LimitBar
    @Environment(\.notchAccent) private var accent

    private var tint: Color {
        switch bar.percent {
        case 90...: .red
        case 70...: .orange
        default: accent
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(bar.label)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(tint).frame(width: Self.barWidth * CGFloat(bar.percent) / 100)
            }
            .frame(width: Self.barWidth, height: 4)
            Text("\(bar.percent)%")
            if let resets = bar.resets {
                Text("reset \(resets)")
            }
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(NotchTokens.secondaryText)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bar.label): đã dùng \(bar.percent)%" + (bar.resets.map { ", đặt lại lúc \($0)" } ?? ""))
    }
}
