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

    /// A time of today that has gone shows red: it is late, though the day is not over.
    private var timePassed: Bool {
        guard let due = reminder.due, due.hour != nil, let date = TodoReminder.dueDate(of: due, calendar: calendar) else { return false }
        return date < now
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
        .background(Color.white.opacity(isHovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
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
                .background(Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var details: some View {
        HStack(spacing: 6) {
            if let badge = TodoFormat.overdueBadge(days: item.overdueDays) {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.red.opacity(0.18), in: Capsule())
                    .lineLimit(1)
            }
            if let time = TodoFormat.time(of: reminder.due, calendar: calendar) {
                Text(time)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(timePassed && item.overdueDays == 0 ? Color.red : NotchTokens.secondaryText)
            }
            if reminder.priority != .none {
                Text(reminder.priority.marks)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.orange)
            }
            Circle().fill(Color(reminder.listColor)).frame(width: 6, height: 6)
                .accessibilityLabel(reminder.listTitle)
        }
        .padding(.top, 3)
        .fixedSize()
    }
}
