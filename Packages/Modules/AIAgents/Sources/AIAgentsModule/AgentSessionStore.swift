import Foundation
import MyNotchCore
import Observation

/// Every Claude Code and Codex session MyNotch knows of, the state each is in and the day's usage. Fed with
/// events from the watcher; time only matters through the injected clock and scheduler, so tests can drive it.
@Observable
final class AgentSessionStore {
    /// A working or waiting session silent for this long, whose registry says idle, was probably interrupted:
    /// Claude Code writes no record and fires no hook when the user presses Esc.
    static let interruptSeconds: TimeInterval = 90
    /// A session silent for this long is dropped; it comes back with its next event.
    static let inactivitySeconds: TimeInterval = 2 * 3600
    /// After a hook event neither the transcript nor the registry decides that session's state for this long. The
    /// hooks know what they can only guess, such as a tool that waits for permission instead of running.
    static let hookPrecedenceSeconds: TimeInterval = 60
    private static let tickInterval: Duration = .seconds(10)

    private(set) var sessions: [AgentSessionKey: AgentSession] = [:]
    private var dayUsage = DayUsageLedger()

    /// How long a finished turn shows before the session is idle; a setting, so views need not follow it.
    @ObservationIgnored var finishedSeconds: Int
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var finishTimers: [AgentSessionKey: ScheduledAction] = [:]
    @ObservationIgnored private var tickTimer: ScheduledAction?
    /// The live Claude processes the registry listed last, by session id.
    @ObservationIgnored private var registry: [String: ClaudeSessionInfo] = [:]
    /// When each session last got a hook event.
    @ObservationIgnored private var lastHookEvent: [AgentSessionKey: Date] = [:]

    init(
        scheduler: any Scheduler,
        finishedSeconds: Int = 5,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.scheduler = scheduler
        self.finishedSeconds = finishedSeconds
        clock = now
        self.calendar = calendar
    }

    /// Newest activity first.
    var orderedSessions: [AgentSession] {
        sessions.values.sorted { ($0.lastEventAt, $1.key.sessionID) > ($1.lastEventAt, $0.key.sessionID) }
    }

    /// Per agent, from events since local midnight. Only what MyNotch has read counts: a transcript found at
    /// launch is read from its last 64 KB, so right after a restart the figures start low.
    var todayUsage: [AgentSource: AgentDayUsage] {
        todayUsage(at: clock())
    }

    func todayUsage(at now: Date) -> [AgentSource: AgentDayUsage] {
        dayUsage.usage(now: now, calendar: calendar)
    }

    func apply(_ event: AgentEvent) {
        apply([event])
    }

    /// Applies events in order and publishes once, so a burst of lines costs views a single update. Old events
    /// replayed from the end of a transcript can leave a turn that ended long ago looking busy; that is settled
    /// before views see it, like any silent session.
    ///
    /// `fromHooks` marks events of the precise-status hooks. While those keep arriving for a session, the same
    /// session's transcript events only give usage and folder, not state.
    func apply(_ events: [AgentEvent], fromHooks: Bool = false) {
        let now = clock()
        for event in events {
            let key = AgentSessionKey(source: event.source, sessionID: event.sessionID)
            if fromHooks {
                lastHookEvent[key] = now
                apply(event, now: now)
            } else if hooksDecideState(of: key, now: now) {
                apply(event.keepingStateAsIs, now: now)
            } else {
                apply(event, now: now)
            }
        }
        tick(now: now)
    }

