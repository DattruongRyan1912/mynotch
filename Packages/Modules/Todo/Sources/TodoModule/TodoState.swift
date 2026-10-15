import Foundation
import Observation

/// What the tab reads. The module fills it on every refresh.
@Observable
final class TodoState {
    enum Phase: Equatable {
        /// Nothing read yet.
        case loading
        case ready
        /// The user hasn't granted Reminders access: the tab offers a button.
        case needsAccess
    }

    var phase = Phase.loading
    /// Today's items as read, the ones done today included, in the order the list shows them.
    var items: [TodoItem] = []
    /// IDs of items just ticked off: their rows stay for a moment, struck through, with "Hoàn tác".
    var lingering: Set<String> = []
    /// When the reminders were read; the tab flags a time that has gone against it.
    var now: Date
    /// A short line under the field: a reminder went to another day, or something could not be saved. Nil when none.
    var notice: String?
    /// Rises each time the quick-add shortcut asks for the field, so the tab knows to focus it.
    var focusRequest = 0
    let calendar: Calendar

    init(now: Date = .now, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
    }

    /// What the list shows: what is left to do, and what was just ticked off until its row goes.
    var rows: [TodoItem] {
        items.filter { !$0.reminder.isCompleted || lingering.contains($0.id) }
    }

    var progress: TodoProgress { TodoToday.progress(of: items) }

    func reset() {
        phase = .loading
        items = []
        lingering = []
        notice = nil
    }
}
