import AppKit
import EventKit

nonisolated extension RGBAColor {
    init(_ color: NSColor?) {
        guard let rgb = color?.usingColorSpace(.sRGB) else {
            self = .gray
            return
        }
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
    }
}

nonisolated extension AgendaEvent.Status {
    init(_ status: EKEventStatus) {
        self = switch status {
        case .canceled: .canceled
        case .tentative: .tentative
        case .none, .confirmed: .confirmed
        @unknown default: .confirmed
        }
    }
}

nonisolated extension AgendaEvent.Participation {
    /// `nil` is an event without an attendee list, such as one the user made for themselves.
    init(_ status: EKParticipantStatus?) {
        self = switch status {
        case .accepted: .accepted
        case .declined: .declined
        case .tentative: .tentative
        case .pending: .pending
        default: .unknown
        }
    }
}

nonisolated extension AgendaEvent {
    init(_ event: EKEvent) {
        let me = event.attendees?.first(where: \.isCurrentUser)
        self.init(
            calendarItemIdentifier: event.calendarItemIdentifier,
            title: event.title,
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            calendarTitle: event.calendar?.title ?? "",
            calendarColor: RGBAColor(event.calendar?.color),
            location: event.location,
            notes: event.notes,
            url: event.url,
            status: Status(event.status),
            myParticipation: Participation(me?.participantStatus)
        )
    }
}

nonisolated extension AgendaReminder {
    init(_ reminder: EKReminder, now: Date, calendar: Calendar) {
        let due = reminder.dueDateComponents
        self.init(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            due: due,
            isOverdue: Self.isOverdue(due: due, now: now, calendar: calendar),
            listTitle: reminder.calendar?.title ?? "",
            listColor: RGBAColor(reminder.calendar?.color)
        )
    }
}

nonisolated extension CalendarInfo {
    init(_ calendar: EKCalendar, isDefault: Bool = false) {
        self.init(
            id: calendar.calendarIdentifier, title: calendar.title, color: RGBAColor(calendar.color),
            allowsModifications: calendar.allowsContentModifications, isDefaultForNewEvents: isDefault
        )
    }
}

nonisolated extension NewEvent {
    /// What EventKit is given for the event. An all-day event is the same day everywhere, so it has no zone, and Calendar
    /// saves its end as the last second of its last day (the draft carries the start of the day after). The others are in the
    /// zone they were typed in.
    var eventKitTiming: (start: Date, end: Date, timeZone: TimeZone?) {
        isAllDay ? (start, end.addingTimeInterval(-1), nil) : (start, end, timeZone)
    }
}
