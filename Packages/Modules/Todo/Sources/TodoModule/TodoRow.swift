import NotchUI
import SwiftUI

/// One reminder on the list: checkbox, title, how late it is, its time, its priority and its list's colour. Ticked off, the
/// title is struck through and "Hoàn tác" takes the place of the details until the row goes.
struct TodoRow: View {
    let item: TodoItem
    let isLingering: Bool
    let now: Date
    let calendar: Calendar
    let complete: () -> Void
    let undo: () -> Void
    @State private var isHovering = false

    private var reminder: TodoReminder { item.reminder }

    /// What follows the title, left to right. A pure list so what a row says is checked without drawing it.
    enum Detail: Equatable {
        /// "hôm qua", "quá hạn 3 ngày".
        case badge(String)
        /// A time of today that has gone is late, though the day is not over; a time of an earlier day is the badge's business.
        case time(String, isLate: Bool)
        /// The reminder repeats.
        case repeats
        /// "!", "!!" or "!!!".
        case priority(String)
    }

    static func details(of item: TodoItem, now: Date, calendar: Calendar) -> [Detail] {
        var details: [Detail] = []
        if let badge = TodoFormat.overdueBadge(days: item.overdueDays) { details.append(.badge(badge)) }
        if let time = TodoFormat.time(of: item.reminder.due, calendar: calendar) {
            let passed = item.reminder.due.flatMap { TodoReminder.dueDate(of: $0, calendar: calendar) }.map { $0 < now } ?? false
            details.append(.time(time, isLate: passed && item.overdueDays == 0))
        }
        if item.reminder.isRecurring { details.append(.repeats) }
        if item.reminder.priority != .none { details.append(.priority(item.reminder.priority.marks)) }
        return details
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            checkbox
            Text(reminder.title.isEmpty ? "(Không có tiêu đề)" : reminder.title)
                .font(.system(size: 12.5))
                .foregroundStyle(reminder.isCompleted ? NotchTokens.secondaryText : NotchTokens.primaryText)
                .strikethrough(reminder.isCompleted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 2)
                .animation(.easeInOut(duration: 0.25), value: reminder.isCompleted)
            Spacer(minLength: 4)
            if reminder.isCompleted {
                if isLingering { undoButton }
            } else {
                details
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(NotchTokens.fill(isHovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private var checkbox: some View {
        Button(action: reminder.isCompleted ? undo : complete) {
            Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : isHovering ? "checkmark.circle" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(Color(reminder.listColor))
                .frame(width: 20, height: 20)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(reminder.isCompleted ? "Hoàn tác" : "Đánh dấu xong")
        .accessibilityLabel(reminder.isCompleted ? "Hoàn tác \(reminder.title)" : "Xong \(reminder.title)")
    }

    private var undoButton: some View {
        Button(action: undo) {
            Text("Hoàn tác")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(NotchTokens.fill(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var details: some View {
        HStack(spacing: 6) {
            ForEach(Array(Self.details(of: item, now: now, calendar: calendar).enumerated()), id: \.offset) { _, detail in
                switch detail {
                case .badge(let text):
                    Text(text)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.18), in: Capsule())
                        .lineLimit(1)
                case .time(let text, let isLate):
                    Text(text)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(isLate ? Color.red : NotchTokens.secondaryText)
                case .repeats:
                    Image(systemName: "repeat")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .accessibilityLabel("Lặp lại")
                case .priority(let marks):
                    Text(marks)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.orange)
                }
            }
            Circle().fill(Color(reminder.listColor)).frame(width: 6, height: 6)
                .accessibilityLabel(reminder.listTitle)
        }
        .padding(.top, 3)
        .fixedSize()
    }
}