    /// Takes the registry of live Claude processes. It never creates a session, since a session shows only
    /// when it does something; sessions it listed before and no longer lists have ended.
    func updateRegistry(_ live: [ClaudeSessionInfo]) {
        let previous = registry
        registry = Dictionary(live.map { ($0.sessionID, $0) }, uniquingKeysWith: { _, latest in latest })
        for id in previous.keys where registry[id] == nil {
            remove(AgentSessionKey(source: .claude, sessionID: id))
        }
        for info in registry.values {
            let key = AgentSessionKey(source: .claude, sessionID: info.sessionID)
            guard let original = sessions[key] else { continue }
            var session = original
            if session.cwd == nil { session.cwd = info.cwd }
            // Busy since after the last event: a turn the transcript has not shown yet. A busy entry from before
            // it is stale, and would undo a finish whose registry write is still to come. While hooks arrive, they
            // know better than the registry: the next prompt or tool comes as a hook too.
            if info.status == .busy, let busySince = info.statusUpdatedAt, busySince > session.lastEventAt, !session.state.isInTurn,
               !hooksDecideState(of: key, now: clock()) {
                session.state = .working(tool: nil, summary: nil)
                session.turnStartedAt = busySince
                cancelFinishTimer(for: key)
            }
            if session != original { sessions[key] = session }
        }
        tick(now: clock())
    }

    /// Ends the interrupted turns and drops the sessions that went quiet. Called by a timer while sessions exist.
    func tick(now: Date) {
        for (key, session) in sessions where isInterrupted(session, now: now) {
            sessions[key]?.state = .idle
        }
        prune(now: now)
    }

    /// Forgets the sessions of one agent, for when the user turns it off.
    func removeSessions(of source: AgentSource) {
        for key in sessions.keys where key.source == source { remove(key) }
        if source == .claude { registry = [:] }
        syncTick()
    }

    // MARK: Events

    private func apply(_ event: AgentEvent, now: Date) {
        let key = AgentSessionKey(source: event.source, sessionID: event.sessionID)
        if event.kind == .sessionEnded {
            remove(key)
            return
        }
        let at = min(event.timestamp ?? now, now)
        // A usage record without a timestamp (a `cost-state` may have none) says nothing about when the agent was
        // last active: it must not revive a session that went quiet, nor bring back one that was dropped. Its
        // tokens still count for today.
        let isUntimed = event.kind == .usageUpdated && event.timestamp == nil
        if isUntimed, sessions[key] == nil {
            if let usage = event.usage { countToday(usage, of: event, at: at, now: now) }
            return
        }
        let previous = sessions[key]?.state
        var session = sessions[key] ?? AgentSession(key: key, lastEventAt: at)
        if !isUntimed {
            session.lastEventAt = max(session.lastEventAt, at)
            updateState(of: &session, from: previous, for: event.kind, at: at, now: now)
        }
        if let usage = event.usage {
            session.ledger.record(usage)
            countToday(usage, of: event, at: at, now: now)
        }
        if let costUSD = event.costUSD { session.ledger.recordReportedCost(costUSD) }
        if let rateLimits = event.rateLimits { session.rateLimits = rateLimits }
        sessions[key] = session
        if !isUntimed {
            updateFinishTimer(for: key, from: previous, to: session.state, remaining: TimeInterval(finishedSeconds) - now.timeIntervalSince(at))
        }
    }

    /// A hook event came for this session recently enough that the transcript and the registry do not decide its state.
    private func hooksDecideState(of key: AgentSessionKey, now: Date) -> Bool {
        guard let hooked = lastHookEvent[key] else { return false }
        return now.timeIntervalSince(hooked) < Self.hookPrecedenceSeconds
    }

    private func countToday(_ usage: AgentUsage, of event: AgentEvent, at: Date, now: Date) {
        dayUsage.record(usage, source: event.source, sessionID: event.sessionID, at: at, now: now, calendar: calendar)
    }

