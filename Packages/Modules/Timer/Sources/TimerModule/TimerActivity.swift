import MyNotchCore
import NotchUI
import SwiftUI

extension TimerKind {
    var accent: Color {
        switch self {
        case .task: .orange
        case .reminder: .cyan
        case .rest: .mint
        }
    }
}

/// The timer's live activity: its glyph on the left, the time on the right, and for a reminder with a label that label
/// in a strip under the notch (the side only has room for the time). `summary` and `minimal` are always filled so the
/// bubble and the list row read well when another activity holds the notch.
enum TimerActivity {
    static func running(session: TimerSession, range: ClosedRange<Date>) -> LiveActivity {
        make(
            glyph: session.kind.systemImage, tint: session.kind.accent,
            trailing: AnyView(TimerClock(range: range, countsDown: true, tint: session.kind.accent)),
            summary: session.summary, strip: session.label)
    }

    static func stopwatch(range: ClosedRange<Date>) -> LiveActivity {
        make(glyph: "stopwatch", tint: .orange, trailing: AnyView(TimerClock(range: range, countsDown: false, tint: .orange)), summary: "Bấm giờ")
    }

    /// Raised above the other activities for `expiresAfter`; a reminder shows its label under the notch. The glyph and the text
    /// pulse while `state.isAlerting`.
    static func finished(session: TimerSession, state: TimerState, expiresAfter: Duration) -> LiveActivity {
        let glyph = AnyView(TimerAlertGlyph(systemImage: session.kind.systemImage, state: state))
        return make(
            leading: glyph, trailing: AnyView(TimerAlertText(state: state)), minimal: glyph,
            summary: session.finishedSummary, strip: session.label, priority: .high, expiresAfter: expiresAfter)
    }

    private static func make(
        glyph: String, tint: Color, trailing: AnyView, summary: String, strip: String = ""
    ) -> LiveActivity {
        let view = AnyView(TimerGlyph(systemImage: glyph, tint: tint))
        return make(leading: view, trailing: trailing, minimal: view, summary: summary, strip: strip)
    }

    private static func make(
        leading: AnyView, trailing: AnyView, minimal: AnyView, summary: String, strip: String = "",
        priority: ActivityPriority = .normal, expiresAfter: Duration? = nil
    ) -> LiveActivity {
        LiveActivity(
            id: TimerModule.activityID,
            priority: priority,
            expiresAfter: expiresAfter,
            leading: leading,
            trailing: trailing,
            bottom: strip.isEmpty ? nil : AnyView(TimerStrip(text: strip)),
            bottomHeight: TimerStrip.height,
            minimal: minimal,
            summary: summary
        )
    }
}

struct TimerGlyph: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
    }
}

/// The running time beside the notch; the system advances it, so the activity is published once, not every second.
struct TimerClock: View {
    let range: ClosedRange<Date>
    let countsDown: Bool
    let tint: Color

    var body: some View {
        Text(timerInterval: range, pauseTime: nil, countsDown: countsDown)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
    }
}

/// One line under the collapsed notch: what a reminder is about.
struct TimerStrip: View {
    static let height: CGFloat = 22

    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(NotchTokens.primaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
    }
}

/// Lock screen widget: the remaining time of a running countdown and nothing else, with the glyph of its type.
struct TimerLockScreenView: View {
    let endDate: Date
    var session = TimerSession.plain

    var range: ClosedRange<Date> { TimerTabView.countdownRange(to: endDate) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.kind.systemImage)
                .font(.system(size: 20, weight: .semibold))
            Text(timerInterval: range, pauseTime: nil, countsDown: true)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(session.kind.accent)
    }
}
