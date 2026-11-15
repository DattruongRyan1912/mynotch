import NotchUI
import SwiftUI

enum MeetingCardAction: CaseIterable, Hashable {
    case join, snooze, dismiss

    var title: String {
        switch self {
        case .join: "Tham gia"
        case .snooze: "Báo lại"
        case .dismiss: "Bỏ qua"
        }
    }
}

/// The buttons under the "Sắp tới" card: "Tham gia" when the event has a link, then "Báo lại" and "Bỏ qua" while the
/// card is on show. They are plain buttons, so they take clicks, hover and the keyboard like any other; the tab asks
/// the notch for the keyboard (`acceptsKeyboard`), and Tab and Space reach them once the notch is open on purpose.
struct MeetingCardActions: View {
    let event: AgendaEvent
    /// When the tab last read the calendar, to say when a snooze would end.
    let now: Date
    let canSnooze: Bool
    let canDismiss: Bool
    let actions: CalendarActions

    /// Join needs a link; the other two follow what the activity can do right now.
    static func available(for event: AgendaEvent, canSnooze: Bool, canDismiss: Bool) -> [MeetingCardAction] {
        var shown: [MeetingCardAction] = []
        if event.meetingURL != nil { shown.append(.join) }
        if canSnooze { shown.append(.snooze) }
        if canDismiss { shown.append(.dismiss) }
        return shown
    }

    /// The colour of the join button's label: white, as it always was, unless the accent is so light that white could hardly be
    /// read on it (yellow, the oranges and the greens), where black is used. Plain white, not the text token: the label is on a
    /// solid accent, which is as dark as the accent whatever the glass behind the notch is.
    static func labelColour(on accent: Color) -> Color {
        let rgb = NSColor(accent).usingColorSpace(.sRGB) ?? .black
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        let whiteContrast = 1.05 / (luminance + 0.05)
        return whiteContrast < 2.5 ? Color.black.opacity(0.85) : Color.white
    }

    /// What VoiceOver reads: the title alone would not say which meeting a button is for.
    static func accessibilityLabel(_ action: MeetingCardAction, for event: AgendaEvent) -> String {
        "\(action.title) cuộc họp \(event.title.isEmpty ? "(Không có tiêu đề)" : event.title)"
    }

    /// The tooltip. A snooze says when the card is due back, which is the start when that is within five minutes.
    static func help(_ action: MeetingCardAction, for event: AgendaEvent, now: Date) -> String {
        switch action {
        case .join: "Mở liên kết cuộc họp"
        case .snooze:
            MeetingReplies.snoozeEnd(for: event, now: now) == event.start ? "Nhắc lại khi cuộc họp bắt đầu" : "Nhắc lại sau 5 phút"
        case .dismiss: "Không nhắc lại cuộc họp này"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Self.available(for: event, canSnooze: canSnooze, canDismiss: canDismiss), id: \.self) { action in
                switch action {
                case .join: JoinButton(action: { actions.join(event) }, event: event, now: now)
                case .snooze: QuietButton(kind: .snooze, action: { actions.snooze(event) }, event: event, now: now)
                case .dismiss: QuietButton(kind: .dismiss, action: { actions.dismiss(event) }, event: event, now: now)
                }
            }
        }
    }
}

/// The filled one, as the card has always had it; it lightens under the pointer.
private struct JoinButton: View {
    let action: () -> Void
    let event: AgendaEvent
    let now: Date
    @Environment(\.notchAccent) private var accent
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(MeetingCardAction.join.title, systemImage: "video.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MeetingCardActions.labelColour(on: accent))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accent, in: Capsule())
                .brightness(isHovering ? 0.12 : 0)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(MeetingCardActions.help(.join, for: event, now: now))
        .accessibilityLabel(MeetingCardActions.accessibilityLabel(.join, for: event))
    }
}

/// Plain text that grows a pill behind it under the pointer, like the rows of the day's list.
private struct QuietButton: View {
    let kind: MeetingCardAction
    let action: () -> Void
    let event: AgendaEvent
    let now: Date
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(kind.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovering ? NotchTokens.primaryText : NotchTokens.secondaryText)
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .background(NotchTokens.fill(isHovering ? 0.1 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(MeetingCardActions.help(kind, for: event, now: now))
        .accessibilityLabel(MeetingCardActions.accessibilityLabel(kind, for: event))
    }
}
