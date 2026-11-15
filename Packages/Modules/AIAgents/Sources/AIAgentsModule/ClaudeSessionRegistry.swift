import Foundation

/// One running Claude Code process, from `~/.claude/sessions/<pid>.json`. The session `name` is left out on
/// purpose: it may be a title generated from the first prompt.
nonisolated struct ClaudeSessionInfo: Equatable, Sendable {
    nonisolated enum Status: String, Sendable {
        case busy, idle
    }

    var pid: pid_t
    var sessionID: String
    var cwd: String?
    /// Nil when the file reports a status this version does not know.
    var status: Status?
    var startedAt: Date?
    var statusUpdatedAt: Date?
    /// When the process started, if the file says; it tells a live process from a recycled pid.
    var procStart: Date?
}

/// Reads Claude Code's registry of running sessions, which says which transcripts are live and whether each is busy.
nonisolated enum ClaudeSessionRegistry {
    /// Nil unless the entry names both a positive pid and a session.
    static func parse(data: Data) -> ClaudeSessionInfo? {
        guard let entry = JSONFields.object(from: data),
              let pid = (entry["pid"] as? Int).flatMap({ pid_t(exactly: $0) }), pid > 0,
              let sessionID = JSONFields.string(entry["sessionId"]) else { return nil }
        return ClaudeSessionInfo(
            pid: pid,
            sessionID: sessionID,
            cwd: JSONFields.string(entry["cwd"]),
            status: (entry["status"] as? String).flatMap(ClaudeSessionInfo.Status.init(rawValue:)),
            startedAt: JSONFields.date(entry["startedAt"]),
            statusUpdatedAt: JSONFields.date(entry["statusUpdatedAt"]),
            procStart: JSONFields.date(entry["procStart"])
        )
    }

    /// A registry file outlives a crashed process, so its pid must still exist. `EPERM` means it exists but
    /// belongs to another user. Non-positive pids would address process groups, so they are never alive.
    static func isAlive(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// A process started this long before or after the recorded `procStart` is still taken to be the same
    /// one, because the file's clock and unit are not documented.
    private static let startTolerance: TimeInterval = 120

    /// Like `isAlive(pid:)`, but a pid that now belongs to a process started at another time than the entry
    /// recorded is a different process. A `procStart` that is no plausible Unix time (unknown unit) is ignored,
    /// so only the pid decides.
    static func isAlive(_ info: ClaudeSessionInfo) -> Bool {
        guard isAlive(pid: info.pid) else { return false }
        guard let recorded = info.procStart, recorded.timeIntervalSince1970 > 1_000_000_000,
              let actual = processStartTime(pid: info.pid) else { return true }
        return abs(actual.timeIntervalSince(recorded)) <= startTolerance
    }

    /// Nil when the process is gone or belongs to another user.
    static func processStartTime(pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }
}
