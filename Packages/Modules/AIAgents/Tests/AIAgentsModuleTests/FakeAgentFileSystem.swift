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
    private var handlers: [UUID: @Sendable () -> Void] = [:]
    private var roots: [URL] = []

    var watchedRoots: [URL] { lock.withLock { roots } }
    var isWatching: Bool { lock.withLock { !handlers.isEmpty } }

    func setAlive(_ pids: pid_t...) {
        lock.withLock { alivePIDs = Set(pids) }
    }

    /// Reports a change, as a file system event would.
    func fire() {
        let current = lock.withLock { Array(handlers.values) }
        current.forEach { $0() }
    }

    func watch(_ roots: [URL], onChange: @escaping @Sendable () -> Void) -> any AgentWatchHandle {
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
