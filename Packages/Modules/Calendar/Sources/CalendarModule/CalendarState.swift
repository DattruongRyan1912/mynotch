import Foundation
import Observation

/// What the Reminders part of the tab shows.
nonisolated enum RemindersSection: Equatable, Sendable {
    /// The `showReminders` setting is off.
    case hidden
    /// On, but the user hasn't granted access: the tab offers a button.
    case needsAccess
    case items([AgendaReminder])
}

/// What the tab reads. The module fills it on every refresh.
@Observable
final class CalendarState {
    /// When the agenda was read; the tab dims past events and flags overdue reminders against it.
    var now: Date
    var agenda = Agenda()
    /// The event the "Sắp tới" card shows: the meeting the activity is about, else the next event.
    var featured: AgendaEvent?
    /// Whether the activity currently shows `featured`, so the card offers "Bỏ qua".
    var canDismissFeatured = false
    /// The same, and the meeting has not started: the card also offers "Báo lại".
    var canSnoozeFeatured = false
    var reminders = RemindersSection.hidden
    let calendar: Calendar

    init(now: Date = .now, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
    }

    /// Whether the Reminders part shows the wrong thing for the current access: a button after access was
    /// granted, or a list after it was taken back. `hidden` follows the setting, which the module observes.
    func remindersAreStale(granted: Bool) -> Bool {
        switch reminders {
        case .hidden: false
        case .needsAccess: granted
        case .items: !granted
        }
    }

    func reset() {
        agenda = Agenda()
        featured = nil
        canDismissFeatured = false
        canSnoozeFeatured = false
        reminders = .hidden
    }
}
