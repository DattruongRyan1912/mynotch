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
}
