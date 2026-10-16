import Darwin

nonisolated enum StopSignal: Sendable {
    case terminate, kill

    var number: Int32 { self == .terminate ? SIGTERM : SIGKILL }
}

nonisolated enum SignalResult: Equatable, Sendable {
    case sent
    /// No such process any more.
    case gone
    case denied
}

/// What the stop flow does to a process, behind a seam so tests never touch a real one. Both calls are system calls: run them off
/// the main actor.
nonisolated protocol ProcessControl: Sendable {
    /// The process now; nil when it is gone (a zombie is gone).
    func identity(of pid: Int32) -> ProcessIdentity?
    func send(_ signal: StopSignal, to pid: Int32) -> SignalResult
}

nonisolated struct LibprocProcessControl: ProcessControl {
    /// `kill` with pid 0 signals the whole process group and with a negative pid every process the user owns, so only real pids
    /// above launchd's ever get that far.
    static func isSignalable(pid: Int32) -> Bool { pid > 1 }

    func identity(of pid: Int32) -> ProcessIdentity? { LibprocProcess.info(of: pid)?.identity }

    func send(_ signal: StopSignal, to pid: Int32) -> SignalResult {
        guard Self.isSignalable(pid: pid) else { return .denied }
        if kill(pid, signal.number) == 0 { return .sent }
        return errno == ESRCH ? .gone : .denied
    }
}
