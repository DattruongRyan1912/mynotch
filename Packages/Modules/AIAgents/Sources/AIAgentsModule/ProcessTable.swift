import Darwin
import Foundation

/// One process as the search for an agent's terminal needs it.
nonisolated struct ProcessEntry: Equatable, Sendable {
    var pid: pid_t
    var parentPID: pid_t
    /// The device name of its controlling terminal, such as `ttys003`; nil when it has none.
    var tty: String?
    var executablePath: String?
}

/// The process table, one process at a time. Behind a protocol so tests walk a table written by hand.
nonisolated protocol ProcessTable: Sendable {
    func entry(pid: pid_t) -> ProcessEntry?
}

/// The real table. The parent and the controlling terminal come from the kernel's process list (what `ps` reads), which
/// answers for any process, the root-owned `login` between a terminal app and the shell included; `proc_pidinfo` refuses those.
/// The executable path comes from libproc and is missing for what belongs to another user. No process is signalled, started
/// or changed.
nonisolated struct SystemProcessTable: ProcessTable {
    func entry(pid: pid_t) -> ProcessEntry? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size == MemoryLayout<kinfo_proc>.stride, info.kp_proc.p_pid == pid
        else { return nil }
        return ProcessEntry(pid: pid, parentPID: info.kp_eproc.e_ppid, tty: Self.ttyName(of: info.kp_eproc.e_tdev), executablePath: Self.path(of: pid))
    }

    /// `devname` keeps its answer in a buffer shared by every caller, so the reentrant form is used.
    static func ttyName(of device: dev_t) -> String? {
        guard device != -1 else { return nil }
        var buffer = [CChar](repeating: 0, count: 64)
        guard devname_r(device, mode_t(S_IFCHR), &buffer, Int32(buffer.count)) != nil else { return nil }
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty || name == "??" ? nil : name
    }

    private static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
