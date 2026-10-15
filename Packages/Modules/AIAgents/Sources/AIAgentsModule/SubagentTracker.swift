import Foundation

/// The subagents of one session: which run, and which finished last. Fed with the events of the hooks, so a subagent counts
/// from its `SubagentStart` to its `SubagentStop`. A stop can fail to come (the user pressed Esc, the agent was killed),
/// so one that has been silent for `silenceTimeout` is dropped. Pure, with the time passed in.
nonisolated struct SubagentTracker: Equatable, Sendable {
    /// Long enough for one slow tool (a build, a test run), short enough that a stop that never came is not shown for long.
    /// Any event of the subagent, such as the tool it calls, starts the wait again.
    static let silenceTimeout: TimeInterval = 10 * 60
    /// A call of the Agent tool and the start of its subagent come together; a call that nobody took by then is not waited for.
    static let callTimeout: TimeInterval = 30
    static let maxRunning = 64
    static let maxCalls = 16

    nonisolated struct Finished: Equatable, Sendable {
        var id: String
        /// What the subagent was asked, as its call described it, else its type.
        var label: String
        var finishedAt: Date
    }

    private nonisolated struct Running: Equatable, Sendable {
        var type: String?
        var label: String?
        var lastSeen: Date
    }

    /// What the Agent tool was asked to do, waiting for the start of its subagent, which is where the type is checked.
    private nonisolated struct Call: Equatable, Sendable {
        var type: String?
        var description: String
        var at: Date
    }

    private var running: [String: Running] = [:]
    private var calls: [Call] = []
    private(set) var lastFinished: Finished?

    var runningCount: Int { running.count }

    /// The Agent tool was called: the few words it was given tell which subagent this is, once that starts.
    mutating func requested(type: String?, description: String, at: Date) {
        calls.append(Call(type: type, description: description, at: at))
        if calls.count > Self.maxCalls { calls.removeFirst(calls.count - Self.maxCalls) }
    }

    mutating func started(id: String, type: String?, at: Date) {
        dropOldCalls(at: at)
        var label = running[id]?.label
        if label == nil, let index = calls.firstIndex(where: { $0.type == nil || type == nil || $0.type == type }) {
            label = calls.remove(at: index).description
        }
        running[id] = Running(type: type ?? running[id]?.type, label: label, lastSeen: at)
        if running.count > Self.maxRunning, let oldest = running.min(by: { ($0.value.lastSeen, $0.key) < ($1.value.lastSeen, $1.key) }) {
            running[oldest.key] = nil
        }
    }

    /// The subagent is done. A stop for one that was not seen start (MyNotch began mid-run) still says what finished; a
    /// second stop for the same one (two helpers report every event) says nothing new.
    mutating func stopped(id: String, type: String?, at: Date) {
        let known = running.removeValue(forKey: id)
        if known == nil, lastFinished?.id == id { return }
        guard let label = known?.label ?? known?.type ?? type else { return }
        lastFinished = Finished(id: id, label: label, finishedAt: at)
    }

    /// Something happened inside this subagent, so it is alive.
    mutating func touch(id: String, at: Date) {
        guard let seen = running[id]?.lastSeen, at > seen else { return }
        running[id]?.lastSeen = at
    }

    func hasExpired(at now: Date) -> Bool {
        calls.contains { now.timeIntervalSince($0.at) >= Self.callTimeout }
            || running.values.contains { now.timeIntervalSince($0.lastSeen) >= Self.silenceTimeout }
    }

    /// Drops what has waited too long, without making any of it the last finished: it is not known to have finished.
    mutating func expire(at now: Date) {
        dropOldCalls(at: now)
        running = running.filter { now.timeIntervalSince($0.value.lastSeen) < Self.silenceTimeout }
    }

    /// The agent was interrupted: nothing it started still runs. What finished before stays.
    mutating func reset() {
        running = [:]
        calls = []
    }

    private mutating func dropOldCalls(at now: Date) {
        calls.removeAll { now.timeIntervalSince($0.at) >= Self.callTimeout }
    }
}
