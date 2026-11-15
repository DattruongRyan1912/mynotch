import MyNotchCore

/// The lines the module writes to the log (category `todo`, notice level). Codes and counts only: never a title, a note or a
/// list's name, so nothing the user typed can reach it. They are made here, not at the call sites, so a test pins what they say.
nonisolated enum TodoLog {
    static let storeRenewed = "store renewed after access was granted"

    static func code(_ status: PermissionStatus) -> String {
        switch status {
        case .granted: "granted"
        case .denied: "denied"
        case .notDetermined: "notDetermined"
        case .unknown: "unknown"
        }
    }

    static func code(_ phase: TodoState.Phase) -> String {
        switch phase {
        case .loading: "loading"
        case .ready: "ready"
        case .needsAccess: "needsAccess"
        }
    }

    /// The status a refresh found, which decides what it does.
    static func refresh(status: PermissionStatus) -> String {
        "refresh status=\(code(status))"
    }

    static func phase(from old: TodoState.Phase, to new: TodoState.Phase) -> String {
        "phase \(code(old)) -> \(code(new))"
    }

    /// What a read brought back, and how many items the list came to.
    static func read(lists: Int, incomplete: Int, completed: Int, items: Int) -> String {
        "read lists=\(lists) incomplete=\(incomplete) completed=\(completed) items=\(items)"
    }

    /// The answer the request returned, which can still be the old status: the system's lags the prompt.
    static func request(before: PermissionStatus, after: PermissionStatus) -> String {
        "access request before=\(code(before)) after=\(code(after))"
    }

    /// What waiting for the status to settle ended with.
    static func recheck(status: PermissionStatus, polls: Int) -> String {
        "access recheck status=\(code(status)) polls=\(polls)"
    }
}
