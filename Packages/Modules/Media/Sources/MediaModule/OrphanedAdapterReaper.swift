import Darwin

/// A running process, as much as the reaper needs to know about it.
nonisolated struct ProcessEntry: Equatable, Sendable {
    var pid: pid_t
    var parentPID: pid_t
    var userID: uid_t
    /// The command line as the process was started with it, the program first.
    var arguments: [String]
}

/// The system's processes and the way to stop one, so that tests never touch a real process.
protocol ProcessTable {
    /// The processes of the current user whose parent is `parent`.
    func processes(withParent parent: pid_t) -> [ProcessEntry]
    /// Asks the process to end (SIGTERM).
    func terminate(_ pid: pid_t)
}

/// Stops adapter streams that an earlier MyNotch left behind. A MyNotch that is killed or crashes cannot stop its
/// `mediaremote-adapter.pl` child, which then runs on with launchd (process 1) as its parent, holding a MediaRemote
/// connection nobody reads. The adapter command line names this bundle's script and framework, so only a stream
/// that was started from this bundle matches: not another app's, not another copy of MyNotch, and not a live stream
/// of this one (whose parent is the app).
struct OrphanedAdapterReaper {
    /// launchd, which adopts the children of a process that has died.
    static let launchdPID: pid_t = 1

    let table: any ProcessTable
    /// What the adapter is run with before its command: the script and the framework (`AdapterProcess.baseArguments`).
    let adapterArguments: [String]
    var userID: uid_t = getuid()

    /// The process IDs that were asked to end.
    @discardableResult
    func reap() -> [pid_t] {
        let orphans = table.processes(withParent: Self.launchdPID).filter(isOrphanedStream)
        for orphan in orphans { table.terminate(orphan.pid) }
        return orphans.map(\.pid)
    }

    /// Re-checked here, whatever the table has already filtered: this is the line between an adapter and a stranger.
    private func isOrphanedStream(_ process: ProcessEntry) -> Bool {
        process.pid > Self.launchdPID && process.pid != getpid()
            && process.parentPID == Self.launchdPID && process.userID == userID
            && process.arguments.dropFirst().starts(with: adapterArguments + ["stream"])
    }
}
