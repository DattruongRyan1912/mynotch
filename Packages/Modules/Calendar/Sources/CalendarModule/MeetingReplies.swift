import Foundation

/// What the user answered to the card of each meeting: "Báo lại" (hidden for a while) or "Bỏ qua" (hidden for good).
/// Kept per occurrence, so answering today's stand-up says nothing about tomorrow's, and stored with the module's
/// settings so a restart does not bring a dismissed card back.
nonisolated struct MeetingReplies: Equatable, Codable, Sendable {
    /// How long "Báo lại" hides the card, unless the meeting starts sooner.
    static let snoozeDuration: TimeInterval = 5 * 60

    struct Reply: Equatable, Codable, Sendable {
        var snoozedUntil: Date?
        var isDismissed: Bool
        /// From this moment the occurrence is over and the answer is no longer needed.
        var expires: Date
    }

    private var replies: [String: Reply] = [:]

    var isEmpty: Bool { replies.isEmpty }
    var count: Int { replies.count }

    /// The event's id together with its start. In EventKit the id already carries the occurrence start; repeating
    /// it here keeps an answer to one occurrence from ever reaching another, whatever builds the id.
    private static func key(for event: AgendaEvent) -> String {
        "\(event.id)|\(Int(event.start.timeIntervalSince1970))"
    }

    /// When a snooze made at `now` ends: five minutes on, or the start if that comes first.
    static func snoozeEnd(for event: AgendaEvent, now: Date) -> Date {
        min(now.addingTimeInterval(snoozeDuration), event.start)
    }

    func isHidden(_ event: AgendaEvent, now: Date) -> Bool {
        guard let reply = replies[Self.key(for: event)] else { return false }
        return reply.isDismissed || reply.snoozedUntil.map { now < $0 } == true
    }

    /// A copy that hides `event` until `snoozeEnd`. A meeting that has started has nothing left to wait for, and
    /// the card is gone five minutes after the start anyway, so it is left as it is; asking again moves the end.
    func snoozing(_ event: AgendaEvent, now: Date) -> MeetingReplies {
        guard now < event.start else { return self }
        var copy = self
        copy.update(event) { $0.snoozedUntil = Self.snoozeEnd(for: event, now: now) }
        return copy
    }

    /// A copy that hides `event` for the rest of its card's life, and leaves its snooze alone: the dismissal wins.
    func dismissing(_ event: AgendaEvent) -> MeetingReplies {
        var copy = self
        copy.update(event) { $0.isDismissed = true }
        return copy
    }

    /// A copy without the answers to occurrences that are over, so the stored map stays as small as the day's meetings.
    func pruned(now: Date) -> MeetingReplies {
        var copy = self
        copy.replies = replies.filter { $0.value.expires > now }
        return copy
    }

    /// The first moment after `now` that a snooze ends: when the card is due back.
    func nextWake(after now: Date) -> Date? {
        replies.values.compactMap { $0.isDismissed ? nil : $0.snoozedUntil }.filter { $0 > now }.min()
    }

    private mutating func update(_ event: AgendaEvent, _ change: (inout Reply) -> Void) {
        // The card shows until `inProgressDuration` after the start, so a meeting shorter than that must not lose its
        // answer when it ends and have the card come back.
        let expires = max(event.end, event.start.addingTimeInterval(UpcomingMeetingPolicy.inProgressDuration))
        var reply = replies[Self.key(for: event)] ?? Reply(snoozedUntil: nil, isDismissed: false, expires: expires)
        change(&reply)
        replies[Self.key(for: event)] = reply
    }
}
