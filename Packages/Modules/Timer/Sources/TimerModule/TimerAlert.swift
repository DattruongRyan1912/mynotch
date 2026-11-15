import MyNotchCore
import NotchUI
import SwiftUI

/// One button of the toast shown when a countdown ends.
struct TimerFinishAction: Identifiable {
    enum Role { case next, snooze, dismiss }

    let role: Role
    let title: String
    let run: @MainActor () -> Void

    /// "Tắt" is the one that ends the alert, so it is the one that stands out.
    var isPrimary: Bool { role == .dismiss }

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
                    ForEach(toast.actions) { TimerToastButton(action: $0) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(toast.title)
    }
}

/// A button of the toast, drawn like the notch's other controls (Calendar's and Todo's pills) and not with a system bordered
/// style, which dims in a window that is not key, as the notch's panel is. The label is the primary text token on a wash of the
/// same colour, so it reads on the black notch and on light and dark glass; the primary button's wash is the accent instead.
struct TimerToastButton: View {
    let action: TimerFinishAction
    @Environment(\.notchAccent) private var accent
    @State private var isHovering = false

    /// Read in a `body`, like every text token.
    static var labelColour: Color { NotchTokens.primaryText }

    var body: some View {
        Button(action: action.run) {
            Text(action.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Self.labelColour)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(wash, in: Capsule())
                .overlay { if action.isPrimary { Capsule().strokeBorder(accent, lineWidth: 1) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var wash: Color {
        action.isPrimary
            ? accent.opacity(isHovering ? NotchTokens.selectionOpacity + 0.14 : NotchTokens.selectionOpacity + 0.08)
            : NotchTokens.fill(isHovering ? 0.22 : 0.14)
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
