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
            statusUpdatedAt: JSONFields.date(entry["statusUpdatedAt"])
        )
    }

    /// A registry file outlives a crashed process, so its pid must still exist. `EPERM` means it exists but
    /// belongs to another user. Non-positive pids would address process groups, so they are never alive.
    static func isAlive(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
