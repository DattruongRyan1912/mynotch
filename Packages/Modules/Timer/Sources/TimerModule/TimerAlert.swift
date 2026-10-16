import MyNotchCore
import NotchUI
import SwiftUI

/// One button of the toast shown when a countdown ends.
struct TimerFinishAction: Identifiable {
    enum Role { case next, snooze, dismiss }

    let role: Role
    let title: String
    /// The type the next step starts, for its colour; nil for the other buttons.
    var accent: Color?
    let run: @MainActor () -> Void

    var id: Role { role }
}

/// What the toast says and offers when a countdown ends. The module builds it, so each button is the module's own operation and
/// can be tested without a view; `TimerFinishToastView` only draws it.
struct TimerFinishToast {
    let session: TimerSession
    let actions: [TimerFinishAction]

    var title: String { session.finishedHeadline }
}

/// The toast over the notch. It stays up for as long as the alert lasts, so a button is there to press while the sound repeats.
struct TimerFinishToastView: View {
    let toast: TimerFinishToast

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: toast.session.kind.systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTokens.primaryText)
                        .lineLimit(2)
                    Text(toast.session.kind.title)
                        .font(.system(size: 12))
                        .foregroundStyle(NotchTokens.secondaryText)
                }
                HStack(spacing: 8) {
                    ForEach(toast.actions) { action in
                        if action.role == .next {
                            Button(action.title, action: action.run)
                                .buttonStyle(.borderedProminent)
                                .tint(action.accent)
                        } else {
                            Button(action.title, action: action.run)
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(toast.title)
    }
}

/// The glyph of the finished activity: red, and pulsing while the user has not answered. It reads the flag itself, so the
/// pulse stops without the activity being published again (which would start its lifetime over).
struct TimerAlertGlyph: View {
    let systemImage: String
    let state: TimerState

    var body: some View {
        TimerGlyph(systemImage: systemImage, tint: .red).notchPulse(isActive: state.isAlerting)
    }
}

/// "Hết giờ" beside the collapsed notch, pulsing with the glyph.
struct TimerAlertText: View {
    let state: TimerState

    var body: some View {
        Text("Hết giờ")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.red)
            .notchPulse(isActive: state.isAlerting)
    }
}

/// Lock screen widget for a countdown that has ended: what it was, in words anyone can read.
struct TimerFinishedLockScreenView: View {
    let session: TimerSession

    var text: String { session.finishedHeadline }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.kind.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.red)
            Text(text)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}
