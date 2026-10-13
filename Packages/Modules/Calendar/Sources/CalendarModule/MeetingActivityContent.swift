import Foundation
import MyNotchCore

/// What the "meeting soon" activity shows right now. Equatable, so the module publishes only when it changes:
/// the countdown moves once a minute and nothing else about the activity does.
nonisolated struct MeetingActivityContent: Equatable, Sendable {
    /// How close to the start the activity turns urgent, on either side of it.
    static let urgentWindow: TimeInterval = 60

    var eventID: String
    var color: RGBAColor
    var state: UpcomingMeetingPolicy.State
    var priority: ActivityPriority

    var countdown: String { AgendaFormat.countdown(state) ?? "" }

    /// nil while the policy hides the event.
    init?(event: AgendaEvent?, policy: UpcomingMeetingPolicy, now: Date) {
        guard let event else { return nil }
        let state = policy.state(for: event, now: now)
        guard state != .hidden else { return nil }
        eventID = event.id
        color = event.calendarColor
        self.state = state
        priority = abs(event.start.timeIntervalSince(now)) <= Self.urgentWindow ? .high : .normal
    }
}
