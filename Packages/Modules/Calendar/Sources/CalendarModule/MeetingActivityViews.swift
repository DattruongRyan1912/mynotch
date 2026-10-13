import MyNotchCore
import NotchUI
import SwiftUI

extension MeetingActivityContent {
    var liveActivity: LiveActivity {
        LiveActivity(
            id: CalendarModule.activityID,
            priority: priority,
            leading: AnyView(MeetingActivityIcon(color: color)),
            trailing: AnyView(MeetingActivityCountdown(text: countdown))
        )
    }
}

/// Left of the closed notch: a dot in the event's calendar colour beside a clock.
struct MeetingActivityIcon: View {
    let color: RGBAColor

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(color))
                .frame(width: 7, height: 7)
            Image(systemName: "clock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
        }
        .accessibilityHidden(true)
    }
}

/// Right of the closed notch, in 64 pt: "5 phút" fits as is, "Đang diễn ra" shrinks a little.
struct MeetingActivityCountdown: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 2)
    }
}
