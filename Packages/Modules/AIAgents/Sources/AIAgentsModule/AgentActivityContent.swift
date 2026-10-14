import Foundation
import MyNotchCore

/// What the live activity beside the notch shows, worked out from all sessions. Equatable so the module
/// publishes only a change: the timer inside a working activity runs on its own.
nonisolated struct AgentActivityContent: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        /// `since` is when the longest-running turn began.
        case working(since: Date)
        case waitingForInput
        /// The turn just ended; the store clears it after the configured time.
        case finished
    }

    var kind: Kind
    /// The agent the glyph shows: the one whose turn the activity is about.
    var source: AgentSource

    /// A session waiting for the user outranks other activities. Working can go on for hours in the background, so
    /// it yields the notch to whatever else is live, such as playing media, and shows as a bubble beside it.
    var priority: ActivityPriority {
        switch kind {
        case .waitingForInput: .high
        case .working: .low
        case .finished: .normal
        }
    }

    /// For VoiceOver.
    var accessibilityLabel: String {
        switch kind {
        case .working: "\(source.displayName) đang chạy"
        case .waitingForInput: "\(source.displayName) đang chờ bạn"
        case .finished: "\(source.displayName) đã xong"
        }
    }

    init(kind: Kind, source: AgentSource) {
        self.kind = kind
        self.source = source
    }

    /// Waiting beats working, which beats finished. Nil when there is nothing to show. With `showWorking` off
    /// only the working activity is left out: being asked something, or told it is done, still shows.
    init?(sessions: some Sequence<AgentSession>, showWorking: Bool) {
        var waiting: AgentSession?
        var working: AgentSession?
        var finished: AgentSession?
        for session in sessions {
            switch session.state {
            case .waitingForInput:
                waiting = Self.mostRecent(waiting, session)
            case .working:
                if showWorking { working = Self.longestRunning(working, session) }
            case .finished:
                finished = Self.mostRecent(finished, session)
            case .idle, .error:
                break
            }
        }
        if let waiting {
            self.init(kind: .waitingForInput, source: waiting.key.source)
        } else if let working {
            self.init(kind: .working(since: Self.start(of: working)), source: working.key.source)
        } else if let finished {
            self.init(kind: .finished, source: finished.key.source)
        } else {
            return nil
        }
    }

    private static func start(of session: AgentSession) -> Date {
        session.turnStartedAt ?? session.lastEventAt
    }

    /// Ties go to the greater session id, so the choice does not depend on dictionary order.
    private static func mostRecent(_ current: AgentSession?, _ candidate: AgentSession) -> AgentSession {
        guard let current else { return candidate }
        return (current.lastEventAt, current.key.sessionID, current.key.source.rawValue)
            < (candidate.lastEventAt, candidate.key.sessionID, candidate.key.source.rawValue) ? candidate : current
    }

    private static func longestRunning(_ current: AgentSession?, _ candidate: AgentSession) -> AgentSession {
        guard let current else { return candidate }
        return (start(of: candidate), candidate.key.sessionID, candidate.key.source.rawValue)
            < (start(of: current), current.key.sessionID, current.key.source.rawValue) ? candidate : current
    }
}
