import MyNotchCore
import NotchUI
import SwiftUI

/// What the "Còn 3 việc" activity shows right now. Equatable, so the module publishes only when it changes.
nonisolated struct TodoActivityContent: Equatable, Sendable {
    var remaining: Int
    var done: Int
    var total: Int

    /// How much of today's list is done, for the ring.
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }

    var summary: String { TodoFormat.remaining(remaining) }
}

extension TodoActivityContent {
    /// Low priority: it is never more than a hint of what is left, so it must not take the notch from music, a meeting
    /// or a timer. It sits in a bubble beside them, and alone it shows the count.
    var liveActivity: LiveActivity {
        LiveActivity(
            id: TodoModule.activityID,
            priority: .low,
            leading: AnyView(TodoActivityIcon()),
            trailing: AnyView(TodoActivityCount(count: remaining)),
            minimal: AnyView(TodoProgressRing(fraction: fraction)),
            summary: summary
        )
    }
}

/// Left of the closed notch.
struct TodoActivityIcon: View {
    var body: some View {
        Image(systemName: "checklist")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
            .accessibilityHidden(true)
    }
}

/// Right of the closed notch: how many are left.
struct TodoActivityCount: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(NotchTokens.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
    }
}

/// The small ring of the bubble beside another activity: the share of today's list that is done.
struct TodoProgressRing: View {
    let fraction: Double
    @Environment(\.notchAccent) private var accent

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(fraction, 0.04))
                .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(2)
        .accessibilityHidden(true)
    }
}
