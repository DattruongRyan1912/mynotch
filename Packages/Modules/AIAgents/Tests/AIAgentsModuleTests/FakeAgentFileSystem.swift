import Foundation
@testable import AIAgentsModule

/// Stands in for the machine: the test says which processes are alive and when files changed.
nonisolated final class FakeAgentFileSystem: AgentFileSystem, @unchecked Sendable {
    private nonisolated final class Handle: AgentWatchHandle {
        let cancelled: @Sendable () -> Void
        init(cancelled: @escaping @Sendable () -> Void) { self.cancelled = cancelled }
        func cancel() { cancelled() }
    }

    private let lock = NSLock()
    private var alivePIDs: Set<pid_t> = []
    private var handlers: [UUID: @Sendable ([String]) -> Void] = [:]
    private var roots: [URL] = []

    var watchedRoots: [URL] { lock.withLock { roots } }
    var isWatching: Bool { lock.withLock { !handlers.isEmpty } }
    /// How many watches are live; `watchedRoots` only remembers the last one's roots.
    var activeWatchCount: Int { lock.withLock { handlers.count } }

    func setAlive(_ pids: pid_t...) {
        lock.withLock { alivePIDs = Set(pids) }
    }

    /// Reports a change, as a file system event would: with the paths that changed, or with none when the
    /// system would not say which.
    func fire(_ paths: String...) {
        let current = lock.withLock { Array(handlers.values) }
        current.forEach { $0(paths) }
    }

    func watch(_ roots: [URL], onChange: @escaping @Sendable ([String]) -> Void) -> any AgentWatchHandle {
        let id = UUID()
        lock.withLock {
            self.roots = roots
            handlers[id] = onChange
        }
        return Handle { [weak self] in self?.lock.withLock { self?.handlers[id] = nil } }
    }

    func isAlive(_ session: ClaudeSessionInfo) -> Bool {
        lock.withLock { alivePIDs.contains(session.pid) }
    }
}
