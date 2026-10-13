import NotchUI
import SwiftUI

/// Left side of the closed notch: the agent's glyph. It pulses while the agent works and turns orange when it
/// waits for the user.
struct AgentActivityLeading: View {
    let content: AgentActivityContent

    private var isWorking: Bool {
        if case .working = content.kind { true } else { false }
    }

    var body: some View {
        Image(systemName: content.source.systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(content.kind == .waitingForInput ? Color.orange : NotchTokens.primaryText)
            .symbolEffect(.pulse, options: .repeating, isActive: isWorking)
            .accessibilityLabel(content.accessibilityLabel)
    }
}

/// Right side of the closed notch: how long the turn has run, an orange "!" while the agent asks for the user,
/// a check mark when it is done. The timer counts on its own, so the activity is not published again every second.
struct AgentActivityTrailing: View {
    let content: AgentActivityContent

    var body: some View {
        switch content.kind {
        case let .working(since):
            Text(timerInterval: since...Date.distantFuture, countsDown: false)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        case .waitingForInput:
            Text("!")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
        case .finished:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.green)
                .accessibilityHidden(true)
        }
    }
}
