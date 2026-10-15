import AppKit
import EventKit

nonisolated extension TodoColor {
    init(_ color: NSColor?) {
        guard let rgb = color?.usingColorSpace(.sRGB) else {
            self = .gray
            return
        }
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
    }
}

nonisolated extension TodoReminder {
    init(_ reminder: EKReminder) {
        self.init(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            due: reminder.dueDateComponents,
            priority: TodoPriority(eventKit: reminder.priority),
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            listID: reminder.calendar?.calendarIdentifier ?? "",
            listTitle: reminder.calendar?.title ?? "",
            listColor: TodoColor(reminder.calendar?.color),
            isRecurring: reminder.hasRecurrenceRules
        )
    }
}

nonisolated extension TodoListInfo {
    init(_ calendar: EKCalendar, isDefault: Bool = false) {
        self.init(
            id: calendar.calendarIdentifier, title: calendar.title, color: TodoColor(calendar.color),
            allowsModifications: calendar.allowsContentModifications, isDefaultForNewReminders: isDefault
        )
    }
}
