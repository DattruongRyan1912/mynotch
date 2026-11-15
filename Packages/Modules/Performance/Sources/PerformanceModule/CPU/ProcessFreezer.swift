import AppKit
import Foundation

/// Safely throttles/freezes heavy background processes using SIGSTOP and restores them with SIGCONT.
///
/// Designed as a thermal reduction mechanism for fanless MacBooks (MacBook Air) or heavy compile spikes.
/// Enforces strict safety rules:
/// - Never freezes system root processes (PID <= 1)
/// - Never freezes MyNotch itself
/// - Never freezes the frontmost active application
/// - Automatically resumes frozen processes after a safety timeout (default 15 seconds) so no process hangs indefinitely.
public final class ProcessFreezer: @unchecked Sendable {
    public typealias SignalSender = @Sendable (_ pid: pid_t, _ signal: Int32) -> Int32
    public typealias PIDProvider = @Sendable () -> pid_t?

    private let killSignal: SignalSender
    private let frontmostPID: PIDProvider
    private let ownPID: @Sendable () -> pid_t

    private let lock = NSLock()
    private var frozenEntries: [Int32: Date] = [:]
    private var autoResumeTasks: [Int32: Task<Void, Never>] = [:]

    public init(
        killSignal: @escaping SignalSender = { pid, sig in Darwin.kill(pid, sig) },
        frontmostPID: @escaping PIDProvider = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        ownPID: @escaping @Sendable () -> pid_t = { Darwin.getpid() }
    ) {
        self.killSignal = killSignal
        self.frontmostPID = frontmostPID
        self.ownPID = ownPID
    }

    public func isProtected(pid: Int32) -> Bool {
        if pid <= 1 { return true }
        if pid == ownPID() { return true }
        if let front = frontmostPID(), pid == front { return true }
        return false
    }

    public func isFrozen(pid: Int32) -> Bool {
        lock.withLock { frozenEntries[pid] != nil }
    }

    public var frozenCount: Int {
        lock.withLock { frozenEntries.count }
    }

    public var hasFrozenProcesses: Bool {
        lock.withLock { !frozenEntries.isEmpty }
    }

    public var frozenPIDs: Set<Int32> {
        lock.withLock { Set(frozenEntries.keys) }
    }

    public func freeze(pid: Int32, timeoutSeconds: TimeInterval = 15) -> Bool {
        if isProtected(pid: pid) { return false }

        return lock.withLock {
            if frozenEntries[pid] != nil { return true }

            let result = killSignal(pid_t(pid), SIGSTOP)
            guard result == 0 else { return false }

            frozenEntries[pid] = Date()

            // Safety Auto-Resume Task
            autoResumeTasks[pid]?.cancel()
            autoResumeTasks[pid] = Task { [weak self] in
                let ms = max(1, Int(timeoutSeconds * 1000))
                try? await Task.sleep(for: .milliseconds(ms))
                _ = self?.resume(pid: pid)
            }
            return true
        }
    }

    public func resume(pid: Int32) -> Bool {
        lock.withLock {
            autoResumeTasks[pid]?.cancel()
            autoResumeTasks.removeValue(forKey: pid)

            guard frozenEntries.removeValue(forKey: pid) != nil else { return false }
            return killSignal(pid_t(pid), SIGCONT) == 0
        }
    }

    public func resumeAll() {
        let pidsToResume = lock.withLock { () -> [Int32] in
            let keys = Array(frozenEntries.keys)
            for task in autoResumeTasks.values { task.cancel() }
            autoResumeTasks.removeAll()
            frozenEntries.removeAll()
            return keys
        }

        for pid in pidsToResume {
            _ = killSignal(pid_t(pid), SIGCONT)
        }
    }

    public func remainingTimeout(for pid: Int32, totalTimeout: TimeInterval = 15) -> Int? {
        lock.withLock {
            guard let startDate = frozenEntries[pid] else { return nil }
            let elapsed = Date().timeIntervalSince(startDate)
            let remaining = totalTimeout - elapsed
            return max(0, Int(remaining.rounded(.up)))
        }
    }
}
