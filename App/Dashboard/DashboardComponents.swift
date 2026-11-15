import MyNotchCore
import SwiftUI

// MARK: - Status Dot

struct DashboardStatusDot: View {
    let level: DashboardStatusLevel
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }

    private var color: Color {
        switch level {
        case .normal: return DashboardTheme.statusNormal
        case .success: return DashboardTheme.statusNormal
        case .warning: return DashboardTheme.statusDegraded
        case .critical: return DashboardTheme.statusCritical
        }
    }
}

// MARK: - Status Badge

struct DashboardBadge: View {
    let text: String
    var level: DashboardStatusLevel = .normal

    var body: some View {
        HStack(spacing: 6) {
            DashboardStatusDot(level: level, size: 5)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var textColor: Color {
        switch level {
        case .normal, .success: return DashboardTheme.successText
        case .warning: return DashboardTheme.warningText
        case .critical: return DashboardTheme.dangerText
        }
    }

    private var bgColor: Color {
        switch level {
        case .normal, .success: return Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.1)
        case .warning: return Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.12)
        case .critical: return Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch level {
        case .normal, .success: return Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.25)
        case .warning: return Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.25)
        case .critical: return Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.25)
        }
    }
}

// MARK: - Metric Card

struct DashboardMetricCard: View {
    let label: String
    let value: String
    var unit: String? = nil
    var icon: String? = nil
    var iconColor: Color? = nil
    var level: DashboardStatusLevel = .normal
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(iconColor ?? DashboardTheme.infoAccent)
                }
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(DashboardTheme.textSecondary)
                    .lineLimit(1)
                Spacer()
                DashboardStatusDot(level: level, size: 7)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(DashboardTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DashboardTheme.textSecondary)
                }
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(DashboardTheme.textMuted)
                    .lineLimit(1)
            }
        }
        .dashboardCard()
    }
}

// MARK: - Section Header

struct DashboardSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DashboardTheme.textPrimary)

                if let subtitle {
                    Text("•  \(subtitle)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DashboardTheme.textMuted)
                }

                Spacer()

                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DashboardTheme.infoAccent)
                    }
                    .buttonStyle(.plain)
                }
            }

            Rectangle()
                .fill(DashboardTheme.hairlineBorder)
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}
