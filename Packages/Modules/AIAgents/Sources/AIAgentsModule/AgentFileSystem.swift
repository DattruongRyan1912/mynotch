import Foundation

/// Stops a watch started with `AgentFileSystem.watch`.
nonisolated protocol AgentWatchHandle: AnyObject, Sendable {
    func cancel()
}

/// What the watcher needs from the machine besides reading files: being told that files changed and asking
/// whether a process is alive. Behind a protocol so tests can say when files changed and which processes live,
/// and never touch the real home directory.
nonisolated protocol AgentFileSystem: Sendable {
    /// Calls `onChange`, on any thread, soon after something below one of `roots` may have changed. It says
    /// nothing about what changed; the watcher rescans.
    func watch(_ roots: [URL], onChange: @escaping @Sendable () -> Void) -> any AgentWatchHandle

    /// Whether the process behind a registry entry is still the one that wrote it.
    func isAlive(_ session: ClaudeSessionInfo) -> Bool
}

/// The real machine: FSEvents for changes, the process table for liveness.
nonisolated struct LocalAgentFileSystem: AgentFileSystem {
    func watch(_ roots: [URL], onChange: @escaping @Sendable () -> Void) -> any AgentWatchHandle {
        FSEventsWatch(paths: roots.map { $0.resolvingSymlinksInPath().path }, onChange: onChange)
    }

    func isAlive(_ session: ClaudeSessionInfo) -> Bool {
        ClaudeSessionRegistry.isAlive(session)
    }
}