    private func updateState(of session: inout AgentSession, from previous: AgentState?, for kind: AgentEvent.Kind, at: Date, now: Date) {
        switch kind {
        case .turnStarted:
            session.state = .working(tool: nil, summary: nil)
            session.turnStartedAt = at
        case let .toolStarted(name, summary):
            beginTurnIfNeeded(&session, from: previous, at: at)
            session.state = .working(tool: name, summary: summary)
        case .toolFinished:
            beginTurnIfNeeded(&session, from: previous, at: at)
            session.state = .working(tool: nil, summary: nil)
        case .waitingForInput:
            session.state = .waitingForInput
        case .turnFinished:
            // Claude writes several records that finish one turn, the first before the answer text.
            // Repeats must not show the finish again or push the idle time back.
            guard previous != .finished, previous != .idle else { return }
            session.state = now.timeIntervalSince(at) >= TimeInterval(finishedSeconds) ? .idle : .finished
        case .turnAborted:
            session.state = .idle
        case .turnFailed:
            session.state = .error
        case let .sessionStarted(cwd, branch):
            if let cwd {
                session.cwd = cwd
                session.branch = branch
            } else if branch != nil {
                session.branch = branch
            }
        case .usageUpdated, .sessionEnded:
            break
        }
    }

    /// Work seen without the prompt that began it (the transcript was joined mid-turn) starts the turn here.
    private func beginTurnIfNeeded(_ session: inout AgentSession, from previous: AgentState?, at: Date) {
        if previous?.isInTurn != true { session.turnStartedAt = at }
    }

    // MARK: Timers

    private func updateFinishTimer(for key: AgentSessionKey, from previous: AgentState?, to state: AgentState, remaining: TimeInterval) {
        switch (previous, state) {
        case (.finished?, .finished):
            break
        case (_, .finished):
            let delay = Duration.seconds(max(remaining, 0))
            finishTimers[key] = scheduler.schedule(after: delay) { [weak self] in
                self?.finishTimers[key] = nil
                if self?.sessions[key]?.state == .finished { self?.sessions[key]?.state = .idle }
            }
        default:
            cancelFinishTimer(for: key)
        }
    }

    private func cancelFinishTimer(for key: AgentSessionKey) {
        finishTimers.removeValue(forKey: key)?.cancel()
    }

    /// Runs while any session exists; with none there is nothing to time out.
    private func syncTick() {
        if sessions.isEmpty {
            tickTimer?.cancel()
            tickTimer = nil
        } else if tickTimer == nil {
            tickTimer = scheduler.schedule(after: Self.tickInterval) { [weak self] in
                guard let self else { return }
                tickTimer = nil
                tick(now: clock())
                syncTick()
            }
        }
    }

    // MARK: Removal

    private func isInterrupted(_ session: AgentSession, now: Date) -> Bool {
        guard now.timeIntervalSince(session.lastEventAt) >= Self.interruptSeconds else { return false }
        let registryIsIdle = session.key.source == .claude && registry[session.key.sessionID]?.status == .idle
        switch session.state {
        case .working:
            // Codex has no registry to confirm the turn is over, so silence alone decides.
            return session.key.source == .codex || registryIsIdle
        case .waitingForInput:
            // Esc at a prompt fires no hook, and silence alone may be a user who is away: only the registry tells.
            return registryIsIdle
        case .finished, .idle, .error:
            return false
        }
    }

    private func prune(now: Date) {
        for (key, session) in sessions where now.timeIntervalSince(session.lastEventAt) >= Self.inactivitySeconds {
            remove(key)
        }
        syncTick()
    }

    private func remove(_ key: AgentSessionKey) {
        sessions[key] = nil
        lastHookEvent[key] = nil
        cancelFinishTimer(for: key)
    }
}

private extension AgentState {
    /// A turn is under way: the agent is working or has stopped to ask.
    var isInTurn: Bool {
        switch self {
        case .working, .waitingForInput: true
        case .finished, .idle, .error: false
        }
    }
}

private extension AgentEvent {
    /// The same event without its effect on the state: what is left is its usage, cost and limits, or the
    /// folder it names. An event with none of those becomes a usage update with nothing in it, which only
    /// notes that the session was active.
    var keepingStateAsIs: AgentEvent {
        switch kind {
        case .sessionStarted, .usageUpdated:
            self
        default:
            AgentEvent(source: source, sessionID: sessionID, timestamp: timestamp, kind: .usageUpdated, usage: usage, costUSD: costUSD, rateLimits: rateLimits)
        }
    }
}
