import MyNotchCore
import NotchUI
import SwiftUI

/// Nội dung Live Activity hiển thị trên Notch khi còn thói quen chưa hoàn thành.
nonisolated public struct HabitActivityContent: Equatable, Sendable {
    public var remaining: Int
    public var done: Int
    public var total: Int

    public init(remaining: Int, done: Int, total: Int) {
        self.remaining = remaining
        self.done = done
        self.total = total
    }

    public var fraction: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }

    public var summary: String {
        "Còn \(remaining) thói quen"
    }
}

extension HabitActivityContent {
    @MainActor
    public var liveActivity: LiveActivity {
        LiveActivity(
            id: HabitModule.activityID,
            priority: .low,
            leading: AnyView(HabitActivityIcon()),
            trailing: AnyView(HabitActivityCount(count: remaining)),
            minimal: AnyView(HabitProgressRing(fraction: fraction)),
            summary: summary
        )
    }
}

/// Icon hiển thị bên trái Notch thu nhỏ.
public struct HabitActivityIcon: View {
    public init() {}

    public var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
            .accessibilityHidden(true)
    }
}

/// Số lượng thói quen còn lại bên phải Notch thu nhỏ.
public struct HabitActivityCount: View {
    public let count: Int

    public init(count: Int) {
        self.count = count
    }

    public var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(NotchTokens.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
    }
}

/// Vòng tròn tiến độ thu nhỏ hiển thị trong bubble.
public struct HabitProgressRing: View {
    public let fraction: Double
    @Environment(\.notchAccent) private var accent

    public init(fraction: Double) {
        self.fraction = fraction
    }

    public var body: some View {
        ZStack {
            Circle().stroke(NotchTokens.fill(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(fraction, 0.04))
                .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(2)
        .accessibilityHidden(true)
    }
}
