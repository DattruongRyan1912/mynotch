import NotchUI
import SwiftUI

/// The "Lịch" tab: today's date, the next event as a card, today's events and the reminders due.
struct CalendarTabView: View {
    static let cardWidth: CGFloat = 188

    let state: CalendarState
    let actions: CalendarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AgendaFormat.dayHeader(state.now, calendar: state.calendar))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
            HStack(alignment: .top, spacing: 12) {
                UpcomingCard(state: state, actions: actions)
                    .frame(width: Self.cardWidth)
                TodayList(state: state, actions: actions)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: actions.appeared)
    }
}

/// The "Sắp tới" card: the event to watch for next, with a way in when it has a link.
private struct UpcomingCard: View {
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
        .padding(8)
        .padding(.horizontal, 2)
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
            HStack(spacing: 6) {
                if event.meetingURL != nil {
                    Button { actions.join(event) } label: {
                        Label("Tham gia", systemImage: "video.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NotchTokens.primaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(NotchTokens.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if state.canDismissFeatured {
                    Button { actions.dismiss(event) } label: {
                        Text("Bỏ qua")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NotchTokens.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// "● Work · Phòng họp 4B": the calendar's colour dot, then its name and the place.
    private func calendarLine(of event: AgendaEvent) -> Text {
        let dot = Text("● ").foregroundStyle(Color(event.calendarColor))
        guard let location = event.location, !location.isEmpty else { return dot + Text(event.calendarTitle) }
        return dot + Text("\(event.calendarTitle) · \(location)")
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
