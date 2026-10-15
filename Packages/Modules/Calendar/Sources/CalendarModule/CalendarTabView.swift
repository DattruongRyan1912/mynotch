import NotchUI
import SwiftUI

/// The "Lịch" tab: today's date, the next event as a card, today's events and the reminders due.
struct CalendarTabView: View {
    /// The notch's preferred height for the tab: the area below the notch, tab bar and inner padding included.
    static let height: CGFloat = 220
    /// Wide enough for "Tham gia", "Báo lại" and "Bỏ qua" in one row.
    static let cardWidth: CGFloat = 216
    /// Left and right space between the card's edge and its text.
    static let cardInset: CGFloat = 10
    /// The date line, which also holds the "+".
    static let headerHeight: CGFloat = 19
    /// The day summary under the date line.
    static let summaryHeight: CGFloat = 14
    /// What is left for the card: the tab's height less the notch's inner padding (14), the tab bar (30), the date
    /// line (19), the day summary under it (14, and 1 between) and the gap under that (8).
    static let cardMaxHeight: CGFloat = height - 14 - 30 - headerHeight - 1 - summaryHeight - 8

    let state: CalendarState
    let actions: CalendarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                header
                if state.quickAdd == nil, let summary = state.daySummary {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .lineLimit(1)
                        .frame(height: Self.summaryHeight, alignment: .leading)
                }
            }
            if let quickAdd = state.quickAdd {
                QuickAddView(quickAdd: quickAdd, now: state.now, calendar: state.calendar, actions: actions)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    UpcomingCard(state: state, actions: actions)
                        .frame(width: Self.cardWidth)
                    TodayList(state: state, actions: actions)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: actions.appeared)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(AgendaFormat.dayHeader(state.now, calendar: state.calendar))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            AddEventButton(isOpen: state.quickAdd != nil, actions: actions)
        }
        .frame(height: Self.headerHeight)
    }
}

/// The "Sắp tới" card: the event to watch for next, with a way in when it has a link.
struct UpcomingCard: View {
    let state: CalendarState
    let actions: CalendarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sắp tới")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(NotchTokens.secondaryText)
            if let event = state.featured {
                details(of: event)
            } else {
                Spacer(minLength: 0)
                Label("Không còn sự kiện nào", systemImage: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTokens.secondaryText)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, CalendarTabView.cardInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func details(of event: AgendaEvent) -> some View {
        Button { actions.open(event) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeLine(of: event))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(NotchTokens.accent)
                    .lineLimit(1)
                Text(event.title.isEmpty ? "(Không có tiêu đề)" : event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                calendarLine(of: event)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Mở trong Lịch")
        Spacer(minLength: 0)
        if event.meetingURL != nil || state.canDismissFeatured {
            MeetingCardActions(
                event: event, now: state.now, canSnooze: state.canSnoozeFeatured, canDismiss: state.canDismissFeatured, actions: actions
            )
        }
    }

    /// "● Work · Phòng họp 4B": the calendar's colour dot, then its name and the place.
    private func calendarLine(of event: AgendaEvent) -> Text {
        let dot = Text("● ").foregroundStyle(Color(event.calendarColor))
        guard let location = event.location, !location.isEmpty else { return Text("\(dot)\(event.calendarTitle)") }
        return Text("\(dot)\(event.calendarTitle) · \(location)")
    }

    /// "10:00 – 11:00", with the day in front when it isn't today.
    private func timeLine(of event: AgendaEvent) -> String {
        let range = AgendaFormat.timeRange(of: event, calendar: state.calendar)
        guard let day = AgendaFormat.dayLabel(for: event.start, now: state.now, calendar: state.calendar) else { return range }
        return "\(day) · \(range)"
    }
}

private struct TodayList: View {
    let state: CalendarState
    let actions: CalendarActions

    var body: some View {
        ScrollView {
            TodayContent(state: state, actions: actions)
        }
        .scrollIndicators(.never)
    }
}

/// Today's events, all-day first with the past ones dimmed, and below them the reminders.
struct TodayContent: View {
    let state: CalendarState
    let actions: CalendarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(state.agenda.today, id: \.id) { event in
                EventRow(event: event, state: state) { actions.open(event) }
            }
            if state.agenda.today.isEmpty {
                Text("Hôm nay không có sự kiện")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .padding(.vertical, 4)
            }
            reminders
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var reminders: some View {
        switch state.reminders {
        case .hidden:
            EmptyView()
        case .needsAccess:
            SectionTitle("Lời nhắc")
            Button { actions.requestRemindersAccess() } label: {
                Label("Cho phép truy cập Lời nhắc", systemImage: "checklist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
        case .items(let items):
            SectionTitle("Lời nhắc")
            ForEach(items, id: \.id) { reminder in
                ReminderRow(reminder: reminder, state: state) { actions.complete(reminder) }
            }
            if items.isEmpty {
                Text("Không có lời nhắc nào đến hạn")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTokens.secondaryText)
            }
        }
    }
}

private struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(NotchTokens.secondaryText)
            .padding(.top, 6)
    }
}

private struct EventRow: View {
    let event: AgendaEvent
    let state: CalendarState
    let open: () -> Void
    @State private var isHovering = false

    /// All-day events never dim: they last until the day ends.
    private var isPast: Bool { !event.isAllDay && event.end <= state.now }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Circle().fill(Color(event.calendarColor)).frame(width: 6, height: 6)
                Text(AgendaFormat.timeRange(of: event, calendar: state.calendar))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(NotchTokens.secondaryText)
                    .frame(width: 88, alignment: .leading)
                Text(event.title.isEmpty ? "(Không có tiêu đề)" : event.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchTokens.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(isHovering ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isPast ? 0.4 : 1)
        .onHover { isHovering = $0 }
        .help("Mở trong Lịch")
    }
}

private struct ReminderRow: View {
    let reminder: AgendaReminder
    let state: CalendarState
    let complete: () -> Void
    @State private var isHovering = false

    private var isOverdue: Bool {
        AgendaReminder.isOverdue(due: reminder.due, now: state.now, calendar: state.calendar)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: complete) {
                Image(systemName: isHovering ? "checkmark.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(reminder.listColor))
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Đánh dấu hoàn thành")
            .accessibilityLabel("Hoàn thành \(reminder.title)")
            Text(reminder.title)
                .font(.system(size: 12))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let label = AgendaFormat.dueLabel(of: reminder, calendar: state.calendar, now: state.now) {
                Text(label)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(isOverdue ? Color.red : NotchTokens.secondaryText)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .onHover { isHovering = $0 }
    }
}
