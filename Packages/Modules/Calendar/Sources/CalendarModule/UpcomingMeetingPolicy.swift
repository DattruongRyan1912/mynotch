import Foundation

/// Decides whether the "meeting soon" live activity shows, and what it says.
nonisolated struct UpcomingMeetingPolicy: Equatable, Sendable {
    /// How long a meeting stays on show after it starts, so someone who is late can still tap "Tham gia".
    static let inProgressDuration: TimeInterval = 5 * 60

    /// How early before the start the activity appears (the `meetingLeadMinutes` setting).
    var leadMinutes: Int
    private var dismissedEventID: String?

    init(leadMinutes: Int) {
        self.leadMinutes = leadMinutes
    }

    enum State: Equatable, Sendable {
        case hidden
        /// Whole minutes until the start, rounded up so "1" holds until the start itself.
        case upcoming(minutesLeft: Int)
        case inProgress
    }

    /// A copy that keeps this event hidden. A rescheduled event has a new id, so it shows again.
    func dismissed(eventID: String) -> UpcomingMeetingPolicy {
        var copy = self
        copy.dismissedEventID = eventID
        return copy
    }

    /// `event` is the agenda's next event. Shown from `leadMinutes` before its start up to 5 minutes after it.
    func state(for event: AgendaEvent?, now: Date) -> State {
        guard let event, event.id != dismissedEventID else { return .hidden }
        let untilStart = event.start.timeIntervalSince(now)
        if untilStart > 0 {
            return untilStart <= Double(leadMinutes) * 60 ? .upcoming(minutesLeft: Int((untilStart / 60).rounded(.up))) : .hidden
        }
        return -untilStart < Self.inProgressDuration ? .inProgress : .hidden
    }

    /// The event the activity is about: the first of `events`, in the order given (by start), that hasn't started or
    /// started less than `inProgressDuration` ago. Taking the first of the agenda's `next` instead would let a
    /// workshop that began at nine hide the meeting at two. The dismissed event steps aside for the next one, so
    /// dismissing a meeting doesn't hide another that starts a few minutes later; `includingDismissed` keeps it.
    func nextMeeting(in events: [AgendaEvent], now: Date, includingDismissed: Bool = false) -> AgendaEvent? {
        events.first { event in
            (includingDismissed || event.id != dismissedEventID)
                && (event.start > now || now.timeIntervalSince(event.start) < Self.inProgressDuration)
        }
    }
}
