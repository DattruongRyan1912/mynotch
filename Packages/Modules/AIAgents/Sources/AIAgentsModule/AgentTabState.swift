import Foundation

/// What the AI tab lists, as text and numbers: the sessions newest first, today's usage per agent and Codex's
/// rate limits. Pure, so the figures are tested without drawing anything.
nonisolated struct AgentTabState: Equatable, Sendable {
    static let emptyMessage = "Không có phiên Claude Code hay Codex nào đang chạy"

    nonisolated enum Status: Equatable, Sendable {
        case working, waitingForInput, finished
        /// A Codex session that runs one silent tool for more than 90 s (a long build or test run) shows as idle
        /// until the tool's output arrives: Codex has no registry to confirm the turn is still running, so the store
        /// takes that much silence for an interrupted turn. Accepted.
        case idle
        case error

        var label: String {
            switch self {
            case .working: "Đang chạy"
            case .waitingForInput: "Chờ bạn"
            case .finished: "Xong"
            case .idle: "Rảnh"
            case .error: "Lỗi"
            }
        }
    }

    nonisolated enum Timing: Equatable, Sendable {
        /// A turn under way, counted live from its start.
        case running(since: Date)
        /// A turn that ended, and how long it ran.
        case took(TimeInterval)
        case unknown
    }

    nonisolated struct Row: Identifiable, Equatable, Sendable {
        let id: AgentSessionKey
        var source: AgentSource
        /// The project folder and git branch.
        var title: String
        var status: Status
        /// The tool running now and its short summary; nothing else of the conversation.
        var detail: String?
        var timing: Timing
        var cwd: String?

        init(_ session: AgentSession) {
            id = session.key
            source = session.key.source
            cwd = session.cwd
            title = Self.title(of: session)
            switch session.state {
            case let .working(tool, summary):
                status = .working
                detail = tool.map { name in summary.map { "\(name) · \($0)" } ?? name }
            case .waitingForInput:
                status = .waitingForInput
            case .finished:
                status = .finished
            case .idle:
                status = .idle
            case .error:
                status = .error
            }
            switch (session.state, session.turnStartedAt) {
            case (.working, let start?), (.waitingForInput, let start?):
                timing = .running(since: start)
            case (_, let start?):
                timing = .took(max(session.lastEventAt.timeIntervalSince(start), 0))
            default:
                timing = .unknown
            }
        }

        private static func title(of session: AgentSession) -> String {
            guard let project = session.project, !project.isEmpty else { return "Phiên \(session.key.sessionID.prefix(8))" }
            guard let branch = session.branch, !branch.isEmpty else { return project }
            return "\(project) • \(branch)"
        }
    }

    /// One agent's usage today.
    nonisolated struct UsageLine: Identifiable, Equatable, Sendable {
        var id: AgentSource { source }
        var source: AgentSource
        var tokens: String
        /// A dash when no model used has a price.
        var cost: String
        /// The cost comes from the price table, not from the agent: it must be labelled `UsageCalculator.estimateLabel`.
        var isEstimated: Bool
    }

    /// One Codex rate-limit window.
    nonisolated struct LimitBar: Identifiable, Equatable, Sendable {
        var id: String
        var label: String
        var percent: Int
        var resets: String?
    }

    var rows: [Row]
    var usage: [UsageLine]
    var limits: [LimitBar]
    var isEmpty: Bool { rows.isEmpty }

    /// - Parameter sessions: in the order to list them.
    init(sessions: [AgentSession], dayUsage: [AgentSource: AgentDayUsage], now: Date, calendar: Calendar = .current) {
        rows = sessions.map(Row.init)
        usage = [AgentSource.claude, .codex].compactMap { source in
            guard let day = dayUsage[source], !day.tokens.isEmpty else { return nil }
            return UsageLine(
                source: source, tokens: AgentFormat.tokens(day.tokens.allTokens),
                cost: AgentFormat.cost(day.estimatedCostUSD), isEstimated: day.estimatedCostUSD != nil
            )
        }
        limits = Self.limits(of: sessions, now: now, calendar: calendar)
    }

    /// The limits come from the Codex session heard from last, and a window that has already reset is left out:
    /// what it said is out of date until Codex reports again.
    private static func limits(of sessions: [AgentSession], now: Date, calendar: Calendar) -> [LimitBar] {
        let latest = sessions
            .filter { $0.key.source == .codex && $0.rateLimits != nil }
            .max { ($0.lastEventAt, $0.key.sessionID) < ($1.lastEventAt, $1.key.sessionID) }
        guard let limits = latest?.rateLimits else { return [] }
        let windows = [("primary", limits.primary, "Ngắn hạn"), ("secondary", limits.secondary, "Dài hạn")]
        return windows.compactMap { id, window, fallbackName in
            guard let window, window.resetsAt.map({ $0 > now }) ?? true else { return nil }
            let percent = window.usedPercent.isFinite ? Int(min(max(window.usedPercent, 0), 100).rounded()) : 0
            return LimitBar(
                id: id, label: AgentFormat.windowName(minutes: window.windowMinutes) ?? fallbackName, percent: percent,
                resets: window.resetsAt.map { AgentFormat.reset($0, now: now, calendar: calendar) }
            )
        }
    }
}

extension AgentTabState {
    /// The store as it is now. Today's usage is read as of `now`, so a tab left open past midnight starts over.
    init(store: AgentSessionStore, now: Date) {
        self.init(sessions: store.orderedSessions, dayUsage: store.todayUsage(at: now), now: now)
    }
}
