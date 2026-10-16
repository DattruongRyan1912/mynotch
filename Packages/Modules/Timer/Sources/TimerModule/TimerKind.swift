import Foundation

/// The three countdowns the tab offers. A type picks the glyph, the accent and the length the dial starts at, and what
/// is offered once it ends. (`rest` is the break: `break` is a keyword.)
nonisolated enum TimerKind: String, Codable, CaseIterable, Sendable {
    case task, reminder, rest

    /// What the dial and the settings can hold. A timer longer than an hour is made by adding minutes to a running one.
    static let minutesRange = 1...60

    var title: String {
        switch self {
        case .task: "Tập trung"
        case .reminder: "Nhắc việc"
        case .rest: "Nghỉ"
        }
    }

    var systemImage: String {
        switch self {
        case .task: "brain.head.profile"
        case .reminder: "bell.fill"
        case .rest: "cup.and.saucer.fill"
        }
    }

    /// Where the dial starts until the user changes the length in Settings.
    var defaultMinutes: Int {
        switch self {
        case .task: 25
        case .reminder: 10
        case .rest: 5
        }
    }

    /// The type to offer when this one ends: work is followed by a break and a break by work. A reminder is a one-off.
    var next: TimerKind? {
        switch self {
        case .task: .rest
        case .rest: .task
        case .reminder: nil
        }
    }
}

/// The one-click next step shown when a timer ends.
nonisolated struct TimerSuggestion: Equatable {
    let kind: TimerKind
    let minutes: Int

    var buttonTitle: String {
        switch kind {
        case .rest: "Nghỉ \(minutes) phút"
        case .task: "Bắt đầu tập trung"
        case .reminder: "Nhắc việc \(minutes) phút"
        }
    }

    /// The same step as a button of the toast, which has no room to say how long.
    var toastTitle: String {
        switch kind {
        case .rest: "Bắt đầu nghỉ"
        case .task: "Bắt đầu tập trung"
        case .reminder: "Bắt đầu nhắc việc"
        }
    }
}

/// A length shown by name rather than by minutes, for what the dial cannot hold or sets in one click.
nonisolated struct TimerLength: Equatable {
    let title: String
    let minutes: Int

    /// Past the dial's hour: the menu next to "Bắt đầu", each starting a timer straight away.
    static let longer = [
        TimerLength(title: "1 giờ", minutes: 60), TimerLength(title: "90 phút", minutes: 90),
        TimerLength(title: "2 giờ", minutes: 120), TimerLength(title: "3 giờ", minutes: 180),
    ]

    /// The old presets: small buttons that start at once, when the row has room for them.
    static let quick = [
        TimerLength(title: "5 phút", minutes: 5), TimerLength(title: "10 phút", minutes: 10), TimerLength(title: "25 phút", minutes: 25),
    ]
}
