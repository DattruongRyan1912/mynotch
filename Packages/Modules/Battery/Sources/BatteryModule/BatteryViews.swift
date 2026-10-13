import NotchUI
import SwiftUI

struct BatteryTabView: View {
    let state: BatteryState

    var body: some View {
        if let snapshot = state.snapshot {
            HStack(spacing: 18) {
                Image(systemName: Self.symbol(for: snapshot))
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(snapshot.percent <= state.lowThreshold && !snapshot.isOnAC ? .red : NotchTokens.primaryText)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(snapshot.percent)%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTokens.primaryText)
                    Text(Self.status(for: snapshot))
                        .font(.callout)
                        .foregroundStyle(NotchTokens.secondaryText)
                    Text(snapshot.isOnAC ? "Nguồn: bộ sạc" : "Nguồn: pin")
                        .font(.caption)
                        .foregroundStyle(NotchTokens.secondaryText)
                }
                Spacer()
            }
            .padding(.top, 8)
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

    static func status(for snapshot: PowerSourceSnapshot) -> String {
        if snapshot.isCharging {
            return snapshot.minutesToFull.map { "Đang sạc · đầy sau \(format($0))" } ?? "Đang sạc"
        }
        if snapshot.isOnAC { return "Đã cắm sạc · không sạc" }
        return snapshot.minutesToEmpty.map { "Còn khoảng \(format($0))" } ?? "Đang tính thời gian còn lại"
    }

    static func format(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) phút" }
        return minutes % 60 == 0 ? "\(minutes / 60) giờ" : "\(minutes / 60) giờ \(minutes % 60) phút"
    }
}

/// Lock screen widget: the percent and nothing else.
struct BatteryLockScreenView: View {
    let state: BatteryState

    var body: some View {
        if let snapshot = state.snapshot {
            HStack(spacing: 10) {
                Image(systemName: BatteryTabView.symbol(for: snapshot))
                    .font(.system(size: 22))
                Text("\(snapshot.percent)%")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(NotchTokens.primaryText)
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
