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
    /// The quick-add shortcut asked for the field to take the keyboard and the tab has not served it yet. One-shot: the field
    /// takes it when it appears (`takeFocusRequest`), so a later open of the tab, which mounts the field again, does not
    /// focus it.
    private(set) var pendingFocus = false
    /// The last read failed: EventKit answered with nothing, not an empty list. What was on the list stays, with a line
    /// saying so and a button to read again.
    var loadFailed = false
    /// Reminders access was refused (not just never asked): the hint then says where to turn it on.
    var accessIsDenied = false
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

    func requestFocus() {
        pendingFocus = true
    }

    /// Whether the field is to take the keyboard now; asking clears the request, so it is served once.
    func takeFocusRequest() -> Bool {
        defer { pendingFocus = false }
        return pendingFocus
    }

    func cancelFocusRequest() {
        pendingFocus = false
    }

    func reset() {
        phase = .loading
        items = []
        lingering = []
        notice = nil
        pendingFocus = false
        loadFailed = false
        accessIsDenied = false
    }
}
